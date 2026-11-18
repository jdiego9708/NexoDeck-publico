//! Ciclo de vida del proceso `llama-server`.
//!
//! Todo lo que hay aca existe por un modo de fallo concreto:
//!
//! - **Puerto efimero**, nunca uno fijo. El proyecto ya sabe lo que cuesta un
//!   puerto ocupado (el 58643 del transporte, documentado en `CLAUDE.md`), y
//!   aca ademas puede haber otra instancia de NexoDeck o un llama-server que el
//!   usuario levanto por su cuenta.
//! - **`CREATE_NO_WINDOW` en Windows.** Sin eso aparece una consola negra
//!   flotando cada vez que arranca el asistente.
//! - **Ring de stderr.** `llama-server` escribe ahi el motivo real de un fallo
//!   de carga (tipicamente falta de VRAM). Sin guardarlo, el usuario ve
//!   "no respondio" y nada mas.
//! - **Reintento con menos `-ngl`.** El calculo de capas es una estimacion; si
//!   se paso, el server muere al cargar. Reintentar con offload parcial
//!   convierte un fallo duro en una sesion mas lenta pero funcional.
//! - **Matar el hijo en `Drop` y al cerrar.** Un `llama-server` huerfano se
//!   queda con los GB de VRAM tomados y el proximo arranque falla por una
//!   razon que no tiene nada que ver.
//! - **Job Object en Windows.** `kill_on_drop(true)` (mas abajo) y
//!   `shutdown()` solo matan al hijo si NexoDeck llega a correr su propio
//!   `Drop` — o sea, si cierra de forma ordenada. Un cierre de golpe
//!   (crash, "Finalizar tarea" del Administrador, un `taskkill /F` externo)
//!   salta el `Drop` por completo, y Windows no mata hijos en cascada por su
//!   cuenta: el `llama-server.exe` queda huerfano reteniendo la VRAM hasta
//!   que alguien lo cierre a mano. Verificado en vivo: dos sesiones de
//!   prueba de esta feature dejaron dos `llama-server.exe` huerfanos, uno de
//!   ellos por un `taskkill /F /IM nexodeck.exe` de otra sesion de trabajo.
//!   `job_object` (mas abajo) ata el hijo a un Job Object con
//!   `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`: Windows cierra el handle del job
//!   solo cuando NexoDeck termina, **de cualquier forma**, y ese cierre por
//!   si mismo mata al hijo sin que ningun `Drop` de Rust tenga que correr.
//!   Mismo tipo de gap que el `taskkill /T` de `nexodeck-actions::runner`
//!   (ver CLAUDE.md) — ahi la solucion completa sigue pendiente; aca ya esta
//!   hecha porque el costo (VRAM entera, no solo un proceso colgado) es
//!   mucho mayor.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};

use crate::error::{AiError, AiResult};

/// Cuantas lineas de stderr se guardan. Suficiente para que entre el bloque de
/// diagnostico que imprime llama.cpp al fallar la carga.
const STDERR_RING_LINES: usize = 80;

/// Cada cuanto se consulta `/health` mientras el modelo carga.
const HEALTH_POLL_INTERVAL: Duration = Duration::from_millis(500);

/// Cargar un GGUF de 18 GB desde un disco mecanico puede tardar varios minutos
/// de forma perfectamente normal. El timeout esta para detectar un proceso
/// muerto, no para apurar la carga.
const HEALTH_TIMEOUT: Duration = Duration::from_secs(420);

/// Con cuantas capas se reintenta cuando el arranque con offload total falla.
/// La mitad es una apuesta deliberadamente conservadora: si el problema era la
/// VRAM, deja margen de sobra.
const NGL_RETRY_FACTOR: f32 = 0.5;

#[derive(Debug, Clone)]
pub struct ServerSpec {
    pub server_path: PathBuf,
    pub model_path: PathBuf,
    pub model_alias: String,
    pub gpu_layers: u32,
    pub threads: u32,
    pub context_size: u32,
}

pub struct LlamaServer {
    child: Child,
    port: u16,
    base_url: String,
    stderr: Arc<Mutex<VecDeque<String>>>,
    last_used: Mutex<Instant>,
    /// Capas que efectivamente se usaron. Puede diferir de lo pedido si hubo
    /// reintento, y la UI lo muestra para que "va lento" tenga explicacion.
    pub gpu_layers: u32,
    /// Nunca se lee: existe solo por su `Drop`. Si el Job Object no se pudo
    /// crear (rarisimo; ver `job_object::JobObject::attach`), queda en
    /// `None` y el sidecar sigue andando igual — es una red de seguridad
    /// extra, no un requisito para que el asistente funcione.
    #[cfg(target_os = "windows")]
    #[allow(dead_code)]
    job: Option<job_object::JobObject>,
}

impl LlamaServer {
    /// Levanta el server y espera a que responda `/health`.
    ///
    /// Si el arranque con las capas pedidas falla y habia offload a GPU,
    /// reintenta una vez con menos capas antes de rendirse.
    pub async fn start(spec: &ServerSpec) -> AiResult<Self> {
        match Self::try_start(spec, spec.gpu_layers).await {
            Ok(server) => Ok(server),
            Err(error) if spec.gpu_layers > 0 => {
                let reduced = reduced_gpu_layers(spec.gpu_layers);
                log::warn!(
                    "llama-server no arranco con -ngl {} ({error}); se reintenta con -ngl {reduced}",
                    spec.gpu_layers
                );
                Self::try_start(spec, reduced).await
            }
            Err(error) => Err(error),
        }
    }

    async fn try_start(spec: &ServerSpec, gpu_layers: u32) -> AiResult<Self> {
        let port = reserve_port()?;
        let mut command = Command::new(&spec.server_path);

        command
            .arg("--model")
            .arg(&spec.model_path)
            .arg("--alias")
            .arg(&spec.model_alias)
            .arg("--host")
            .arg("127.0.0.1")
            .arg("--port")
            .arg(port.to_string())
            .arg("--ctx-size")
            .arg(spec.context_size.to_string())
            .arg("--threads")
            .arg(spec.threads.to_string())
            .arg("--n-gpu-layers")
            .arg(gpu_layers.to_string())
            // Sin `--jinja` la plantilla de chat del modelo no se aplica y los
            // tool calls salen mal formados o directamente no salen. Toda la
            // salida estructurada del asistente depende de esta bandera.
            .arg("--jinja");

        // Las DLLs del CUDA runtime se extraen al lado del binario; ejecutar
        // desde ahi evita depender del PATH del usuario.
        if let Some(dir) = spec.server_path.parent() {
            command.current_dir(dir);
        }

        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            // Red de seguridad para un cierre ORDENADO: si el `Child` se
            // dropea sin pasar por `shutdown()` (un error temprano, un
            // panic), tokio mata al hijo igual. No cubre un cierre de golpe
            // del PROPIO NexoDeck -- para eso esta el Job Object de abajo.
            .kill_on_drop(true);

        apply_platform_flags(&mut command);

        let mut child = command.spawn().map_err(|e| AiError::SpawnServer {
            path: spec.server_path.clone(),
            detail: e.to_string(),
        })?;

        #[cfg(target_os = "windows")]
        let job = attach_job_object(&child);

        let stderr = Arc::new(Mutex::new(VecDeque::with_capacity(STDERR_RING_LINES)));
        if let Some(pipe) = child.stderr.take() {
            spawn_stderr_reader(pipe, Arc::clone(&stderr));
        }

        let base_url = format!("http://127.0.0.1:{port}");
        let server = Self {
            child,
            port,
            base_url,
            stderr,
            last_used: Mutex::new(Instant::now()),
            gpu_layers,
            #[cfg(target_os = "windows")]
            job,
        };

        server.wait_until_healthy().await?;
        Ok(server)
    }

    async fn wait_until_healthy(&self) -> AiResult<()> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap_or_default();
        let url = format!("{}/health", self.base_url);
        let started = Instant::now();

        while started.elapsed() < HEALTH_TIMEOUT {
            // Si el proceso ya murio no tiene sentido seguir esperando: el
            // motivo esta en stderr y hay que devolverlo ya.
            //
            // `try_wait` necesita `&mut`, y aca solo tenemos `&self`; se
            // detecta la muerte por el lado de la conexion (rechazo constante)
            // mas el timeout, y el detalle real sale del ring de stderr.
            match client.get(&url).send().await {
                Ok(response) if response.status().is_success() => return Ok(()),
                // 503 mientras carga el modelo es lo esperado, no un error.
                _ => tokio::time::sleep(HEALTH_POLL_INTERVAL).await,
            }
        }

        Err(AiError::ServerNeverReady {
            waited_secs: HEALTH_TIMEOUT.as_secs(),
            stderr_tail: self.stderr_tail(),
        })
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Ultimas lineas de stderr, para explicar un fallo.
    pub fn stderr_tail(&self) -> String {
        self.stderr
            .lock()
            .map(|lines| lines.iter().cloned().collect::<Vec<_>>().join("\n"))
            .unwrap_or_default()
    }

    /// Marca actividad. Lo llama el proveedor en cada peticion para que el
    /// apagado por inactividad no mate un server que se esta usando.
    pub fn touch(&self) {
        if let Ok(mut last) = self.last_used.lock() {
            *last = Instant::now();
        }
    }

    pub fn idle_for(&self) -> Duration {
        self.last_used
            .lock()
            .map(|last| last.elapsed())
            .unwrap_or_default()
    }

    /// Apagado ordenado. Se llama al cerrar la app o al cambiar de modelo.
    pub async fn shutdown(mut self) {
        let _ = self.child.kill().await;
        let _ = self.child.wait().await;
    }
}

fn reduced_gpu_layers(requested: u32) -> u32 {
    // `999` es el sentinela de "todas las capas": la mitad de 999 no significa
    // nada, asi que se baja a un valor concreto y conservador.
    if requested >= 999 {
        20
    } else {
        ((requested as f32 * NGL_RETRY_FACTOR) as u32).max(1)
    }
}

/// Reserva un puerto libre dejando que el SO elija (`:0`) y lo devuelve.
///
/// Entre que se cierra el listener y que `llama-server` hace su bind hay una
/// ventana de carrera teorica. Es la misma tecnica que usa media industria y el
/// riesgo real es despreciable frente a la alternativa (un puerto fijo, que
/// choca de verdad y a menudo).
fn reserve_port() -> AiResult<u16> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    drop(listener);
    Ok(port)
}

fn spawn_stderr_reader(
    pipe: tokio::process::ChildStderr,
    ring: Arc<Mutex<VecDeque<String>>>,
) {
    tokio::spawn(async move {
        let mut lines = BufReader::new(pipe).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            log::debug!("llama-server: {line}");
            if let Ok(mut ring) = ring.lock() {
                if ring.len() == STDERR_RING_LINES {
                    ring.pop_front();
                }
                ring.push_back(line);
            }
        }
    });
}

#[cfg(target_os = "windows")]
fn apply_platform_flags(command: &mut Command) {
    // Mismo valor que usa `nexodeck-actions::terminal`: sin esto aparece una
    // consola negra por cada arranque del asistente.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(target_os = "windows"))]
fn apply_platform_flags(_command: &mut Command) {}

/// Ata `child` a un Job Object nuevo con `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
///
/// Fallar es posible pero raro (falta de privilegios, un limite del sistema);
/// cuando pasa se loguea y se sigue sin el -- el asistente tiene que poder
/// arrancar igual, esto es una red de seguridad extra, no un requisito. Ver el
/// comentario del modulo para el porque completo.
#[cfg(target_os = "windows")]
fn attach_job_object(child: &Child) -> Option<job_object::JobObject> {
    let Some(handle) = child.raw_handle() else {
        // No debería pasar con un proceso recien creado, pero un `None` aca
        // no es motivo para abortar el arranque del sidecar.
        return None;
    };

    match job_object::JobObject::attach(handle) {
        Ok(job) => Some(job),
        Err(error) => {
            log::warn!(
                "no se pudo atar llama-server a un Job Object de Windows -- si \
                 NexoDeck se cierra de golpe, el proceso puede quedar huerfano \
                 reteniendo la VRAM hasta que se cierre a mano: {error}"
            );
            None
        }
    }
}

#[cfg(target_os = "windows")]
mod job_object {
    use windows::Win32::Foundation::{CloseHandle, HANDLE};
    use windows::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
        SetInformationJobObject,
    };
    use windows::core::{PCWSTR, Result as WinResult};

    /// Handle de un Job Object anonimo, cerrado en `Drop`.
    ///
    /// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` significa: cuando se cierra el
    /// **ultimo** handle del job, Windows mata a todos los procesos que
    /// tiene asignados. NexoDeck es dueno del unico handle, asi que ese
    /// cierre pasa exactamente cuando NexoDeck termina -- sea porque este
    /// `Drop` corrio (cierre ordenado, redundante con `kill_on_drop`) o
    /// porque el propio proceso de NexoDeck murio y el sistema operativo
    /// cerro todos sus handles como parte de la limpieza (cierre de golpe,
    /// el caso que este tipo existe para cubrir).
    pub(super) struct JobObject(HANDLE);

    impl JobObject {
        pub(super) fn attach(process: std::os::windows::io::RawHandle) -> WinResult<Self> {
            unsafe {
                let job = CreateJobObjectW(None, PCWSTR::null())?;

                let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                let result = SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    &info as *const _ as *const _,
                    std::mem::size_of_val(&info) as u32,
                );
                if let Err(error) = result {
                    let _ = CloseHandle(job);
                    return Err(error);
                }

                let result = AssignProcessToJobObject(job, HANDLE(process));
                if let Err(error) = result {
                    let _ = CloseHandle(job);
                    return Err(error);
                }

                Ok(Self(job))
            }
        }
    }

    impl Drop for JobObject {
        fn drop(&mut self) {
            // `CloseHandle`, no dejar que se filtre: es este cierre el que
            // dispara `KILL_ON_JOB_CLOSE` si era el ultimo handle vivo.
            unsafe {
                let _ = CloseHandle(self.0);
            }
        }
    }

    // El HANDLE es un id opaco del kernel, no memoria compartida: es seguro
    // moverlo y usarlo desde cualquier hilo. Mismo criterio que aplica el
    // resto del ecosistema windows-rs para sus wrappers de handles.
    unsafe impl Send for JobObject {}
    unsafe impl Sync for JobObject {}
}

/// Escribe el ultimo stderr a disco para poder diagnosticar un fallo ocurrido
/// en una sesion anterior.
pub fn dump_stderr(tail: &str) -> Option<PathBuf> {
    let path = crate::paths::logs_dir().ok()?.join("llama-server.log");
    std::fs::write(&path, tail).ok()?;
    Some(path)
}

/// Comprueba que el binario exista y sea ejecutable antes de intentar lanzarlo,
/// para dar un error claro en vez de un `spawn` fallido con un `os error 2`.
pub fn validate_server_binary(path: &Path) -> AiResult<()> {
    if !path.is_file() {
        return Err(AiError::MissingBinary(
            path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("llama-server")
                .to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reserve_port_devuelve_puertos_utilizables_y_distintos() {
        let a = reserve_port().unwrap();
        let b = reserve_port().unwrap();

        assert!(a > 1024, "el SO tiene que dar un puerto no privilegiado");
        assert!(b > 1024);
        // No es estrictamente garantizado que sean distintos, pero el SO
        // rota los efimeros: dos iguales seguidos indicaria algo raro.
        assert_ne!(a, b);
    }

    /// El sentinela `999` no se puede dividir: la mitad de "todas las capas"
    /// no significa nada.
    #[test]
    fn el_reintento_traduce_el_sentinela_a_un_numero_concreto() {
        assert_eq!(reduced_gpu_layers(999), 20);
        assert_eq!(reduced_gpu_layers(40), 20);
        assert_eq!(reduced_gpu_layers(1), 1);
    }

    #[test]
    fn validate_server_binary_falla_con_una_ruta_inexistente() {
        let error = validate_server_binary(Path::new("C:/no/existe/llama-server.exe")).unwrap_err();
        assert!(matches!(error, AiError::MissingBinary(_)));
    }

    /// Verifica el mecanismo real del Job Object, no solo que compile.
    ///
    /// No hace falta matar de verdad este proceso de test para probar el caso
    /// que importa (NexoDeck muriendo de golpe): `KILL_ON_JOB_CLOSE` dispara
    /// apenas se cierra el ULTIMO handle del job, y `drop(job)` dispara
    /// exactamente ese cierre. Es el mismo evento que Windows genera solo
    /// cuando el proceso dueno del handle termina, sea como sea que haya
    /// terminado.
    #[cfg(target_os = "windows")]
    #[tokio::test]
    async fn cerrar_el_job_mata_al_hijo_sin_que_nadie_lo_pida() {
        let mut child = Command::new("ping")
            .args(["-n", "30", "127.0.0.1"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(false) // el punto es que ESTO no sea lo que lo mata
            .spawn()
            .expect("ping.exe deberia estar siempre disponible en Windows");

        let handle = child.raw_handle().expect("recien arrancado, tiene que tener handle");
        let job = job_object::JobObject::attach(handle)
            .expect("CreateJobObjectW no deberia fallar en esta maquina");

        drop(job);

        // Le da al SO un instante para completar la terminacion.
        for _ in 0..20 {
            if child.try_wait().ok().flatten().is_some() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        let status = child
            .try_wait()
            .expect("try_wait no deberia fallar sobre un proceso propio");
        assert!(
            status.is_some(),
            "el ping tendria que haber muerto al cerrarse el ultimo handle del job"
        );

        // Limpieza: si la asercion de arriba fallo, no dejar el ping colgado.
        let _ = child.start_kill();
    }
}
