use nvml_wrapper::Nvml;
use nvml_wrapper::enum_wrappers::device::{Clock, TemperatureSensor};
use sysinfo::{Components, CpuRefreshKind, Disks, Networks, System};

/// Actividad de lectura/escritura por disco (senal de vida de la UI). El
/// modulo entero degrada a "sin dato" fuera de Windows -- no esta gateado
/// por `cfg` a nivel de archivo porque `DiskIoReader::sample()` ya maneja
/// esa rama adentro, mismo criterio que `cpu_temp` y `foreground`.
mod disk_io;
/// Temperatura por disco. Mismo criterio que `disk_io`: el modulo entero
/// degrada a "sin dato" fuera de Windows en vez de gatearse por `cfg` desde
/// quien lo usa.
mod disk_temp;
#[cfg(target_os = "windows")]
mod gpu_windows;
/// Helpers de PDH compartidos por el uso agregado de GPU y el uso por
/// proceso. Solo Windows: PDH no existe en otras plataformas.
#[cfg(target_os = "windows")]
mod pdh;
/// Uso y frecuencia del CPU con los contadores del Administrador de tareas.
/// Publico solo para el ejemplo `cpu_compare`.
#[cfg(target_os = "windows")]
pub mod cpu_counters;

/// Frecuencia actual del CPU en MHz: la nominal por `% Processor Performance`
/// / 100, que es la cuenta del Administrador de tareas.
///
/// Pura y fuera de `cpu_counters` (que es solo Windows) para poder testearla
/// en cualquier plataforma. `None` ante datos que no son una frecuencia: una
/// nominal o un rendimiento no positivos significan que el contador no dio
/// dato, y mostrar "0.00 GHz" seria afirmar algo falso.
pub fn current_cpu_frequency_mhz(nominal_mhz: f32, performance_percent: f32) -> Option<u64> {
    if !(nominal_mhz > 0.0 && performance_percent > 0.0) {
        return None;
    }
    Some((nominal_mhz * performance_percent / 100.0).round() as u64)
}

pub mod capabilities;
pub mod components;
mod cpu_temp;
pub mod disks;
pub mod foreground;
pub mod processes;
/// Estado e instalacion del servicio de sensores (solo Windows lo usa).
pub mod sensor_helper;
pub mod vulkan;

pub use capabilities::{
    CpuInfo, GpuInfo, GpuInfoSource, GpuVendor, HostCapabilities, HostOs, free_disk_mb,
    probe_host_capabilities,
};
pub use components::{HostComponents, probe_host_components};
pub use disks::{DiskMediaKind, DiskUsage};
pub use foreground::{ForegroundApp, ForegroundWatcher};
pub use sensor_helper::{SensorHelperStatus, install_sensor_helper, sensor_helper_status};
pub use processes::{
    KillReport, ProcessCollector, ProcessDetails, ProcessGroup, TopProcesses,
};

const BYTES_PER_MB: f64 = 1024.0 * 1024.0;

/// NVML devuelve toda la potencia en milivatios (`u32`); la UI la muestra en
/// watts.
fn milliwatts_to_watts(milliwatts: u32) -> f32 {
    milliwatts as f32 / 1000.0
}

/// El uso global llevado a hilos: 58% de 16 hilos son 9.
///
/// Redondeo normal --para que el numero cierre con el porcentaje que se ve al
/// lado-- pero con **piso en 1** mientras haya algo de uso: decir "0 de 16"
/// con el procesador claramente haciendo algo seria peor que redondear mal.
/// Pura y testeada porque es el numero que el usuario compara contra ese
/// porcentaje.
pub fn equivalent_busy_threads(cpu_usage_percent: f32, thread_count: u32) -> u32 {
    if thread_count == 0 || cpu_usage_percent <= 0.0 {
        return 0;
    }
    let equivalent = cpu_usage_percent / 100.0 * thread_count as f32;
    (equivalent.round() as u32).clamp(1, thread_count)
}

/// Lo que devuelve la lectura de GPU. Es un struct y no una tupla porque son
/// siete `Option` del mismo tipo: en una tupla, invertir dos por accidente
/// compila igual y el error aparece recien en la pantalla.
#[derive(Debug, Clone, Copy, Default)]
struct GpuSnapshot {
    usage: Option<f32>,
    temp: Option<f32>,
    vram_used_mb: Option<f64>,
    vram_total_mb: Option<f64>,
    clock_mhz: Option<u32>,
    power_watts: Option<f32>,
    power_limit_watts: Option<f32>,
}

/// Snapshot puntual del estado del hardware local. No se serializa con
/// serde/postcard aqui: en Fase 1 solo viaja de Rust a Dart via
/// flutter_rust_bridge (nexodeck-ffi). Cuando el transporte remoto llegue
/// (Fase 4), esto alimenta la variante `HardwareSnapshot` del protocolo.
///
/// Ya no es `Copy`: `disks` es un `Vec`. Se mueve en todos sus usos (tanto el
/// stream del FFI como el del servidor lo mandan y lo sueltan), asi que el
/// cambio no obliga a clonar en ninguna ruta caliente.
#[derive(Debug, Clone, PartialEq)]
pub struct HardwareSnapshot {
    pub cpu_usage: f32,
    pub cpu_freq_mhz: Option<u64>,
    /// Temperatura del CPU, del mejor sensor disponible entre los que expone
    /// el SO y, en Windows, los de LibreHardwareMonitor/OpenHardwareMonitor
    /// si el usuario tiene uno corriendo (ver el modulo `cpu_temp`). En un
    /// Windows sin zonas termicas ACPI y sin esas herramientas queda en `None`
    /// — no es un bug, es una limitacion real de la plataforma.
    pub cpu_temp: Option<f32>,
    /// Hilos logicos totales del procesador.
    pub cpu_threads_total: u32,
    /// Hilos **equivalentes** en uso: el porcentaje global llevado a hilos.
    ///
    /// No es "cuantos hilos tienen actividad": esa cuenta satura enseguida
    /// --el planificador de Windows reparte el trabajo entre todos, asi que
    /// con el equipo compilando marcaba 16/16 aunque ninguno estuviera al
    /// tope-- y por lo tanto informaba poco. Asi, el numero siempre es
    /// coherente con el porcentaje que se ve al lado: 58% de 16 hilos son 9.
    pub cpu_threads_busy: u32,

    pub ram_used_mb: f64,
    pub ram_total_mb: f64,

    /// Agregado de los discos de `disks`, no de todos los volumenes
    /// montados: las unidades de nube y de red quedan afuera (ver
    /// `disks::collect`).
    pub disk_used_mb: f64,
    pub disk_total_mb: f64,
    /// Un elemento por disco fisico montado, para la lista de almacenamiento
    /// de la UI. Ordenada por punto de montaje.
    pub disks: Vec<DiskUsage>,

    /// Bytes recibidos/transmitidos desde el ultimo snapshot (no un total
    /// acumulado). Llamar a `snapshot()` aproximadamente una vez por
    /// segundo hace que esto se lea directamente como bytes/s.
    pub net_rx_bytes: u64,
    pub net_tx_bytes: u64,

    /// `None` si no se pudo leer por ninguna via disponible. GPU NVIDIA via
    /// NVML (todas las plataformas); GPU AMD via PDH/DXGI/ADL solo en
    /// Windows (ver `gpu_windows`) -- AMD en Linux e Intel en cualquier
    /// plataforma siguen pendientes (documento de arquitectura).
    pub gpu_usage: Option<f32>,
    pub gpu_temp: Option<f32>,
    pub gpu_vram_used_mb: Option<f64>,
    pub gpu_vram_total_mb: Option<f64>,
    /// Reloj grafico **actual** en MHz. Es un dato vivo --sube y baja con la
    /// carga, que es justo lo interesante-- y por eso viaja en el snapshot y
    /// no en `components`, que se lee una sola vez. Solo NVIDIA: no hay ruta
    /// vendor-agnostica para leerlo.
    pub gpu_clock_mhz: Option<u32>,
    /// Potencia que esta consumiendo la GPU ahora mismo, en watts (nucleo mas
    /// memoria, que es lo que mide NVML). Dato vivo, igual que el reloj.
    /// Solo NVIDIA: en la ruta de Windows para AMD/Intel no hay ninguna de
    /// las tres fuentes (PDH/DXGI/ADL) que lo exponga -- ver `gpu_windows`.
    pub gpu_power_watts: Option<f32>,
    /// Techo de potencia que el driver esta imponiendo, en watts
    /// (`nvmlDeviceGetEnforcedPowerLimit`: el efectivo tras todos los
    /// limitadores, no el nominal de la tarjeta). Viaja al lado de
    /// `gpu_power_watts` por la misma razon que `gpu_vram_total_mb` viaja al
    /// lado del usado: sin el techo, los watts son un numero que solo dice
    /// algo si ya sabes que GPU hay del otro lado -- 180 W son "tranquila" en
    /// una tarjeta de 450 W y "al limite" en una de 200 W.
    pub gpu_power_limit_watts: Option<f32>,
}

/// Mantiene el estado de los distintos lectores de `sysinfo` (y NVML/GPU
/// Windows si aplica) vivo entre snapshots, porque recrearlos en cada
/// llamada es caro y porque las tasas de red (y el uso de GPU via PDH)
/// dependen de un delta contra el snapshot anterior.
pub struct HardwareMonitor {
    system: System,
    disks: Disks,
    networks: Networks,
    components: Components,
    nvml: Option<Nvml>,
    cpu_temp: cpu_temp::CpuTempReader,
    disk_io: disk_io::DiskIoReader,
    disk_temp: disk_temp::DiskTempReader,
    #[cfg(target_os = "windows")]
    windows_gpu: gpu_windows::WindowsGpuMonitor,
    /// Los contadores del Administrador de tareas. `None` si PDH no los pudo
    /// abrir: ahi se cae a lo que da `sysinfo`. Ver `cpu_counters`.
    #[cfg(target_os = "windows")]
    cpu_counters: Option<cpu_counters::CpuCounters>,
}

impl HardwareMonitor {
    pub fn new() -> Self {
        // `new_all()` ya hace un refresh de CPU: esa primera lectura queda
        // como linea base del primer delta de uso. NO agregar un
        // `refresh_cpu_all()` extra aca -- ver el comentario largo en
        // `snapshot()` sobre por que dos refreshes seguidos rompen el
        // porcentaje en Windows.
        let system = System::new_all();

        Self {
            system,
            disks: Disks::new_with_refreshed_list(),
            networks: Networks::new_with_refreshed_list(),
            components: Components::new_with_refreshed_list(),
            // Sin GPU NVIDIA o sin driver -> Err, se degrada a None en
            // cada snapshot en vez de fallar el monitor completo.
            nvml: Nvml::init().ok(),
            cpu_temp: cpu_temp::CpuTempReader::new(),
            disk_io: disk_io::DiskIoReader::new(),
            disk_temp: disk_temp::DiskTempReader::new(),
            #[cfg(target_os = "windows")]
            windows_gpu: gpu_windows::WindowsGpuMonitor::new(),
            #[cfg(target_os = "windows")]
            cpu_counters: cpu_counters::CpuCounters::new(),
        }
    }

    pub fn snapshot(&mut self) -> HardwareSnapshot {
        // UN SOLO refresh de CPU por snapshot, a proposito. En Windows
        // sysinfo calcula el uso como `100 - \Processor(_Total)\% Idle Time`
        // leido por PDH, y `refresh_cpu_specifics()` recalcula ese valor en
        // CADA llamada (ignora el `CpuRefreshKind` que recibe). Como
        // `refresh_cpu_usage()` y `refresh_cpu_frequency()` delegan las dos
        // en el mismo metodo, encadenarlas dejaba una ventana de muestreo de
        // ~0 ms para la segunda: el contador devuelve PDH_INVALID_DATA,
        // sysinfo lo traduce a 0.0 en silencio, y el uso quedaba clavado en
        // `100.0 - 0.0 = 100.0`. `CpuRefreshKind::everything()` trae uso y
        // frecuencia con un unico PdhCollectQueryData sobre el intervalo
        // real entre snapshots.
        self.system
            .refresh_cpu_specifics(CpuRefreshKind::everything());
        self.system.refresh_memory();
        self.disks.refresh(true);
        self.networks.refresh(true);
        self.components.refresh(true);

        // El agregado sale de la MISMA lista que ve la UI, y no de recorrer
        // `self.disks` por separado: si se calcularan aparte, el filtro de
        // volumenes de nube/red se aplicaria a la lista pero no al total, y
        // la suma de las filas no daria el numero de la barra.
        let mut disk_list = disks::collect(&self.disks);
        let (disk_used_mb, disk_total_mb) = disks::totals(&disk_list);

        // Se mergea DESPUES de calcular el agregado de capacidad, y sobre la
        // misma lista que ve la UI: las tasas son otra pregunta que no debe
        // afectar el numero de la barra. Un volumen sin letra (montado en una
        // carpeta) no tiene contador `LogicalDisk` que consultar y se queda
        // en `None`, igual que cualquier otra plataforma sin PDH.
        let disk_io_rates = self.disk_io.sample();
        // La temperatura sale de un hilo con su propia cadencia (30 s), no de
        // esta pasada: se lee la ultima muestra conocida, que puede no existir
        // todavia en los primeros segundos de vida de la app.
        let disk_temps = self.disk_temp.read();
        let now = disk_temp::now_epoch_secs();
        for disk in &mut disk_list {
            let key = disk.mount_point.to_ascii_uppercase();
            if let Some(&(read, write)) = disk_io_rates.get(&key) {
                disk.read_bytes_per_sec = Some(read);
                disk.write_bytes_per_sec = Some(write);
            }
            if let Some(reading) = disk_temps.get(&key) {
                disk.temp_c = Some(reading.celsius);
                disk.temp_age_secs = Some(reading.age_secs(now));
            }
        }

        let cpu_usage = self.system.global_cpu_usage().clamp(0.0, 100.0);
        let thread_count = self.system.cpus().len() as u32;
        let cpu_freq_mhz = self.cpu_frequency_mhz();

        let (net_rx_bytes, net_tx_bytes) =
            self.networks
                .list()
                .values()
                .fold((0u64, 0u64), |(rx, tx), net| {
                    (rx + net.received(), tx + net.transmitted())
                });

        let GpuSnapshot {
            usage: gpu_usage,
            temp: gpu_temp,
            vram_used_mb: gpu_vram_used_mb,
            vram_total_mb: gpu_vram_total_mb,
            clock_mhz: gpu_clock_mhz,
            power_watts: gpu_power_watts,
            power_limit_watts: gpu_power_limit_watts,
        } = self.gpu_snapshot();

        HardwareSnapshot {
            // Clamp defensivo: si el contador de rendimiento vuelve a
            // fallar, que la UI muestre un valor dentro de rango en vez de
            // algo absurdo.
            cpu_usage,
            cpu_freq_mhz,
            cpu_temp: self.cpu_temp.read(&self.components),
            cpu_threads_total: thread_count,
            cpu_threads_busy: equivalent_busy_threads(cpu_usage, thread_count),
            ram_used_mb: self.system.used_memory() as f64 / BYTES_PER_MB,
            ram_total_mb: self.system.total_memory() as f64 / BYTES_PER_MB,
            disk_used_mb,
            disk_total_mb,
            disks: disk_list,
            net_rx_bytes,
            net_tx_bytes,
            gpu_usage,
            gpu_temp,
            gpu_vram_used_mb,
            gpu_vram_total_mb,
            gpu_clock_mhz,
            gpu_power_watts,
            gpu_power_limit_watts,
        }
    }

    /// Frecuencia **actual** del CPU en MHz.
    ///
    /// En Windows sale de los contadores del Administrador de tareas (la
    /// nominal por `% Processor Performance`), porque la de `sysinfo` es la
    /// nominal fija: en el equipo principal marcaba 3401 MHz siempre, con el
    /// procesador en 4.2-4.5 GHz. Ver `cpu_counters`. Si PDH no da muestra se
    /// cae a `sysinfo` -- un numero nominal es mejor que ninguno, y fuera de
    /// Windows es la unica fuente.
    fn cpu_frequency_mhz(&self) -> Option<u64> {
        #[cfg(target_os = "windows")]
        if let Some(mhz) = self
            .cpu_counters
            .as_ref()
            .and_then(cpu_counters::CpuCounters::sample)
            .and_then(|sample| sample.current_mhz())
        {
            return Some(mhz);
        }
        self.system
            .cpus()
            .first()
            .map(|cpu| cpu.frequency())
            .filter(|&mhz| mhz > 0)
    }

    /// Prioriza NVML (GPU NVIDIA real, via el device index 0) y cae a la
    /// ruta de Windows (PDH/DXGI/ADL, ver `gpu_windows`) cuando no hay
    /// NVIDIA -- el caso de esta maquina de desarrollo, con una AMD
    /// Radeon RX 580.
    fn gpu_snapshot(&self) -> GpuSnapshot {
        if let Some(nvml) = &self.nvml {
            if let Ok(device) = nvml.device_by_index(0) {
                let memory = device.memory_info().ok();
                return GpuSnapshot {
                    usage: device.utilization_rates().ok().map(|u| u.gpu as f32),
                    temp: device
                        .temperature(TemperatureSensor::Gpu)
                        .ok()
                        .map(|t| t as f32),
                    vram_used_mb: memory.as_ref().map(|m| m.used as f64 / BYTES_PER_MB),
                    vram_total_mb: memory.as_ref().map(|m| m.total as f64 / BYTES_PER_MB),
                    clock_mhz: device.clock_info(Clock::Graphics).ok(),
                    power_watts: device.power_usage().ok().map(milliwatts_to_watts),
                    // `enforced_power_limit` y no `power_management_limit`: el
                    // primero es el techo efectivo tras todos los limitadores
                    // (incluido el fuera de banda), que es contra el que tiene
                    // sentido comparar la lectura de al lado.
                    power_limit_watts: device
                        .enforced_power_limit()
                        .ok()
                        .map(milliwatts_to_watts),
                };
            }
        }

        #[cfg(target_os = "windows")]
        {
            let (usage, temp, vram_used_mb, vram_total_mb) = self.windows_gpu.snapshot();
            GpuSnapshot {
                usage,
                temp,
                vram_used_mb,
                vram_total_mb,
                // El reloj y la potencia solo los expone NVML; en AMD/Intel
                // quedan sin dato y la UI no dibuja esos badges. PDH no tiene
                // contador de watts, DXGI solo da propiedades estaticas, y
                // ADL los expone recien por Overdrive6/8 (dependiente de la
                // generacion de la tarjeta, sin la garantia que si tiene
                // `ADL_Overdrive5_Temperature_Get`).
                clock_mhz: None,
                power_watts: None,
                power_limit_watts: None,
            }
        }

        #[cfg(not(target_os = "windows"))]
        {
            GpuSnapshot::default()
        }
    }
}

impl Default for HardwareMonitor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::equivalent_busy_threads;

    #[test]
    fn los_hilos_equivalentes_siguen_al_porcentaje() {
        // 58% de 16 hilos son 9,3 -> 9.
        assert_eq!(equivalent_busy_threads(58.0, 16), 9);
        assert_eq!(equivalent_busy_threads(50.0, 16), 8);
        assert_eq!(equivalent_busy_threads(100.0, 16), 16);
        assert_eq!(equivalent_busy_threads(12.0, 16), 2);
    }

    /// Con el procesador haciendo algo, por poco que sea, no puede decir
    /// "0 de 16" al lado de un porcentaje distinto de cero.
    #[test]
    fn un_uso_minimo_cuenta_como_un_hilo() {
        assert_eq!(equivalent_busy_threads(0.5, 16), 1);
        assert_eq!(equivalent_busy_threads(0.0, 16), 0);
    }

    #[test]
    fn nunca_pasa_del_total_ni_divide_por_cero() {
        assert_eq!(equivalent_busy_threads(150.0, 8), 8);
        assert_eq!(equivalent_busy_threads(50.0, 0), 0);
    }

    use super::*;

    #[test]
    fn current_frequency_is_nominal_times_performance() {
        // Lectura real del equipo principal: 3401 MHz nominales al 132.4%.
        assert_eq!(current_cpu_frequency_mhz(3401.0, 132.4), Some(4503));
        // En reposo profundo el rendimiento baja de 100 y la frecuencia tambien.
        assert_eq!(current_cpu_frequency_mhz(3401.0, 50.0), Some(1701));
    }

    #[test]
    fn missing_counter_data_is_not_a_frequency() {
        assert_eq!(current_cpu_frequency_mhz(0.0, 130.0), None);
        assert_eq!(current_cpu_frequency_mhz(3401.0, 0.0), None);
        assert_eq!(current_cpu_frequency_mhz(f32::NAN, 130.0), None);
    }

    #[test]
    fn snapshot_reports_plausible_ram() {
        let mut monitor = HardwareMonitor::new();
        let snapshot = monitor.snapshot();
        assert!(snapshot.ram_total_mb > 0.0);
        assert!(snapshot.ram_used_mb <= snapshot.ram_total_mb);
    }

    /// Solo verifica el rango. No se afirma `< 100.0` a proposito: en una
    /// maquina cargada (o en CI) el 100% real es posible y el test seria
    /// flaky. La comprobacion de que el porcentaje es *correcto* (y no el
    /// 100% fijo que producia el doble refresh, ver `snapshot()`) se hace a
    /// mano con `cargo run -p nexodeck-hardware --example snapshot`
    /// comparando contra el Administrador de tareas.
    #[test]
    fn cpu_usage_stays_within_range_across_samples() {
        let mut monitor = HardwareMonitor::new();
        for _ in 0..2 {
            std::thread::sleep(std::time::Duration::from_millis(600));
            let snapshot = monitor.snapshot();
            assert!(
                (0.0..=100.0).contains(&snapshot.cpu_usage),
                "cpu_usage fuera de rango: {}",
                snapshot.cpu_usage
            );
        }
    }
}
