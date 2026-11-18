//! El tunel completo en un solo proceso: PC -> relay -> telefono.
//!
//! Levanta un relay de verdad en loopback, aparca el host en el, y empareja
//! desde el cliente **sin usar la LAN**. Es la prueba de que el camino del
//! VPS no necesita ninguna excepcion: mismo TLS, mismo pairing por PIN,
//! mismos eventos que por WiFi.
//!
//! En un archivo aparte de `loopback_pairing.rs` porque `TransportHost` y
//! `TransportClient` son singletons de proceso (`OnceLock`): cada binario de
//! test tiene los suyos, pero dentro de uno solo cabe un escenario.

use std::time::Duration;

use nexodeck_relay::hello::TOKEN_LEN;
use nexodeck_transport::{client, server};

const TOKEN: [u8; TOKEN_LEN] = [0xA5; TOKEN_LEN];

#[tokio::test(flavor = "multi_thread")]
async fn pairing_completo_a_traves_del_relay() {
    // 1. El relay, en un puerto efimero.
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("el relay deberia poder escuchar");
    let relay_addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        nexodeck_relay::serve(listener, nexodeck_relay::RelayConfig::default()).await;
    });

    // 2. La PC. Su listener de LAN queda en un puerto efimero y no se usa:
    //    todo el trafico de esta prueba pasa por el relay.
    let host = server::TransportHost::start(server::HostConfig {
        device_name: "TestHost".into(),
        port: 0,
    })
    .await
    .expect("el host deberia arrancar");

    let mut host_pairing_events = host.pairing_events();
    let mut host_connection_events = host.connection_events();
    let mut relay_status = host.relay_events();

    let endpoint = server::RelayEndpoint {
        host: relay_addr.ip().to_string(),
        port: relay_addr.port(),
        token: TOKEN,
    };
    host.serve_via_relay(endpoint.clone());

    // 3. Hasta que la PC no este aparcada, el telefono no tiene a quien
    //    llamar. Esperarlo explicitamente evita una prueba intermitente.
    match recv_relay(&mut relay_status).await {
        server::RelayStatus::Parked => {}
        otro => panic!("el host deberia quedar aparcado, quedo en {otro:?}"),
    }

    let pin = host.arm_pairing().expect("arm_pairing");

    // 4. El telefono, que solo conoce la direccion del relay y el token.
    let cli = client::client();
    let mut client_pairing_events = cli.pairing_events();
    let mut client_connection_events = cli.connection_events();

    let pairing_client = cli.clone();
    let endpoint_cliente = endpoint.clone();
    tokio::spawn(async move {
        let _ = pairing_client
            .connect_first_pairing_via_relay(endpoint_cliente, "TestAndroid".into())
            .await;
    });

    match recv_relay(&mut relay_status).await {
        server::RelayStatus::Matched => {}
        otro => panic!("el relay deberia haber empalmado, dijo {otro:?}"),
    }

    // 5. De aca en adelante el ritual es identico al de WiFi.
    match recv_timeout(&mut client_pairing_events).await {
        client::PairingEvent::HostPinReceived { pin: recibido, .. } => {
            assert_eq!(recibido, pin, "el PIN tiene que cruzar el tunel intacto");
        }
        otro => panic!("evento inesperado en el cliente: {otro:?}"),
    }
    cli.send_pair_confirm().expect("send_pair_confirm");

    match recv_timeout(&mut host_pairing_events).await {
        server::PairingEvent::DeviceRequestedPairing { device_name, .. } => {
            assert_eq!(device_name, "TestAndroid");
        }
        otro => panic!("evento inesperado en el host: {otro:?}"),
    }
    host.confirm_pairing(true).expect("confirm_pairing");

    let (device_id, host_fp) = match recv_timeout(&mut host_pairing_events).await {
        server::PairingEvent::PairingSucceeded {
            device_id,
            cert_fingerprint,
        } => (device_id, cert_fingerprint),
        otro => panic!("el host deberia haber emparejado, dijo {otro:?}"),
    };

    match recv_timeout(&mut client_pairing_events).await {
        client::PairingEvent::PairingSucceeded {
            device_id: id_cliente,
            cert_fingerprint,
        } => {
            assert_eq!(id_cliente, device_id, "las dos puntas, el mismo device_id");
            // Lo mas importante de toda la prueba: el fingerprint que el
            // telefono pinnea a traves del tunel es el de la PC, no el de
            // ningun intermediario. Si el relay terminara el TLS --como
            // hace un tunel tipo Cloudflare-- esto no coincidiria.
            assert_eq!(
                cert_fingerprint, host_fp,
                "el relay no puede alterar el certificado que ve el telefono"
            );
        }
        otro => panic!("el cliente deberia haber emparejado, dijo {otro:?}"),
    }

    // 6. Y la sesion queda viva de los dos lados.
    match recv_timeout(&mut host_connection_events).await {
        server::ConnectionEvent::DeviceConnected { device_id: id } => {
            assert_eq!(id, device_id);
        }
        otro => panic!("el host deberia ver la conexion, dijo {otro:?}"),
    }
    match recv_timeout(&mut client_connection_events).await {
        client::ConnectionEvent::Connected => {}
        otro => panic!("el cliente deberia verse conectado, dijo {otro:?}"),
    }

    // 7. Y la PC le entrega al telefono como volver a encontrarla desde
    //    afuera. Esto viaja en TODA sesion, tambien las de la LAN: es lo que
    //    permite que el token nunca se escriba a mano ni salga por un canal
    //    mas debil que la sesion ya autenticada.
    let offer = loop {
        match recv_timeout(&mut client_connection_events).await {
            client::ConnectionEvent::RelayOfferReceived {
                host,
                port,
                token_hex,
            } => break (host, port, token_hex),
            // El snapshot de hardware empieza a llegar enseguida; no es
            // motivo para fallar.
            client::ConnectionEvent::HardwareSnapshotReceived(_) => continue,
            otro => panic!("evento inesperado antes de la oferta: {otro:?}"),
        }
    };
    assert_eq!(offer.0, endpoint.host);
    assert_eq!(offer.1, endpoint.port);
    assert_eq!(
        offer.2,
        nexodeck_relay::hello::token_to_hex(&TOKEN),
        "el token tiene que llegar entero: es la unica credencial del tunel"
    );
}

async fn recv_timeout<T: Clone>(rx: &mut tokio::sync::broadcast::Receiver<T>) -> T {
    tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .expect("timeout esperando un evento")
        .expect("el canal de eventos se cerro")
}

async fn recv_relay(
    rx: &mut tokio::sync::broadcast::Receiver<server::RelayStatus>,
) -> server::RelayStatus {
    recv_timeout(rx).await
}
