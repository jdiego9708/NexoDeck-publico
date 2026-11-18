use std::time::{Duration, Instant};

use nexodeck_transport::{client, server};

/// Emparejamiento a demanda: la PC retiene un `PairHello` sin armar hasta que
/// alguien muestra el PIN, en vez de rechazarlo.
///
/// **Un solo test y en su propio binario**, por el mismo motivo que
/// `loopback_pairing.rs`: `TransportHost` y `TransportClient` son singletons de
/// proceso, y un segundo `start` en el mismo binario devolveria el host de otro
/// test (con otra gracia y otro estado de enfriamiento).
#[tokio::test(flavor = "multi_thread")]
async fn held_pair_hello_waits_for_arming_then_cools_down() {
    let host = server::TransportHost::start(server::HostConfig {
        device_name: "TestHost".into(),
        port: 0,
    })
    .await
    .expect("el host deberia arrancar");
    let grace = Duration::from_secs(2);
    host.set_on_demand_pairing_grace(Some(grace));
    let port = host.port();

    let mut host_events = host.pairing_events();
    let cli = client::client();
    let mut client_events = cli.pairing_events();

    // 1. Sin armar: el hello queda retenido, la PC avisa, y al armar el PIN el
    //    MISMO intento del telefono lo recibe -- sin reintentar.
    spawn_pairing_attempt(cli.clone(), port);
    let requested = recv_matching(&mut host_events, |e| match e {
        server::PairingEvent::PairingRequestedWhileDisarmed { device_name, .. } => {
            Some(device_name.clone())
        }
        _ => None,
    })
    .await;
    assert_eq!(requested, "TestAndroid");

    let pin = host.arm_pairing().expect("arm_pairing");
    let received = recv_matching(&mut client_events, |e| match e {
        client::PairingEvent::HostPinReceived { pin, .. } => Some(pin.clone()),
        _ => None,
    })
    .await;
    assert_eq!(
        received, pin,
        "el telefono tiene que recibir el PIN que la PC esta mostrando"
    );

    // Se cierra este intento rechazandolo en la PC, para dejar el host limpio.
    cli.send_pair_confirm().expect("send_pair_confirm");
    recv_matching(&mut host_events, |e| match e {
        server::PairingEvent::DeviceRequestedPairing { .. } => Some(()),
        _ => None,
    })
    .await;
    host.confirm_pairing(false).expect("confirm_pairing");
    recv_rejection(&mut client_events).await;
    host.disarm_pairing();

    // 2. Sin armar y sin nadie que arme: avisa igual, y rechaza al vencer la
    //    gracia -- no antes.
    let started = Instant::now();
    spawn_pairing_attempt(cli.clone(), port);
    recv_matching(&mut host_events, |e| match e {
        server::PairingEvent::PairingRequestedWhileDisarmed { .. } => Some(()),
        _ => None,
    })
    .await;
    recv_rejection(&mut client_events).await;
    assert!(
        started.elapsed() >= grace - Duration::from_millis(200),
        "el rechazo llego a los {:?}, antes de vencer la gracia de {grace:?}",
        started.elapsed()
    );

    // 3. En enfriamiento: rechazo inmediato y SIN aviso. Es el freno contra un
    //    dispositivo que reintenta en bucle.
    let started = Instant::now();
    spawn_pairing_attempt(cli.clone(), port);
    recv_rejection(&mut client_events).await;
    assert!(
        started.elapsed() < grace,
        "en enfriamiento el rechazo tiene que ser inmediato, tardo {:?}",
        started.elapsed()
    );
    let mut notified_again = false;
    while let Ok(event) = host_events.try_recv() {
        if matches!(event, server::PairingEvent::PairingRequestedWhileDisarmed { .. }) {
            notified_again = true;
        }
    }
    assert!(
        !notified_again,
        "en enfriamiento la PC no tiene que volver a avisar"
    );
}

fn spawn_pairing_attempt(cli: std::sync::Arc<client::TransportClient>, port: u16) {
    tokio::spawn(async move {
        let _ = cli
            .connect_first_pairing("127.0.0.1".into(), port, "TestAndroid".into())
            .await;
    });
}

async fn recv_rejection(rx: &mut tokio::sync::broadcast::Receiver<client::PairingEvent>) {
    recv_matching(rx, |e| match e {
        client::PairingEvent::PairingRejected { .. } => Some(()),
        _ => None,
    })
    .await;
}

async fn recv_matching<T: Clone, R>(
    rx: &mut tokio::sync::broadcast::Receiver<T>,
    mut matcher: impl FnMut(&T) -> Option<R>,
) -> R {
    tokio::time::timeout(Duration::from_secs(8), async {
        loop {
            let event = rx.recv().await.expect("el canal no deberia cerrarse");
            if let Some(result) = matcher(&event) {
                return result;
            }
        }
    })
    .await
    .expect("timeout esperando el evento esperado")
}
