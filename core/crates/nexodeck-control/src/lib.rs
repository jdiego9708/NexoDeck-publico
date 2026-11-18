//! Servidor de control: la boca de entrada de NexoDeck.
//!
//! Hasta ahora NexoDeck solo escuchaba en un sitio, el 58643 del transporte, y
//! ese cable es para el telefono: va en postcard sobre TLS con pinning, atado
//! al ritual de emparejamiento. No sirve para que un programa de la propia
//! maquina le pida algo.
//!
//! Este crate abre el otro lado: un servidor HTTP **solo en loopback** que
//! habla MCP, para que Claude Code descubra las herramientas y sus parametros
//! sin que nadie tenga que escribirlos a mano en cada sesion.
//!
//! ## Tres cosas que no son negociables
//!
//! 1. **Se escucha en `127.0.0.1`, nunca en `0.0.0.0`.** El del transporte se
//!    ata a todas las interfaces porque el telefono llega desde la LAN; este no
//!    tiene ningun cliente legitimo fuera de la maquina.
//! 2. **Token obligatorio en cada peticion.** Loopback no es una frontera de
//!    seguridad: cualquier proceso del usuario puede hablar con el puerto.
//! 3. **Ningun navegador entra**, aunque tenga el token. Ver `auth.rs`.
//!
//! ## Por que es opt-in
//!
//! Mismo criterio que la IA: apagado por defecto, con flag en `app_settings`.
//! Un servidor que acepta ordenes no puede aparecer solo en una instalacion
//! nueva porque alguien actualizo la app.

mod auth;
mod mcp;
mod outbox;
mod tools;

pub use outbox::{
    CorrespondentEvent, CorrespondentSession, OutboxMessage, SESSION_STALE_AFTER,
};

use std::net::Ipv4Addr;
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use nexodeck_notify::CommandChannel;
use tokio::sync::{broadcast, oneshot};

/// Puerto por defecto. La familia va seguida a proposito: 58643 es el host del
/// telefono y 58644 el relay, asi que quien vea uno en un `netstat` reconoce
/// los otros.
pub const DEFAULT_PORT: u16 = 58646;

const BROADCAST_CAPACITY: usize = 128;

#[derive(Debug, thiserror::Error)]
pub enum ControlError {
    #[error(
        "el puerto {0} ya esta ocupado: puede haber otra instancia de NexoDeck \
         corriendo, o un ejemplo de diagnostico"
    )]
    PortInUse(u16),
    #[error("no se pudo escuchar en 127.0.0.1:{port}: {source}")]
    Bind {
        port: u16,
        #[source]
        source: std::io::Error,
    },
    #[error("el servidor de control ya estaba corriendo")]
    AlreadyRunning,
    #[error("el token de control no puede estar vacio")]
    EmptyToken,
    #[error("no se pudo resolver el directorio de datos del usuario")]
    NoDataDir,
    #[error("no se pudo guardar el token de control: {source}")]
    TokenStore {
        #[source]
        source: std::io::Error,
    },
}

/// Lo que pasa en el servidor, para que la UI pueda mostrarlo.
///
/// `Rejected` esta aca por la misma razon que todo lo demas en este proyecto:
/// un intento no autorizado que no deja rastro es indistinguible de que no haya
/// pasado nada. Si alguien esta golpeando el puerto, el usuario tiene que
/// poder verlo.
#[derive(Debug, Clone)]
pub enum ControlEvent {
    Started { port: u16 },
    Stopped,
    ToolCalled { tool: String, summary: String, ok: bool },
    Rejected { reason: String },
}

/// Lo que hace falta para levantar el servidor. Todo viene de Dart, que es
/// quien tiene la base de datos.
#[derive(Debug, Clone)]
pub struct ControlConfig {
    pub port: u16,
    pub token: String,
    pub channels: Vec<CommandChannel>,
}

/// Estado compartido con los handlers de axum.
pub(crate) struct ControlState {
    token: RwLock<String>,
    /// Los canales de aviso viven aca porque una peticion MCP llega **a Rust**,
    /// y Rust no puede consultar Drift. Dart los empuja al arrancar y cada vez
    /// que el usuario los cambia.
    channels: RwLock<Vec<CommandChannel>>,
    events: broadcast::Sender<ControlEvent>,
    /// La cola hacia Claude Code. Vive en el estado y no en el servidor porque
    /// tiene que sobrevivir a apagar y encender: un mensaje encolado con el
    /// servidor parado sigue esperando a que alguien lo recoja.
    outbox: Arc<outbox::Outbox>,
    /// El buzon de documentacion. `None` hasta que la app lo inicializa: sin
    /// el, las herramientas del buzon lo dicen en vez de fallar raro.
    docs: RwLock<Option<Arc<nexodeck_docs::DocsService>>>,
}

impl ControlState {
    pub(crate) fn token(&self) -> String {
        self.token.read().map(|t| t.clone()).unwrap_or_default()
    }

    pub(crate) fn channels(&self) -> Vec<CommandChannel> {
        self.channels.read().map(|c| c.clone()).unwrap_or_default()
    }

    pub(crate) fn emit(&self, event: ControlEvent) {
        let _ = self.events.send(event);
    }

    pub(crate) fn outbox(&self) -> &Arc<outbox::Outbox> {
        &self.outbox
    }

    pub(crate) fn docs(&self) -> Option<Arc<nexodeck_docs::DocsService>> {
        self.docs.read().ok().and_then(|d| d.clone())
    }
}

struct RunningServer {
    shutdown: oneshot::Sender<()>,
    port: u16,
}

pub struct Control {
    state: Arc<ControlState>,
    running: Mutex<Option<RunningServer>>,
}

static CONTROL: OnceLock<Arc<Control>> = OnceLock::new();

/// Singleton. Vive fuera de cualquier arranque del servidor porque el stream de
/// eventos que escucha Dart se abre una vez, al montar la pantalla, y tiene que
/// seguir sirviendo despues de apagar y volver a encender el servidor. Mismo
/// razonamiento que el `runner()` de `nexodeck-actions`.
pub fn control() -> Arc<Control> {
    CONTROL
        .get_or_init(|| {
            let (events, _) = broadcast::channel(BROADCAST_CAPACITY);
            Arc::new(Control {
                state: Arc::new(ControlState {
                    token: RwLock::new(String::new()),
                    channels: RwLock::new(Vec::new()),
                    events,
                    outbox: Arc::new(outbox::Outbox::default()),
                    docs: RwLock::new(None),
                }),
                running: Mutex::new(None),
            })
        })
        .clone()
}

impl Control {
    pub fn subscribe(&self) -> broadcast::Receiver<ControlEvent> {
        self.state.events.subscribe()
    }

    pub fn is_running(&self) -> bool {
        self.running.lock().map(|r| r.is_some()).unwrap_or(false)
    }

    /// Puerto real en el que quedo escuchando. `None` si no esta corriendo.
    /// No siempre coincide con el pedido: con `port = 0` lo elige el sistema,
    /// que es como se levantan los tests sin pelearse por un puerto fijo.
    pub fn port(&self) -> Option<u16> {
        self.running.lock().ok().and_then(|r| r.as_ref().map(|s| s.port))
    }

    /// Reemplaza los canales de aviso. Surte efecto en la siguiente peticion,
    /// sin reiniciar el servidor.
    pub fn set_channels(&self, channels: Vec<CommandChannel>) {
        if let Ok(mut slot) = self.state.channels.write() {
            *slot = channels;
        }
    }

    /// Engancha el buzon de documentacion. Se hace aparte de `start` porque el
    /// buzon vive aunque el servidor este apagado: los hallazgos ya guardados
    /// se siguen procesando.
    pub fn set_docs(&self, docs: Option<Arc<nexodeck_docs::DocsService>>) {
        if let Ok(mut slot) = self.state.docs.write() {
            *slot = docs;
        }
    }

    /// Eventos de la correspondencia con Claude Code. Canal aparte del de
    /// `ControlEvent`: uno alimenta el panel de actividad y el otro el chat, y
    /// mezclarlos obligaria a cada consumidor a filtrar lo del otro.
    pub fn subscribe_correspondent(&self) -> broadcast::Receiver<CorrespondentEvent> {
        self.state.outbox.subscribe()
    }

    /// Encola una pregunta para Claude Code y devuelve su marca. La respuesta
    /// llega como `CorrespondentEvent::Replied` con esa misma marca.
    ///
    /// `session` elige a que terminal se le pregunta; en `None` va a todas, que
    /// es lo que hay que usar cuando da igual quien conteste.
    ///
    /// **No falla si esa sesion no esta escuchando**: el mensaje queda en la
    /// cola. Lo que si pasa es que la pregunta vence enseguida, con el motivo,
    /// en vez de esperar el plazo completo -- ver `Outbox::expire_old`.
    pub fn ask_correspondent(&self, text: String, session: Option<String>) -> u64 {
        self.state.outbox.push(text, true, session)
    }

    /// Un aviso suelto hacia Claude Code, sin esperar respuesta.
    pub fn tell_correspondent(&self, text: String, session: Option<String>) -> u64 {
        self.state.outbox.push(text, false, session)
    }

    /// Las sesiones de Claude Code que estan escuchando.
    pub fn correspondent_sessions(&self) -> Vec<CorrespondentSession> {
        self.state.outbox.sessions()
    }

    /// Cuantas preguntas siguen esperando respuesta.
    pub fn pending_replies(&self) -> usize {
        self.state.outbox.pending_count()
    }

    /// Si **alguna** sesion recogio algo alguna vez. Con preguntas encoladas y
    /// esto en `false`, no hay nadie escuchando.
    pub fn anyone_delivered(&self) -> bool {
        self.state.outbox.anyone_delivered()
    }

    pub async fn start(&self, config: ControlConfig) -> Result<u16, ControlError> {
        if config.token.trim().is_empty() {
            return Err(ControlError::EmptyToken);
        }

        {
            let running = self.running.lock().map_err(|_| ControlError::AlreadyRunning)?;
            if running.is_some() {
                return Err(ControlError::AlreadyRunning);
            }
        }

        if let Ok(mut token) = self.state.token.write() {
            *token = config.token;
        }
        self.set_channels(config.channels);

        // `Ipv4Addr::LOCALHOST`, nunca `0.0.0.0`: este servidor no tiene ningun
        // cliente legitimo fuera de la maquina.
        let listener = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, config.port))
            .await
            .map_err(|source| match source.kind() {
                // Se distingue a proposito. El sintoma de "otra instancia ya
                // tiene el puerto" es identico al de un fallo de red si se
                // reporta el `io::Error` crudo, y el usuario no tiene forma de
                // adivinar cual de los dos es. Ya paso con el 58643.
                std::io::ErrorKind::AddrInUse => ControlError::PortInUse(config.port),
                _ => ControlError::Bind {
                    port: config.port,
                    source,
                },
            })?;

        let port = listener
            .local_addr()
            .map(|addr| addr.port())
            .unwrap_or(config.port);

        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let app = mcp::router(Arc::clone(&self.state));

        tokio::spawn(async move {
            let _ = axum::serve(listener, app)
                .with_graceful_shutdown(async move {
                    let _ = shutdown_rx.await;
                })
                .await;
        });

        // Sin esto, una pregunta que nadie recoge se queda en "pensando" para
        // siempre. Va aqui y no en `control()` porque necesita un runtime de
        // tokio vivo, y el singleton se construye desde donde sea.
        outbox::spawn_expiry_task(Arc::clone(&self.state.outbox));

        if let Ok(mut running) = self.running.lock() {
            *running = Some(RunningServer {
                shutdown: shutdown_tx,
                port,
            });
        }
        self.state.emit(ControlEvent::Started { port });
        Ok(port)
    }

    /// Idempotente: parar algo que no esta corriendo no es un error.
    pub fn stop(&self) {
        let taken = self.running.lock().ok().and_then(|mut r| r.take());
        if let Some(server) = taken {
            // El `Err` significa que la tarea del servidor ya termino sola. No
            // hay nada que hacer con eso.
            let _ = server.shutdown.send(());
            self.state.emit(ControlEvent::Stopped);
        }
    }
}

/// El token de esta instalacion, generandolo la primera vez.
///
/// ## Por que NO vive en Drift
///
/// Es un secreto, y la regla del proyecto es que los secretos no tocan Drift en
/// texto plano. `nexodeck-vault` todavia es un stub (Fase 7), pero ya existe el
/// sitio correcto y con precedente: el **directorio de datos del usuario**, que
/// es donde `nexodeck-transport/src/tls.rs` guarda la clave privada del
/// certificado del host. Este token va al lado, por el mismo camino.
///
/// ## Por que se persiste en vez de generarse en cada arranque
///
/// El token tiene que estar tambien del otro lado, en la configuracion MCP de
/// Claude Code. Uno nuevo en cada arranque obligaria a reconfigurar el cliente
/// cada vez que se abre NexoDeck, que es lo mismo que no funcionar. Es el mismo
/// razonamiento que hace persistente al certificado del host.
pub fn ensure_token() -> Result<String, ControlError> {
    let path = token_path()?;

    if let Ok(existing) = std::fs::read_to_string(&path) {
        let existing = existing.trim().to_string();
        if !existing.is_empty() {
            return Ok(existing);
        }
        // Un fichero vacio es un arranque anterior que murio a medias. Se
        // regenera en vez de arrancar con un token vacio, que el servidor
        // rechazaria despues con un error que no explicaria nada.
    }

    let token = generate_token();
    std::fs::write(&path, &token).map_err(|source| ControlError::TokenStore { source })?;
    Ok(token)
}

/// Donde vive el token. Publico para que la UI pueda decirselo al usuario si
/// hace falta mirarlo a mano.
pub fn token_path() -> Result<std::path::PathBuf, ControlError> {
    let dirs = directories::ProjectDirs::from("dev", "nexodeck", "NexoDeck")
        .ok_or(ControlError::NoDataDir)?;
    let dir = dirs.data_dir().to_path_buf();
    std::fs::create_dir_all(&dir).map_err(|source| ControlError::TokenStore { source })?;
    Ok(dir.join("control_token.txt"))
}

/// Token nuevo, en hexadecimal. Se genera aca y no en Dart porque el generador
/// de aleatoriedad criptografica ya esta de este lado.
pub fn generate_token() -> String {
    use rand::Rng;
    let bytes: [u8; 32] = rand::thread_rng().gen();
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// El token tiene que sobrevivir al reinicio: si cambiara, habria que
    /// reconfigurar Claude Code cada vez que se abre NexoDeck.
    #[test]
    fn the_token_is_stable_across_calls() {
        let first = ensure_token().expect("token");
        let second = ensure_token().expect("token");
        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
    }

    #[test]
    fn a_generated_token_is_64_hex_chars_and_never_repeats() {
        let a = generate_token();
        let b = generate_token();
        assert_eq!(a.len(), 64);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);
    }

    #[tokio::test]
    async fn an_empty_token_is_refused_before_binding_anything() {
        let control = control();
        let err = control
            .start(ControlConfig {
                port: 0,
                token: "   ".into(),
                channels: Vec::new(),
            })
            .await
            .expect_err("un token vacio no puede levantar el servidor");
        assert!(matches!(err, ControlError::EmptyToken));
        assert!(!control.is_running());
    }
}
