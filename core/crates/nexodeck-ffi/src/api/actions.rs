use nexodeck_actions::TerminalType as CoreTerminalType;

use crate::frb_generated::StreamSink;

/// Espejo de `nexodeck_actions::TerminalType` -- por la misma razon que el
/// resto de DTOs de este crate: `nexodeck-ffi` es el unico lugar donde vive
/// la forma exacta del dato que cruza el bridge.
#[derive(Debug, Clone, Copy)]
pub enum TerminalType {
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

impl From<TerminalType> for CoreTerminalType {
    fn from(value: TerminalType) -> Self {
        match value {
            TerminalType::DefaultShell => CoreTerminalType::DefaultShell,
            TerminalType::PowerShell => CoreTerminalType::PowerShell,
            TerminalType::Bash => CoreTerminalType::Bash,
            TerminalType::Cmd => CoreTerminalType::Cmd,
        }
    }
}

/// Ejecuta una accion `actionType = clipboard`: copia `text` (ya con los
/// placeholders `{{variable}}` reemplazados del lado Dart) al portapapeles
/// del sistema.
///
/// Con `paste_into_active_window`, ademas le devuelve el foco a la ventana
/// que lo tenia antes de que el usuario tocara NexoDeck y le manda Ctrl+V
/// -- ver `nexodeck_actions::focus`. Sin eso, una accion de portapapeles
/// disparada con el mouse deja el texto copiado pero **nunca pegado**: el
/// propio clic le saco el foco al bloc de notas.
pub fn execute_clipboard_action(text: String, paste_into_active_window: bool) -> Result<(), String> {
    nexodeck_actions::run_clipboard_action(&text, paste_into_active_window)
        .map_err(|e| e.to_string())
}

/// Empieza a anotar que ventana tiene el foco, para que
/// `execute_clipboard_action` sepa a cual volver.
///
/// Se llama una vez al arrancar la app y **tiene que ser antes** del primer
/// clic en el deck: cuando la accion se ejecuta, el foco ya es de NexoDeck.
/// Es idempotente; fuera de Windows no hace nada.
pub fn start_focus_tracking() {
    nexodeck_actions::start_focus_tracking();
}

/// Ejecuta una accion `actionType = terminal`: corre `command`. Si
/// `show_window` es `true`, se abre una ventana de terminal nueva y
/// visible; si es `false`, corre por debajo sin mostrar ninguna consola
/// (para acciones tipo "abrir una app"). Si `requires_admin` es `true` en
/// Windows, dispara el prompt de UAC del sistema de todas formas.
pub fn execute_terminal_action(
    command: String,
    terminal_type: TerminalType,
    requires_admin: bool,
    show_window: bool,
) -> Result<(), String> {
    nexodeck_actions::run_in_terminal(&command, terminal_type.into(), requires_admin, show_window)
        .map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------
// Ejecucion capturada
// ---------------------------------------------------------------------
//
// Lo de arriba (`execute_terminal_action`) sigue siendo el modo **ventana**:
// abre una consola real y es la unica via para comandos interactivos. Lo de
// abajo es el modo **capturado**: el comando corre sin ninguna ventana y su
// salida vuelve por `watch_command_runs`.
//
// Ningun `u64` cruza el puente: flutter_rust_bridge lo mapea a `BigInt` del
// lado Dart (se ve en `HardwareSnapshot.netRxBytes`) y eso es incomodo como
// clave de un `Map` en la UI sin ganar nada. Por eso el id es `String` y los
// tiempos son `u32` de milisegundos.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandOutputStream {
    Stdout,
    Stderr,
}

impl From<nexodeck_actions::OutputStream> for CommandOutputStream {
    fn from(value: nexodeck_actions::OutputStream) -> Self {
        match value {
            nexodeck_actions::OutputStream::Stdout => CommandOutputStream::Stdout,
            nexodeck_actions::OutputStream::Stderr => CommandOutputStream::Stderr,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandRunStatus {
    Succeeded,
    Failed,
    Cancelled,
    /// Seguia viva pasado el umbral y sin decir nada: era una app, no un
    /// comando. Cuenta como exito para quien espera.
    Detached,
}

impl From<nexodeck_actions::RunStatus> for CommandRunStatus {
    fn from(value: nexodeck_actions::RunStatus) -> Self {
        match value {
            nexodeck_actions::RunStatus::Succeeded => CommandRunStatus::Succeeded,
            nexodeck_actions::RunStatus::Failed => CommandRunStatus::Failed,
            nexodeck_actions::RunStatus::Cancelled => CommandRunStatus::Cancelled,
            nexodeck_actions::RunStatus::Detached => CommandRunStatus::Detached,
        }
    }
}

#[derive(Debug, Clone)]
pub struct CommandRunOutcome {
    pub run_id: String,
    pub status: CommandRunStatus,
    pub exit_code: Option<i32>,
    pub elapsed_ms: u32,
    pub output_tail: String,
    /// `Detached` cuenta como exito: un paso de macro que abre OBS no puede
    /// bloquear la macro hasta que el usuario cierre OBS.
    pub ok: bool,
}

impl From<nexodeck_actions::RunOutcome> for CommandRunOutcome {
    fn from(value: nexodeck_actions::RunOutcome) -> Self {
        let ok = value.is_ok();
        CommandRunOutcome {
            run_id: value.run_id,
            status: value.status.into(),
            exit_code: value.exit_code,
            elapsed_ms: value.elapsed_ms,
            output_tail: value.output_tail,
            ok,
        }
    }
}

#[derive(Debug, Clone)]
pub enum CommandRunEvent {
    Started {
        run_id: String,
        label: String,
        command: String,
        /// `false` en la ruta elevada: un proceso de integridad media no
        /// puede matar a uno de integridad alta, asi que la UI tiene que
        /// esconder el boton de cancelar en vez de ofrecer uno inerte.
        cancellable: bool,
    },
    Output {
        run_id: String,
        stream: CommandOutputStream,
        lines: Vec<String>,
    },
    Detached {
        run_id: String,
        elapsed_ms: u32,
    },
    Finished {
        run_id: String,
        exit_code: Option<i32>,
        elapsed_ms: u32,
        ok: bool,
        /// Ya se habia dado por "lanzada": no hay ninguna notificacion viva
        /// para este run, asi que si `ok` es `false` hay que abrir una nueva.
        after_detach: bool,
        dropped_lines: u32,
        output_tail: String,
    },
    Cancelled {
        run_id: String,
        elapsed_ms: u32,
    },
    Failed {
        run_id: String,
        detail: String,
    },
}

impl From<nexodeck_actions::RunEvent> for CommandRunEvent {
    fn from(value: nexodeck_actions::RunEvent) -> Self {
        use nexodeck_actions::RunEvent as E;
        match value {
            E::Started {
                run_id,
                label,
                command,
                cancellable,
            } => CommandRunEvent::Started {
                run_id,
                label,
                command,
                cancellable,
            },
            E::Output {
                run_id,
                stream,
                lines,
            } => CommandRunEvent::Output {
                run_id,
                stream: stream.into(),
                lines,
            },
            E::Detached { run_id, elapsed_ms } => CommandRunEvent::Detached { run_id, elapsed_ms },
            E::Finished {
                run_id,
                exit_code,
                elapsed_ms,
                ok,
                after_detach,
                dropped_lines,
                output_tail,
            } => CommandRunEvent::Finished {
                run_id,
                exit_code,
                elapsed_ms,
                ok,
                after_detach,
                dropped_lines,
                output_tail,
            },
            E::Cancelled { run_id, elapsed_ms } => CommandRunEvent::Cancelled { run_id, elapsed_ms },
            E::Failed { run_id, detail } => CommandRunEvent::Failed { run_id, detail },
        }
    }
}

/// Arranca una ejecucion capturada y devuelve su id.
///
/// **Es `async` por obligacion**, no por gusto: frb corre las funciones
/// `async` dentro de su propio `tokio::runtime::Runtime`, y esta funcion hace
/// `tokio::spawn` de las tareas que bombean la salida. Desde una funcion
/// sincrona no habria reactor y el spawn panickearia.
///
/// El `Err` cubre lo mismo que hoy cubre `execute_terminal_action`: no se
/// pudo lanzar el proceso. Todo lo demas (codigo != 0, cancelacion) llega por
/// `watch_command_runs` y por `await_command_run`.
pub async fn start_captured_command(
    label: String,
    command: String,
    terminal_type: TerminalType,
    requires_admin: bool,
) -> Result<String, String> {
    nexodeck_actions::runner()
        .start(nexodeck_actions::RunSpec {
            label,
            command,
            terminal_type: terminal_type.into(),
            requires_admin,
        })
        .map_err(|e| e.to_string())
}

/// Se resuelve cuando la ejecucion llega a un estado terminal. **`Detached`
/// cuenta como terminal**: es lo que permite que una macro siga despues de un
/// paso "Abrir OBS" en vez de esperar a que el usuario cierre OBS.
pub async fn await_command_run(run_id: String) -> Result<CommandRunOutcome, String> {
    nexodeck_actions::runner()
        .wait(&run_id)
        .await
        .map(CommandRunOutcome::from)
        .ok_or_else(|| format!("no existe la ejecucion {run_id}"))
}

/// `false` si el id no existe o si la ejecucion no es cancelable (elevada).
pub async fn cancel_command_run(run_id: String) -> bool {
    nexodeck_actions::runner().cancel(&run_id)
}

/// Salida completa que quedo en el anillo. Existe para cuando el usuario abre
/// el detalle DESPUES de que el comando termino: sin esto la unica salida
/// disponible seria la que la UI alcanzo a acumular en vivo.
pub async fn command_run_output(run_id: String) -> Vec<String> {
    nexodeck_actions::runner().output(&run_id)
}

/// Stream global de eventos de **todas** las ejecuciones. No devuelve
/// `Result` (limitacion de FRB): los fallos llegan como
/// `CommandRunEvent::Failed`.
///
/// Del lado Dart se consume con **suscripcion directa al `Stream`**, nunca
/// con `ref.listen` sobre un provider: dos `Output` identicos seguidos son
/// perfectamente posibles y Riverpod no vuelve a notificar cuando el valor
/// nuevo es `==` al anterior. Ver la seccion "Eventos del bridge" de
/// `CLAUDE.md`.
pub async fn watch_command_runs(sink: StreamSink<CommandRunEvent>) {
    let mut events = nexodeck_actions::runner().subscribe();
    loop {
        match events.recv().await {
            Ok(event) => {
                if sink.add(event.into()).is_err() {
                    break; // Dart cerro el stream
                }
            }
            // Se perdieron eventos por atraso. **Hay que seguir**: un
            // `flutter analyze` emitiendo 8 lotes por segundo contra una UI
            // reconstruyendose puede atrasar el canal, y cortar aca dejaria
            // la notificacion congelada a mitad de la ejecucion.
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
}
