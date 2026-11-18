//! Quien esta consumiendo el hardware: la lista tipo Administrador de tareas
//! que alimenta el panel de procesos.
//!
//! **Vive fuera de [`crate::HardwareMonitor`] a proposito.** `snapshot()` es
//! la ruta caliente de 1 s que comparten el stream del FFI y el del servidor
//! (o sea, tambien el que va al telefono); meterle un recorrido de ~400
//! procesos degradaria las dos por un dato que el telefono ni siquiera
//! recibe. Ademas los ciclos de vida son distintos: este colector solo existe
//! mientras el panel esta abierto, asi que con el panel cerrado el costo es
//! exactamente cero.
//!
//! Tampoco toca `refresh_cpu_*` **nunca**: ver el comentario largo de
//! `snapshot()` sobre por que en Windows dos refrescos de CPU seguidos dejan
//! el uso clavado en 100. Para normalizar por nucleos se usa
//! `available_parallelism()`, que no consulta a sysinfo.

mod gpu_usage;

use std::collections::HashMap;
use std::time::{Duration, Instant};

use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind, Users};

/// Cada cuanto se toma una muestra. Dos segundos y no uno: una lista que se
/// reordena sola cada segundo es ilegible, y el recorrido completo de
/// procesos es justo lo que `foreground.rs` evita hacer a 1/s.
pub const SAMPLE_INTERVAL: Duration = Duration::from_secs(2);

/// Retraso de la primera muestra. No es inmediato --daria una ventana de
/// ~0 ms contra la linea base, el mismo error que `interval` vs
/// `interval_at`-- pero tampoco espera los 2 s completos, que dejarian el
/// panel vacio de mas justo despues del clic. Queda comodamente por encima
/// del `MINIMUM_CPU_UPDATE_INTERVAL` de 200 ms de sysinfo en Windows.
pub const FIRST_SAMPLE_DELAY: Duration = Duration::from_millis(500);

/// Por debajo de esto un proceso no entra en las listas de porcentajes (CPU y
/// GPU): la UI muestra un decimal, asi que cualquier cosa menor se dibujaria
/// como "0.0%" y ocuparia una fila para no decir nada.
///
/// **No aplica a la memoria**: ahi todo proceso consume algo y un umbral solo
/// esconderia informacion real.
const MIN_VISIBLE_PERCENT: f64 = 0.05;

/// Piso para la lista de disco, en bytes/segundo. Es un umbral absoluto y no
/// porcentual --a diferencia de CPU/GPU-- porque no hay un "100%" natural
/// para E/S de disco. 1 KB/s es indistinguible de reposo para el usuario;
/// sin este piso la lista se llena de procesos en "0 B/s" que no dicen nada,
/// el mismo sintoma que motivo el umbral de CPU.
const MIN_VISIBLE_DISK_BPS: f64 = 1024.0;

/// Cuantas filas se mandan por lista. Con ~150 grupos vivos, mostrar mas que
/// esto en un panel lateral no entra ni aporta.
const TOP_N: usize = 12;

/// Una aplicacion: todos los procesos que comparten nombre de ejecutable.
///
/// Se agrupa **por nombre y no por pid** porque Chrome, VS Code o Discord
/// corren como diez o veinte procesos y una lista por pid seria doce filas
/// identicas. Es la misma decision que toma la pestana "Procesos" del
/// Administrador de tareas.
#[derive(Debug, Clone, PartialEq)]
pub struct ProcessGroup {
    pub name: String,
    /// Todos los pids del grupo. Viajan enteros porque son lo que hace segura
    /// la terminacion (ver [`terminate_process_group`]).
    pub pids: Vec<u32>,
    /// Suma del grupo, ya normalizada a 0-100 sobre el total de la maquina.
    pub cpu_percent: f32,
    pub memory_mb: f64,
    /// Suma de los porcentajes por pid, clampeada. `None` si esta maquina no
    /// informa uso de GPU por proceso.
    pub gpu_percent: Option<f32>,
    /// Bytes/segundo de lectura + escritura combinadas, sumado del grupo.
    /// Combinado y no separado -- a diferencia de la senal de vida de la UI,
    /// donde la direccion importa -- porque una sola columna del panel de
    /// procesos responde "cuanto esta moviendo esta app", igual que la
    /// columna de Disco del Administrador de tareas.
    pub disk_bytes_per_sec: f64,
    /// Segundos que lleva corriendo el miembro **mas viejo**, que es el que
    /// responde "desde cuando esta abierta esta app": los procesos hijos
    /// arrancan despues y darian un numero que no significa nada.
    pub run_time_secs: u32,
    /// El grupo al que pertenece NexoDeck. Se muestra igual --esconderlo
    /// seria deshonesto-- pero no se deja terminar.
    pub is_self: bool,
}

/// Las tres listas, ya ordenadas y recortadas del lado de Rust.
///
/// Van las tres juntas en cada muestra, en vez de una sola segun la metrica
/// elegida, porque **cambiar de metrica no puede costar una muestra nueva**:
/// el uso de CPU por proceso es un delta contra el estado anterior, asi que
/// re-suscribirse en cada clic daria una primera lectura en cero. Calcular
/// las tres cuesta casi lo mismo que una: lo caro es el unico
/// `refresh_processes_specifics`.
#[derive(Debug, Clone, PartialEq)]
pub struct TopProcesses {
    pub by_cpu: Vec<ProcessGroup>,
    pub by_memory: Vec<ProcessGroup>,
    pub by_gpu: Vec<ProcessGroup>,
    pub by_disk: Vec<ProcessGroup>,
    /// Si esta maquina puede medir GPU por proceso. Distingue "no se puede
    /// medir" de "nadie esta usando la GPU": sin esto los dos casos son una
    /// lista vacia y el usuario no sabe cual de los dos esta viendo.
    pub gpu_available: bool,
    /// Cuantos procesos se recorrieron para armar esto.
    pub sampled_process_count: u32,
}

/// Toma muestras periodicas. Mantiene su propio `System` --como
/// `ForegroundWatcher`-- para no compartir estado con el monitor de metricas.
pub struct ProcessCollector {
    system: System,
    gpu: gpu_usage::GpuUsageReader,
    cpu_count: f32,
    own_pid: u32,
    /// Cuando se tomo la ultima muestra, para convertir el delta de bytes
    /// que da `sysinfo` (desde el ultimo refresh, no acumulado) en
    /// bytes/segundo. `SAMPLE_INTERVAL` es nominal; el loop real tiene
    /// jitter, y dividir por un intervalo fijo desalinearia la tasa.
    last_sample: Instant,
}

impl Default for ProcessCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessCollector {
    pub fn new() -> Self {
        // `System::new()` vacio y no `new_all()`: la tabla se puebla en el
        // primer refresh, que ademas es el que fija la linea base del delta
        // de CPU.
        let mut system = System::new();
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing()
                .with_cpu()
                .with_memory()
                .with_disk_usage(),
        );

        Self {
            system,
            gpu: gpu_usage::GpuUsageReader::new(),
            // `available_parallelism()` y no `System::cpus().len()`: leer los
            // cpus obligaria a refrescarlos, y este modulo no puede tocar
            // `refresh_cpu_*` (ver el encabezado).
            cpu_count: std::thread::available_parallelism()
                .map(|n| n.get() as f32)
                .unwrap_or(1.0),
            own_pid: std::process::id(),
            last_sample: Instant::now(),
        }
    }

    pub fn sample(&mut self) -> TopProcesses {
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing()
                .with_cpu()
                .with_memory()
                .with_disk_usage(),
        );
        let gpu_per_pid = self.gpu.sample();

        // Segundos reales desde la muestra anterior, no `SAMPLE_INTERVAL`
        // nominal: sysinfo da un delta de BYTES (no una tasa) para disco, y
        // dividirlo por un intervalo fijo desalinearia la tasa apenas el
        // loop tuviera jitter. Piso de 0.001s: la primera muestra tiene un
        // `elapsed()` casi cero y dividir por eso daria un pico absurdo.
        let elapsed_secs = self.last_sample.elapsed().as_secs_f64().max(0.001);
        self.last_sample = Instant::now();

        let raw: Vec<RawProcess> = self
            .system
            .processes()
            .iter()
            .map(|(pid, process)| {
                let pid = pid.as_u32();
                let disk = process.disk_usage();
                RawProcess {
                    pid,
                    name: process.name().to_string_lossy().into_owned(),
                    // `cpu_usage()` viene sumado sobre todos los nucleos (en
                    // una maquina de 16 hilos, un proceso que satura uno solo
                    // da 100). Se divide para que la columna sea comparable
                    // con la metrica de CPU y con el Administrador de tareas.
                    cpu_percent: process.cpu_usage() / self.cpu_count,
                    memory_mb: process.memory() as f64 / BYTES_PER_MB,
                    gpu_percent: gpu_per_pid.get(&pid).copied(),
                    disk_bytes_per_sec: (disk.read_bytes + disk.written_bytes) as f64
                        / elapsed_secs,
                    run_time_secs: run_time_secs(process),
                    is_self: pid == self.own_pid,
                }
            })
            .collect();

        let sampled_process_count = raw.len() as u32;
        let groups = group_processes(raw, self.gpu.is_available());

        TopProcesses {
            // CPU y GPU descartan a los que no llegan a MIN_VISIBLE_PERCENT.
            // Sin eso, con la maquina tranquila la lista de CPU se llenaba de
            // filas diciendo "0.0%" ordenadas alfabeticamente --verificado en
            // la app real-- y habia que buscar entre ellas los tres procesos
            // que de verdad consumian algo. Es preferible una lista corta.
            by_cpu: top_n_by(
                &groups,
                |group| group.cpu_percent as f64,
                Some(MIN_VISIBLE_PERCENT),
            ),
            // La memoria no lleva umbral: todo proceso ocupa algo.
            by_memory: top_n_by(&groups, |group| group.memory_mb, None),
            by_gpu: top_n_by(
                &groups,
                |group| group.gpu_percent.unwrap_or(0.0) as f64,
                Some(MIN_VISIBLE_PERCENT),
            ),
            by_disk: top_n_by(
                &groups,
                |group| group.disk_bytes_per_sec,
                Some(MIN_VISIBLE_DISK_BPS),
            ),
            gpu_available: self.gpu.is_available(),
            sampled_process_count,
        }
    }
}

const BYTES_PER_MB: f64 = 1024.0 * 1024.0;

/// Segundos que lleva corriendo un proceso, o `0` si no se sabe.
///
/// `Process::run_time()` es `ahora - start_time`, y para los procesos que
/// corren como SYSTEM (`dwm.exe`, `csrss.exe`...) Windows no deja leer el
/// tiempo de arranque: `start_time()` devuelve 0 y la resta da **el epoch
/// entero**. Verificado en vivo: `dwm.exe` aparecia con "20691 d 20 h", o sea
/// desde 1970. Se devuelve 0 --que la UI dibuja como "—"-- porque afirmar 56
/// anios es peor que admitir que no se sabe.
fn run_time_secs(process: &sysinfo::Process) -> u32 {
    if process.start_time() == 0 {
        return 0;
    }
    process.run_time().min(u32::MAX as u64) as u32
}

/// Un proceso suelto, antes de agruparse. Publico solo dentro del crate para
/// poder testear [`group_processes`] sin un `System` real.
#[derive(Debug, Clone)]
pub(crate) struct RawProcess {
    pub(crate) pid: u32,
    pub(crate) name: String,
    pub(crate) cpu_percent: f32,
    pub(crate) memory_mb: f64,
    pub(crate) gpu_percent: Option<f32>,
    pub(crate) disk_bytes_per_sec: f64,
    pub(crate) run_time_secs: u32,
    pub(crate) is_self: bool,
}

/// Junta los procesos que comparten nombre de ejecutable.
///
/// `gpu_available` decide si el campo de GPU queda en `Some(0.0)` o en
/// `None`: en una maquina que no sabe medirlo, un cero seria una afirmacion
/// falsa.
pub(crate) fn group_processes(raw: Vec<RawProcess>, gpu_available: bool) -> Vec<ProcessGroup> {
    let mut by_name: HashMap<String, ProcessGroup> = HashMap::new();

    for process in raw {
        let entry = by_name
            .entry(process.name.clone())
            .or_insert_with(|| ProcessGroup {
                name: process.name.clone(),
                pids: Vec::new(),
                cpu_percent: 0.0,
                memory_mb: 0.0,
                gpu_percent: if gpu_available { Some(0.0) } else { None },
                disk_bytes_per_sec: 0.0,
                run_time_secs: 0,
                is_self: false,
            });

        entry.pids.push(process.pid);
        entry.cpu_percent += process.cpu_percent;
        entry.memory_mb += process.memory_mb;
        entry.disk_bytes_per_sec += process.disk_bytes_per_sec;
        if let Some(slot) = entry.gpu_percent.as_mut() {
            *slot += process.gpu_percent.unwrap_or(0.0);
        }
        // El mas viejo del grupo, que es el proceso padre.
        entry.run_time_secs = entry.run_time_secs.max(process.run_time_secs);
        entry.is_self |= process.is_self;
    }

    by_name
        .into_values()
        .map(|mut group| {
            group.cpu_percent = group.cpu_percent.clamp(0.0, 100.0);
            if let Some(slot) = group.gpu_percent.as_mut() {
                *slot = slot.clamp(0.0, 100.0);
            }
            // Orden estable dentro del grupo: los pids se usan para terminar
            // y una lista que se reordena sola es imposible de leer en un log.
            group.pids.sort_unstable();
            group
        })
        .collect()
}

/// Los [`TOP_N`] grupos con mayor valor segun `score`, de mayor a menor.
///
/// `min_visible` es el piso por debajo del cual un grupo queda afuera en vez
/// de rellenar la lista con ceros -- `None` no filtra nada (la memoria, donde
/// todo proceso ocupa algo). El piso es un parametro y no una constante fija
/// porque CPU/GPU (porcentaje, [`MIN_VISIBLE_PERCENT`]) y disco
/// (bytes/segundo, [`MIN_VISIBLE_DISK_BPS`]) viven en escalas distintas.
pub(crate) fn top_n_by<F>(
    groups: &[ProcessGroup],
    score: F,
    min_visible: Option<f64>,
) -> Vec<ProcessGroup>
where
    F: Fn(&ProcessGroup) -> f64,
{
    let mut scored: Vec<(f64, &ProcessGroup)> = groups
        .iter()
        .map(|group| (score(group), group))
        .filter(|(value, _)| min_visible.is_none_or(|min| *value >= min))
        .collect();

    // `total_cmp` y no `partial_cmp`: un NaN haria panickear a un comparador
    // que devuelva `Ordering` a la fuerza. Se desempata por nombre para que
    // dos grupos con el mismo valor no bailen entre muestras.
    scored.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| a.1.name.cmp(&b.1.name)));
    scored
        .into_iter()
        .take(TOP_N)
        .map(|(_, group)| group.clone())
        .collect()
}

/// Procesos que no se dejan terminar porque cerrarlos apaga o rompe Windows.
/// La comparacion es sin distinguir mayusculas: los nombres llegan tal como
/// los reporta el SO.
pub(crate) fn is_protected_process_name(name: &str) -> bool {
    const PROTECTED: [&str; 10] = [
        "system",
        "registry",
        "idle",
        "smss.exe",
        "csrss.exe",
        "wininit.exe",
        "winlogon.exe",
        "services.exe",
        "lsass.exe",
        "svchost.exe",
    ];
    let name = name.trim().to_ascii_lowercase();
    PROTECTED.iter().any(|protected| *protected == name)
}

/// Que paso al intentar cerrar un grupo.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct KillReport {
    pub requested: u32,
    pub killed: u32,
    /// Matchearon pero `kill()` fallo. Casi siempre son permisos: sysinfo no
    /// expone el `GetLastError`, asi que no se puede afirmar cual.
    pub failed: u32,
    /// El pid ya no existe, o ahora pertenece a otro programa.
    pub gone: u32,
}

/// Cierra todos los procesos de `pids` que **ademas** sigan llamandose
/// `name`.
///
/// La doble condicion no es paranoia: Windows reutiliza los pids rapido, y
/// estos vienen de una muestra de hasta dos segundos atras. Actuar solo por
/// pid puede matar un programa que el usuario nunca vio en la lista. Por el
/// mismo motivo **no** se buscan procesos nuevos con ese nombre: el usuario
/// solo puede cerrar lo que estaba mirando.
pub fn terminate_process_group(name: &str, pids: &[u32]) -> Result<KillReport, String> {
    if is_protected_process_name(name) {
        return Err(format!(
            "«{name}» es un proceso critico de Windows: cerrarlo apagaria el equipo"
        ));
    }

    let own_pid = std::process::id();
    if pids.contains(&own_pid) {
        return Err("No se puede cerrar NexoDeck desde su propio panel".to_owned());
    }

    let mut system = System::new();
    let sysinfo_pids: Vec<Pid> = pids.iter().map(|pid| Pid::from_u32(*pid)).collect();
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&sysinfo_pids),
        true,
        // Ni cpu ni memoria: solo hace falta el nombre para confirmar que
        // sigue siendo el mismo proceso.
        ProcessRefreshKind::nothing(),
    );

    let mut report = KillReport {
        requested: pids.len() as u32,
        ..Default::default()
    };

    for pid in pids {
        let Some(process) = system.process(Pid::from_u32(*pid)) else {
            report.gone += 1;
            continue;
        };
        if !process
            .name()
            .to_string_lossy()
            .eq_ignore_ascii_case(name)
        {
            report.gone += 1;
            continue;
        }
        if process.kill() {
            report.killed += 1;
        } else {
            report.failed += 1;
        }
    }

    Ok(report)
}

/// Lo que hace falta para que la IA pueda explicar un proceso, y que
/// `ProcessGroup` no trae: quien lo lanzo, con que linea de comando, desde
/// donde y como que usuario. Se pide una sola vez, al tocar el boton nuevo
/// del panel -- nunca en la ruta caliente de 2 s (ver el comentario del
/// modulo).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessDetails {
    /// El pid representativo: el de mas `run_time` entre `pids` -- mismo
    /// criterio que ya usa `group_processes` para `run_time_secs` (el mas
    /// viejo del grupo es el padre).
    pub pid: u32,
    pub parent_name: Option<String>,
    pub command_line: Option<String>,
    pub exe_path: Option<String>,
    pub owner: Option<String>,
}

/// Detalle fresco de un proceso ya visto en el panel. `None` si ninguno de
/// `pids` sigue vivo con ese `name` -- mismo doble chequeo que
/// `terminate_process_group`, por el mismo motivo (pids reciclados).
///
/// **Nunca pide cpu/memoria**: un `System::new()` de un solo tiro no puede
/// darlos bien (son un delta entre dos muestras, ver el comentario del
/// modulo) -- quien llama ya tiene esos numeros en pantalla, de la muestra
/// del panel.
pub fn process_details(name: &str, pids: &[u32]) -> Option<ProcessDetails> {
    let mut system = System::new();
    let sysinfo_pids: Vec<Pid> = pids.iter().map(|pid| Pid::from_u32(*pid)).collect();
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&sysinfo_pids),
        true,
        ProcessRefreshKind::nothing()
            .with_cmd(UpdateKind::Always)
            .with_exe(UpdateKind::Always)
            .with_user(UpdateKind::Always),
    );

    // El representativo es el de mayor `run_time()`: el mas viejo, el padre
    // del grupo. Si ese ya no esta (o cambio de nombre), se cae al primero
    // que siga siendo el mismo proceso -- perder el detalle entero por un
    // pid reciclado seria peor que dar el de otro hermano del grupo.
    //
    // Todo lo que hace falta de `process` se saca a valores propios ANTES
    // de volver a tocar `system`: el segundo refresh (para el nombre del
    // padre) pide `&mut system`, y `process` es un prestamo de `system` que
    // el borrow checker no deja vivo al mismo tiempo.
    let (pid, parent_pid, command_line, exe_path, owner) = pids
        .iter()
        .filter_map(|pid| {
            let process = system.process(Pid::from_u32(*pid))?;
            if !process.name().to_string_lossy().eq_ignore_ascii_case(name) {
                return None;
            }

            let command_line = {
                let cmd = process.cmd();
                (!cmd.is_empty()).then(|| {
                    cmd.iter()
                        .map(|part| part.to_string_lossy())
                        .collect::<Vec<_>>()
                        .join(" ")
                })
            };
            let exe_path = process.exe().map(|path| path.to_string_lossy().into_owned());
            let owner = process.user_id().and_then(|uid| {
                Users::new_with_refreshed_list()
                    .get_user_by_id(uid)
                    .map(|user| user.name().to_owned())
            });

            Some((
                *pid,
                process.parent(),
                command_line,
                exe_path,
                owner,
                process.run_time(),
            ))
        })
        .max_by_key(|(.., run_time)| *run_time)
        .map(|(pid, parent_pid, command_line, exe_path, owner, _)| {
            (pid, parent_pid, command_line, exe_path, owner)
        })?;

    let parent_name = parent_pid.and_then(|parent_pid| {
        // El padre puede no estar en `pids` (no es parte de este grupo por
        // nombre) -- un refresh chico aparte, solo para el.
        system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[parent_pid]),
            true,
            ProcessRefreshKind::nothing(),
        );
        system
            .process(parent_pid)
            .map(|parent| parent.name().to_string_lossy().into_owned())
    });

    Some(ProcessDetails {
        pid,
        parent_name,
        command_line,
        exe_path,
        owner,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(pid: u32, name: &str, cpu: f32, mem: f64, run_time: u32) -> RawProcess {
        RawProcess {
            pid,
            name: name.to_owned(),
            cpu_percent: cpu,
            memory_mb: mem,
            gpu_percent: None,
            disk_bytes_per_sec: 0.0,
            run_time_secs: run_time,
            is_self: false,
        }
    }

    #[test]
    fn agrupa_por_nombre_sumando_consumo() {
        let groups = group_processes(
            vec![
                raw(1, "chrome.exe", 3.0, 100.0, 3600),
                raw(2, "chrome.exe", 2.0, 250.0, 60),
                raw(3, "obs64.exe", 1.0, 500.0, 120),
            ],
            false,
        );

        let chrome = groups
            .iter()
            .find(|group| group.name == "chrome.exe")
            .expect("deberia estar chrome");
        assert_eq!(chrome.pids, vec![1, 2]);
        assert_eq!(chrome.cpu_percent, 5.0);
        assert_eq!(chrome.memory_mb, 350.0);
        // El mas viejo, no el ultimo visto ni la suma.
        assert_eq!(chrome.run_time_secs, 3600);
        assert_eq!(groups.len(), 2);
    }

    /// Igual que el consumo de CPU/memoria, la actividad de disco se suma
    /// entre los procesos del grupo.
    #[test]
    fn agrupa_por_nombre_sumando_disco() {
        let groups = group_processes(
            vec![
                RawProcess {
                    disk_bytes_per_sec: 1000.0,
                    ..raw(1, "chrome.exe", 0.0, 0.0, 0)
                },
                RawProcess {
                    disk_bytes_per_sec: 500.0,
                    ..raw(2, "chrome.exe", 0.0, 0.0, 0)
                },
            ],
            false,
        );
        assert_eq!(groups[0].disk_bytes_per_sec, 1500.0);
    }

    /// En una maquina que no sabe medir GPU por proceso, un cero seria una
    /// afirmacion falsa: tiene que quedar en `None`.
    #[test]
    fn sin_gpu_disponible_el_campo_queda_en_none() {
        let sin = group_processes(vec![raw(1, "a.exe", 0.0, 1.0, 1)], false);
        assert_eq!(sin[0].gpu_percent, None);

        let con = group_processes(vec![raw(1, "a.exe", 0.0, 1.0, 1)], true);
        assert_eq!(con[0].gpu_percent, Some(0.0));
    }

    #[test]
    fn el_grupo_hereda_la_marca_de_proceso_propio() {
        let mut propio = raw(9, "nexodeck.exe", 1.0, 1.0, 1);
        propio.is_self = true;
        let groups = group_processes(vec![raw(8, "nexodeck.exe", 1.0, 1.0, 1), propio], false);
        assert!(groups[0].is_self);
    }

    fn group(name: &str, cpu: f32, gpu: Option<f32>) -> ProcessGroup {
        ProcessGroup {
            name: name.to_owned(),
            pids: vec![1],
            cpu_percent: cpu,
            memory_mb: 0.0,
            gpu_percent: gpu,
            disk_bytes_per_sec: 0.0,
            run_time_secs: 0,
            is_self: false,
        }
    }

    #[test]
    fn el_top_ordena_de_mayor_a_menor_y_recorta() {
        let groups: Vec<ProcessGroup> = (1..21)
            .map(|i| group(&format!("p{i:02}.exe"), i as f32, None))
            .collect();

        let top = top_n_by(&groups, |g| g.cpu_percent as f64, None);
        assert_eq!(top.len(), TOP_N);
        assert_eq!(top[0].name, "p20.exe");
        assert_eq!(top[1].name, "p19.exe");
    }

    /// Con la maquina tranquila casi todos los procesos dan 0.0% de CPU. Sin
    /// el umbral, la lista se llenaba de ceros ordenados alfabeticamente y
    /// habia que buscar entre ellos los que de verdad consumian algo
    /// (verificado en la app real antes de agregarlo).
    #[test]
    fn el_top_de_cpu_deja_afuera_a_los_que_no_consumen() {
        let groups = vec![
            group("activo.exe", 3.2, None),
            group("dormido.exe", 0.0, None),
            group("casi_dormido.exe", 0.01, None),
        ];

        let top = top_n_by(&groups, |g| g.cpu_percent as f64, Some(MIN_VISIBLE_PERCENT));
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "activo.exe");
    }

    /// La memoria NO lleva umbral: todo proceso ocupa algo y esconderlo seria
    /// tapar informacion real.
    #[test]
    fn el_top_de_memoria_no_descarta_a_nadie() {
        let groups = vec![
            ProcessGroup {
                memory_mb: 0.5,
                ..group("chico.exe", 0.0, None)
            },
            ProcessGroup {
                memory_mb: 500.0,
                ..group("grande.exe", 0.0, None)
            },
        ];

        let top = top_n_by(&groups, |g| g.memory_mb, None);
        assert_eq!(top.len(), 2);
        assert_eq!(top[0].name, "grande.exe");
    }

    #[test]
    fn con_menos_grupos_que_el_tope_devuelve_todos() {
        let groups = vec![group("a.exe", 1.0, None), group("b.exe", 2.0, None)];
        assert_eq!(top_n_by(&groups, |g| g.cpu_percent as f64, None).len(), 2);
    }

    /// Doce ceros no son informacion: la lista de GPU se queda corta.
    #[test]
    fn el_top_de_gpu_excluye_los_que_no_usan_la_gpu() {
        let groups = vec![
            group("juego.exe", 0.0, Some(42.0)),
            group("notepad.exe", 0.0, Some(0.0)),
            // Un valor que la UI redondearia a "0.0%": tampoco entra.
            group("casi_cero.exe", 0.0, Some(0.02)),
            group("sin_dato.exe", 0.0, None),
        ];

        let top = top_n_by(
            &groups,
            |g| g.gpu_percent.unwrap_or(0.0) as f64,
            Some(MIN_VISIBLE_PERCENT),
        );
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "juego.exe");
    }

    /// Mismo criterio que CPU/GPU, con el piso propio de disco: un proceso
    /// que mueve menos de 1 KB/s no entra a la lista.
    #[test]
    fn el_top_de_disco_excluye_lo_que_esta_practicamente_inactivo() {
        let groups = vec![
            ProcessGroup {
                disk_bytes_per_sec: 5_000_000.0,
                ..group("copiando.exe", 0.0, None)
            },
            ProcessGroup {
                disk_bytes_per_sec: 10.0,
                ..group("casi_quieto.exe", 0.0, None)
            },
        ];

        let top = top_n_by(
            &groups,
            |g| g.disk_bytes_per_sec,
            Some(MIN_VISIBLE_DISK_BPS),
        );
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "copiando.exe");
    }

    /// Dos grupos con el mismo valor no pueden intercambiarse entre muestras:
    /// la lista se refresca cada 2 s y bailaria sola.
    #[test]
    fn los_empates_se_desempatan_por_nombre() {
        let groups = vec![group("zzz.exe", 5.0, None), group("aaa.exe", 5.0, None)];
        let top = top_n_by(&groups, |g| g.cpu_percent as f64, None);
        assert_eq!(top[0].name, "aaa.exe");
    }

    #[test]
    fn los_procesos_criticos_no_se_dejan_cerrar() {
        assert!(is_protected_process_name("csrss.exe"));
        assert!(is_protected_process_name("CSRSS.EXE"));
        assert!(is_protected_process_name(" System "));
        assert!(!is_protected_process_name("chrome.exe"));
        // Un nombre que solo CONTIENE uno protegido no lo es.
        assert!(!is_protected_process_name("mi_csrss.exe"));
    }

    #[test]
    fn terminar_un_proceso_critico_falla_sin_tocar_nada() {
        let error = terminate_process_group("lsass.exe", &[4]).expect_err("deberia rechazar");
        assert!(error.contains("critico"), "mensaje inesperado: {error}");
    }

    #[test]
    fn no_se_puede_cerrar_a_si_mismo() {
        let error = terminate_process_group("test.exe", &[std::process::id()])
            .expect_err("deberia rechazar");
        assert!(error.contains("NexoDeck"), "mensaje inesperado: {error}");
    }

    /// Un pid que ya no existe se cuenta como `gone`, no como fallo: no hay
    /// nada que arreglar ahi.
    #[test]
    fn un_pid_que_ya_no_existe_no_cuenta_como_fallo() {
        // Un pid altisimo que casi con seguridad no existe.
        let report = terminate_process_group("fantasma.exe", &[4_294_967_294])
            .expect("no deberia ser error");
        assert_eq!(report.requested, 1);
        assert_eq!(report.killed, 0);
        assert_eq!(report.failed, 0);
        assert_eq!(report.gone, 1);
    }

    /// El colector real contra la maquina: no se puede afirmar que procesos
    /// hay, pero si que el resultado es coherente.
    #[test]
    fn la_muestra_real_es_coherente() {
        let mut collector = ProcessCollector::new();
        std::thread::sleep(Duration::from_millis(300));
        let sample = collector.sample();

        assert!(sample.sampled_process_count > 0, "no vio ningun proceso");
        assert!(sample.by_cpu.len() <= TOP_N);
        assert!(sample.by_memory.len() <= TOP_N);
        assert!(sample.by_disk.len() <= TOP_N);

        for group in &sample.by_cpu {
            assert!(!group.pids.is_empty(), "grupo sin pids: {group:?}");
            assert!(
                (0.0..=100.0).contains(&group.cpu_percent),
                "cpu fuera de rango: {group:?}"
            );
        }
        // Ordenado de mayor a menor.
        for pair in sample.by_memory.windows(2) {
            assert!(pair[0].memory_mb >= pair[1].memory_mb);
        }
    }
}
