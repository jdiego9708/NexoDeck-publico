use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio_rustls::TlsAcceptor;
use uuid::Uuid;

use nexodeck_protocol::{DevicePlatformWire, MessageV1};

use crate::discovery::{self, Advertiser};
use crate::error::{Result, TransportError};
use crate::pairing::{PairingState, generate_pin};
use crate::relay;
use crate::session::{SessionTransport, WsSession};
use crate::tls::{self, ServerIdentity};

pub const DEFAULT_PORT: u16 = 58643;
const PAIRING_STEP_TIMEOUT: Duration = Duration::from_secs(120);

/// Tras una espera a demanda que vencio sin que nadie armara el PIN, los
/// `PairHello` sin armar se rechazan al instante durante este tiempo, sin
/// volver a avisar. Es el freno contra un dispositivo desconocido de la LAN
/// que reintenta en bucle: sin esto, cada intento le abriria la ventana de
/// NexoDeck al usuario. Ver `wait_for_on_demand_arming`.
const ON_DEMAND_COOLDOWN: Duration = Duration::from_secs(60);

#[derive(Debug, Clone)]
pub enum PairingEvent {
    DeviceRequestedPairing {
        device_name: String,
        platform: DevicePlatformWire,
    },
    PairingSucceeded {
        device_id: String,
        cert_fingerprint: String,
    },
    PairingRejected {
        reason: String,
    },
    /// Llego un `PairHello` sin el PIN armado y la PC lo esta reteniendo
    /// (ver `TransportHost::set_on_demand_pairing_grace`). Quien escuche tiene
    /// que armar el pairing -- mostrando el PIN a un humano -- antes de que
    /// venza la gracia, o el telefono recibe el rechazo de siempre.
    ///
    /// Evento local, no un mensaje del protocolo: no viaja por el cable.
    PairingRequestedWhileDisarmed {
        device_name: String,
        platform: DevicePlatformWire,
    },
}

#[derive(Debug, Clone)]
pub enum ConnectionEvent {
    DeviceConnected { device_id: String },
    DeviceDisconnected { device_id: String },
    ActionExecutionRequested {
        device_id: String,
        action_id: String,
        /// Valores de los `{{placeholders}}` cargados en el dispositivo
        /// remoto. Vacio si la accion no tiene parametros.
        params: Vec<nexodeck_protocol::ActionParamValue>,
    },
    /// El telefono escribio esto en el chat del asistente.
    AiMessageRequested {
        device_id: String,
        text: String,
    },
    /// El telefono pide activar el asistente en la PC.
    AiActivateRequested { device_id: String },
    /// El telefono pide guardar un borrador como boton nuevo. Los comandos
    /// de cada paso ya vienen resueltos -- ver `MessageV1::AiApplyDraft`.
    AiApplyDraftRequested {
        device_id: String,
        draft: nexodeck_protocol::AiDraftWire,
    },
    /// El telefono pide correr un borrador ahora, en vivo.
    AiRunDraftRequested {
        device_id: String,
        draft: nexodeck_protocol::AiDraftWire,
    },
    /// El telefono pide que la IA explique un proceso -- ver
    /// `MessageV1::AiAskAboutProcess`.
    AiAskAboutProcessRequested {
        device_id: String,
        group: nexodeck_protocol::ProcessGroupWire,
    },
}

struct SessionHandle {
    outbound: mpsc::UnboundedSender<MessageV1>,
    close: mpsc::UnboundedSender<()>,
}

struct PendingPairing {
    decision_tx: oneshot::Sender<bool>,
}

struct HostState {
    pairing: PairingState,
    pending: Option<PendingPairing>,
    authorized: HashMap<String, bool>,
    sessions: HashMap<String, SessionHandle>,
    /// Hay una sesion reteniendo su `PairHello` a la espera del PIN. Una sola
    /// a la vez: con dos, la segunda reabriria el aviso por un pedido que ya
    /// esta en pantalla.
    on_demand_waiting: bool,
    /// Hasta cuando rige `ON_DEMAND_COOLDOWN`.
    on_demand_cooldown_until: Option<Instant>,
}

pub struct HostConfig {
    pub device_name: String,
    pub port: u16,
}

pub struct TransportHost {
    state: Mutex<HostState>,
    identity: ServerIdentity,
    device_name: String,
    port: u16,
    pairing_tx: broadcast::Sender<PairingEvent>,
    connection_tx: broadcast::Sender<ConnectionEvent>,
    relay_tx: broadcast::Sender<RelayStatus>,
    /// El tunel configurado, si hay. Se guarda ademas de pasarse a la tarea
    /// porque hace falta en OTRO lugar: cada sesion nueva --incluidas las
    /// que entran por la LAN-- le ofrece estos datos al telefono.
    relay_endpoint: Mutex<Option<RelayEndpoint>>,
    relay_task: Mutex<Option<tokio::task::AbortHandle>>,
    /// Despierta a la sesion que retiene un `PairHello` cuando se arma el PIN.
    armed_notify: tokio::sync::Notify,
    /// Cuanto se retiene un `PairHello` sin armar. `None` (el default) es el
    /// rechazo inmediato de siempre.
    on_demand_grace: Mutex<Option<Duration>>,
    /// La boveda de notas, si la FFI la engancho. Va por aca y no por una
    /// dependencia porque este crate tambien se compila para Android, donde
    /// `nexodeck-docs` no entra -- ver `notes.rs`.
    notes_vault: Mutex<Option<Arc<dyn crate::notes::NotesVault>>>,
    _advertiser: Advertiser,
}

/// A donde marcar para aparcarse en el tunel.
#[derive(Debug, Clone)]
pub struct RelayEndpoint {
    pub host: String,
    pub port: u16,
    /// Secreto compartido con el telefono. No se escribe a mano: la PC lo
    /// genera y viaja por la sesion ya autenticada de la LAN.
    pub token: [u8; nexodeck_relay::hello::TOKEN_LEN],
}

/// En que anda el tunel, para que la UI pueda decirlo.
///
/// Sin esto el usuario no tendria forma de distinguir "el tunel esta listo y
/// nadie llamo" de "el VPS no contesta", que se ven exactamente igual desde
/// la pantalla: sin conexion.
#[derive(Debug, Clone)]
pub enum RelayStatus {
    /// Aparcado y esperando. El telefono ya puede llegar.
    Parked,
    /// Llego un telefono; la sesion arranca.
    Matched,
    /// El intento fallo. Se reintenta con espera creciente.
    Failed(String),
    /// El tunel se apago a pedido.
    Stopped,
}



static HOST: OnceLock<Arc<TransportHost>> = OnceLock::new();

pub fn host() -> Option<Arc<TransportHost>> {
    HOST.get().cloned()
}

impl TransportHost {
    pub async fn start(config: HostConfig) -> Result<Arc<TransportHost>> {
        if let Some(existing) = HOST.get() {
            return Ok(existing.clone());
        }

        let identity = tls::load_or_generate_server_identity()?;
        let listener = TcpListener::bind(("0.0.0.0", config.port)).await?;
        let local_port = listener.local_addr()?.port();
        let advertiser = discovery::advertise(local_port, &config.device_name)?;

        let (pairing_tx, _) = broadcast::channel(32);
        let (connection_tx, _) = broadcast::channel(64);
        let (relay_tx, _) = broadcast::channel(16);

        let host = Arc::new(TransportHost {
            state: Mutex::new(HostState {
                pairing: PairingState::Idle,
                pending: None,
                authorized: HashMap::new(),
                sessions: HashMap::new(),
                on_demand_waiting: false,
                on_demand_cooldown_until: None,
            }),
            identity,
            device_name: config.device_name,
            port: local_port,
            pairing_tx,
            connection_tx,
            relay_tx,
            relay_endpoint: Mutex::new(None),
            relay_task: Mutex::new(None),
            armed_notify: tokio::sync::Notify::new(),
            on_demand_grace: Mutex::new(None),
            notes_vault: Mutex::new(None),
            _advertiser: advertiser,
        });

        let accept_host = host.clone();
        tokio::spawn(async move {
            accept_loop(accept_host, listener).await;
        });

        // Si otra tarea ya gano la carrera de inicializacion, usamos esa
        // instancia (`start` puede llamarse mas de una vez sin efecto).
        match HOST.set(host.clone()) {
            Ok(()) => Ok(host),
            Err(_) => Ok(HOST.get().expect("se acaba de setear").clone()),
        }
    }

    pub fn relay_events(&self) -> broadcast::Receiver<RelayStatus> {
        self.relay_tx.subscribe()
    }

    /// Enciende el tunel: mantiene una conexion aparcada en el relay y, cada
    /// vez que un telefono llega, atiende la sesion y se vuelve a aparcar.
    ///
    /// **El listener de la LAN sigue intacto.** El tunel es un camino
    /// ADICIONAL, no un reemplazo: en la red de casa el telefono sigue
    /// entrando por mDNS sin tocar el relay, y ese camino no cambia en nada.
    ///
    /// La conexion queda aparcada aunque no haya nadie del otro lado, y no
    /// puede ser de otra manera: la PC no tiene forma de saber en que red
    /// esta el telefono, asi que el punto de encuentro tiene que estar
    /// puesto ANTES de que haga falta.
    pub fn serve_via_relay(self: &Arc<Self>, endpoint: RelayEndpoint) {
        // Encender dos veces no puede dejar dos tareas aparcandose con el
        // mismo token: la segunda recibiria ERR_HOST_TAKEN de la primera y el
        // tunel entraria en un ciclo de reintentos contra si mismo.
        self.stop_relay();
        *self.relay_endpoint.lock().unwrap() = Some(endpoint.clone());
        let host = self.clone();
        let task = tokio::spawn(async move { relay_loop(host, endpoint).await });
        *self.relay_task.lock().unwrap() = Some(task.abort_handle());
    }

    /// Apaga el tunel. La PC sigue atendiendo la LAN exactamente igual.
    pub fn stop_relay(&self) {
        if let Some(task) = self.relay_task.lock().unwrap().take() {
            task.abort();
            let _ = self.relay_tx.send(RelayStatus::Stopped);
        }
        // Se limpia tambien el endpoint para que las sesiones nuevas dejen de
        // ofrecer un tunel que ya no existe -- si no, el telefono guardaria
        // una direccion muerta y la reintentaria para siempre.
        *self.relay_endpoint.lock().unwrap() = None;
    }

    pub fn cert_fingerprint(&self) -> String {
        self.identity.fingerprint_hex.clone()
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Emparejamiento a demanda: cuanto retener un `PairHello` que llega sin
    /// el PIN armado, en vez de rechazarlo en el acto.
    ///
    /// Existe para el modo sin interfaz de la PC: ahi nadie tiene la hoja de
    /// emparejar abierta, asi que un pedido del telefono se rechazaria siempre.
    /// Retenido, la PC avisa (`PairingEvent::PairingRequestedWhileDisarmed`),
    /// muestra el PIN y el mismo intento del telefono sigue adelante, sin que
    /// el usuario tenga que volver a tocar nada.
    ///
    /// **Tiene que quedar por debajo de lo que espera el telefono** (20 s en
    /// `PairingTimings.connectHandshake`): pasado eso el telefono ya se rindio y
    /// descartaria el PIN que le llegue tarde.
    pub fn set_on_demand_pairing_grace(&self, grace: Option<Duration>) {
        *self.on_demand_grace.lock().unwrap() = grace;
    }

    /// Engancha la boveda que resolvera las peticiones de notas del telefono.
    /// La llama la FFI al abrir el buzon; sin esto, se contesta `Failed`.
    pub fn set_notes_vault(&self, vault: Option<Arc<dyn crate::notes::NotesVault>>) {
        *self.notes_vault.lock().unwrap() = vault;
    }

    /// Avisa a todos los telefonos conectados de que la boveda cambio.
    ///
    /// **Solo el aviso, nunca el cambio**: cada telefono pide el manifiesto y
    /// compara contra su copia. Los que no esten conectados se enteran al
    /// reconectar, que es cuando piden el manifiesto igualmente.
    pub fn notify_notes_changed(&self) {
        let state = self.state.lock().unwrap();
        for session in state.sessions.values() {
            let _ = session.outbound.send(MessageV1::NotesChanged);
        }
    }

    pub fn arm_pairing(&self) -> Result<String> {
        let mut state = self.state.lock().unwrap();
        if state.pending.is_some() {
            return Err(TransportError::AlreadyPairing);
        }
        let pin = generate_pin();
        state.pairing = PairingState::Armed { pin: pin.clone() };
        drop(state);
        // Una sesion puede estar reteniendo su `PairHello` a la espera de
        // esto -- ver `wait_for_on_demand_arming`.
        self.armed_notify.notify_waiters();
        Ok(pin)
    }

    pub fn disarm_pairing(&self) {
        let mut state = self.state.lock().unwrap();
        if matches!(state.pairing, PairingState::Armed { .. }) {
            state.pairing = PairingState::Idle;
        }
    }

    pub fn confirm_pairing(&self, accept: bool) -> Result<()> {
        let pending = {
            let mut state = self.state.lock().unwrap();
            state.pending.take()
        };
        let Some(pending) = pending else {
            return Err(TransportError::NotConnected);
        };
        // El receptor puede haber expirado por timeout del lado de la
        // conexion -- no es un error, simplemente ya no hay nadie
        // escuchando la decision.
        let _ = pending.decision_tx.send(accept);
        Ok(())
    }

    pub fn pairing_events(&self) -> broadcast::Receiver<PairingEvent> {
        self.pairing_tx.subscribe()
    }

    pub fn connection_events(&self) -> broadcast::Receiver<ConnectionEvent> {
        self.connection_tx.subscribe()
    }

    pub fn sync_authorized_devices(&self, devices: Vec<(String, bool)>) {
        let mut state = self.state.lock().unwrap();
        state.authorized = devices.into_iter().collect();
    }

    pub fn set_device_authorized(&self, device_id: &str, authorized: bool) {
        let mut state = self.state.lock().unwrap();
        state.authorized.insert(device_id.to_string(), authorized);
        if !authorized {
            if let Some(session) = state.sessions.get(device_id) {
                let _ = session.close.send(());
            }
        }
    }

    pub fn send_action_ack(
        &self,
        device_id: &str,
        action_id: String,
        success: bool,
        error: Option<String>,
    ) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::ActionAck {
                action_id,
                success,
                error,
            })
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Como le va al comando que ese dispositivo mando ejecutar.
    ///
    /// Complementa a [`Self::send_action_ack`], que sigue significando "lo
    /// recibi y lo lance". Esto es lo que pasa despues: si termino bien, con
    /// que codigo y con el final de la salida.
    pub fn send_action_run_update(
        &self,
        device_id: &str,
        update: MessageV1,
    ) -> Result<()> {
        debug_assert!(matches!(update, MessageV1::ActionRunUpdate { .. }));
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(update)
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Empuja el catalogo de acciones disponibles hacia un dispositivo ya
    /// conectado -- ver el comentario en `MessageV1::ActionsCatalog` sobre
    /// por que esto no puede resolverse solo con el `action_id` local de
    /// Android.
    pub fn send_actions_catalog(
        &self,
        device_id: &str,
        actions: Vec<nexodeck_protocol::RemoteAction>,
    ) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::ActionsCatalog { actions })
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Empuja el estado completo de las suscripciones en vivo (SignalR o
    /// WebSocket crudo) hacia un dispositivo ya conectado -- ver el
    /// comentario en `MessageV1::HubSubscriptionsSnapshot`.
    pub fn send_hub_subscriptions_snapshot(
        &self,
        device_id: &str,
        subscriptions: Vec<nexodeck_protocol::HubSubscriptionWire>,
    ) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::HubSubscriptionsSnapshot { subscriptions })
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Empuja los nombres de las piezas hacia un dispositivo ya conectado --
    /// ver el comentario en `MessageV1::HostComponents`. Se llama una sola
    /// vez al conectar, no en cada snapshot.
    pub fn send_host_components(
        &self,
        device_id: &str,
        components: nexodeck_protocol::HostComponentsWire,
    ) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::HostComponents(components))
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Empuja si el asistente de IA esta habilitado y listo -- ver el
    /// comentario en `MessageV1::AiStatus`.
    pub fn send_ai_status(&self, device_id: &str, enabled: bool, ready: bool) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::AiStatus { enabled, ready })
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }

    /// Empuja un evento de la conversacion con el asistente -- ver el
    /// comentario en `MessageV1::AiChatEvent`.
    pub fn send_ai_chat_event(
        &self,
        device_id: &str,
        event: nexodeck_protocol::AiChatEventWire,
    ) -> Result<()> {
        let state = self.state.lock().unwrap();
        let session = state
            .sessions
            .get(device_id)
            .ok_or(TransportError::NotConnected)?;
        session
            .outbound
            .send(MessageV1::AiChatEvent(event))
            .map_err(|_| TransportError::NotConnected)?;
        Ok(())
    }
}

async fn accept_loop(host: Arc<TransportHost>, listener: TcpListener) {
    let acceptor = match tls::make_server_config(&host.identity) {
        Ok(cfg) => TlsAcceptor::from(Arc::new(cfg)),
        Err(e) => {
            log::error!("no se pudo preparar TLS del host: {e}");
            return;
        }
    };

    loop {
        let (tcp, addr) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                log::warn!("error aceptando conexion: {e}");
                continue;
            }
        };
        let host = host.clone();
        let acceptor = acceptor.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_connection(host, acceptor, tcp).await {
                log::warn!("conexion {addr} termino con error: {e}");
            }
        });
    }
}

/// De un TCP ya establecido a una sesion.
///
/// No sabe --ni le importa-- si el socket vino de la LAN o de un empalme del
/// relay: en los dos casos es un `TcpStream` sobre el que corre el mismo
/// TLS con el mismo certificado. Es lo que hace que el tunel no duplique ni
/// una linea del manejo de sesion.
async fn handle_connection(
    host: Arc<TransportHost>,
    acceptor: TlsAcceptor,
    tcp: TcpStream,
) -> Result<()> {
    let tls_stream = acceptor
        .accept(tcp)
        .await
        .map_err(|e| TransportError::Tls(e.to_string()))?;
    let ws = tokio_tungstenite::accept_async(tls_stream).await?;
    dispatch_first_message(host, WsSession(ws)).await
}

/// Lee el primer mensaje de una sesion recien conectada y decide entre
/// pairing nuevo o reconexion -- generico sobre el transporte para que el
/// futuro entry-point USB (Fase 5-C) lo reuse en vez de duplicar este
/// `match`.
pub(crate) async fn dispatch_first_message<T: SessionTransport>(
    host: Arc<TransportHost>,
    mut session: T,
) -> Result<()> {
    let first = tokio::time::timeout(PAIRING_STEP_TIMEOUT, session.recv())
        .await
        .map_err(|_| TransportError::Protocol("timeout esperando el primer mensaje".into()))??;

    let Some(first) = first else {
        return Ok(());
    };

    match first {
        MessageV1::PairHello {
            device_name,
            platform,
        } => handle_pairing(host, session, device_name, platform).await,
        MessageV1::Reconnect { device_id } => handle_reconnect(host, session, device_id).await,
        _ => {
            session
                .send(&MessageV1::PairRejected {
                    reason: "mensaje inicial invalido".into(),
                })
                .await?;
            Ok(())
        }
    }
}

async fn handle_pairing<T: SessionTransport>(
    host: Arc<TransportHost>,
    mut session: T,
    device_name: String,
    platform: DevicePlatformWire,
) -> Result<()> {
    let pin = match armed_pin(&host) {
        Some(pin) => Some(pin),
        None => wait_for_on_demand_arming(&host, &device_name, platform).await,
    };

    let Some(pin) = pin else {
        session
            .send(&MessageV1::PairRejected {
                reason: "la PC no esta aceptando dispositivos nuevos".into(),
            })
            .await?;
        return Ok(());
    };

    session
        .send(&MessageV1::PairPin {
            pin,
            host_name: host.device_name.clone(),
            host_platform: current_platform(),
        })
        .await?;

    let confirmed = matches!(
        tokio::time::timeout(PAIRING_STEP_TIMEOUT, session.recv()).await,
        Ok(Ok(Some(MessageV1::PairConfirm)))
    );
    if !confirmed {
        return Ok(());
    }

    let (decision_tx, decision_rx) = oneshot::channel();
    {
        let mut state = host.state.lock().unwrap();
        state.pending = Some(PendingPairing { decision_tx });
    }
    let _ = host.pairing_tx.send(PairingEvent::DeviceRequestedPairing {
        device_name: device_name.clone(),
        platform,
    });

    let accept = tokio::time::timeout(PAIRING_STEP_TIMEOUT, decision_rx)
        .await
        .unwrap_or(Ok(false))
        .unwrap_or(false);

    // Limpieza incondicional: si nunca se llamo a confirm_pairing (por
    // timeout de este lado), el estado pendiente quedaria huerfano y
    // bloquearia el proximo arm_pairing con AlreadyPairing.
    {
        let mut state = host.state.lock().unwrap();
        state.pending = None;
    }

    if !accept {
        let reason = "rechazado en la PC".to_string();
        session
            .send(&MessageV1::PairRejected {
                reason: reason.clone(),
            })
            .await?;
        let _ = host.pairing_tx.send(PairingEvent::PairingRejected { reason });
        return Ok(());
    }

    let device_id = Uuid::new_v4().to_string();
    let cert_fingerprint = host.identity.fingerprint_hex.clone();

    session
        .send(&MessageV1::PairAccepted {
            device_id: device_id.clone(),
            cert_fingerprint: cert_fingerprint.clone(),
        })
        .await?;

    {
        let mut state = host.state.lock().unwrap();
        state.authorized.insert(device_id.clone(), true);
        state.pairing = PairingState::Idle;
    }

    let _ = host.pairing_tx.send(PairingEvent::PairingSucceeded {
        device_id: device_id.clone(),
        cert_fingerprint,
    });

    run_session(host, session, device_id).await
}

fn armed_pin(host: &TransportHost) -> Option<String> {
    let state = host.state.lock().unwrap();
    match &state.pairing {
        PairingState::Armed { pin } => Some(pin.clone()),
        _ => None,
    }
}

/// Retiene un `PairHello` que llego sin el PIN armado, hasta que alguien lo
/// arme o venza la gracia. Devuelve el PIN, o `None` si hay que rechazar.
///
/// Rechaza sin esperar ni avisar cuando: no hay gracia configurada (el
/// comportamiento de siempre), ya hay otra sesion esperando, o rige el
/// enfriamiento de un intento anterior que vencio.
///
/// **El `Notified` se habilita ANTES de volver a mirar el estado.** Al reves
/// hay una carrera: si el PIN se arma justo entre mirar y empezar a esperar,
/// `notify_waiters` no encuentra a nadie registrado y la sesion duerme hasta
/// que vence la gracia, con el PIN ya en la pantalla de la PC.
async fn wait_for_on_demand_arming(
    host: &TransportHost,
    device_name: &str,
    platform: DevicePlatformWire,
) -> Option<String> {
    let grace = (*host.on_demand_grace.lock().unwrap())?;
    {
        let mut state = host.state.lock().unwrap();
        let cooling_down = state
            .on_demand_cooldown_until
            .is_some_and(|until| Instant::now() < until);
        if state.on_demand_waiting || cooling_down {
            return None;
        }
        state.on_demand_waiting = true;
    }

    let _ = host
        .pairing_tx
        .send(PairingEvent::PairingRequestedWhileDisarmed {
            device_name: device_name.to_owned(),
            platform,
        });

    let deadline = tokio::time::Instant::now() + grace;
    let pin = loop {
        let mut notified = std::pin::pin!(host.armed_notify.notified());
        notified.as_mut().enable();
        if let Some(pin) = armed_pin(host) {
            break Some(pin);
        }
        if tokio::time::timeout_at(deadline, notified).await.is_err() {
            break armed_pin(host);
        }
    };

    let mut state = host.state.lock().unwrap();
    state.on_demand_waiting = false;
    if pin.is_none() {
        state.on_demand_cooldown_until = Some(Instant::now() + ON_DEMAND_COOLDOWN);
    }
    pin
}

async fn handle_reconnect<T: SessionTransport>(
    host: Arc<TransportHost>,
    mut session: T,
    device_id: String,
) -> Result<()> {
    let authorized = {
        let state = host.state.lock().unwrap();
        state.authorized.get(&device_id).copied().unwrap_or(false)
    };

    if !authorized {
        // Se loguea porque este rechazo no emite ningun evento: es la unica
        // traza del lado PC de un telefono que reintenta conectar y no
        // puede. Sin esto, el host parece no estar recibiendo nada (pasaba
        // exactamente asi contra el telefono real: "sin eventos en 30s"
        // mientras el telefono reintentaba cada pocos segundos).
        log::warn!("rechazando reconexion de un dispositivo no autorizado: {device_id}");
        session
            .send(&MessageV1::ReconnectRejected {
                reason: "dispositivo no autorizado".into(),
            })
            .await?;
        return Ok(());
    }

    session.send(&MessageV1::ReconnectAccepted).await?;
    run_session(host, session, device_id).await
}

async fn run_session<T: SessionTransport>(
    host: Arc<TransportHost>,
    mut session: T,
    device_id: String,
) -> Result<()> {
    let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<MessageV1>();
    let (close_tx, mut close_rx) = mpsc::unbounded_channel::<()>();
    // Se guarda una copia propia para poder distinguir, al limpiar, si la
    // entrada en `sessions` todavia es la de ESTA tarea -- si el mismo
    // `device_id` reconecto mientras esta sesion vieja seguia cerrando, no
    // queremos borrar por error la entrada de la sesion nueva.
    let my_outbound = outbound_tx.clone();

    {
        let mut state = host.state.lock().unwrap();
        // Si ya habia una sesion viva para este device_id (por ejemplo, una
        // reconexion via USB que debe ganarle a una sesion WiFi que sigue
        // sana), `insert` reemplaza la entrada y DROPEA el `close_tx` viejo
        // -- eso alcanza por si solo para terminar la tarea vieja: su
        // `close_rx.recv()` en el `select!` de abajo matchea con el patron
        // `_` tanto `Some(())` como `None` (canal cerrado por el ultimo
        // sender dropeado), asi que rompe su loop sin necesitar un mensaje
        // explicito. Verificado con un test de integracion (ver
        // `tests/loopback_pairing.rs`) que confirma que la sesion vieja dejo
        // de tickear `HardwareSnapshot` apenas se reemplaza la entrada.
        state.sessions.insert(
            device_id.clone(),
            SessionHandle {
                outbound: outbound_tx,
                close: close_tx,
            },
        );
    }
    let _ = host.connection_tx.send(ConnectionEvent::DeviceConnected {
        device_id: device_id.clone(),
    });

    // El token del tunel se entrega AQUI, sobre la sesion ya autenticada, y
    // en toda sesion --tambien las de la LAN--. Ese es justamente el caso
    // que importa: estando los dos en casa, el telefono se lleva lo que
    // necesita para volver a encontrar la PC desde afuera. Reenviarlo en
    // cada conexion, y no solo la primera, es lo que hace que cambiar de
    // relay o rotar el token no obligue a re-emparejar.
    if let Some(endpoint) = host.relay_endpoint.lock().unwrap().clone() {
        let _ = my_outbound.send(MessageV1::RelayOffer {
            host: endpoint.host.clone(),
            port: endpoint.port,
            token_hex: nexodeck_relay::hello::token_to_hex(&endpoint.token),
        });
    }

    let mut monitor = nexodeck_hardware::HardwareMonitor::new();
    // El colector de procesos se crea **recien** cuando el telefono lo pide y
    // se suelta al cancelar: recorrer ~370 procesos cada dos segundos por si
    // acaso seria gastar CPU de la PC y bateria del telefono para nada. Misma
    // regla que en el escritorio, donde el panel cerrado no cuesta nada.
    let mut processes: Option<nexodeck_hardware::ProcessCollector> = None;
    let mut process_ticker = tokio::time::interval(
        nexodeck_hardware::processes::SAMPLE_INTERVAL,
    );
    // `interval_at` y no `interval`, por el mismo motivo que en
    // `nexodeck-ffi/src/api/hardware.rs`: el primer tick inmediato daria un
    // snapshot muestreado sobre una ventana de ~0 ms.
    let mut ticker = tokio::time::interval_at(
        tokio::time::Instant::now() + Duration::from_secs(1),
        Duration::from_secs(1),
    );

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                let snapshot = crate::hardware_snapshot_to_wire(monitor.snapshot());
                if session.send(&MessageV1::HardwareSnapshot(snapshot)).await.is_err() {
                    break;
                }
            }
            // Solo se muestrea si hay suscripcion viva: sin ella, esta rama
            // no puede completarse nunca y `select!` la ignora.
            _ = process_ticker.tick(), if processes.is_some() => {
                if let Some(collector) = processes.as_mut() {
                    let sample = crate::top_processes_to_wire(collector.sample());
                    if session.send(&MessageV1::TopProcesses(sample)).await.is_err() {
                        break;
                    }
                }
            }
            incoming = session.recv() => {
                match incoming {
                    Ok(Some(MessageV1::ExecuteAction { action_id, params })) => {
                        let _ = host.connection_tx.send(ConnectionEvent::ActionExecutionRequested {
                            device_id: device_id.clone(),
                            action_id,
                            params,
                        });
                    }
                    Ok(Some(MessageV1::WatchProcesses { enabled })) => {
                        if enabled {
                            if processes.is_none() {
                                processes = Some(Default::default());
                                // El ticker se reinicia con la suscripcion para
                                // que la primera muestra no llegue a los pocos
                                // milisegundos de abrir el panel, con el delta
                                // de CPU sin ventana.
                                process_ticker = tokio::time::interval_at(
                                    tokio::time::Instant::now()
                                        + nexodeck_hardware::processes::FIRST_SAMPLE_DELAY,
                                    nexodeck_hardware::processes::SAMPLE_INTERVAL,
                                );
                            }
                        } else {
                            processes = None;
                        }
                    }
                    Ok(Some(MessageV1::TerminateProcessGroup { name, pids })) => {
                        let reply = match nexodeck_hardware::processes::terminate_process_group(
                            &name, &pids,
                        ) {
                            Ok(report) => MessageV1::ProcessTerminated {
                                name,
                                killed: report.killed,
                                failed: report.failed,
                                rejected_reason: None,
                            },
                            // La PC rechaza entera la operacion con procesos
                            // criticos de Windows o consigo misma. El motivo
                            // viaja para que el telefono lo diga, en vez de
                            // quedarse mirando una fila que no desaparece.
                            Err(reason) => MessageV1::ProcessTerminated {
                                name,
                                killed: 0,
                                failed: 0,
                                rejected_reason: Some(reason),
                            },
                        };
                        if session.send(&reply).await.is_err() {
                            break;
                        }
                    }
                    Ok(Some(MessageV1::NotesRequest { request_id, request })) => {
                        // Leer la boveda entera o guardar una tanda es lento y
                        // sincrono: dentro del `select!` dejaria la sesion sin
                        // atender (ni snapshots, ni acks) mientras dura. Va a un
                        // hilo de bloqueo, y la respuesta sale por el canal de
                        // salida, que es quien serializa los envios.
                        let vault = host.notes_vault.lock().unwrap().clone();
                        let reply_tx = my_outbound.clone();
                        tokio::task::spawn_blocking(move || {
                            let response = match vault {
                                Some(vault) => crate::notes::resolve(vault.as_ref(), request),
                                None => crate::notes::no_vault(),
                            };
                            let _ = reply_tx.send(MessageV1::NotesResponse {
                                request_id,
                                response,
                            });
                        });
                    }
                    Ok(Some(MessageV1::AiSendMessage { text })) => {
                        let _ = host.connection_tx.send(ConnectionEvent::AiMessageRequested {
                            device_id: device_id.clone(),
                            text,
                        });
                    }
                    Ok(Some(MessageV1::AiActivate)) => {
                        let _ = host.connection_tx.send(ConnectionEvent::AiActivateRequested {
                            device_id: device_id.clone(),
                        });
                    }
                    Ok(Some(MessageV1::AiApplyDraft { draft })) => {
                        let _ = host.connection_tx.send(ConnectionEvent::AiApplyDraftRequested {
                            device_id: device_id.clone(),
                            draft,
                        });
                    }
                    Ok(Some(MessageV1::AiRunDraft { draft })) => {
                        let _ = host.connection_tx.send(ConnectionEvent::AiRunDraftRequested {
                            device_id: device_id.clone(),
                            draft,
                        });
                    }
                    Ok(Some(MessageV1::AiAskAboutProcess { group })) => {
                        let _ = host.connection_tx.send(ConnectionEvent::AiAskAboutProcessRequested {
                            device_id: device_id.clone(),
                            group,
                        });
                    }
                    Ok(Some(_)) => {}
                    Ok(None) | Err(_) => break,
                }
            }
            outgoing = outbound_rx.recv() => {
                match outgoing {
                    Some(msg) => {
                        if session.send(&msg).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                }
            }
            _ = close_rx.recv() => {
                break;
            }
        }
    }

    let still_mine = {
        let mut state = host.state.lock().unwrap();
        let still_mine = state
            .sessions
            .get(&device_id)
            .map(|s| s.outbound.same_channel(&my_outbound))
            .unwrap_or(false);
        if still_mine {
            state.sessions.remove(&device_id);
        }
        still_mine
    };
    // Igual que en client.rs: si esta sesion ya no es la activa para este
    // device_id (una reconexion mas nueva la reemplazo), no anunciar
    // DeviceDisconnected -- pisaria por error el DeviceConnected de la
    // sesion nueva.
    if still_mine {
        let _ = host
            .connection_tx
            .send(ConnectionEvent::DeviceDisconnected { device_id });
    }

    Ok(())
}

fn current_platform() -> DevicePlatformWire {
    #[cfg(target_os = "windows")]
    {
        DevicePlatformWire::Windows
    }
    #[cfg(target_os = "linux")]
    {
        DevicePlatformWire::Linux
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        DevicePlatformWire::Linux
    }
}

/// Reintento con espera creciente: el VPS puede estar reiniciandose, o la
/// PC puede haber perdido internet un momento. Sin tope, un relay caido
/// convertiria esto en un martilleo; con uno muy largo, volver del corte
/// tardaria minutos.
const RELAY_BACKOFF_MIN: Duration = Duration::from_secs(2);
const RELAY_BACKOFF_MAX: Duration = Duration::from_secs(60);

async fn relay_loop(host: Arc<TransportHost>, endpoint: RelayEndpoint) {
    let acceptor = match tls::make_server_config(&host.identity) {
        Ok(cfg) => TlsAcceptor::from(Arc::new(cfg)),
        Err(e) => {
            let _ = host
                .relay_tx
                .send(RelayStatus::Failed(format!("TLS del host: {e}")));
            return;
        }
    };

    let mut backoff = RELAY_BACKOFF_MIN;
    loop {
        match park_once(&host, &endpoint, &acceptor).await {
            Ok(()) => {
                // Una sesion que termina bien no es un error: se vuelve a
                // aparcar en el acto y el backoff arranca de cero.
                backoff = RELAY_BACKOFF_MIN;
            }
            Err(e) => {
                let _ = host.relay_tx.send(RelayStatus::Failed(e.to_string()));
                log::warn!("tunel: {e}; reintento en {backoff:?}");
                tokio::time::sleep(backoff).await;
                backoff = (backoff * 2).min(RELAY_BACKOFF_MAX);
            }
        }
    }
}

/// Un ciclo completo: aparcarse, esperar, atender, volver.
async fn park_once(
    host: &Arc<TransportHost>,
    endpoint: &RelayEndpoint,
    acceptor: &TlsAcceptor,
) -> Result<()> {
    let mut tcp = relay::conectar(&endpoint.host, endpoint.port).await?;
    relay::saludar_como_host(&mut tcp, &endpoint.token).await?;
    let _ = host.relay_tx.send(RelayStatus::Parked);

    // Esta espera puede durar horas: es el estado normal del tunel cuando el
    // telefono esta en casa y entra por la LAN.
    relay::esperar_cliente(&mut tcp).await?;
    let _ = host.relay_tx.send(RelayStatus::Matched);

    // Y de aca en adelante es una sesion como cualquier otra.
    handle_connection(host.clone(), acceptor.clone(), tcp).await
}
