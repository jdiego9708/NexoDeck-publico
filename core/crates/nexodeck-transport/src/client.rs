use std::sync::{Arc, Mutex, OnceLock};

use rustls_pki_types::ServerName;
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc};
use tokio_rustls::TlsConnector;

use nexodeck_protocol::{DevicePlatformWire, HardwareSnapshot, MessageV1};

use crate::error::{Result, TransportError};
use crate::server::RelayEndpoint;
use crate::session::{SessionTransport, WsSession};
use crate::tls::{self, ClientTrust};

#[derive(Debug, Clone)]
pub enum PairingEvent {
    HostPinReceived {
        pin: String,
        host_name: String,
        host_platform: DevicePlatformWire,
    },
    PairingSucceeded {
        device_id: String,
        cert_fingerprint: String,
    },
    PairingRejected {
        reason: String,
    },
}

#[derive(Debug, Clone)]
pub enum ConnectionEvent {
    Connected,
    Disconnected,
    HardwareSnapshotReceived(HardwareSnapshot),
    ActionsCatalogReceived(Vec<nexodeck_protocol::RemoteAction>),
    ActionAckReceived {
        action_id: String,
        success: bool,
        error: Option<String>,
    },
    /// Como le fue de verdad al comando que este dispositivo mando ejecutar.
    /// Llega despues del ack, que solo dice "lo lance".
    ActionRunUpdateReceived {
        run_id: String,
        action_id: String,
        phase: nexodeck_protocol::RunPhaseWire,
        exit_code: Option<i32>,
        elapsed_ms: u32,
        output_tail: String,
    },
    /// La PC dice como alcanzarla desde fuera de su red.
    ///
    /// Llega por la sesion ya autenticada, en cada conexion. `host` vacio
    /// significa que la PC apago el tunel y hay que olvidar lo guardado.
    RelayOfferReceived {
        host: String,
        port: u16,
        token_hex: String,
    },
    /// Lista de procesos de la PC, mientras haya suscripcion viva.
    TopProcessesReceived(nexodeck_protocol::TopProcessesWire),
    /// Resultado de haber pedido cerrar una aplicacion en la PC.
    ProcessTerminatedReceived {
        name: String,
        killed: u32,
        failed: u32,
        /// Con texto cuando la PC rechazo el pedido entero (proceso critico de
        /// Windows, o el propio NexoDeck).
        rejected_reason: Option<String>,
    },
    /// Estado completo de las suscripciones en vivo de la PC (SignalR o
    /// WebSocket crudo) -- lista entera, no un diff. Ver el comentario en
    /// `MessageV1::HubSubscriptionsSnapshot`.
    HubSubscriptionsSnapshotReceived(Vec<nexodeck_protocol::HubSubscriptionWire>),
    /// Nombres y caracteristicas de las piezas de la PC (modelo de CPU,
    /// memoria, GPU, adaptador de red). Llega una sola vez por sesion, no en
    /// cada snapshot -- ver el comentario en `MessageV1::HostComponents`.
    HostComponentsReceived(nexodeck_protocol::HostComponentsWire),
    /// Si el asistente de IA esta habilitado y listo en la PC -- ver el
    /// comentario en `MessageV1::AiStatus`.
    AiStatusReceived { enabled: bool, ready: bool },
    /// Un evento de la conversacion con el asistente -- ver el comentario en
    /// `MessageV1::AiChatEvent`.
    AiChatEventReceived(nexodeck_protocol::AiChatEventWire),
    /// La PC contesto una peticion de notas. El `request_id` es el que mando
    /// este telefono: puede haber varias en vuelo a la vez.
    NotesResponseReceived {
        request_id: String,
        response: nexodeck_protocol::NotesResponseWire,
    },
    /// La boveda de la PC cambio. **No viene el cambio**: el telefono pide el
    /// manifiesto y compara contra su copia -- ver `MessageV1::NotesChanged`.
    NotesChanged,
}

type ClientWs = tokio_tungstenite::WebSocketStream<tokio_rustls::client::TlsStream<TcpStream>>;

struct ClientState {
    outbound: mpsc::UnboundedSender<MessageV1>,
}

pub struct TransportClient {
    state: Mutex<Option<ClientState>>,
    pairing_tx: broadcast::Sender<PairingEvent>,
    connection_tx: broadcast::Sender<ConnectionEvent>,
}

static CLIENT: OnceLock<Arc<TransportClient>> = OnceLock::new();

pub fn client() -> Arc<TransportClient> {
    CLIENT
        .get_or_init(|| {
            Arc::new(TransportClient {
                state: Mutex::new(None),
                pairing_tx: broadcast::channel(32).0,
                connection_tx: broadcast::channel(64).0,
            })
        })
        .clone()
}

impl TransportClient {
    pub fn pairing_events(&self) -> broadcast::Receiver<PairingEvent> {
        self.pairing_tx.subscribe()
    }

    pub fn connection_events(&self) -> broadcast::Receiver<ConnectionEvent> {
        self.connection_tx.subscribe()
    }

    /// Primer pairing con un host recien descubierto: confianza "trust on
    /// first use" (todavia no hay nada que pinnear) + envia `PairHello`.
    ///
    /// Devuelve apenas la conexion queda ESTABLECIDA, no cuando termina la
    /// sesion -- ver `spawn_session`.
    pub async fn connect_first_pairing(
        self: &Arc<Self>,
        host: String,
        port: u16,
        device_name: String,
    ) -> Result<()> {
        let captured = Arc::new(Mutex::new(None));
        let config = tls::make_client_config(ClientTrust::TrustOnFirstUse { captured });
        let ws = self.connect_tls(&host, port, config).await?;
        let mut session = WsSession(ws);
        session
            .send(&MessageV1::PairHello {
                device_name,
                platform: current_platform(),
            })
            .await?;
        self.spawn_session(session);
        Ok(())
    }

    /// Reconexion con un dispositivo ya emparejado: la confianza del
    /// certificado esta PINNEADA al fingerprint guardado tras el pairing
    /// original -- si el host presenta un certificado distinto, el
    /// handshake TLS falla aca mismo, antes de mandar ningun mensaje.
    pub async fn reconnect(
        self: &Arc<Self>,
        device_id: String,
        host: String,
        port: u16,
        pinned_fingerprint: String,
    ) -> Result<()> {
        let config = tls::make_client_config(ClientTrust::Pinned(pinned_fingerprint));
        let ws = self.connect_tls(&host, port, config).await?;
        let mut session = WsSession(ws);
        session.send(&MessageV1::Reconnect { device_id }).await?;
        self.spawn_session(session);
        Ok(())
    }

    /// Primer pairing a traves del tunel.
    ///
    /// Existe para el caso de emparejar sin haber estado nunca en la misma
    /// red. Hoy no lo usa la app --el token del tunel se entrega justamente
    /// durante un pairing en la LAN-- pero el camino es identico al de WiFi
    /// y no tenerlo obligaria a inventarlo cuando haga falta.
    pub async fn connect_first_pairing_via_relay(
        self: &Arc<Self>,
        endpoint: RelayEndpoint,
        device_name: String,
    ) -> Result<()> {
        let captured = Arc::new(Mutex::new(None));
        let config = tls::make_client_config(ClientTrust::TrustOnFirstUse { captured });
        let ws = self.connect_tls_via_relay(&endpoint, config).await?;
        let mut session = WsSession(ws);
        session
            .send(&MessageV1::PairHello {
                device_name,
                platform: current_platform(),
            })
            .await?;
        self.spawn_session(session);
        Ok(())
    }

    /// Reconexion a traves del tunel, con el MISMO fingerprint pinneado que
    /// se usa en la LAN. Que el camino cambie no relaja la confianza: si la
    /// PC del otro lado no presenta el certificado esperado, el handshake
    /// falla aca igual que siempre.
    pub async fn reconnect_via_relay(
        self: &Arc<Self>,
        device_id: String,
        endpoint: RelayEndpoint,
        pinned_fingerprint: String,
    ) -> Result<()> {
        let config = tls::make_client_config(ClientTrust::Pinned(pinned_fingerprint));
        let ws = self.connect_tls_via_relay(&endpoint, config).await?;
        let mut session = WsSession(ws);
        session.send(&MessageV1::Reconnect { device_id }).await?;
        self.spawn_session(session);
        Ok(())
    }

    /// Suelta el loop de la sesion al background y devuelve el control.
    ///
    /// La division importa para quien llama: `connect_first_pairing` y
    /// `reconnect` resuelven cuando la conexion QUEDO ESTABLECIDA, asi que
    /// un `Err` significa "no se pudo conectar" y es accionable. Antes las
    /// dos esperaban toda la sesion, asi que el FFI las tenia que spawnear
    /// y descartar el error con `let _ = ...`: un TCP rechazado o un
    /// fingerprint que no matchea NO llegaban nunca a Dart, y la UI se
    /// quedaba en "Reconectando..." sin explicacion ni salida. Verificado
    /// contra el telefono real.
    fn spawn_session(self: &Arc<Self>, session: WsSession<tokio_rustls::client::TlsStream<TcpStream>>) {
        let this = self.clone();
        tokio::spawn(async move {
            let _ = this.run_connection(session).await;
        });
    }

    /// Igual que `connect_first_pairing`/`reconnect` pero sobre una sesion
    /// YA abierta, sin TLS ni descubrimiento: el caso del cable USB, donde
    /// el canal lo abre Android (`usb::android`) a partir del fd del
    /// accessory. De aca en adelante el flujo de mensajes es identico al de
    /// WiFi -- por eso `run_connection` es generico sobre `SessionTransport`.
    ///
    /// El TLS de WiFi no falta por descuido: por USB el "canal" es un cable
    /// fisico entre dos aparatos que el usuario tiene enfrente, no una red
    /// compartida, asi que no hay un tercero al que cifrarle nada. El PIN de
    /// pairing se sigue pidiendo igual.
    // Solo lo usa `usb::android`, que no existe fuera de Android; sin el
    // gate, el build de escritorio lo ve como codigo muerto.
    #[cfg(target_os = "android")]
    pub(crate) async fn run_over_session<T: SessionTransport>(
        self: &Arc<Self>,
        mut session: T,
        first: MessageV1,
    ) -> Result<()> {
        session.send(&first).await?;
        self.run_connection(session).await
    }

    pub fn send_pair_confirm(&self) -> Result<()> {
        self.send(MessageV1::PairConfirm)
    }

    /// `params` son los valores que el usuario cargo en el prompt del
    /// telefono para los `{{placeholders}}` de la accion; va vacio si la
    /// accion no tiene parametros.
    pub fn send_execute_action(
        &self,
        action_id: String,
        params: Vec<nexodeck_protocol::ActionParamValue>,
    ) -> Result<()> {
        self.send(MessageV1::ExecuteAction { action_id, params })
    }

    /// Pide (o corta) el envio de la lista de procesos de la PC.
    ///
    /// Es una suscripcion y no un push permanente: recorrer los procesos de la
    /// PC cuesta CPU alla y bateria aca, asi que solo se paga mientras el
    /// panel este abierto.
    pub fn send_watch_processes(&self, enabled: bool) -> Result<()> {
        self.send(MessageV1::WatchProcesses { enabled })
    }

    /// Pide cerrar todos los procesos de una aplicacion en la PC.
    ///
    /// Van nombre **y** pids: la PC solo cierra los que sigan llamandose asi.
    /// Windows reutiliza los pids rapido y estos vienen de una muestra de hasta
    /// dos segundos atras mas la latencia de la red.
    pub fn send_terminate_process_group(
        &self,
        name: String,
        pids: Vec<u32>,
    ) -> Result<()> {
        self.send(MessageV1::TerminateProcessGroup { name, pids })
    }

    /// Manda un mensaje del usuario al chat del asistente que corre en la PC.
    pub fn send_ai_message(&self, text: String) -> Result<()> {
        self.send(MessageV1::AiSendMessage { text })
    }

    /// Pide que la PC active el asistente. Solo tiene sentido si el ultimo
    /// `AiStatusReceived` dijo `enabled: true, ready: false`.
    pub fn send_ai_activate(&self) -> Result<()> {
        self.send(MessageV1::AiActivate)
    }

    /// Pide guardar un borrador como boton nuevo -- ver el comentario en
    /// `MessageV1::AiApplyDraft`.
    pub fn send_ai_apply_draft(&self, draft: nexodeck_protocol::AiDraftWire) -> Result<()> {
        self.send(MessageV1::AiApplyDraft { draft })
    }

    /// Pide correr un borrador ahora, en vivo.
    pub fn send_ai_run_draft(&self, draft: nexodeck_protocol::AiDraftWire) -> Result<()> {
        self.send(MessageV1::AiRunDraft { draft })
    }

    pub fn send_ai_ask_about_process(
        &self,
        group: nexodeck_protocol::ProcessGroupWire,
    ) -> Result<()> {
        self.send(MessageV1::AiAskAboutProcess { group })
    }

    /// Pide algo sobre las notas a la PC: el manifiesto de la boveda, el texto
    /// de unas notas, o aplicar los cambios que este telefono tenia encolados.
    ///
    /// El `request_id` lo genera quien llama, que es quien espera la respuesta:
    /// puede haber varias peticiones en vuelo a la vez.
    pub fn send_notes_request(
        &self,
        request_id: String,
        request: nexodeck_protocol::NotesRequestWire,
    ) -> Result<()> {
        self.send(MessageV1::NotesRequest {
            request_id,
            request,
        })
    }

    fn send(&self, msg: MessageV1) -> Result<()> {
        let state = self.state.lock().unwrap();
        let state = state.as_ref().ok_or(TransportError::ClientNotStarted)?;
        state
            .outbound
            .send(msg)
            .map_err(|_| TransportError::ClientNotStarted)?;
        Ok(())
    }

    async fn connect_tls(
        &self,
        host: &str,
        port: u16,
        config: rustls::ClientConfig,
    ) -> Result<ClientWs> {
        let addr = format!("{host}:{port}");
        let tcp = TcpStream::connect(&addr).await?;
        tls_sobre(tcp, server_name_for(host)?, config).await
    }

    /// Igual que `connect_tls` pero contra la PC del otro lado del tunel.
    ///
    /// El socket es contra el relay, pero **el TLS es con la PC**: el relay
    /// solo copia bytes y no ve nada del contenido. Por eso el pinning
    /// funciona igual que en la LAN, sin ninguna excepcion ni modo especial.
    async fn connect_tls_via_relay(
        &self,
        endpoint: &RelayEndpoint,
        config: rustls::ClientConfig,
    ) -> Result<ClientWs> {
        let mut tcp = crate::relay::conectar(&endpoint.host, endpoint.port).await?;
        crate::relay::saludar_como_cliente(&mut tcp, &endpoint.token).await?;
        tls_sobre(tcp, server_name_for(RELAY_SNI)?, config).await
    }

    async fn run_connection<T: SessionTransport>(self: &Arc<Self>, mut session: T) -> Result<()> {
        let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<MessageV1>();
        // Copia propia para el chequeo de "todavia soy yo" al limpiar --
        // ver el comentario analogo en `server.rs::run_session`. Sin esto,
        // una reconexion que reemplaza el estado del singleton puede hacer
        // que la conexion VIEJA, al cerrarse, borre por error el estado de
        // la conexion NUEVA que la reemplazo.
        let my_outbound = outbound_tx.clone();
        {
            let mut state = self.state.lock().unwrap();
            *state = Some(ClientState {
                outbound: outbound_tx,
            });
        }

        loop {
            tokio::select! {
                incoming = session.recv() => {
                    match incoming {
                        Ok(Some(msg)) => {
                            if !self.dispatch_incoming(msg) {
                                break;
                            }
                        }
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
            }
        }

        let still_mine = {
            let mut state = self.state.lock().unwrap();
            let still_mine = state
                .as_ref()
                .map(|s| s.outbound.same_channel(&my_outbound))
                .unwrap_or(false);
            if still_mine {
                *state = None;
            }
            still_mine
        };
        // Si esta conexion ya no es la activa (fue reemplazada por una
        // reconexion mas nueva), no anunciar `Disconnected` -- esa sesion
        // vieja cerrandose no significa que la conexion actual se cayo, y
        // mandar el evento igual pisaria por error el `Connected` de la
        // sesion nueva en la UI.
        if still_mine {
            let _ = self.connection_tx.send(ConnectionEvent::Disconnected);
        }
        Ok(())
    }

    fn dispatch_incoming(&self, msg: MessageV1) -> bool {
        match msg {
            MessageV1::PairPin {
                pin,
                host_name,
                host_platform,
            } => {
                let _ = self.pairing_tx.send(PairingEvent::HostPinReceived {
                    pin,
                    host_name,
                    host_platform,
                });
                true
            }
            MessageV1::PairAccepted {
                device_id,
                cert_fingerprint,
            } => {
                let _ = self.pairing_tx.send(PairingEvent::PairingSucceeded {
                    device_id,
                    cert_fingerprint,
                });
                let _ = self.connection_tx.send(ConnectionEvent::Connected);
                true
            }
            MessageV1::PairRejected { reason } => {
                let _ = self.pairing_tx.send(PairingEvent::PairingRejected { reason });
                false
            }
            MessageV1::ReconnectAccepted => {
                let _ = self.connection_tx.send(ConnectionEvent::Connected);
                true
            }
            MessageV1::ReconnectRejected { reason } => {
                let _ = self.pairing_tx.send(PairingEvent::PairingRejected { reason });
                false
            }
            MessageV1::TopProcesses(sample) => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::TopProcessesReceived(sample));
                true
            }
            MessageV1::NotesResponse {
                request_id,
                response,
            } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::NotesResponseReceived {
                        request_id,
                        response,
                    });
                true
            }
            // La boveda de la PC cambio. No viene el cambio: el telefono pide el
            // manifiesto y compara contra su copia.
            MessageV1::NotesChanged => {
                let _ = self.connection_tx.send(ConnectionEvent::NotesChanged);
                true
            }
            MessageV1::RelayOffer {
                host,
                port,
                token_hex,
            } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::RelayOfferReceived {
                        host,
                        port,
                        token_hex,
                    });
                true
            }
            MessageV1::ProcessTerminated {
                name,
                killed,
                failed,
                rejected_reason,
            } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::ProcessTerminatedReceived {
                        name,
                        killed,
                        failed,
                        rejected_reason,
                    });
                true
            }
            MessageV1::HardwareSnapshot(snapshot) => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::HardwareSnapshotReceived(snapshot));
                true
            }
            MessageV1::ActionsCatalog { actions } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::ActionsCatalogReceived(actions));
                true
            }
            MessageV1::ActionAck {
                action_id,
                success,
                error,
            } => {
                let _ = self.connection_tx.send(ConnectionEvent::ActionAckReceived {
                    action_id,
                    success,
                    error,
                });
                true
            }
            MessageV1::ActionRunUpdate {
                run_id,
                action_id,
                phase,
                exit_code,
                elapsed_ms,
                output_tail,
            } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::ActionRunUpdateReceived {
                        run_id,
                        action_id,
                        phase,
                        exit_code,
                        elapsed_ms,
                        output_tail,
                    });
                true
            }
            MessageV1::HubSubscriptionsSnapshot { subscriptions } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::HubSubscriptionsSnapshotReceived(
                        subscriptions,
                    ));
                true
            }
            MessageV1::HostComponents(components) => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::HostComponentsReceived(components));
                true
            }
            MessageV1::AiStatus { enabled, ready } => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::AiStatusReceived { enabled, ready });
                true
            }
            MessageV1::AiChatEvent(event) => {
                let _ = self
                    .connection_tx
                    .send(ConnectionEvent::AiChatEventReceived(event));
                true
            }
            _ => true,
        }
    }
}

fn current_platform() -> DevicePlatformWire {
    #[cfg(target_os = "android")]
    {
        DevicePlatformWire::Android
    }
    #[cfg(target_os = "ios")]
    {
        DevicePlatformWire::Ios
    }
    #[cfg(target_os = "windows")]
    {
        DevicePlatformWire::Windows
    }
    #[cfg(target_os = "linux")]
    {
        DevicePlatformWire::Linux
    }
    #[cfg(not(any(
        target_os = "android",
        target_os = "ios",
        target_os = "windows",
        target_os = "linux"
    )))]
    {
        DevicePlatformWire::Linux
    }
}

/// Nombre que se le pone al handshake TLS cuando se sale por el tunel.
///
/// Es una formalidad: del otro lado hay una PC cuyo nombre real no se
/// conoce, y los verificadores de `tls.rs` no miran el nombre --deciden por
/// fingerprint--. Un valor fijo evita tener que inventar uno por sesion.
const RELAY_SNI: &str = "nexodeck";

/// Levanta TLS y WebSocket sobre un socket YA abierto.
///
/// Separado de `connect_tls` porque el tunel llega aca con el TCP hecho: el
/// socket ya paso por el saludo del relay. De este punto en adelante los dos
/// caminos son indistinguibles, y por eso comparten esta funcion en vez de
/// tener cada uno su copia del handshake.
async fn tls_sobre(
    tcp: TcpStream,
    server_name: ServerName<'static>,
    config: rustls::ClientConfig,
) -> Result<ClientWs> {
    let connector = TlsConnector::from(Arc::new(config));
    let tls_stream = connector
        .connect(server_name, tcp)
        .await
        .map_err(|e| TransportError::Tls(e.to_string()))?;
    // La URL no la lee nadie: el WebSocket viaja adentro del TLS y el host
    // de destino ya quedo decidido por el socket.
    let (ws, _response) = tokio_tungstenite::client_async("wss://nexodeck/", tls_stream).await?;
    Ok(ws)
}

/// El `ServerName` que rustls exige para el handshake.
///
/// Acepta tanto una IP literal como un nombre DNS. Antes solo aceptaba IP y
/// cualquier nombre moria con "host invalido" antes de abrir el socket, lo
/// que dejaba fuera los nombres MagicDNS de Tailscale
/// (`mi-pc.tail1234.ts.net`) que la UI si ofrece escribir.
///
/// **Esto no relaja ninguna verificacion.** Los dos verificadores de
/// `tls.rs` (TOFU y pinneado) ignoran el `server_name` por completo: la
/// confianza sale del fingerprint del certificado y de nada mas. El nombre
/// es un requisito formal de la API de rustls.
fn server_name_for(host: &str) -> Result<ServerName<'static>> {
    ServerName::try_from(host.to_owned())
        .map_err(|_| TransportError::Protocol(format!("host invalido: {host}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acepta_ipv4_ipv6_y_nombre_dns() {
        assert!(matches!(
            server_name_for("192.168.1.8").unwrap(),
            ServerName::IpAddress(_)
        ));
        assert!(matches!(
            server_name_for("fd7a:115c::1").unwrap(),
            ServerName::IpAddress(_)
        ));
        // El caso que fallaba: el nombre MagicDNS de Tailscale.
        assert!(matches!(
            server_name_for("mi-pc.tail1234.ts.net").unwrap(),
            ServerName::DnsName(_)
        ));
    }

    #[test]
    fn rechaza_lo_que_no_es_un_host() {
        for malo in ["", "con espacio", "http://x"] {
            assert!(server_name_for(malo).is_err(), "deberia rechazar {malo:?}");
        }
    }
}
