use std::time::Duration;

use nexodeck_transport::{client, server};

/// Prueba de integracion en loopback (127.0.0.1), sin FFI/Flutter de por
/// medio: un solo proceso jugando ambos roles (host y cliente) a la vez.
/// Todo en un solo test porque `TransportHost`/`TransportClient` son
/// singletons de proceso (`OnceLock`) -- correr varios `#[tokio::test]`
/// en el mismo binario colisionaria sobre el mismo host/cliente.
#[tokio::test(flavor = "multi_thread")]
async fn full_pairing_and_session_lifecycle() {
    let host = server::TransportHost::start(server::HostConfig {
        device_name: "TestHost".into(),
        port: 0,
    })
    .await
    .expect("el host deberia arrancar");
    let port = host.port();

    let mut host_pairing_events = host.pairing_events();
    let mut host_connection_events = host.connection_events();

    let pin = host.arm_pairing().expect("arm_pairing");

    let cli = client::client();
    let mut client_pairing_events = cli.pairing_events();
    let mut client_connection_events = cli.connection_events();

    let pairing_client = cli.clone();
    tokio::spawn(async move {
        let _ = pairing_client
            .connect_first_pairing("127.0.0.1".into(), port, "TestAndroid".into())
            .await;
    });

    // El cliente recibe el PIN del host y lo confirma.
    let pin_event = recv_timeout(&mut client_pairing_events).await;
    match pin_event {
        client::PairingEvent::HostPinReceived { pin: received, .. } => {
            assert_eq!(received, pin, "el PIN mostrado al cliente debe ser el mismo que arm_pairing genero")
        }
        other => panic!("evento inesperado: {other:?}"),
    }
    cli.send_pair_confirm().expect("send_pair_confirm");

    // El host ve la solicitud y la acepta.
    let request_event = recv_timeout(&mut host_pairing_events).await;
    match request_event {
        server::PairingEvent::DeviceRequestedPairing { device_name, .. } => {
            assert_eq!(device_name, "TestAndroid")
        }
        other => panic!("evento inesperado: {other:?}"),
    }
    host.confirm_pairing(true).expect("confirm_pairing");

    // Ambos lados terminan de acuerdo en el mismo device_id/fingerprint.
    let host_succeeded = recv_timeout(&mut host_pairing_events).await;
    let (device_id, host_fp) = match host_succeeded {
        server::PairingEvent::PairingSucceeded {
            device_id,
            cert_fingerprint,
        } => (device_id, cert_fingerprint),
        other => panic!("evento inesperado: {other:?}"),
    };

    let client_succeeded = recv_timeout(&mut client_pairing_events).await;
    match client_succeeded {
        client::PairingEvent::PairingSucceeded {
            device_id: client_device_id,
            cert_fingerprint: client_fp,
        } => {
            assert_eq!(device_id, client_device_id);
            assert_eq!(host_fp, client_fp);
        }
        other => panic!("evento inesperado: {other:?}"),
    }
    assert_eq!(host_fp, host.cert_fingerprint());

    // PC -> Android: un HardwareSnapshot real llega en ~1s.
    let snapshot = recv_matching(&mut client_connection_events, |e| match e {
        client::ConnectionEvent::HardwareSnapshotReceived(s) => Some(s.clone()),
        _ => None,
    })
    .await;
    assert!(snapshot.ram_total_mb > 0.0, "el snapshot deberia traer RAM real");

    // PC -> Android: catalogo de acciones (ids de la PC, no de Android).
    host.send_actions_catalog(
        &device_id,
        vec![nexodeck_protocol::RemoteAction {
            id: "git-status".into(),
            name: "Git status".into(),
            icon: "terminal".into(),
            color_hex: "#6366F1".into(),
            group_id: None,
            group_name: None,
            group_color_hex: None,
            kind: nexodeck_protocol::RemoteActionKind::Terminal,
            parameters: vec![nexodeck_protocol::RemoteActionParam {
                key: "rama".into(),
                label: "Rama".into(),
                kind: nexodeck_protocol::RemoteParamKind::Text,
                default_value: Some("main".into()),
                options: vec![],
            }],
            step_count: 0,
        }],
    )
    .expect("send_actions_catalog");
    let catalog = recv_matching(&mut client_connection_events, |e| match e {
        client::ConnectionEvent::ActionsCatalogReceived(actions) => Some(actions.clone()),
        _ => None,
    })
    .await;
    assert_eq!(catalog.len(), 1);
    assert_eq!(catalog[0].id, "git-status");
    // El catalogo tiene que llegar con los parametros COMPLETOS (no solo la
    // key): es lo que le permite al telefono dibujar el prompt en vez de
    // ejecutar con los valores por defecto sin preguntar.
    assert_eq!(catalog[0].parameters.len(), 1);
    assert_eq!(catalog[0].parameters[0].label, "Rama");
    assert_eq!(
        catalog[0].parameters[0].default_value.as_deref(),
        Some("main")
    );

    // Android -> PC: ExecuteAction se ve como evento del lado host, y el
    // ack de vuelta llega al cliente. Los valores cargados en el telefono
    // viajan con el pedido -- sin esto la PC ejecutaba con los defaults.
    cli.send_execute_action(
        "git-status".into(),
        vec![nexodeck_protocol::ActionParamValue {
            key: "rama".into(),
            value: "feature/macros".into(),
        }],
    )
    .expect("send_execute_action");
    let (action_device_id, action_id, action_params) =
        recv_matching(&mut host_connection_events, |e| match e {
            server::ConnectionEvent::ActionExecutionRequested {
                device_id,
                action_id,
                params,
            } => Some((device_id.clone(), action_id.clone(), params.clone())),
            _ => None,
        })
        .await;
    assert_eq!(action_device_id, device_id);
    assert_eq!(action_id, "git-status");
    assert_eq!(action_params.len(), 1);
    assert_eq!(action_params[0].key, "rama");
    assert_eq!(action_params[0].value, "feature/macros");

    host.send_action_ack(&device_id, "git-status".into(), true, None)
        .expect("send_action_ack");
    let (ack_action_id, ack_success) =
        recv_matching(&mut client_connection_events, |e| match e {
            client::ConnectionEvent::ActionAckReceived {
                action_id, success, ..
            } => Some((action_id.clone(), *success)),
            _ => None,
        })
        .await;
    assert_eq!(ack_action_id, "git-status");
    assert!(ack_success);

    // Reconexion con el fingerprint correcto: el cliente vuelve a
    // conectar (con un `device_id` ya emparejado) y el host la acepta.
    let reconnect_client = client::client();
    let good_fp = host_fp.clone();
    let good_device_id = device_id.clone();
    tokio::spawn(async move {
        let _ = reconnect_client
            .reconnect(good_device_id, "127.0.0.1".into(), port, good_fp)
            .await;
    });
    let reconnected = recv_matching(&mut client_connection_events, |e| match e {
        client::ConnectionEvent::Connected => Some(()),
        _ => None,
    })
    .await;
    let _ = reconnected;

    // La reconexion reemplaza la sesion vieja del host para este mismo
    // device_id (`HostState.sessions.insert` pisa la entrada) -- eso
    // dispara un DeviceConnected nuevo, y ademas DROPEA el `close_tx` de la
    // sesion vieja, lo cual por si solo hace que su `close_rx.recv()`
    // rompa el loop (el patron `_` en el `select!` matchea tanto `Some(())`
    // como `None`/canal cerrado). Necesario para la prioridad USB-sobre-WiFi
    // de Fase 5: si no se cerrara, la sesion vieja seguiria tickeando
    // HardwareSnapshot en paralelo hacia un socket abandonado, y el cliente
    // (que sigue escuchando ese socket viejo) veria eventos duplicados.
    let reconnected_device_id = recv_matching(&mut host_connection_events, |e| match e {
        server::ConnectionEvent::DeviceConnected { device_id } => Some(device_id.clone()),
        _ => None,
    })
    .await;
    assert_eq!(reconnected_device_id, device_id);

    let snapshot_count = count_events_for(Duration::from_millis(2500), &mut client_connection_events, |e| {
        matches!(e, client::ConnectionEvent::HardwareSnapshotReceived(_))
    })
    .await;
    assert!(
        snapshot_count <= 3,
        "se esperaban ~2-3 HardwareSnapshot en 2.5s de una sola sesion activa, se recibieron {snapshot_count} -- sugiere que la sesion vieja no se cerro y sigue tickeando en paralelo"
    );

    // Reconexion con un fingerprint distinto falla EN EL HANDSHAKE TLS,
    // antes de intercambiar ningun mensaje -- esto es lo que hace que el
    // pinning realmente rechace un certificado cambiado.
    let bad_fp = "0".repeat(64);
    let bad_result = client::client()
        .reconnect(device_id.clone(), "127.0.0.1".into(), port, bad_fp)
        .await;
    assert!(
        bad_result.is_err(),
        "reconectar con un fingerprint incorrecto deberia fallar"
    );

    // Revocar autorizacion corta la sesion viva del dispositivo.
    host.set_device_authorized(&device_id, false);
    let disconnected_id = recv_matching(&mut host_connection_events, |e| match e {
        server::ConnectionEvent::DeviceDisconnected { device_id } => Some(device_id.clone()),
        _ => None,
    })
    .await;
    assert_eq!(disconnected_id, device_id);

    // Con la autorizacion revocada, la proxima reconexion se rechaza.
    let rejected_client = client::client();
    let rejected_device_id = device_id.clone();
    tokio::spawn(async move {
        let _ = rejected_client
            .reconnect(rejected_device_id, "127.0.0.1".into(), port, host_fp)
            .await;
    });
    let rejection = recv_matching(&mut client_pairing_events, |e| match e {
        client::PairingEvent::PairingRejected { reason } => Some(reason.clone()),
        _ => None,
    })
    .await;
    assert!(!rejection.is_empty());
}

async fn recv_timeout<T: Clone + std::fmt::Debug>(rx: &mut tokio::sync::broadcast::Receiver<T>) -> T {
    tokio::time::timeout(Duration::from_secs(5), rx.recv())
        .await
        .expect("timeout esperando el evento")
        .expect("el canal no deberia cerrarse")
}

async fn recv_matching<T: Clone, R>(
    rx: &mut tokio::sync::broadcast::Receiver<T>,
    mut matcher: impl FnMut(&T) -> Option<R>,
) -> R {
    tokio::time::timeout(Duration::from_secs(5), async {
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

/// Cuenta cuantos eventos que matchean `predicate` llegan durante `window`
/// -- usado para detectar sesiones "fantasma" que siguen emitiendo eventos
/// en paralelo con la sesion activa real (ver el comentario en el test
/// principal sobre el fix de cierre de sesion vieja).
async fn count_events_for<T: Clone>(
    window: Duration,
    rx: &mut tokio::sync::broadcast::Receiver<T>,
    predicate: impl Fn(&T) -> bool,
) -> usize {
    let mut count = 0;
    let _ = tokio::time::timeout(window, async {
        loop {
            let event = rx.recv().await.expect("el canal no deberia cerrarse");
            if predicate(&event) {
                count += 1;
            }
        }
    })
    .await;
    count
}
