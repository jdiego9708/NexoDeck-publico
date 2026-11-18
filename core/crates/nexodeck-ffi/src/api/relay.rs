//! El tunel: como la PC queda alcanzable desde fuera de su red.
//!
//! Dos roles, como todo lo demas. La **PC** enciende el tunel y queda
//! aparcada en el relay; el **telefono** lo usa como ultimo recurso, cuando
//! ni mDNS ni la direccion manual llegan.
//!
//! El token no se escribe a mano en ningun lado: lo genera la PC y viaja al
//! telefono por la sesion ya autenticada (`RelayOffer`). Ver
//! `docs/ideas/conexion-fuera-de-la-lan.md`.

use crate::frb_generated::StreamSink;

/// En que anda el tunel, para poder mostrarlo.
///
/// Existe porque "aparcado esperando" y "el VPS no contesta" se ven
/// exactamente igual desde la pantalla --sin conexion-- y la diferencia es
/// justo la que el usuario necesita para saber si tiene que hacer algo.
#[derive(Debug, Clone)]
pub enum RelayStatus {
    /// Aparcado en el relay. El telefono ya puede llegar.
    Parked,
    /// Llego un telefono y la sesion arranco.
    Matched,
    /// El intento fallo; se reintenta con espera creciente.
    Failed { reason: String },
    /// Apagado a pedido.
    Stopped,
}

impl From<nexodeck_transport::server::RelayStatus> for RelayStatus {
    fn from(s: nexodeck_transport::server::RelayStatus) -> Self {
        use nexodeck_transport::server::RelayStatus as S;
        match s {
            S::Parked => RelayStatus::Parked,
            S::Matched => RelayStatus::Matched,
            S::Failed(reason) => RelayStatus::Failed { reason },
            S::Stopped => RelayStatus::Stopped,
        }
    }
}

/// Rol PC: genera el secreto del tunel. 32 bytes aleatorios en hex.
///
/// Se genera una sola vez y se guarda; rotarlo obliga a que el telefono se
/// vuelva a conectar en la LAN para recibir el nuevo.
pub fn generate_relay_token() -> String {
    nexodeck_transport::pairing::generate_relay_token()
}

/// Rol PC: enciende el tunel.
///
/// **No reemplaza nada.** El host sigue escuchando en la LAN igual que
/// antes; esto agrega un camino mas -- no espera a que el relay conteste, eso
/// se ve en `watch_relay_status` y se reintenta solo, no como un error de
/// esta llamada.
///
/// **`async` por obligacion, igual que `start_captured_command`**: adentro,
/// `serve_via_relay` hace `tokio::spawn`, que panickea con "there is no
/// reactor running" si no corre dentro del runtime de tokio. Una funcion
/// sincrona del bridge no lo tiene -- frb solo entra al runtime para las
/// `async fn`. Encontrado en vivo: el switch de "Tunel remoto" tiraba
/// exactamente ese panic al prenderlo por primera vez.
pub async fn start_relay_tunnel(
    host: String,
    port: u16,
    token_hex: String,
) -> Result<(), String> {
    let token = nexodeck_relay::hello::token_from_hex(&token_hex)
        .ok_or_else(|| "el token del tunel tiene que ser 64 caracteres hex".to_string())?;
    let transport = nexodeck_transport::server::host()
        .ok_or_else(|| "el host de transporte no esta iniciado".to_string())?;
    transport.serve_via_relay(nexodeck_transport::server::RelayEndpoint { host, port, token });
    Ok(())
}

/// Rol PC: apaga el tunel. La LAN sigue funcionando igual.
pub fn stop_relay_tunnel() -> Result<(), String> {
    let transport = nexodeck_transport::server::host()
        .ok_or_else(|| "el host de transporte no esta iniciado".to_string())?;
    transport.stop_relay();
    Ok(())
}

pub async fn watch_relay_status(sink: StreamSink<RelayStatus>) {
    let Some(host) = nexodeck_transport::server::host() else {
        return;
    };
    let mut rx = host.relay_events();
    while let Ok(status) = rx.recv().await {
        if sink.add(RelayStatus::from(status)).is_err() {
            break;
        }
    }
}

/// Rol telefono: reconexion a traves del tunel.
///
/// Se usa **despues** de que mDNS y la direccion manual fallen. El
/// `pinned_fingerprint` es el mismo de siempre: que el camino cambie no
/// relaja la confianza, y si la PC del otro lado no presenta el certificado
/// esperado el handshake falla igual que en la LAN.
pub async fn reconnect_via_relay(
    device_id: String,
    host: String,
    port: u16,
    token_hex: String,
    pinned_fingerprint: String,
) -> Result<(), String> {
    let token = nexodeck_relay::hello::token_from_hex(&token_hex)
        .ok_or_else(|| "el token del tunel tiene que ser 64 caracteres hex".to_string())?;
    nexodeck_transport::client::client()
        .reconnect_via_relay(
            device_id,
            nexodeck_transport::server::RelayEndpoint { host, port, token },
            pinned_fingerprint,
        )
        .await
        .map_err(|e| e.to_string())
}
