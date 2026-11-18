use std::net::{IpAddr, Ipv4Addr};
use std::time::Duration;

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};

use crate::error::{Result, TransportError};

pub const SERVICE_TYPE: &str = "_nexodeck._tcp.local.";

fn sanitize_instance_name(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '-' })
        .collect();
    if cleaned.is_empty() {
        "nexodeck".to_string()
    } else {
        cleaned
    }
}

/// Mantiene vivo el daemon de mDNS mientras el host anuncie el servicio --
/// al dropear esto, el registro se retira de la red. El campo nunca se lee
/// directamente: su unico proposito es el drop (RAII).
#[allow(dead_code)]
pub struct Advertiser(ServiceDaemon);

pub fn advertise(port: u16, device_name: &str) -> Result<Advertiser> {
    let daemon = ServiceDaemon::new().map_err(|e| TransportError::Discovery(e.to_string()))?;
    let instance_name = sanitize_instance_name(device_name);
    let host_name = format!("{instance_name}.local.");

    let service = ServiceInfo::new(SERVICE_TYPE, &instance_name, &host_name, "", port, None)
        .map_err(|e| TransportError::Discovery(e.to_string()))?
        .enable_addr_auto();

    daemon
        .register(service)
        .map_err(|e| TransportError::Discovery(e.to_string()))?;

    Ok(Advertiser(daemon))
}

#[derive(Debug, Clone)]
pub struct DiscoveredHost {
    pub name: String,
    pub host: String,
    pub port: u16,
}

/// Explora la red buscando hosts NexoDeck anunciados por `advertise`. El
/// fingerprint del certificado TLS **no** viaja por aca -- mDNS es
/// broadcast sin autenticar y por lo tanto falsificable; el fingerprint
/// real solo se establece durante el handshake TLS (ver `tls.rs`).
pub fn browse() -> Result<tokio::sync::mpsc::Receiver<DiscoveredHost>> {
    let daemon = ServiceDaemon::new().map_err(|e| TransportError::Discovery(e.to_string()))?;
    let receiver = daemon
        .browse(SERVICE_TYPE)
        .map_err(|e| TransportError::Discovery(e.to_string()))?;
    let (tx, rx) = tokio::sync::mpsc::channel(16);

    tokio::spawn(async move {
        // El daemon debe seguir vivo mientras se navega -- se mueve a esta
        // tarea y se dropea recien cuando el canal de eventos se cierra.
        let _daemon = daemon;
        while let Ok(event) = receiver.recv_async().await {
            if let ServiceEvent::ServiceResolved(info) = event {
                // Una PC tipica anuncia VARIAS IPv4 y solo una sirve: en el
                // equipo principal hay 6 --la de la LAN, la del switch
                // virtual de Hyper-V (172.29.x) y cuatro APIPA (169.254.x)
                // de adaptadores sin red--. `get_addresses()` es un HashSet
                // sin orden garantizado, asi que tomar la primera IPv4
                // hacia que el telefono se conectara **a veces si y a veces
                // no**, segun con cual se quedara ese arranque: contra la
                // de Hyper-V se queda reintentando para siempre, sin ningun
                // error visible. Verificado en vivo (el telefono alcanza
                // 192.168.1.8 y no 172.29.160.1).
                //
                // Las IPv6 quedan fuera aparte: las link-local (fe80::...)
                // no son conectables sin el scope id de la interfaz, que
                // `ServiceInfo` no expone.
                let port = info.get_port();
                let candidates = rank_ipv4_candidates(info.get_addresses().iter().copied());
                let Some(addr) = first_reachable(&candidates, port).await else {
                    continue;
                };
                let discovered = DiscoveredHost {
                    name: info.get_fullname().to_string(),
                    host: addr.to_string(),
                    port,
                };
                if tx.send(discovered).await.is_err() {
                    break;
                }
            }
        }
    });

    Ok(rx)
}

/// Cuanto se espera por cada candidata antes de pasar a la siguiente.
///
/// Corto a proposito: son direcciones de la LAN, y una que responde lo hace
/// en milisegundos. Lo que se esta descartando es justo el caso que no
/// responde nunca (una IP de un adaptador virtual), y ahi lo unico que
/// importa es no quedarse esperando.
const PROBE_TIMEOUT: Duration = Duration::from_millis(400);

/// Las IPv4 utilizables de un anuncio, mejor primero.
///
/// Descarta lo que **nunca** puede servir --loopback (solo vale dentro de
/// esa maquina), link-local/APIPA (169.254.x, adaptadores sin red) y
/// unspecified-- y despues ordena por que tan probable es que sea la LAN de
/// verdad: primero los rangos domesticos (192.168.x y 10.x), despues el
/// resto de las privadas --ahi caen los switches virtuales de Hyper-V, WSL y
/// Docker, en 172.16/12-- y al final cualquier otra.
///
/// El orden es una preferencia, no una garantia: quien decide de verdad es
/// [`first_reachable`], que prueba el puerto. Pero un buen orden hace que en
/// el caso normal acierte la primera y no se pague ninguna espera.
pub fn rank_ipv4_candidates(addresses: impl Iterator<Item = IpAddr>) -> Vec<Ipv4Addr> {
    let mut candidates: Vec<Ipv4Addr> = addresses
        .filter_map(|addr| match addr {
            IpAddr::V4(v4) => Some(v4),
            IpAddr::V6(_) => None,
        })
        .filter(|v4| !v4.is_loopback() && !v4.is_link_local() && !v4.is_unspecified())
        .collect();

    candidates.sort_by_key(|v4| (address_rank(v4), v4.octets()));
    candidates.dedup();
    candidates
}

fn address_rank(addr: &Ipv4Addr) -> u8 {
    let [a, b, ..] = addr.octets();
    match (a, b) {
        (192, 168) => 0,
        (10, _) => 0,
        (172, 16..=31) => 1,
        _ => 2,
    }
}

/// La primera candidata que acepta una conexion TCP en `port`.
///
/// Es lo que hace que la eleccion sea correcta y no una apuesta: la unica
/// prueba de que una IP sirve es que del otro lado conteste. Sin esto, una
/// heuristica de rangos no alcanza -- la IP de Hyper-V (172.29.x) es una
/// privada perfectamente legitima y no hay forma limpia de reconocerla.
async fn first_reachable(candidates: &[Ipv4Addr], port: u16) -> Option<Ipv4Addr> {
    for addr in candidates {
        let connected = tokio::time::timeout(
            PROBE_TIMEOUT,
            tokio::net::TcpStream::connect((*addr, port)),
        )
        .await;
        if matches!(connected, Ok(Ok(_))) {
            return Some(*addr);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(text: &str) -> IpAddr {
        text.parse().expect("ip invalida en el test")
    }

    /// El caso real que rompia la conexion del telefono: la PC anuncia seis
    /// direcciones y solo una sirve.
    #[test]
    fn descarta_las_apipa_y_deja_primero_la_lan() {
        let anunciadas = [
            ip("172.29.160.1"),   // switch virtual de Hyper-V
            ip("169.254.54.187"), // Bluetooth sin red
            ip("169.254.121.212"),
            ip("192.168.1.8"),    // la LAN de verdad
            ip("169.254.48.141"), // Wi-Fi sin IP valida
            ip("127.0.0.1"),
        ];

        let ranked = rank_ipv4_candidates(anunciadas.into_iter());

        // Las APIPA y loopback no pueden servir nunca: quedan afuera.
        assert_eq!(ranked.len(), 2);
        // Y la de la LAN se prueba ANTES que la del adaptador virtual.
        assert_eq!(ranked[0].to_string(), "192.168.1.8");
        assert_eq!(ranked[1].to_string(), "172.29.160.1");
    }

    #[test]
    fn las_ipv6_no_entran() {
        // Las link-local (fe80::) no son conectables sin el scope id de la
        // interfaz, que `ServiceInfo` no expone.
        let ranked = rank_ipv4_candidates(
            [ip("fe80::1"), ip("10.0.0.5")].into_iter(),
        );
        assert_eq!(ranked.len(), 1);
        assert_eq!(ranked[0].to_string(), "10.0.0.5");
    }

    #[test]
    fn el_orden_es_estable_entre_llamadas() {
        // `get_addresses()` es un HashSet: si el orden de salida dependiera
        // del de entrada, el telefono elegiria distinto en cada arranque,
        // que es exactamente el bug que esto viene a cerrar.
        let a = rank_ipv4_candidates([ip("10.0.0.5"), ip("192.168.1.8")].into_iter());
        let b = rank_ipv4_candidates([ip("192.168.1.8"), ip("10.0.0.5")].into_iter());
        assert_eq!(a, b);
    }

    #[test]
    fn sin_candidatas_utiles_no_devuelve_nada() {
        let ranked = rank_ipv4_candidates([ip("169.254.1.1"), ip("127.0.0.1")].into_iter());
        assert!(ranked.is_empty());
    }
}
