use crate::frb_generated::StreamSink;
use nexodeck_hardware::processes::{self, ProcessCollector};

/// Una aplicacion y lo que consume, para el panel de procesos.
///
/// DTO propio y no el tipo de `nexodeck-hardware`, como todo lo que cruza el
/// puente. Ningun `u64`: frb los mapea a `BigInt` del lado Dart y eso es
/// incomodo sin ganar nada -- los pids son `u32` y el tiempo va en segundos
/// `u32` (aguanta 136 anios).
#[derive(Debug, Clone)]
pub struct ProcessGroup {
    /// Nombre del ejecutable, que es lo que agrupa a los procesos de una
    /// misma app (`chrome.exe` y sus 32 procesos son una sola fila).
    pub name: String,
    /// Todos los pids del grupo. Van enteros porque son lo que hace segura la
    /// terminacion: se cierra por pid **y** nombre.
    pub pids: Vec<u32>,
    pub cpu_percent: f32,
    pub memory_mb: f64,
    /// `None` si esta maquina no informa uso de GPU por proceso.
    pub gpu_percent: Option<f32>,
    /// Bytes/segundo de lectura + escritura combinadas, sumado del grupo.
    pub disk_bytes_per_sec: f64,
    /// Segundos corriendo del proceso mas viejo del grupo. `0` significa
    /// **desconocido**, no recien arrancado: Windows no deja leer el tiempo
    /// de arranque de los procesos del sistema.
    pub run_time_secs: u32,
    /// El grupo de NexoDeck. La UI lo muestra pero no deja cerrarlo.
    pub is_self: bool,
}

/// Las tres listas de una misma muestra.
#[derive(Debug, Clone)]
pub struct TopProcesses {
    pub by_cpu: Vec<ProcessGroup>,
    pub by_memory: Vec<ProcessGroup>,
    pub by_gpu: Vec<ProcessGroup>,
    pub by_disk: Vec<ProcessGroup>,
    /// Si esta maquina puede medir GPU por proceso. Sin este dato, "no se
    /// puede medir aca" y "nadie esta usando la GPU" son la misma lista
    /// vacia y la UI no podria explicar cual de los dos esta pasando.
    pub gpu_available: bool,
    pub sampled_process_count: u32,
}

/// Resultado de cerrar un grupo.
#[derive(Debug, Clone, Copy)]
pub struct KillReport {
    pub requested: u32,
    pub killed: u32,
    /// Matchearon pero no se pudieron cerrar; casi siempre, permisos.
    pub failed: u32,
    /// Ya no estaban, o el pid ahora es de otro programa.
    pub gone: u32,
}

impl From<nexodeck_hardware::ProcessGroup> for ProcessGroup {
    fn from(group: nexodeck_hardware::ProcessGroup) -> Self {
        Self {
            name: group.name,
            pids: group.pids,
            cpu_percent: group.cpu_percent,
            memory_mb: group.memory_mb,
            gpu_percent: group.gpu_percent,
            disk_bytes_per_sec: group.disk_bytes_per_sec,
            run_time_secs: group.run_time_secs,
            is_self: group.is_self,
        }
    }
}

impl From<nexodeck_hardware::TopProcesses> for TopProcesses {
    fn from(sample: nexodeck_hardware::TopProcesses) -> Self {
        Self {
            by_cpu: sample.by_cpu.into_iter().map(Into::into).collect(),
            by_memory: sample.by_memory.into_iter().map(Into::into).collect(),
            by_gpu: sample.by_gpu.into_iter().map(Into::into).collect(),
            by_disk: sample.by_disk.into_iter().map(Into::into).collect(),
            gpu_available: sample.gpu_available,
            sampled_process_count: sample.sampled_process_count,
        }
    }
}

impl From<nexodeck_hardware::KillReport> for KillReport {
    fn from(report: nexodeck_hardware::KillReport) -> Self {
        Self {
            requested: report.requested,
            killed: report.killed,
            failed: report.failed,
            gone: report.gone,
        }
    }
}

impl From<nexodeck_protocol::ProcessGroupWire> for ProcessGroup {
    fn from(g: nexodeck_protocol::ProcessGroupWire) -> Self {
        Self {
            name: g.name,
            pids: g.pids,
            cpu_percent: g.cpu_percent,
            memory_mb: g.memory_mb,
            gpu_percent: g.gpu_percent,
            disk_bytes_per_sec: g.disk_bytes_per_sec,
            run_time_secs: g.run_time_secs,
            is_self: g.is_self,
        }
    }
}

/// Direccion inversa: el telefono manda el grupo tal cual lo tiene en
/// pantalla al pedir `AiAskAboutProcess`.
impl From<ProcessGroup> for nexodeck_protocol::ProcessGroupWire {
    fn from(g: ProcessGroup) -> Self {
        Self {
            name: g.name,
            pids: g.pids,
            cpu_percent: g.cpu_percent,
            memory_mb: g.memory_mb,
            gpu_percent: g.gpu_percent,
            disk_bytes_per_sec: g.disk_bytes_per_sec,
            run_time_secs: g.run_time_secs,
            is_self: g.is_self,
        }
    }
}

/// El detalle que le hace falta a la IA para explicar un proceso -- ver
/// `nexodeck_hardware::processes::process_details`. Solo se pide en la PC
/// (donde vive el proceso de verdad); el telefono nunca llama a esto.
#[derive(Debug, Clone)]
pub struct ProcessDetails {
    pub pid: u32,
    pub parent_name: Option<String>,
    pub command_line: Option<String>,
    pub exe_path: Option<String>,
    pub owner: Option<String>,
}

impl From<nexodeck_hardware::processes::ProcessDetails> for ProcessDetails {
    fn from(details: nexodeck_hardware::processes::ProcessDetails) -> Self {
        Self {
            pid: details.pid,
            parent_name: details.parent_name,
            command_line: details.command_line,
            exe_path: details.exe_path,
            owner: details.owner,
        }
    }
}

/// Rol PC: junta lo que la IA necesita para explicar un proceso -- proceso
/// padre, linea de comando, ejecutable y dueno. `None` si ninguno de los
/// `pids` sigue vivo con ese nombre.
pub fn process_details(name: String, pids: Vec<u32>) -> Option<ProcessDetails> {
    processes::process_details(&name, &pids).map(Into::into)
}

/// Lo que llega por el cable desde la PC, al mismo DTO que usa el panel local.
///
/// El telefono dibuja la tabla con el **mismo** widget que el escritorio, asi
/// que los dos caminos tienen que terminar en el mismo tipo -- igual que
/// `HardwareSnapshot`, que tiene un `From` por cada fuente.
impl From<nexodeck_protocol::TopProcessesWire> for TopProcesses {
    fn from(t: nexodeck_protocol::TopProcessesWire) -> Self {
        Self {
            by_cpu: t.by_cpu.into_iter().map(Into::into).collect(),
            by_memory: t.by_memory.into_iter().map(Into::into).collect(),
            by_gpu: t.by_gpu.into_iter().map(Into::into).collect(),
            by_disk: t.by_disk.into_iter().map(Into::into).collect(),
            gpu_available: t.gpu_available,
            // No viaja por el cable: es un dato de diagnostico de la maquina
            // local y el telefono no lo muestra en ningun lado.
            sampled_process_count: 0,
        }
    }
}

/// Emite las tres listas de procesos cada dos segundos, mientras el panel las
/// escuche.
///
/// **Un solo stream con las tres metricas, y no uno por metrica.** Cambiar de
/// metrica seleccionada tiene que ser gratis: el uso de CPU por proceso es un
/// delta contra la muestra anterior, asi que re-suscribirse en cada clic
/// daria una primera lectura en cero y el usuario veria la lista vaciarse
/// cada vez que toca otra tile. Calcular las tres cuesta casi lo mismo que
/// una (medido: ~20 ms por muestra, 368 procesos, incluida la lectura de GPU).
///
/// El colector solo existe mientras dura esta suscripcion: con el panel
/// cerrado no se recorre ningun proceso.
pub async fn watch_process_usage(sink: StreamSink<TopProcesses>) {
    let mut collector = ProcessCollector::new();

    // `interval_at` y no `interval`, por el mismo motivo que el stream de
    // metricas: el primer tick de `interval` se dispara al instante y esa
    // muestra se tomaria sobre una ventana de ~0 ms contra la linea base que
    // fija `ProcessCollector::new()`.
    let mut ticker = tokio::time::interval_at(
        tokio::time::Instant::now() + processes::FIRST_SAMPLE_DELAY,
        processes::SAMPLE_INTERVAL,
    );

    loop {
        ticker.tick().await;
        if sink.add(collector.sample().into()).is_err() {
            // Dart cerro el stream (se cerro el panel).
            break;
        }
    }
}

/// Cierra todos los procesos de `pids` que sigan llamandose `name`.
///
/// Sincrona porque `kill()` es inmediato. Devuelve `Err` solo cuando la
/// operacion entera se rechaza (un proceso critico de Windows, o el propio
/// NexoDeck); que algun pid no se pueda cerrar viaja dentro del reporte, para
/// que la UI pueda decir "no se pudieron cerrar 2 de 12" en vez de fallar
/// entera.
pub fn terminate_process_group(name: String, pids: Vec<u32>) -> Result<KillReport, String> {
    processes::terminate_process_group(&name, &pids).map(Into::into)
}
