//! El servidor del relay: acepta conexiones, empareja por token y empalma.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use socket2::{SockRef, TcpKeepalive};
use tokio::io::{split, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::oneshot;

use crate::hello::{self, status, Role, HELLO_LEN, TOKEN_LEN};

/// Cuanto se espera el saludo antes de cortar. Quien se conecta y no dice
/// nada no puede quedarse ocupando una ranura.
const HELLO_TIMEOUT: Duration = Duration::from_secs(10);

/// Cuanto puede quedar un byte sin acusar antes de dar el peer por muerto.
///
/// Es lo que convierte una muerte EN SILENCIO (el telefono cambia de red y su
/// socket deja de existir sin FIN ni RST) en un error, en vez de esperar el
/// `tcp_retries2` del kernel --unos 15 minutos-- mientras el buffer de envio
/// crece sin limite y el empalme no termina.
const DEAD_PEER_AFTER: Duration = Duration::from_secs(20);

/// Cada cuanto se le manda un byte al host aparcado.
///
/// No es opcional: un TCP inactivo a traves de NAT se cae solo a los pocos
/// minutos, y la PC puede estar aparcada horas sin que nadie la llame. El
/// byte sirve ademas para detectar que la PC se fue y limpiar su registro.
const KEEPALIVE_EVERY: Duration = Duration::from_secs(30);

pub struct RelayConfig {
    /// Si esta, solo estos tokens pueden usar el relay. Conviene usarla
    /// cuando el relay vive en un servidor compartido: sin lista, cualquiera
    /// que conozca la direccion puede usarlo de punto de encuentro para su
    /// propio trafico.
    pub allowed_tokens: Option<HashSet<[u8; TOKEN_LEN]>>,
    /// Tope de conexiones simultaneas, para que el relay no pueda comerse
    /// los descriptores del servidor que lo aloja.
    pub max_connections: usize,
    /// Cada cuanto se le manda un byte al host aparcado. Configurable solo
    /// para poder testearlo: con los 30 s de produccion, una prueba del
    /// keepalive tardaria mas que toda la suite.
    pub keepalive_every: Duration,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            allowed_tokens: None,
            max_connections: 64,
            keepalive_every: KEEPALIVE_EVERY,
        }
    }
}

/// Una PC aparcada, con un id propio.
///
/// El id existe para que el cierre de ESTE park no borre el de otro park
/// posterior con el mismo token. La PC reconecta mientras el socket viejo
/// termina de morir, y sin el id el park nuevo quedaba registrado en su
/// socket pero ausente del mapa: los clientes recibian `ERR_NO_HOST` y la
/// unica salida era reiniciar el relay. Ver `Registry::remove_if_mine`.
struct Parked {
    id: u64,
    tx: oneshot::Sender<TcpStream>,
}

/// El mapa de hosts aparcados, por token, con un contador de ids.
#[derive(Default)]
struct Registry {
    hosts: Mutex<HashMap<[u8; TOKEN_LEN], Parked>>,
    next_id: AtomicU64,
}

impl Registry {
    /// Registra un park. `None` si ya hay uno con ese token.
    fn park(&self, token: [u8; TOKEN_LEN], tx: oneshot::Sender<TcpStream>) -> Option<u64> {
        let mut hosts = self.hosts.lock().unwrap();
        if hosts.contains_key(&token) {
            return None;
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        hosts.insert(token, Parked { id, tx });
        Some(id)
    }

    /// Quita el park SOLO si el que hay sigue siendo el nuestro.
    ///
    /// Incondicional, el cierre de un park viejo borraria el de la
    /// reconexion nueva con el mismo token y dejaria a la PC aparcada pero
    /// invisible.
    fn remove_if_mine(&self, token: &[u8; TOKEN_LEN], id: u64) {
        let mut hosts = self.hosts.lock().unwrap();
        if hosts.get(token).map(|p| p.id) == Some(id) {
            hosts.remove(token);
        }
    }

    /// Saca el park de ese token para empalmar un cliente. `None` si no hay.
    fn take(&self, token: &[u8; TOKEN_LEN]) -> Option<oneshot::Sender<TcpStream>> {
        self.hosts.lock().unwrap().remove(token).map(|p| p.tx)
    }
}

/// Ajusta el socket aceptado para detectar un peer que murio EN SILENCIO.
///
/// Sin esto, cuando el telefono cambia de WiFi a datos su conexion al relay
/// deja de existir sin FIN ni RST: el kernel no lo sabe, el relay sigue
/// escribiendole el trafico de la PC, `copy_bidirectional` no termina nunca,
/// la PC queda encerrada en esa sesion y **no vuelve a aparcarse**. El relay
/// pasa entonces a no tener host y todos los intentos nuevos reciben
/// `ERR_NO_HOST` hasta reiniciarlo. Se vio en vivo: el backlog de envio
/// creciendo a decenas de KB con la PC "conectada" y el telefono sin poder
/// entrar.
///
/// `TCP_USER_TIMEOUT` cubre el caso con datos en vuelo --el normal, la PC
/// manda un snapshot cada segundo--; el keepalive cubre la conexion ociosa.
/// Los dos son best-effort: una plataforma que no los soporte no rompe nada.
fn configure_dead_peer_detection(stream: &TcpStream) {
    let sock = SockRef::from(stream);
    #[cfg(any(target_os = "linux", target_os = "android", target_os = "fuchsia"))]
    let _ = sock.set_tcp_user_timeout(Some(DEAD_PEER_AFTER));
    let _ = sock.set_tcp_keepalive(
        &TcpKeepalive::new()
            .with_time(DEAD_PEER_AFTER)
            .with_interval(Duration::from_secs(5))
            .with_retries(3),
    );
}

pub async fn serve(listener: TcpListener, config: RelayConfig) {
    let registry = Arc::new(Registry::default());
    let config = Arc::new(config);
    let permits = Arc::new(tokio::sync::Semaphore::new(config.max_connections));

    loop {
        let (stream, _peer) = match listener.accept().await {
            Ok(v) => v,
            Err(_) => continue,
        };
        configure_dead_peer_detection(&stream);
        // `try_acquire_owned` y no `acquire`: con el tope alcanzado se
        // rechaza al que llega en vez de encolarlo, que es lo unico honesto
        // -- una cola invisible se ve igual que un cuelgue.
        let permit = match permits.clone().try_acquire_owned() {
            Ok(p) => p,
            Err(_) => continue,
        };
        let registry = registry.clone();
        let config = config.clone();
        tokio::spawn(async move {
            let _permit = permit;
            let _ = handle(stream, registry, config).await;
        });
    }
}

async fn handle(
    mut stream: TcpStream,
    registry: Arc<Registry>,
    config: Arc<RelayConfig>,
) -> std::io::Result<()> {
    let mut buf = [0u8; HELLO_LEN];
    match tokio::time::timeout(HELLO_TIMEOUT, stream.read_exact(&mut buf)).await {
        Ok(Ok(_)) => {}
        _ => return Ok(()),
    }

    let (role, token) = match hello::decode(&buf) {
        Ok(v) => v,
        Err(_) => {
            let _ = stream.write_all(&[status::ERR_BAD_HELLO]).await;
            return Ok(());
        }
    };

    if let Some(allowed) = &config.allowed_tokens {
        if !allowed.contains(&token) {
            let _ = stream.write_all(&[status::ERR_TOKEN_REJECTED]).await;
            return Ok(());
        }
    }

    match role {
        Role::Host => park_host(stream, token, registry, config.keepalive_every).await,
        Role::Client => join_host(stream, token, registry).await,
    }
}

/// La PC: se registra y espera a que alguien la llame.
async fn park_host(
    mut stream: TcpStream,
    token: [u8; TOKEN_LEN],
    registry: Arc<Registry>,
    keepalive_every: Duration,
) -> std::io::Result<()> {
    let (tx, mut rx) = oneshot::channel::<TcpStream>();
    let Some(my_id) = registry.park(token, tx) else {
        let _ = stream.write_all(&[status::ERR_HOST_TAKEN]).await;
        return Ok(());
    };

    let result = wait_for_client(stream, &mut rx, keepalive_every).await;
    // Solo borra si sigue siendo NUESTRO park: la PC puede haber reconectado
    // ya y haber registrado uno nuevo con el mismo token, y borrar ese dejaria
    // a la PC aparcada pero invisible para los clientes.
    registry.remove_if_mine(&token, my_id);

    let Some((mut stream, mut client)) = result else {
        return Ok(());
    };

    // Los dos avisos salen de aca, antes del empalme, para que no exista una
    // ventana en la que uno ya este mandando TLS mientras el otro todavia
    // espera su byte de estado.
    stream.write_all(&[status::HOST_MATCHED]).await?;
    client.write_all(&[status::MATCHED]).await?;

    // De aca en adelante el relay no vuelve a escribir un byte propio.
    let _ = tokio::io::copy_bidirectional(&mut stream, &mut client).await;
    Ok(())
}

/// Como termino la espera: con un cliente empalmado o porque la PC se fue.
enum Espera {
    Cliente(TcpStream),
    HostIdo,
}

/// Espera al cliente mandando keepalives. `None` si la PC se fue primero.
///
/// **Lee tambien del socket del host.** Un host que cierra (FIN) no rompe la
/// escritura de keepalives, asi que mirando solo esa escritura no habia forma
/// de enterarse a tiempo: el socket quedaba aparcado de mas y, al morir por
/// fin, su cierre podia borrar el registro de la reconexion nueva con el mismo
/// token. Cualquier byte antes de `HOST_MATCHED` es una violacion del protocolo
/// --la PC no habla hasta recibir el aviso-- y se corta igual.
async fn wait_for_client<T>(
    stream: T,
    rx: &mut oneshot::Receiver<TcpStream>,
    keepalive_every: Duration,
) -> Option<(T, TcpStream)>
where
    T: AsyncRead + AsyncWrite + Unpin,
{
    let (mut rd, mut wr) = split(stream);
    if wr.write_all(&[status::REGISTERED]).await.is_err() {
        return None;
    }

    let mut tick = tokio::time::interval(keepalive_every);
    tick.tick().await; // el primer tick de `interval` es inmediato
    let mut buf = [0u8; 1];

    // El `select!` solo decide; separar el desenlace de la reunion del socket
    // deja que los futuros se suelten antes de mover `rd`/`wr`.
    let desenlace = loop {
        tokio::select! {
            got = &mut *rx => {
                break match got {
                    Ok(client) => Espera::Cliente(client),
                    Err(_) => Espera::HostIdo,
                };
            }
            _ = tick.tick() => {
                // Un error aca es COMO se detecta que la PC se desconecto:
                // sin escribirle nada, un host muerto quedaria registrado
                // para siempre y su token inutilizable.
                if wr.write_all(&[status::KEEPALIVE]).await.is_err() {
                    break Espera::HostIdo;
                }
            }
            _ = rd.read(&mut buf) => {
                // EOF (0), error, o un byte antes de tiempo: la PC se fue o
                // no respeta el protocolo. En los dos casos se libera el token.
                break Espera::HostIdo;
            }
        }
    };

    match desenlace {
        // El socket de la PC vuelve entero: `copy_bidirectional` necesita leer
        // y escribir sobre el mismo stream.
        Espera::Cliente(client) => Some((rd.unsplit(wr), client)),
        Espera::HostIdo => None,
    }
}

/// El telefono: busca un host ya registrado con su token.
async fn join_host(
    mut stream: TcpStream,
    token: [u8; TOKEN_LEN],
    registry: Arc<Registry>,
) -> std::io::Result<()> {
    let tx = match registry.take(&token) {
        Some(tx) => tx,
        None => {
            let _ = stream.write_all(&[status::ERR_NO_HOST]).await;
            return Ok(());
        }
    };
    // Si el host murio entre su registro y ahora, el envio falla y hay que
    // decirlo: el telefono muestra "la PC no esta conectada al relay" en vez
    // de quedarse esperando un TLS que no va a llegar nunca.
    if let Err(mut returned) = tx.send(stream) {
        let _ = returned.write_all(&[status::ERR_NO_HOST]).await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOKEN: [u8; TOKEN_LEN] = [9u8; TOKEN_LEN];

    /// Un `Sender` suelto: el `Receiver` se descarta, pero estos tests solo
    /// miran el mapa, nunca envian por el canal.
    fn tx() -> oneshot::Sender<TcpStream> {
        let (tx, _rx) = oneshot::channel();
        tx
    }

    /// La regresion que esto arregla: el cierre tardio de un park viejo no
    /// puede llevarse por delante el de la reconexion nueva con el mismo
    /// token. Antes el `remove` era incondicional y la PC quedaba aparcada
    /// pero invisible (clientes con `ERR_NO_HOST`) hasta reiniciar el relay.
    #[test]
    fn un_park_viejo_no_borra_al_nuevo_con_el_mismo_token() {
        let registry = Registry::default();
        let id_viejo = registry.park(TOKEN, tx()).unwrap();
        // El cliente se lleva el park viejo (lo saca `take`)...
        assert!(registry.take(&TOKEN).is_some());
        // ...y la PC reconecta: park nuevo con el mismo token.
        let id_nuevo = registry.park(TOKEN, tx()).unwrap();
        assert_ne!(id_viejo, id_nuevo);

        // El cierre tardio del park viejo NO puede borrar el nuevo.
        registry.remove_if_mine(&TOKEN, id_viejo);
        assert!(registry.hosts.lock().unwrap().contains_key(&TOKEN));

        // Y el cierre del park nuevo si lo borra.
        registry.remove_if_mine(&TOKEN, id_nuevo);
        assert!(!registry.hosts.lock().unwrap().contains_key(&TOKEN));
    }

    #[test]
    fn un_segundo_park_con_el_mismo_token_no_entra() {
        let registry = Registry::default();
        assert!(registry.park(TOKEN, tx()).is_some());
        assert!(registry.park(TOKEN, tx()).is_none());
    }
}
