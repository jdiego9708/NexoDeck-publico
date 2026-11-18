//! El servidor de control, visto desde Dart.
//!
//! ## Solo escritorio, pero con la firma siempre presente
//!
//! `nexodeck-control` no entra en la build de Android: Claude Code no corre en
//! el telefono. Aun asi las funciones **existen en los tres targets** con el
//! cuerpo cfg-gateado, igual que `paste_to_clipboard` y que `api/usb.rs`.
//! Cfg-ear la funcion entera romperia el enlace del lado que falta, porque
//! flutter_rust_bridge genera el glue para todos los targets por igual.

use crate::frb_generated::StreamSink;

/// Puerto por defecto del servidor de control. Se expone para que la UI pueda
/// mostrarlo y para que el diagnostico no tenga el numero escrito dos veces.
#[cfg(not(target_os = "android"))]
pub fn default_control_port() -> u16 {
    nexodeck_control::DEFAULT_PORT
}

#[cfg(target_os = "android")]
pub fn default_control_port() -> u16 {
    0
}

/// Espejo de `nexodeck_control::ControlEvent`.
#[derive(Debug, Clone)]
pub enum ControlEvent {
    Started {
        port: u16,
    },
    Stopped,
    /// Alguien llamo a una herramienta. `summary` es una linea para el panel:
    /// el usuario tiene que poder ver que le pidieron a su maquina sin leer
    /// ningun JSON.
    ToolCalled {
        tool: String,
        summary: String,
        ok: bool,
    },
    /// Una peticion que no paso la puerta. **Se muestra a proposito**: si algo
    /// esta golpeando el puerto, un rechazo silencioso es indistinguible de que
    /// no este pasando nada.
    Rejected {
        reason: String,
    },
}

#[cfg(not(target_os = "android"))]
impl From<nexodeck_control::ControlEvent> for ControlEvent {
    fn from(value: nexodeck_control::ControlEvent) -> Self {
        use nexodeck_control::ControlEvent as E;
        match value {
            E::Started { port } => ControlEvent::Started { port },
            E::Stopped => ControlEvent::Stopped,
            E::ToolCalled { tool, summary, ok } => ControlEvent::ToolCalled { tool, summary, ok },
            E::Rejected { reason } => ControlEvent::Rejected { reason },
        }
    }
}

/// El token de esta instalacion, generandolo la primera vez.
///
/// **No hay una funcion "generar token" separada, y es a proposito.** Dart no
/// puede tener un token que el servidor no vaya a usar: la UI lo enseñaria, el
/// usuario lo copiaria a la configuracion de Claude Code, y las peticiones
/// darian 401 sin que nada explicara por que. Quien genera y quien guarda son
/// el mismo sitio.
///
/// El token no vive en Drift, sino en el directorio de datos del usuario, al
/// lado de la clave privada del certificado del host. Ver `ensure_token` en
/// `nexodeck-control`.
pub fn ensure_control_token() -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::ensure_token().map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err("el servidor de control es solo de escritorio".to_string())
    }
}

/// Donde quedo guardado el token, para poder enseñarselo al usuario.
pub fn control_token_path() -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::token_path()
            .map(|p| p.to_string_lossy().to_string())
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err("el servidor de control es solo de escritorio".to_string())
    }
}

/// Levanta el servidor y devuelve el puerto real en el que quedo escuchando.
///
/// Con `port = 0` lo elige el sistema. El `Err` lleva ya el texto que la UI
/// tiene que mostrar: el caso frecuente es el puerto ocupado por otra instancia
/// de NexoDeck, y ese mensaje es lo unico que distingue ese caso de un fallo de
/// red cualquiera.
///
/// **Es `async` por obligacion**: adentro se hace `bind` y `tokio::spawn`, y
/// frb corre las funciones `async` dentro de su propio runtime.
pub async fn start_control_server(port: u16, channels_json: String) -> Result<u16, String> {
    #[cfg(not(target_os = "android"))]
    {
        // El token lo carga Rust, no lo pasa Dart: asi no hay forma de arrancar
        // el servidor con un token distinto del que la UI le enseño al usuario.
        let token = nexodeck_control::ensure_token().map_err(|e| e.to_string())?;
        nexodeck_control::control()
            .start(nexodeck_control::ControlConfig {
                port,
                token,
                channels: nexodeck_notify::channels_from_json(&channels_json),
            })
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (port, channels_json);
        Err("el servidor de control es solo de escritorio".to_string())
    }
}

/// Idempotente: parar algo que no esta corriendo no es un error.
pub fn stop_control_server() {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control().stop();
    }
}

pub fn is_control_server_running() -> bool {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control().is_running()
    }
    #[cfg(target_os = "android")]
    {
        false
    }
}

/// Reemplaza los canales de aviso sin reiniciar el servidor. Se llama cada vez
/// que el usuario los cambia: sin esto, una peticion MCP seguiria usando la
/// configuracion con la que se arranco.
pub fn set_control_channels(channels_json: String) {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control().set_channels(nexodeck_notify::channels_from_json(&channels_json));
    }
    #[cfg(target_os = "android")]
    {
        let _ = channels_json;
    }
}

// ---------------------------------------------------------------------
// Correspondencia con Claude Code
// ---------------------------------------------------------------------
//
// El sentido que el servidor MCP no tiene. NexoDeck encola la pregunta y un
// oyente externo (`scripts/nexodeck-listen.sh`, lanzado con la herramienta
// Monitor de Claude Code) la recoge por HTTP; la respuesta vuelve como llamada
// a la herramienta `reply`.
//
// Los ids son `u64` del lado Rust pero cruzan el puente como `String`: frb
// mapea `u64` a `BigInt` en Dart, y eso es incomodo como clave de un `Map` sin
// ganar nada. Mismo criterio que el `run_id` del runner de comandos.

/// Una sesion de Claude Code que esta escuchando.
///
/// **La identidad la pone el vigilante**, no Claude Code: su pid como id, y la
/// carpeta con la rama como nombre. No hizo falta ninguna bandera de Claude
/// Code para esto.
#[derive(Debug, Clone)]
pub struct CorrespondentSession {
    pub id: String,
    pub label: String,
    pub cwd: String,
    pub last_seen_secs_ago: u32,
    /// Dejo de consultar: la terminal se cerro. Se sigue mostrando en vez de
    /// desaparecer, para que se entienda que paso con lo que se le mando.
    pub stale: bool,
}

/// Espejo de `nexodeck_control::CorrespondentEvent`.
#[derive(Debug, Clone)]
pub enum CorrespondentEvent {
    /// El oyente recogio el mensaje. Es el acuse de que hay alguien al otro
    /// lado: sin esto, "todavia no contesto" y "no hay nadie escuchando" se
    /// verian igual en el chat.
    Delivered { id: String, session: String },
    Replied { id: String, text: String },
    /// Claude Code dijo algo sin que nadie preguntara. `from` es cooperativo y
    /// puede faltar: todas las sesiones hablan con el mismo token, asi que el
    /// servidor no puede saber cual fue si ella no lo dice.
    Posted { text: String, from: Option<String> },
    /// Vencio. `reason` distingue "nadie contesto a tiempo" de "la sesion se
    /// cerro", que se arreglan distinto.
    TimedOut { id: String, reason: String },
    /// Aparecio o se cerro una sesion: el selector del chat se redibuja.
    SessionsChanged,
}

#[cfg(not(target_os = "android"))]
impl From<nexodeck_control::CorrespondentEvent> for CorrespondentEvent {
    fn from(value: nexodeck_control::CorrespondentEvent) -> Self {
        use nexodeck_control::CorrespondentEvent as E;
        match value {
            E::Delivered { seq, session } => CorrespondentEvent::Delivered {
                id: seq.to_string(),
                session,
            },
            E::Replied { seq, text } => CorrespondentEvent::Replied {
                id: seq.to_string(),
                text,
            },
            E::Posted { text, from } => CorrespondentEvent::Posted { text, from },
            E::TimedOut { seq, reason } => CorrespondentEvent::TimedOut {
                id: seq.to_string(),
                reason,
            },
            E::SessionsChanged => CorrespondentEvent::SessionsChanged,
        }
    }
}

/// Encola una pregunta para Claude Code y devuelve su id.
///
/// **No falla si no hay nadie escuchando**, y es a proposito: el mensaje queda
/// en la cola y lo recoge el oyente cuando arranque. Que nadie lo haya recogido
/// se ve en la ausencia de `Delivered`, no en un error aqui.
pub fn ask_claude_code(text: String, session: Option<String>) -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        Ok(nexodeck_control::control()
            .ask_correspondent(text, session)
            .to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (text, session);
        Err("el puente con Claude Code es solo de escritorio".to_string())
    }
}

/// Las sesiones de Claude Code que estan escuchando ahora.
///
/// Se refresca con `CorrespondentEvent::SessionsChanged`, que salta cuando una
/// aparece o se cierra.
pub fn claude_code_sessions() -> Vec<CorrespondentSession> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control()
            .correspondent_sessions()
            .into_iter()
            .map(|s| CorrespondentSession {
                id: s.id,
                label: s.label,
                cwd: s.cwd,
                last_seen_secs_ago: s.last_seen_secs_ago,
                stale: s.stale,
            })
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        Vec::new()
    }
}

/// Un aviso suelto hacia Claude Code, sin esperar respuesta.
pub fn tell_claude_code(text: String, session: Option<String>) -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        Ok(nexodeck_control::control()
            .tell_correspondent(text, session)
            .to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (text, session);
        Err("el puente con Claude Code es solo de escritorio".to_string())
    }
}

/// Cuantas preguntas siguen esperando respuesta.
pub fn pending_claude_code_replies() -> u32 {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control().pending_replies() as u32
    }
    #[cfg(target_os = "android")]
    {
        0
    }
}

/// Si algun oyente recogio algo alguna vez. `false` con mensajes encolados
/// significa que **nadie esta escuchando**, que es justo lo que el chat tiene
/// que decir en vez de dejar al usuario esperando.
pub fn claude_code_listener_seen() -> bool {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_control::control().anyone_delivered()
    }
    #[cfg(target_os = "android")]
    {
        false
    }
}

/// Stream de la correspondencia. Canal aparte del de `ControlEvent`: uno
/// alimenta el panel de actividad y el otro el chat, y mezclarlos obligaria a
/// cada consumidor a filtrar lo del otro.
///
/// Se consume con **suscripcion directa al `Stream`**, nunca con `ref.listen`:
/// dos `Posted` con el mismo texto seguidos son perfectamente posibles.
pub async fn watch_correspondent_events(sink: StreamSink<CorrespondentEvent>) {
    #[cfg(not(target_os = "android"))]
    {
        let mut events = nexodeck_control::control().subscribe_correspondent();
        loop {
            match events.recv().await {
                Ok(event) => {
                    if sink.add(event.into()).is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink;
    }
}

/// Stream de lo que pasa en el servidor. No devuelve `Result` (limitacion de
/// FRB): los rechazos llegan como `ControlEvent::Rejected`.
///
/// Del lado Dart se consume con **suscripcion directa al `Stream`**, nunca con
/// `ref.listen` sobre un provider: dos rechazos identicos seguidos son
/// perfectamente posibles y Riverpod no vuelve a notificar cuando el valor
/// nuevo es `==` al anterior. Ver la seccion "Eventos del bridge" de
/// `CLAUDE.md`.
pub async fn watch_control_events(sink: StreamSink<ControlEvent>) {
    #[cfg(not(target_os = "android"))]
    {
        let mut events = nexodeck_control::control().subscribe();
        loop {
            match events.recv().await {
                Ok(event) => {
                    if sink.add(event.into()).is_err() {
                        break; // Dart cerro el stream
                    }
                }
                // Se perdieron eventos por atraso. **Hay que seguir**: cortar
                // aca dejaria el panel congelado para siempre.
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink;
    }
}
