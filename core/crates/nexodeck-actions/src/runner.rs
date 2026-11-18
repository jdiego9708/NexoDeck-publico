//! Ejecucion **capturada** de comandos: el proceso corre sin ninguna ventana
//! de consola y su salida se lee por pipes y se emite como eventos, para que
//! la UI pueda mostrar en vivo si arranco, que esta imprimiendo, cuanto
//! tarda, y con que codigo termino.
//!
//! Convive con `terminal.rs`, que sigue siendo el modo **ventana**: ese abre
//! una consola real y es la unica via para comandos interactivos (`ssh`,
//! `npm init`), que capturados se colgarian esperando un input que nadie
//! puede escribir. Quien elige entre los dos es el flag `show_window` de la
//! accion.
//!
//! El patron de "singleton + broadcast" esta calcado de
//! `nexodeck-ai/src/engine.rs`, y el de "leer la salida de un hijo" de
//! `nexodeck-ai/src/sidecar.rs` -- **con una diferencia deliberada**: aca NO
//! se usa `BufReader::lines()`. Ver `LineSplitter`.

use std::collections::{HashMap, VecDeque};
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use tokio::io::AsyncReadExt;
use tokio::sync::{broadcast, mpsc, oneshot};

use crate::terminal::{self, TerminalType};
use crate::ActionError;

// ---------------------------------------------------------------------
// Constantes de comportamiento
// ---------------------------------------------------------------------

// NO hay umbral de "detach por silencio", y no es un olvido.
//
// El diseno original marcaba como "app lanzada" a todo proceso que siguiera
// vivo y mudo a los 2 s. Medido contra el caso de uso real
// (`cd <repo> && flutter analyze`, con la salida a un pipe): la **primera
// linea tarda 104 segundos**. O sea que la heuristica daba por "lanzada" —y
// cerraba la notificacion— justo el comando que mas necesita mostrarse, y
// dejaba al usuario sin ninguna senal por casi dos minutos.
//
// El silencio simplemente no distingue "app de ventana" de "comando lento":
// lo unico que los separa de verdad es tener una ventana visible, y eso no se
// puede saber sin enumerar el arbol de procesos con la API de Windows.
//
// En la practica el caso que la heuristica venia a cubrir casi no existe:
// las acciones que abren apps usan `start` (`start obs64.exe`), y con
// `cmd /C` eso **retorna en el acto**, asi que el run termina normalmente en
// ~100 ms con codigo 0. Solo quedaria colgado un GUI invocado sin `start`, y
// para eso esta el boton de cancelar.
//
// `RunStatus::Detached` sigue existiendo porque el protocolo lo transporta
// (`RunPhaseWire::Launched`) y porque una deteccion por ventana real seria el
// lugar natural para reintroducirlo.

/// Cada cuanto se agrupan las lineas nuevas en un solo evento. Sin esto un
/// `cargo build` verboso genera miles de mensajes por el bridge FFI para
/// dibujar un texto que igual cambia 8 veces por segundo.
const BATCH_INTERVAL: Duration = Duration::from_millis(120);

/// Techo de la salida que se guarda en memoria por ejecucion. Un `Vec` sin
/// techo es una fuga con cualquier comando que loguee en loop.
const RING_LINES: usize = 2000;
const RING_BYTES: usize = 256 * 1024;

/// Un comando que escupe megabytes sin un solo salto de linea no puede hacer
/// crecer el acumulador sin limite.
const MAX_LINE_BYTES: usize = 4096;

/// Cuanto del final de la salida viaja en el evento de cierre (historial y,
/// recortado de nuevo, el telefono).
const TAIL_BYTES: usize = 8 * 1024;

/// Margen para que los lectores de los pipes terminen de drenar despues de
/// que el proceso murio. Sin techo, un nieto que heredo el pipe y sigue vivo
/// dejaria la ejecucion "abierta" para siempre.
const DRAIN_GRACE: Duration = Duration::from_millis(500);

/// Cuantas ejecuciones ya terminadas se recuerdan para poder responderle a un
/// `wait()` que llegue tarde.
const MAX_REMEMBERED: usize = 64;

const BROADCAST_CAPACITY: usize = 512;

// ---------------------------------------------------------------------
// Tipos publicos
// ---------------------------------------------------------------------

/// Identificador de una ejecucion.
///
/// `String` y no `u64` **a proposito**: flutter_rust_bridge mapea `u64` a
/// `BigInt` del lado Dart (se ve en `HardwareSnapshot.netRxBytes`, que llega
/// como `BigInt`), y un `BigInt` como clave de un `Map` en la UI es incomodo
/// sin ganar nada. Ademas este mismo string nombra el script temporal, asi
/// que un archivo huerfano en `%TEMP%` se puede atribuir a una ejecucion.
pub type RunId = String;

#[derive(Debug, Clone)]
pub struct RunSpec {
    /// Nombre de la accion, para que la notificacion no muestre el comando
    /// crudo. Viaja en `Started` para que la UI no tenga que mantener su
    /// propio mapa `run_id -> nombre`.
    pub label: String,
    pub command: String,
    pub terminal_type: TerminalType,
    pub requires_admin: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputStream {
    Stdout,
    Stderr,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunStatus {
    Succeeded,
    Failed,
    Cancelled,
    /// Sigue vivo pero se dejo de seguir: era una app, no un comando.
    Detached,
}

#[derive(Debug, Clone)]
pub enum RunEvent {
    Started {
        run_id: RunId,
        label: String,
        command: String,
        /// `false` en la ruta elevada: un proceso de integridad media no
        /// puede matar a uno de integridad alta, asi que la UI esconde el
        /// boton en vez de ofrecer uno que no hace nada.
        cancellable: bool,
    },
    Output {
        run_id: RunId,
        stream: OutputStream,
        lines: Vec<String>,
    },
    /// El proceso sigue vivo y no dijo nada en `DETACH_AFTER`: casi seguro es
    /// una app de ventana (OBS, VS Code) y no un comando con salida. La UI lo
    /// muestra como "Lanzada" y cierra la notificacion.
    ///
    /// **No se deja de supervisar.** Si mas tarde sale con codigo != 0 se
    /// emite igual un `Finished { after_detach: true }`: un fallo mudo es
    /// exactamente lo que este modulo viene a eliminar.
    Detached {
        run_id: RunId,
        elapsed_ms: u32,
    },
    Finished {
        run_id: RunId,
        exit_code: Option<i32>,
        elapsed_ms: u32,
        ok: bool,
        /// Ya se habia dado por "lanzada" cuando termino: la UI no tiene
        /// ninguna notificacion viva para este run y, si `ok` es `false`,
        /// tiene que abrir una nueva.
        after_detach: bool,
        /// Lineas descartadas por el anillo. Que la UI pueda decir "se
        /// omitieron N lineas" en vez de mentir por omision.
        dropped_lines: u32,
        output_tail: String,
    },
    Cancelled {
        run_id: RunId,
        elapsed_ms: u32,
    },
    /// No se pudo ejecutar. Distinto de `Finished { ok: false }`: ahi el
    /// comando corrio y fallo; aca nunca llego a correr.
    Failed {
        run_id: RunId,
        detail: String,
    },
}

impl RunEvent {
    pub fn run_id(&self) -> &str {
        match self {
            RunEvent::Started { run_id, .. }
            | RunEvent::Output { run_id, .. }
            | RunEvent::Detached { run_id, .. }
            | RunEvent::Finished { run_id, .. }
            | RunEvent::Cancelled { run_id, .. }
            | RunEvent::Failed { run_id, .. } => run_id,
        }
    }
}

/// Lo que le importa a quien **espera** una ejecucion (el motor de macros y
/// el deck): si puede seguir o si tiene que abortar.
#[derive(Debug, Clone)]
pub struct RunOutcome {
    pub run_id: RunId,
    pub status: RunStatus,
    pub exit_code: Option<i32>,
    pub elapsed_ms: u32,
    pub output_tail: String,
}

impl RunOutcome {
    /// `Detached` cuenta como exito **a proposito**: un paso de macro que
    /// abre OBS no puede bloquear la macro hasta que el usuario cierre OBS.
    /// Es la linea que protege a toda accion "Abrir X" dentro de una macro.
    pub fn is_ok(&self) -> bool {
        matches!(self.status, RunStatus::Succeeded | RunStatus::Detached)
    }
}

/// Una ejecucion tal como la ve quien pregunta desde fuera, sin haber
/// escuchado los eventos.
#[derive(Debug, Clone)]
pub struct RunSummary {
    pub run_id: RunId,
    pub label: String,
    pub command: String,
    /// `None` mientras sigue corriendo.
    pub status: Option<RunStatus>,
    pub exit_code: Option<i32>,
    pub elapsed_ms: u32,
    pub cancellable: bool,
}

impl RunSummary {
    pub fn is_running(&self) -> bool {
        self.status.is_none()
    }
}

// ---------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------

struct RunSlot {
    /// Nombre y comando se guardan para poder **listar** las ejecuciones
    /// (`CommandRunner::list`). Hasta que existio esa API alcanzaba con
    /// mandarlos en `RunEvent::Started`, porque el unico consumidor era la UI
    /// y esa se los quedaba al vuelo; quien llega despues, como el servidor de
    /// control, no vio ese evento pasar.
    label: String,
    command: String,
    started: Instant,
    /// `None` una vez que ya se pidio la cancelacion.
    cancel: Option<oneshot::Sender<()>>,
    /// Se completa cuando la ejecucion queda resuelta para quien espera
    /// (o sea: tambien al detachar, no solo al terminar).
    outcome: Option<RunOutcome>,
    waiters: Vec<oneshot::Sender<RunOutcome>>,
    /// El anillo sigue disponible despues de terminar, para que abrir el
    /// detalle de una notificacion vieja muestre la salida completa.
    output: Arc<Mutex<OutputRing>>,
    cancellable: bool,
}

pub struct CommandRunner {
    events: broadcast::Sender<RunEvent>,
    slots: Mutex<HashMap<RunId, RunSlot>>,
    /// Orden de llegada, para poder podar los slots viejos ya resueltos.
    order: Mutex<VecDeque<RunId>>,
    counter: AtomicU64,
}

static RUNNER: OnceLock<Arc<CommandRunner>> = OnceLock::new();

/// Singleton. Vive fuera de cualquier sesion porque el stream de eventos que
/// escucha Dart se abre una sola vez, al arrancar la app, y tiene que seguir
/// sirviendo a todas las ejecuciones posteriores -- mismo razonamiento que el
/// `Engine` de `nexodeck-ai`.
pub fn runner() -> Arc<CommandRunner> {
    RUNNER
        .get_or_init(|| {
            let (events, _) = broadcast::channel(BROADCAST_CAPACITY);
            Arc::new(CommandRunner {
                events,
                slots: Mutex::new(HashMap::new()),
                order: Mutex::new(VecDeque::new()),
                counter: AtomicU64::new(0),
            })
        })
        .clone()
}

impl CommandRunner {
    pub fn subscribe(&self) -> broadcast::Receiver<RunEvent> {
        self.events.subscribe()
    }

    /// Lanza el comando y devuelve su id **apenas el proceso arranco**. El
    /// seguimiento sigue en una tarea aparte; el resultado se obtiene con
    /// [`CommandRunner::wait`] o escuchando los eventos.
    ///
    /// Tiene que llamarse desde adentro de un runtime de tokio -- lo
    /// garantiza la capa FFI, que expone esto como `async fn` (frb corre las
    /// `async fn` en su propio `Runtime`; desde una funcion sincrona no
    /// habria reactor y el `tokio::spawn` de adentro panickearia).
    pub fn start(self: &Arc<Self>, spec: RunSpec) -> Result<RunId, ActionError> {
        let run_id = format!(
            "run_{}_{}",
            self.counter.fetch_add(1, Ordering::Relaxed),
            terminal::unique_suffix()
        );

        let launch = match build_launch(&run_id, &spec) {
            Ok(launch) => launch,
            Err(e) => {
                // El evento se emite igual para que la notificacion pueda
                // mostrar el fallo, ademas de devolver el Err a quien llamo.
                let _ = self.events.send(RunEvent::Failed {
                    run_id,
                    detail: e.to_string(),
                });
                return Err(e);
            }
        };

        let (cancel_tx, cancel_rx) = oneshot::channel();
        let output = Arc::new(Mutex::new(OutputRing::default()));
        self.insert_slot(
            &run_id,
            &spec,
            cancel_tx,
            Arc::clone(&output),
            launch.cancellable,
        );

        let _ = self.events.send(RunEvent::Started {
            run_id: run_id.clone(),
            label: spec.label.clone(),
            command: spec.command.clone(),
            cancellable: launch.cancellable,
        });

        let this = Arc::clone(self);
        let id = run_id.clone();
        tokio::spawn(async move {
            this.supervise(id, launch, output, cancel_rx).await;
        });
        Ok(run_id)
    }

    /// Mata el arbol de procesos de esa ejecucion. No espera a que muera.
    /// Devuelve `false` si el id no existe o si el run no es cancelable.
    pub fn cancel(&self, run_id: &str) -> bool {
        let Ok(mut slots) = self.slots.lock() else {
            return false;
        };
        let Some(slot) = slots.get_mut(run_id) else {
            return false;
        };
        if !slot.cancellable {
            return false;
        }
        match slot.cancel.take() {
            Some(tx) => {
                let _ = tx.send(());
                true
            }
            None => false,
        }
    }

    /// Espera a que la ejecucion quede resuelta. `None` si ese `run_id` no
    /// existe ni se recuerda.
    pub async fn wait(&self, run_id: &str) -> Option<RunOutcome> {
        let rx = {
            let mut slots = self.slots.lock().ok()?;
            let slot = slots.get_mut(run_id)?;
            if let Some(outcome) = &slot.outcome {
                return Some(outcome.clone());
            }
            let (tx, rx) = oneshot::channel();
            slot.waiters.push(tx);
            rx
        };
        rx.await.ok()
    }

    /// Anillo completo de salida. Existe para cuando el usuario abre el
    /// detalle DESPUES de que el comando termino: sin esto la unica salida
    /// disponible seria la que la UI alcanzo a acumular en vivo.
    pub fn output(&self, run_id: &str) -> Vec<String> {
        self.slots
            .lock()
            .ok()
            .and_then(|slots| {
                slots
                    .get(run_id)
                    .and_then(|slot| slot.output.lock().ok().map(|ring| ring.lines()))
            })
            .unwrap_or_default()
    }

    /// Todas las ejecuciones que el runner todavia recuerda, **de la mas
    /// reciente a la mas vieja**.
    ///
    /// Existe para quien llega a mitad de partido: la UI se entera de cada
    /// ejecucion por `RunEvent::Started` y se arma su propia lista, pero el
    /// servidor de control responde a preguntas puntuales y nunca vio pasar
    /// esos eventos. Sin esto, preguntarle "que esta corriendo" solo podria
    /// contestarse desde el momento en que alguien se suscribio.
    pub fn list(&self) -> Vec<RunSummary> {
        let (Ok(slots), Ok(order)) = (self.slots.lock(), self.order.lock()) else {
            return Vec::new();
        };
        order
            .iter()
            .rev()
            .filter_map(|run_id| {
                let slot = slots.get(run_id)?;
                Some(RunSummary {
                    run_id: run_id.clone(),
                    label: slot.label.clone(),
                    command: slot.command.clone(),
                    // Una ejecucion viva no tiene estado terminal todavia. Es
                    // `None` y no un `RunStatus::Running` inventado: el enum
                    // describe como TERMINO algo, y agregarle una variante
                    // "corriendo" obligaria a tocar cada `match` que ya existe.
                    status: slot.outcome.as_ref().map(|o| o.status),
                    exit_code: slot.outcome.as_ref().and_then(|o| o.exit_code),
                    elapsed_ms: match &slot.outcome {
                        Some(outcome) => outcome.elapsed_ms,
                        None => slot.started.elapsed().as_millis().min(u128::from(u32::MAX)) as u32,
                    },
                    cancellable: slot.cancellable && slot.outcome.is_none(),
                })
            })
            .collect()
    }

    fn insert_slot(
        &self,
        run_id: &str,
        spec: &RunSpec,
        cancel: oneshot::Sender<()>,
        output: Arc<Mutex<OutputRing>>,
        cancellable: bool,
    ) {
        if let (Ok(mut slots), Ok(mut order)) = (self.slots.lock(), self.order.lock()) {
            slots.insert(
                run_id.to_string(),
                RunSlot {
                    label: spec.label.clone(),
                    command: spec.command.clone(),
                    started: Instant::now(),
                    cancel: Some(cancel),
                    outcome: None,
                    waiters: Vec::new(),
                    output,
                    cancellable,
                },
            );
            order.push_back(run_id.to_string());

            // Poda: solo se descartan los que ya estan resueltos, para no
            // dejar sin respuesta a un `wait()` de una ejecucion viva.
            let mut checked = 0;
            while order.len() > MAX_REMEMBERED && checked < order.len() {
                let Some(old) = order.pop_front() else { break };
                let resolved = slots
                    .get(&old)
                    .map(|slot| slot.outcome.is_some())
                    .unwrap_or(true);
                if resolved {
                    slots.remove(&old);
                } else {
                    order.push_back(old);
                    checked += 1;
                }
            }
        }
    }

    /// Deja el resultado disponible para quien espere y despierta a los que
    /// ya estaban esperando. Idempotente: **el primero gana**, que es lo que
    /// hace que `Detached` desbloquee la macro y un `Finished` posterior no
    /// la vuelva a tocar.
    fn resolve(&self, outcome: RunOutcome) {
        let waiters = {
            let Ok(mut slots) = self.slots.lock() else {
                return;
            };
            let Some(slot) = slots.get_mut(&outcome.run_id) else {
                return;
            };
            if slot.outcome.is_some() {
                return;
            }
            slot.outcome = Some(outcome.clone());
            // OJO: aca **no** se suelta `slot.cancel`. Soltar el `Sender`
            // hace que el `Receiver` del supervisor se complete con `Err`, y
            // un `oneshot` en un `select!` despierta igual por error que por
            // valor. Como `resolve()` corre tambien al detachar, soltarlo
            // convertia toda app lanzada en una "Cancelada" a los 2 s, y de
            // paso le tiraba un `taskkill` encima. El supervisor ahora
            // distingue los dos casos, pero conservar el sender ademas deja
            // que se pueda cancelar una ejecucion ya detachada.
            std::mem::take(&mut slot.waiters)
        };
        for waiter in waiters {
            let _ = waiter.send(outcome.clone());
        }
    }

    async fn supervise(
        self: Arc<Self>,
        run_id: RunId,
        launch: Launch,
        ring: Arc<Mutex<OutputRing>>,
        mut cancel_rx: oneshot::Receiver<()>,
    ) {
        let started = Instant::now();
        let Launch {
            mut child,
            script_path,
            redirect_path,
            ..
        } = launch;

        let pid = child.id();
        let (tx, mut rx) = mpsc::channel::<(OutputStream, String)>(256);

        if let Some(pipe) = child.stdout.take() {
            spawn_pipe_reader(pipe, OutputStream::Stdout, tx.clone());
        }
        if let Some(pipe) = child.stderr.take() {
            spawn_pipe_reader(pipe, OutputStream::Stderr, tx.clone());
        }
        // La ruta elevada no tiene pipes utiles: la salida real del comando
        // va a un archivo que el propio script escribe (ver `spawn_elevated`).
        let tail_stop = redirect_path.as_ref().map(|path| {
            let (stop_tx, stop_rx) = oneshot::channel();
            spawn_file_tailer(path.clone(), tx.clone(), stop_rx);
            stop_tx
        });
        drop(tx);

        let mut pending: Vec<(OutputStream, String)> = Vec::new();
        let mut ticker = tokio::time::interval(BATCH_INTERVAL);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

        let mut cancelled = false;
        // El `oneshot` de cancelacion ya se resolvio (de una forma u otra) y
        // no se puede volver a poll-ear.
        let mut cancel_settled = false;
        let mut readers_done = false;
        let mut exit: Option<std::process::ExitStatus> = None;
        let mut drain_deadline: Option<tokio::time::Instant> = None;

        loop {
            tokio::select! {
                biased;

                requested = &mut cancel_rx, if !cancel_settled => {
                    cancel_settled = true;
                    // **Solo un `Ok` es una cancelacion.** Un `Err` significa
                    // que el `Sender` se solto sin mandar nada, que no es lo
                    // mismo ni por asomo: un `oneshot` en un `select!`
                    // despierta igual por error que por valor.
                    if requested.is_ok() {
                        cancelled = true;
                        if let Some(pid) = pid {
                            kill_tree(pid);
                        }
                    }
                }

                status = child.wait(), if exit.is_none() => {
                    exit = Some(status.unwrap_or_else(|_| failed_exit_status()));
                    drain_deadline = Some(tokio::time::Instant::now() + DRAIN_GRACE);
                }

                line = rx.recv(), if !readers_done => {
                    match line {
                        Some((stream, text)) => {
                            if let Ok(mut ring) = ring.lock() {
                                ring.push(&text);
                            }
                            pending.push((stream, text));
                        }
                        None => readers_done = true,
                    }
                }

                _ = ticker.tick() => {
                    self.flush(&run_id, &mut pending);
                }
            }

            if exit.is_some() {
                let drained = readers_done
                    || drain_deadline
                        .map(|deadline| tokio::time::Instant::now() >= deadline)
                        .unwrap_or(true);
                if drained {
                    break;
                }
            }
        }

        // El tailer del archivo (ruta elevada) se corta recien aca, para que
        // alcance a leer lo que el comando escribio justo antes de salir.
        if let Some(stop) = tail_stop {
            let _ = stop.send(());
            // Una vuelta mas de drenado, corta.
            let deadline = tokio::time::Instant::now() + DRAIN_GRACE;
            while tokio::time::Instant::now() < deadline {
                match tokio::time::timeout(Duration::from_millis(50), rx.recv()).await {
                    Ok(Some((stream, text))) => {
                        if let Ok(mut ring) = ring.lock() {
                            ring.push(&text);
                        }
                        pending.push((stream, text));
                    }
                    Ok(None) => break,
                    Err(_) => continue,
                }
            }
        }
        self.flush(&run_id, &mut pending);

        let elapsed = elapsed_ms(started);
        let (output_tail, dropped_lines) = ring
            .lock()
            .map(|ring| (ring.tail(), ring.dropped))
            .unwrap_or_default();
        let exit_code = exit.as_ref().and_then(|status| status.code());

        if cancelled {
            let _ = self.events.send(RunEvent::Cancelled {
                run_id: run_id.clone(),
                elapsed_ms: elapsed,
            });
            self.resolve(RunOutcome {
                run_id,
                status: RunStatus::Cancelled,
                exit_code,
                elapsed_ms: elapsed,
                output_tail,
            });
        } else {
            let ok = exit.as_ref().map(|status| status.success()).unwrap_or(false);
            let _ = self.events.send(RunEvent::Finished {
                run_id: run_id.clone(),
                exit_code,
                elapsed_ms: elapsed,
                ok,
                // Hoy siempre `false`: ya no hay detach por silencio (ver la
                // nota larga arriba). El campo se conserva porque el
                // protocolo y la UI ya saben interpretarlo, y volveria a
                // usarse si alguna vez se detecta la app por su ventana.
                after_detach: false,
                dropped_lines,
                output_tail: output_tail.clone(),
            });
            self.resolve(RunOutcome {
                run_id,
                status: if ok {
                    RunStatus::Succeeded
                } else {
                    RunStatus::Failed
                },
                exit_code,
                elapsed_ms: elapsed,
                output_tail,
            });
        }

        cleanup(script_path, redirect_path);
    }

    fn flush(&self, run_id: &str, pending: &mut Vec<(OutputStream, String)>) {
        if pending.is_empty() {
            return;
        }
        // Se agrupa por stream conservando el orden: mezclar stdout y stderr
        // en un solo evento perderia cual era cual, y son colores distintos
        // en la UI.
        let mut batch: Vec<String> = Vec::new();
        let mut current = pending[0].0;
        for (stream, text) in pending.drain(..) {
            if stream != current && !batch.is_empty() {
                let _ = self.events.send(RunEvent::Output {
                    run_id: run_id.to_string(),
                    stream: current,
                    lines: std::mem::take(&mut batch),
                });
            }
            current = stream;
            batch.push(text);
        }
        if !batch.is_empty() {
            let _ = self.events.send(RunEvent::Output {
                run_id: run_id.to_string(),
                stream: current,
                lines: batch,
            });
        }
    }
}

fn elapsed_ms(started: Instant) -> u32 {
    started.elapsed().as_millis().min(u32::MAX as u128) as u32
}

// ---------------------------------------------------------------------
// Partido en lineas
// ---------------------------------------------------------------------

/// Convierte bytes crudos en lineas de texto.
///
/// **No se usa `BufReader::lines()`**, aunque sea lo que hace `sidecar.rs`.
/// Ese metodo exige UTF-8 valido y devuelve `Err(InvalidData)` en cuanto
/// aparece un byte que no lo es; con `while let Ok(Some(..))` eso **corta la
/// lectura en silencio**. En Windows la consola entrega cp850/cp1252, asi que
/// la primera tilde de un mensaje en espanol truncaria la salida a la mitad
/// sin ningun error visible -- justo el sintoma mudo que este modulo viene a
/// eliminar. `llama-server` se salva de esto solo porque emite ASCII.
///
/// Ademas parte por `\r` suelto: `flutter analyze` y `cargo` dibujan su
/// progreso con retornos de carro, y sin esto 30 segundos de comando
/// producirian una sola linea gigante.
#[derive(Default)]
struct LineSplitter {
    buf: Vec<u8>,
}

impl LineSplitter {
    fn push(&mut self, bytes: &[u8]) -> Vec<String> {
        self.buf.extend_from_slice(bytes);
        let mut out = Vec::new();

        loop {
            let Some(idx) = self.buf.iter().position(|b| *b == b'\n' || *b == b'\r') else {
                break;
            };
            // Un `\r` justo al final del buffer todavia no se puede resolver:
            // puede ser un `\r\n` partido entre dos lecturas.
            if self.buf[idx] == b'\r' && idx + 1 == self.buf.len() {
                break;
            }
            let consume = if self.buf[idx] == b'\r' && self.buf.get(idx + 1) == Some(&b'\n') {
                idx + 2
            } else {
                idx + 1
            };
            let line = decode(&self.buf[..idx]);
            self.buf.drain(..consume);
            out.push(line);
        }

        if self.buf.len() > MAX_LINE_BYTES {
            out.push(decode(&self.buf));
            self.buf.clear();
        }
        out
    }

    /// Ultima linea, si el comando no termino con salto.
    fn finish(&mut self) -> Option<String> {
        if self.buf.is_empty() {
            return None;
        }
        let line = decode(&self.buf);
        self.buf.clear();
        if line.is_empty() {
            None
        } else {
            Some(line)
        }
    }
}

/// Decodifica tolerando bytes invalidos y saca las secuencias de color ANSI.
/// La mayoria de las herramientas apagan el color cuando su salida no es una
/// tty, pero no todas, y una notificacion llena de `\x1b[32m` es ilegible.
fn decode(bytes: &[u8]) -> String {
    strip_ansi(&String::from_utf8_lossy(bytes))
}

fn strip_ansi(input: &str) -> String {
    if !input.contains('\x1b') {
        return input.to_string();
    }
    let mut out = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\x1b' {
            out.push(c);
            continue;
        }
        match chars.peek() {
            // CSI: ESC [ ... <byte final en 0x40..=0x7E>
            Some('[') => {
                chars.next();
                for c in chars.by_ref() {
                    if ('\u{40}'..='\u{7e}').contains(&c) {
                        break;
                    }
                }
            }
            // OSC: ESC ] ... BEL o ESC \
            Some(']') => {
                chars.next();
                while let Some(c) = chars.next() {
                    if c == '\u{7}' {
                        break;
                    }
                    if c == '\x1b' {
                        chars.next();
                        break;
                    }
                }
            }
            _ => {
                chars.next();
            }
        }
    }
    out
}

// ---------------------------------------------------------------------
// Anillo de salida
// ---------------------------------------------------------------------

#[derive(Default)]
struct OutputRing {
    lines: VecDeque<String>,
    bytes: usize,
    dropped: u32,
}

impl OutputRing {
    fn push(&mut self, line: &str) {
        self.bytes += line.len() + 1;
        self.lines.push_back(line.to_string());
        while self.lines.len() > RING_LINES || self.bytes > RING_BYTES {
            let Some(dropped) = self.lines.pop_front() else {
                break;
            };
            self.bytes -= dropped.len() + 1;
            self.dropped += 1;
        }
    }

    fn lines(&self) -> Vec<String> {
        self.lines.iter().cloned().collect()
    }

    fn tail(&self) -> String {
        let mut out = String::new();
        for line in self.lines.iter().rev() {
            if out.len() + line.len() + 1 > TAIL_BYTES {
                break;
            }
            out.insert(0, '\n');
            out.insert_str(0, line);
        }
        if self.dropped > 0 {
            out.insert_str(0, &format!("[...{} lineas omitidas...]\n", self.dropped));
        }
        out
    }
}

// ---------------------------------------------------------------------
// Lectores
// ---------------------------------------------------------------------

fn spawn_pipe_reader<R>(pipe: R, stream: OutputStream, tx: mpsc::Sender<(OutputStream, String)>)
where
    R: tokio::io::AsyncRead + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let mut pipe = pipe;
        let mut splitter = LineSplitter::default();
        let mut buf = [0u8; 8192];
        loop {
            let Ok(read) = pipe.read(&mut buf).await else {
                break;
            };
            if read == 0 {
                break;
            }
            for line in splitter.push(&buf[..read]) {
                // El `await` de un canal lleno frena la lectura del pipe y,
                // por rebote, al proceso: es contrapresion, no descarte.
                // Tirar salida en silencio es exactamente lo que no se puede
                // hacer aca.
                if tx.send((stream, line)).await.is_err() {
                    return;
                }
            }
        }
        if let Some(line) = splitter.finish() {
            let _ = tx.send((stream, line)).await;
        }
    });
}

/// Sigue un archivo que crece, para la ruta elevada. Se hace con `std::fs` y
/// no con `tokio::fs` porque son lecturas chicas cada 200 ms: no justifica
/// sumarle la feature `fs` a tokio.
fn spawn_file_tailer(
    path: PathBuf,
    tx: mpsc::Sender<(OutputStream, String)>,
    mut stop: oneshot::Receiver<()>,
) {
    tokio::spawn(async move {
        let mut offset: u64 = 0;
        let mut splitter = LineSplitter::default();
        let mut stopping = false;

        loop {
            if let Ok(mut file) = std::fs::File::open(&path) {
                if file.seek(SeekFrom::Start(offset)).is_ok() {
                    let mut buf = Vec::new();
                    if let Ok(read) = file.read_to_end(&mut buf) {
                        offset += read as u64;
                        for line in splitter.push(&buf) {
                            if tx.send((OutputStream::Stdout, line)).await.is_err() {
                                return;
                            }
                        }
                    }
                }
            }

            // Una vuelta mas despues del stop: es la que recoge lo que el
            // comando escribio justo antes de terminar.
            if stopping {
                if let Some(line) = splitter.finish() {
                    let _ = tx.send((OutputStream::Stdout, line)).await;
                }
                return;
            }
            tokio::select! {
                _ = &mut stop => stopping = true,
                _ = tokio::time::sleep(Duration::from_millis(200)) => {}
            }
        }
    });
}

// ---------------------------------------------------------------------
// Lanzamiento
// ---------------------------------------------------------------------

struct Launch {
    child: tokio::process::Child,
    script_path: Option<PathBuf>,
    redirect_path: Option<PathBuf>,
    cancellable: bool,
}

fn build_launch(run_id: &str, spec: &RunSpec) -> Result<Launch, ActionError> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        if spec.requires_admin {
            return spawn_elevated(run_id, spec);
        }
        spawn_piped(spec)
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = (run_id, spec);
        Err(ActionError::UnsupportedPlatform)
    }
}

#[cfg(target_os = "windows")]
fn spawn_piped(spec: &RunSpec) -> Result<Launch, ActionError> {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let mut command;
    let mut script_path = None;

    match spec.terminal_type {
        // WSL es el unico caso que NO pasa por script temporal, igual que en
        // el modo ventana: el script viviria en el filesystem de Windows y
        // traducir la ruta a `/mnt/c/...` es mas fragil que pasar el comando
        // inline. No lo "arregles" al tocar esto.
        TerminalType::Bash => {
            command = tokio::process::Command::new("wsl");
            command.args(["bash", "-lc", &spec.command]);
        }
        TerminalType::PowerShell => {
            let path = terminal::write_script(&spec.command, spec.terminal_type, None)?;
            command = tokio::process::Command::new("powershell");
            // `-ExecutionPolicy Bypass` no estaba en el modo ventana y es un
            // bug latente ahi: en una maquina con la politica en `Restricted`
            // el script no corre. `-NonInteractive` evita que un `Read-Host`
            // cuelgue la ejecucion para siempre, que capturado no se ve.
            command.args([
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
            ]);
            command.arg(&path);
            script_path = Some(path);
        }
        TerminalType::DefaultShell | TerminalType::Cmd => {
            let path = terminal::write_script(&spec.command, spec.terminal_type, None)?;
            command = tokio::process::Command::new("cmd");
            // `/C` y nunca `/K`: `/K` deja el interprete vivo esperando un
            // prompt que aca no existe (stdin es null), asi que la ejecucion
            // no terminaria nunca.
            command.arg("/C").arg(&path);
            script_path = Some(path);
        }
    }

    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .kill_on_drop(true);

    let child = command.spawn()?;
    Ok(Launch {
        child,
        script_path,
        redirect_path: None,
        cancellable: true,
    })
}

#[cfg(target_os = "linux")]
fn spawn_piped(spec: &RunSpec) -> Result<Launch, ActionError> {
    let path = terminal::write_script(&spec.command, spec.terminal_type, None)?;
    let mut command = tokio::process::Command::new("bash");
    command
        .arg(&path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    // Grupo propio: es lo que permite matar el arbol entero con `kill -<pgid>`
    // cuando el usuario cancela. Sin esto solo moriria el `bash` de arriba y
    // el comando real seguiria corriendo.
    {
        use std::os::unix::process::CommandExt;
        command.as_std_mut().process_group(0);
    }

    let child = command.spawn()?;
    Ok(Launch {
        child,
        script_path: Some(path),
        redirect_path: None,
        cancellable: true,
    })
}

/// Ruta elevada (UAC). **No se puede piped**: PowerShell prohibe combinar
/// `-Verb RunAs` con `-RedirectStandardOutput`, y el proceso elevado no es
/// hijo directo nuestro. Asi que la redireccion va adentro del script que
/// corre elevado, y de este lado se sigue ese archivo mientras el trampolin
/// (que si es un hijo normal, y si se puede piped) espera con `-Wait`.
///
/// Es best-effort y **no se puede verificar de punta a punta sin un humano**
/// que apruebe el dialogo del UAC -- la misma limitacion que ya arrastra la
/// ruta de elevacion del modo ventana.
///
/// Tampoco es cancelable: un proceso de integridad media no puede matar a uno
/// de integridad alta, asi que `cancellable: false` y la UI esconde el boton
/// en vez de ofrecer uno que no hace nada.
#[cfg(target_os = "windows")]
fn spawn_elevated(run_id: &str, spec: &RunSpec) -> Result<Launch, ActionError> {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let redirect = std::env::temp_dir().join(format!("nexodeck_{run_id}.out"));
    // Se crea vacio para que el tailer no tenga que distinguir "todavia no
    // existe" de "fallo".
    std::fs::write(&redirect, "")?;

    let script = terminal::write_script(&spec.command, spec.terminal_type, Some(&redirect))?;
    let script_arg = escape_single_quotes(&script.to_string_lossy());
    let (program, args) = match spec.terminal_type {
        TerminalType::PowerShell => (
            "powershell",
            format!(
                "'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File','{script_arg}'"
            ),
        ),
        _ => ("cmd", format!("'/C','{script_arg}'")),
    };

    // `exit $p.ExitCode` propaga el codigo del comando elevado al trampolin,
    // que si es un hijo normal: es de ahi de donde sale el codigo final.
    // 1223 = ERROR_CANCELLED, el caso de "el usuario dijo que no al UAC",
    // que hoy es completamente mudo.
    let trampoline = format!(
        "$ErrorActionPreference='Stop'; \
         try {{ $p = Start-Process -FilePath '{program}' -ArgumentList {args} \
         -Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $p.ExitCode }} \
         catch {{ Write-Error $_.Exception.Message; exit 1223 }}"
    );

    let mut command = tokio::process::Command::new("powershell");
    command
        .args(["-NoProfile", "-NonInteractive", "-Command", &trampoline])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .kill_on_drop(true);

    let child = command.spawn()?;
    Ok(Launch {
        child,
        script_path: Some(script),
        redirect_path: Some(redirect),
        cancellable: false,
    })
}

#[cfg(target_os = "linux")]
fn spawn_elevated(_run_id: &str, spec: &RunSpec) -> Result<Launch, ActionError> {
    // `pkexec` levanta su propio agente grafico y su salida SI se puede
    // piped, asi que en Linux la elevacion se captura sin trampolin ni
    // archivo intermedio. Sin maquina Linux para verificarlo.
    let path = terminal::write_script(&spec.command, spec.terminal_type, None)?;
    let mut command = tokio::process::Command::new("pkexec");
    command
        .arg("bash")
        .arg(&path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let child = command.spawn()?;
    Ok(Launch {
        child,
        script_path: Some(path),
        redirect_path: None,
        cancellable: false,
    })
}

#[cfg(target_os = "windows")]
fn escape_single_quotes(s: &str) -> String {
    s.replace('\'', "''")
}

// ---------------------------------------------------------------------
// Cancelacion
// ---------------------------------------------------------------------

/// Mata el proceso **y su descendencia**.
///
/// En Windows matar el `cmd.exe` no mata a sus hijos: cancelar un
/// `flutter analyze` dejaria al `dart.exe` real corriendo, comiendo CPU, sin
/// que nada lo muestre. `taskkill /T` es lo que baja el arbol entero.
///
/// Limitacion conocida y aceptada: `taskkill /T` recorre el arbol de padres
/// **vivos**, asi que un nieto cuyo padre intermedio ya murio no se mata. La
/// alternativa completa es un Job Object de Windows, que resuelve tambien ese
/// caso pero suma la dependencia del crate `windows` y obliga a limpiar
/// `KILL_ON_JOB_CLOSE` al detachar (o cerrar NexoDeck mataria el OBS que el
/// usuario acaba de abrir). No vale la pena para el caso real.
#[cfg(target_os = "windows")]
fn kill_tree(pid: u32) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let _ = std::process::Command::new("taskkill")
        .args(["/T", "/F", "/PID", &pid.to_string()])
        .creation_flags(CREATE_NO_WINDOW)
        // Sin esto, `taskkill` hereda nuestra salida y escupe su reporte por
        // la consola de la app (o del test).
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

#[cfg(not(target_os = "windows"))]
fn kill_tree(pid: u32) {
    // El `-` pide matar al grupo entero, que existe gracias al
    // `process_group(0)` de `spawn_piped`.
    for target in [format!("-{pid}"), pid.to_string()] {
        let _ = std::process::Command::new("kill")
            .args(["-9", &target])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

// ---------------------------------------------------------------------
// Varios
// ---------------------------------------------------------------------

fn failed_exit_status() -> std::process::ExitStatus {
    // Solo se llega aca si `wait()` fallo a nivel del sistema operativo, que
    // en la practica no pasa. Se representa como "termino mal".
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        std::process::ExitStatus::from_raw(1)
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::ExitStatusExt;
        std::process::ExitStatus::from_raw(1)
    }
}

/// Los scripts temporales hasta hoy no se borraban nunca y se acumulaban en
/// `%TEMP%`. Se borran **despues** de que el proceso murio, nunca antes:
/// `cmd.exe` relee el `.bat` a medida que lo ejecuta, y borrarlo mientras
/// corre rompe la ejecucion de una forma que parece un error de sintaxis al
/// azar.
fn cleanup(script: Option<PathBuf>, redirect: Option<PathBuf>) {
    if let Some(path) = script {
        let _ = std::fs::remove_file(path);
    }
    if let Some(path) = redirect {
        let _ = std::fs::remove_file(path);
    }
}

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(command: &str) -> RunSpec {
        RunSpec {
            label: "test".into(),
            command: command.into(),
            terminal_type: TerminalType::DefaultShell,
            requires_admin: false,
        }
    }

    /// Junta todos los eventos de un `run_id` hasta que llega uno terminal.
    async fn collect(
        mut rx: broadcast::Receiver<RunEvent>,
        run_id: &str,
        stop_on_detach: bool,
    ) -> Vec<RunEvent> {
        let mut events = Vec::new();
        let deadline = tokio::time::Instant::now() + Duration::from_secs(40);
        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            let Ok(Ok(event)) = tokio::time::timeout(remaining, rx.recv()).await else {
                break;
            };
            if event.run_id() != run_id {
                continue;
            }
            let terminal = matches!(
                event,
                RunEvent::Finished { .. } | RunEvent::Cancelled { .. } | RunEvent::Failed { .. }
            ) || (stop_on_detach && matches!(event, RunEvent::Detached { .. }));
            events.push(event);
            if terminal {
                break;
            }
        }
        events
    }

    fn finished_of(events: &[RunEvent]) -> Option<(bool, Option<i32>)> {
        events.iter().find_map(|e| match e {
            RunEvent::Finished { ok, exit_code, .. } => Some((*ok, *exit_code)),
            _ => None,
        })
    }

    #[tokio::test]
    async fn success_reports_ok_and_output() {
        let runner = runner();
        let rx = runner.subscribe();
        let run_id = runner.start(spec("echo hola")).expect("start");

        let events = collect(rx, &run_id, false).await;
        let (ok, code) = finished_of(&events).expect("Finished");
        assert!(ok, "deberia haber salido bien: {events:?}");
        assert_eq!(code, Some(0));

        let outcome = runner.wait(&run_id).await.expect("outcome");
        assert!(outcome.is_ok());
        assert!(
            outcome.output_tail.contains("hola"),
            "tail: {:?}",
            outcome.output_tail
        );
    }

    /// `list()` tiene que servir a quien **no** escucho los eventos: ese es su
    /// unico motivo de existir. Por eso aca se pregunta despues de terminar,
    /// sin haberse suscrito a nada.
    #[tokio::test]
    async fn list_reports_a_run_to_someone_who_never_subscribed() {
        let runner = runner();
        let rx = runner.subscribe();
        let run_id = runner
            .start(RunSpec {
                label: "Etiqueta visible".into(),
                command: "echo listado".into(),
                terminal_type: TerminalType::DefaultShell,
                requires_admin: false,
            })
            .expect("start");
        let _ = collect(rx, &run_id, false).await;

        let listed = runner
            .list()
            .into_iter()
            .find(|r| r.run_id == run_id)
            .expect("la ejecucion tiene que aparecer en list()");

        assert_eq!(listed.label, "Etiqueta visible");
        assert_eq!(listed.command, "echo listado");
        assert!(!listed.is_running());
        assert_eq!(listed.exit_code, Some(0));
        // Ya resuelta: ofrecer cancelarla seria un boton inerte.
        assert!(!listed.cancellable);
    }

    #[tokio::test]
    async fn non_zero_exit_is_reported_as_failure() {
        let runner = runner();
        let rx = runner.subscribe();
        let command = if cfg!(windows) { "exit /b 3" } else { "exit 3" };
        let run_id = runner.start(spec(command)).expect("start");

        let events = collect(rx, &run_id, false).await;
        let (ok, code) = finished_of(&events).expect("Finished");
        assert!(!ok);
        assert_eq!(code, Some(3));
        assert!(!runner.wait(&run_id).await.expect("outcome").is_ok());
    }

    #[tokio::test]
    async fn stderr_is_tagged_as_stderr() {
        let runner = runner();
        let rx = runner.subscribe();
        let command = if cfg!(windows) {
            "echo problema 1>&2"
        } else {
            "echo problema >&2"
        };
        let run_id = runner.start(spec(command)).expect("start");

        let events = collect(rx, &run_id, false).await;
        let has_stderr = events.iter().any(|e| {
            matches!(e, RunEvent::Output { stream: OutputStream::Stderr, lines, .. }
                if lines.iter().any(|l| l.contains("problema")))
        });
        assert!(has_stderr, "no llego nada por stderr: {events:?}");
    }

    /// Un comando que tarda en decir la primera palabra **sigue siendo un
    /// comando en curso**, no una app lanzada.
    ///
    /// Es la leccion medida contra el caso real: `flutter analyze` con la
    /// salida a un pipe tarda **104 segundos** en emitir su primera linea. La
    /// heuristica anterior (mudo a los 2 s = app) daba por "lanzado" justo el
    /// comando que mas necesita verse, y encima —porque `resolve()` soltaba
    /// el `Sender` de cancelacion y un `oneshot` en un `select!` despierta
    /// igual por `Err` que por valor— terminaba emitiendo `Cancelled` y
    /// matando el proceso con `taskkill`. Lo veia el usuario como "Cancelada
    /// 2.2s" sin haber tocado nada.
    #[tokio::test]
    async fn silent_slow_command_stays_running_and_finishes_normally() {
        let runner = runner();
        let rx = runner.subscribe();
        // Vive varios segundos sin imprimir una sola linea.
        let command = if cfg!(windows) {
            "ping -n 6 127.0.0.1 > nul"
        } else {
            "sleep 6"
        };
        let run_id = runner.start(spec(command)).expect("start");

        let events = collect(rx, &run_id, false).await;

        assert!(
            !events
                .iter()
                .any(|e| matches!(e, RunEvent::Cancelled { .. })),
            "nadie cancelo esto: {events:?}"
        );
        assert!(
            !events.iter().any(|e| matches!(e, RunEvent::Detached { .. })),
            "el silencio ya no significa 'app lanzada': {events:?}"
        );

        let (ok, code) = finished_of(&events).expect("Finished");
        assert!(ok, "termino solo y bien: {events:?}");
        assert_eq!(code, Some(0));

        let outcome = runner.wait(&run_id).await.expect("outcome");
        assert_eq!(outcome.status, RunStatus::Succeeded);
    }

    /// Las acciones que abren apps usan `start`, y con `cmd /C` eso retorna en
    /// el acto: el run termina normalmente en milisegundos sin necesitar
    /// ninguna heuristica. Es la razon por la que sacar el detach por silencio
    /// no deja al caso "Abrir OBS" sin cubrir.
    #[tokio::test]
    #[cfg(windows)]
    async fn start_based_launchers_return_immediately() {
        let runner = runner();
        let rx = runner.subscribe();
        // `start` sobre algo que existe seguro y no abre ventana molesta.
        let run_id = runner
            .start(spec("start \"\" cmd /c exit"))
            .expect("start");

        let events = collect(rx, &run_id, false).await;
        let (ok, _) = finished_of(&events).expect("Finished");
        assert!(ok);

        let outcome = runner.wait(&run_id).await.expect("outcome");
        assert!(
            outcome.elapsed_ms < 2000,
            "`start` tiene que retornar enseguida, tardo {}ms",
            outcome.elapsed_ms
        );
    }

    #[tokio::test]
    async fn cancel_stops_the_run() {
        let runner = runner();
        let rx = runner.subscribe();
        let command = if cfg!(windows) {
            "ping -n 40 127.0.0.1"
        } else {
            "sleep 40"
        };
        let run_id = runner.start(spec(command)).expect("start");

        tokio::time::sleep(Duration::from_millis(400)).await;
        assert!(runner.cancel(&run_id), "deberia ser cancelable");

        let events = collect(rx, &run_id, false).await;
        assert!(
            events.iter().any(|e| matches!(e, RunEvent::Cancelled { .. })),
            "no se cancelo: {events:?}"
        );
        let outcome = runner.wait(&run_id).await.expect("outcome");
        assert_eq!(outcome.status, RunStatus::Cancelled);
        assert!(!outcome.is_ok());
    }

    #[tokio::test]
    async fn output_is_batched_not_one_event_per_line() {
        let runner = runner();
        let rx = runner.subscribe();
        let command = if cfg!(windows) {
            "for /L %%i in (1,1,200) do @echo linea %%i"
        } else {
            "for i in $(seq 1 200); do echo linea $i; done"
        };
        let run_id = runner.start(spec(command)).expect("start");

        let events = collect(rx, &run_id, false).await;
        let output_events = events
            .iter()
            .filter(|e| matches!(e, RunEvent::Output { .. }))
            .count();
        let total_lines: usize = events
            .iter()
            .filter_map(|e| match e {
                RunEvent::Output { lines, .. } => Some(lines.len()),
                _ => None,
            })
            .sum();

        assert!(total_lines >= 200, "faltan lineas: {total_lines}");
        assert!(
            output_events < total_lines,
            "no se agrupo nada: {output_events} eventos para {total_lines} lineas"
        );
    }

    #[tokio::test]
    async fn unknown_command_still_resolves() {
        let runner = runner();
        let rx = runner.subscribe();
        let run_id = runner
            .start(spec("nexodeck_comando_que_no_existe_1234"))
            .expect("el shell arranca igual");

        let events = collect(rx, &run_id, false).await;
        let (ok, _) = finished_of(&events).expect("Finished");
        assert!(!ok, "un comando inexistente no puede reportar exito");
    }

    // ---- Unidades puras ----

    #[test]
    fn splitter_handles_crlf_lf_and_lone_cr() {
        let mut s = LineSplitter::default();
        let lines = s.push(b"uno\r\ndos\ntres\rcuatro\n");
        assert_eq!(lines, vec!["uno", "dos", "tres", "cuatro"]);
    }

    #[test]
    fn splitter_waits_for_a_crlf_split_across_reads() {
        let mut s = LineSplitter::default();
        // El `\r` llega al final de una lectura y el `\n` en la siguiente:
        // no puede emitirse una linea vacia extra.
        assert!(s.push(b"uno\r").is_empty());
        assert_eq!(s.push(b"\ndos\n"), vec!["uno", "dos"]);
    }

    #[test]
    fn splitter_survives_invalid_utf8() {
        let mut s = LineSplitter::default();
        // 0xF1 suelto es `ñ` en cp1252 y NO es UTF-8 valido. Con
        // `BufReader::lines()` esto abortaba la lectura en silencio.
        let lines = s.push(b"a\xf1o\nsigue\n");
        assert_eq!(lines.len(), 2);
        assert!(lines[1] == "sigue", "la lectura tiene que continuar");
    }

    #[test]
    fn splitter_breaks_absurdly_long_lines() {
        let mut s = LineSplitter::default();
        let huge = vec![b'x'; MAX_LINE_BYTES + 10];
        assert_eq!(s.push(&huge).len(), 1);
    }

    #[test]
    fn ansi_sequences_are_stripped() {
        assert_eq!(strip_ansi("\x1b[32mverde\x1b[0m ok"), "verde ok");
        assert_eq!(strip_ansi("sin color"), "sin color");
    }

    #[test]
    fn ring_caps_memory_and_counts_drops() {
        let mut ring = OutputRing::default();
        for i in 0..(RING_LINES + 500) {
            ring.push(&format!("linea {i}"));
        }
        assert_eq!(ring.lines.len(), RING_LINES);
        assert_eq!(ring.dropped, 500);

        let tail = ring.tail();
        assert!(tail.contains("500 lineas omitidas"));
        // El final es lo que se conserva, no el principio.
        assert!(tail.contains(&format!("linea {}", RING_LINES + 499)));
    }

    #[test]
    fn detached_counts_as_success_for_macros() {
        let outcome = RunOutcome {
            run_id: "x".into(),
            status: RunStatus::Detached,
            exit_code: None,
            elapsed_ms: 2000,
            output_tail: String::new(),
        };
        assert!(
            outcome.is_ok(),
            "si esto se rompe, todo paso de macro que abra una app falla"
        );
    }
}
