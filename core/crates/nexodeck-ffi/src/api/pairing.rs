use crate::frb_generated::StreamSink;

/// Espejo de `nexodeck_protocol::DevicePlatformWire` -- mismo motivo que el
/// resto de DTOs de este crate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DevicePlatform {
    Android,
    Ios,
    Windows,
    Linux,
}

impl From<nexodeck_protocol::DevicePlatformWire> for DevicePlatform {
    fn from(p: nexodeck_protocol::DevicePlatformWire) -> Self {
        match p {
            nexodeck_protocol::DevicePlatformWire::Android => DevicePlatform::Android,
            nexodeck_protocol::DevicePlatformWire::Ios => DevicePlatform::Ios,
            nexodeck_protocol::DevicePlatformWire::Windows => DevicePlatform::Windows,
            nexodeck_protocol::DevicePlatformWire::Linux => DevicePlatform::Linux,
        }
    }
}

/// Union de los eventos de pairing de `nexodeck_transport::server` (rol PC)
/// y `nexodeck_transport::client` (rol Android) -- la misma funcion de
/// stream se usa en ambas plataformas, y cada rol solo emite las variantes
/// que le corresponden.
#[derive(Debug, Clone)]
pub enum PairingEvent {
    /// Rol host: un cliente pidio emparejarse (ya mostro/recibio el PIN).
    DeviceRequestedPairing {
        device_name: String,
        platform: DevicePlatform,
    },
    /// Rol cliente: la PC contesto con el PIN armado -- mostrar para
    /// comparacion visual con lo que se ve en la PC.
    HostPinReceived {
        pin: String,
        host_name: String,
        host_platform: DevicePlatform,
    },
    PairingSucceeded {
        device_id: String,
        cert_fingerprint: String,
    },
    PairingRejected {
        reason: String,
    },
    /// Rol host: un telefono pidio emparejarse sin el PIN armado y la PC lo
    /// esta reteniendo. Hay que mostrar el PIN (armarlo) antes de que venza la
    /// gracia -- ver `TransportHost::set_on_demand_pairing_grace`.
    PairingRequestedWhileDisarmed {
        device_name: String,
        platform: DevicePlatform,
    },
}

impl From<nexodeck_transport::server::PairingEvent> for PairingEvent {
    fn from(e: nexodeck_transport::server::PairingEvent) -> Self {
        use nexodeck_transport::server::PairingEvent as E;
        match e {
            E::DeviceRequestedPairing {
                device_name,
                platform,
            } => PairingEvent::DeviceRequestedPairing {
                device_name,
                platform: platform.into(),
            },
            E::PairingSucceeded {
                device_id,
                cert_fingerprint,
            } => PairingEvent::PairingSucceeded {
                device_id,
                cert_fingerprint,
            },
            E::PairingRejected { reason } => PairingEvent::PairingRejected { reason },
            E::PairingRequestedWhileDisarmed {
                device_name,
                platform,
            } => PairingEvent::PairingRequestedWhileDisarmed {
                device_name,
                platform: platform.into(),
            },
        }
    }
}

impl From<nexodeck_transport::client::PairingEvent> for PairingEvent {
    fn from(e: nexodeck_transport::client::PairingEvent) -> Self {
        use nexodeck_transport::client::PairingEvent as E;
        match e {
            E::HostPinReceived {
                pin,
                host_name,
                host_platform,
            } => PairingEvent::HostPinReceived {
                pin,
                host_name,
                host_platform: host_platform.into(),
            },
            E::PairingSucceeded {
                device_id,
                cert_fingerprint,
            } => PairingEvent::PairingSucceeded {
                device_id,
                cert_fingerprint,
            },
            E::PairingRejected { reason } => PairingEvent::PairingRejected { reason },
        }
    }
}

#[derive(Debug, Clone)]
pub struct DiscoveredHost {
    pub name: String,
    pub host: String,
    pub port: u16,
}

impl From<nexodeck_transport::discovery::DiscoveredHost> for DiscoveredHost {
    fn from(h: nexodeck_transport::discovery::DiscoveredHost) -> Self {
        Self {
            name: h.name,
            host: h.host,
            port: h.port,
        }
    }
}

/// Rol PC: arranca el servidor WebSocket+TLS, el anuncio mDNS y el escaneo
/// USB. Se llama una sola vez al inicio de la app en desktop (ver
/// `main.dart`).
pub async fn start_transport_host(device_name: String) -> Result<(), String> {
    let host = nexodeck_transport::server::TransportHost::start(
        nexodeck_transport::server::HostConfig {
            device_name,
            port: nexodeck_transport::server::DEFAULT_PORT,
        },
    )
    .await
    .map_err(|e| e.to_string())?;

    // El puente USB comparte el mismo `TransportHost`: un dispositivo que
    // entra por cable pasa por el mismo pairing, las mismas autorizaciones y
    // los mismos `ConnectionEvent` que uno que entra por WiFi. La identidad
    // de accessory es deliberadamente constante (no lleva el nombre del
    // equipo): Android la matchea contra su `accessory_filter.xml`, asi que
    // si varia por maquina, el telefono entra en accessory mode pero ninguna
    // app recibe el intent.
    #[cfg(not(target_os = "android"))]
    nexodeck_transport::usb::UsbBridge::start(
        host.clone(),
        nexodeck_transport::usb::AccessoryIdentity::default(),
    );
    // Emparejamiento a demanda (modo sin interfaz): 15 s, por debajo de los
    // 20 s que espera el telefono -- ver `set_on_demand_pairing_grace`.
    host.set_on_demand_pairing_grace(Some(std::time::Duration::from_secs(15)));
    // Si el buzon ya estaba abierto, el telefono puede pedir notas desde la
    // primera sesion. Si todavia no, `docs_inbox_init` registra al abrirlo.
    #[cfg(not(target_os = "android"))]
    if let Ok(service) = super::docs::service() {
        super::notes_vault::register(&service);
    }
    let _ = host;

    Ok(())
}

pub fn arm_pairing() -> Result<String, String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.arm_pairing().map_err(|e| e.to_string())
}

pub fn disarm_pairing() -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.disarm_pairing();
    Ok(())
}

/// Rol PC: acepta o rechaza al dispositivo que esta esperando confirmacion
/// (ver `PairingEvent::DeviceRequestedPairing`). El `device_id` real llega
/// por separado via `PairingEvent::PairingSucceeded`.
pub fn confirm_pairing(accept: bool) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.confirm_pairing(accept).map_err(|e| e.to_string())
}

pub fn get_server_cert_fingerprint() -> Result<String, String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    Ok(host.cert_fingerprint())
}

/// Funciona en ambos roles: multiplexa los eventos del host (si esta
/// iniciado) y del cliente (siempre disponible como singleton) hacia un
/// unico stream. En desktop solo se emiten eventos de host; en Android,
/// solo de cliente.
pub async fn watch_pairing_events(sink: StreamSink<PairingEvent>) {
    let mut client_rx = nexodeck_transport::client::client().pairing_events();
    let mut host_rx = nexodeck_transport::server::host().map(|h| h.pairing_events());

    loop {
        let forwarded = tokio::select! {
            ev = client_rx.recv() => ev.ok().map(PairingEvent::from),
            ev = recv_optional_pairing(&mut host_rx) => ev.map(PairingEvent::from),
        };
        match forwarded {
            Some(event) => {
                if sink.add(event).is_err() {
                    break;
                }
            }
            None => continue,
        }
    }
}

async fn recv_optional_pairing(
    rx: &mut Option<tokio::sync::broadcast::Receiver<nexodeck_transport::server::PairingEvent>>,
) -> Option<nexodeck_transport::server::PairingEvent> {
    match rx {
        Some(r) => r.recv().await.ok(),
        None => std::future::pending().await,
    }
}

/// Rol Android: navega la red buscando hosts NexoDeck anunciados por mDNS.
/// Requiere el multicast lock adquirido del lado Dart antes de llamar esto
/// (ver `MainActivity.kt` / `multicast_lock_service.dart`).
pub async fn discover_hosts(sink: StreamSink<DiscoveredHost>) {
    let mut rx = match nexodeck_transport::discovery::browse() {
        Ok(rx) => rx,
        Err(_) => return,
    };
    while let Some(host) = rx.recv().await {
        if sink.add(host.into()).is_err() {
            break;
        }
    }
}

/// Rol Android: primer pairing con un host recien descubierto. Dispara la
/// conexion en segundo plano y vuelve enseguida -- el progreso se observa
/// via `watch_pairing_events`/`watch_connection_events`, no via el
/// resultado de esta llamada (la conexion dura mientras la sesion siga
/// viva, no tiene sentido esperarla aca).
/// Resuelve cuando la conexion quedo establecida; el loop de la sesion
/// sigue en background (lo suelta `spawn_session` del lado transporte). Se
/// espera a proposito en vez de spawnear todo: asi un fallo de conexion
/// llega a Dart como excepcion en vez de desaparecer.
pub async fn connect_to_host(host: String, port: u16, device_name: String) -> Result<(), String> {
    nexodeck_transport::client::client()
        .connect_first_pairing(host, port, device_name)
        .await
        .map_err(|e| e.to_string())
}

/// Rol Android: reconexion con un dispositivo ya emparejado, usando el
/// fingerprint pinneado guardado en Drift tras el pairing original.
pub async fn reconnect_to_host(
    device_id: String,
    host: String,
    port: u16,
    pinned_fingerprint: String,
) -> Result<(), String> {
    nexodeck_transport::client::client()
        .reconnect(device_id, host, port, pinned_fingerprint)
        .await
        .map_err(|e| e.to_string())
}

pub fn send_pair_confirm() -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_pair_confirm()
        .map_err(|e| e.to_string())
}
