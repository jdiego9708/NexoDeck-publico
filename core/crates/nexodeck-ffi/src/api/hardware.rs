use std::time::Duration;

use crate::frb_generated::StreamSink;
use nexodeck_hardware::HardwareMonitor;

/// DTO expuesto a Dart. Se mantiene separado de `nexodeck_hardware::HardwareSnapshot`
/// a proposito: `nexodeck-ffi` es el unico crate que Flutter puede tocar, asi
/// que es el unico lugar donde vive la forma exacta del dato cruzando el bridge.
#[derive(Debug, Clone)]
pub struct DiskUsage {
    /// `C:` en Windows, punto de montaje en Unix.
    pub mount_point: String,
    /// Etiqueta del volumen; puede venir vacia y ahi la UI cae al punto de
    /// montaje.
    pub label: String,
    pub kind: DiskMediaKind,
    pub used_mb: f64,
    pub total_mb: f64,
    /// Bytes/segundo de lectura y escritura, para la senal de vida de la UI.
    /// `None` cuando no se puede medir (fuera de Windows, o un volumen sin
    /// letra de unidad).
    pub read_bytes_per_sec: Option<f64>,
    pub write_bytes_per_sec: Option<f64>,
    /// Temperatura del disco fisico en grados Celsius. Dos particiones del
    /// mismo disco traen el mismo numero: es un solo sensor.
    pub temp_c: Option<f32>,
    /// Hace cuantos segundos se tomo `temp_c`. Un disco dormido no contesta y
    /// conserva su ultima lectura, asi que la UI necesita esto para atenuarla
    /// en vez de presentarla como recien medida.
    pub temp_age_secs: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiskMediaKind {
    Ssd,
    Hdd,
    Unknown,
}

#[derive(Debug, Clone)]
pub struct HardwareSnapshot {
    pub cpu_usage: f32,
    pub cpu_freq_mhz: Option<u64>,
    pub cpu_temp: Option<f32>,
    pub ram_used_mb: f64,
    pub ram_total_mb: f64,
    pub disk_used_mb: f64,
    pub disk_total_mb: f64,
    /// Un elemento por disco fisico, para la lista de almacenamiento. Vacia
    /// cuando el snapshot viene de un binario viejo del otro lado del cable.
    pub disks: Vec<DiskUsage>,
    pub net_rx_bytes: u64,
    pub net_tx_bytes: u64,
    pub gpu_usage: Option<f32>,
    pub gpu_temp: Option<f32>,
    pub gpu_vram_used_mb: Option<f64>,
    pub gpu_vram_total_mb: Option<f64>,
    /// Reloj grafico actual en MHz; `None` fuera de NVIDIA.
    pub gpu_clock_mhz: Option<u32>,
    /// Potencia actual de la GPU en watts y el techo efectivo que le impone
    /// el driver; los dos `None` fuera de NVIDIA. El techo viaja con la
    /// lectura porque es lo que la vuelve interpretable sin saber que tarjeta
    /// hay del otro lado.
    pub gpu_power_watts: Option<f32>,
    pub gpu_power_limit_watts: Option<f32>,
    pub cpu_threads_total: u32,
    /// Cuantos hilos estan trabajando ahora. Distinto del uso global: 4 hilos
    /// al 100% y 12 dormidos dan el mismo 25% que 16 al 25%.
    pub cpu_threads_busy: u32,
}

impl From<nexodeck_hardware::HardwareSnapshot> for HardwareSnapshot {
    fn from(s: nexodeck_hardware::HardwareSnapshot) -> Self {
        Self {
            cpu_usage: s.cpu_usage,
            cpu_freq_mhz: s.cpu_freq_mhz,
            cpu_temp: s.cpu_temp,
            ram_used_mb: s.ram_used_mb,
            ram_total_mb: s.ram_total_mb,
            disk_used_mb: s.disk_used_mb,
            disk_total_mb: s.disk_total_mb,
            disks: s
                .disks
                .into_iter()
                .map(|disk| DiskUsage {
                    mount_point: disk.mount_point,
                    label: disk.label,
                    kind: match disk.kind {
                        nexodeck_hardware::DiskMediaKind::Ssd => DiskMediaKind::Ssd,
                        nexodeck_hardware::DiskMediaKind::Hdd => DiskMediaKind::Hdd,
                        nexodeck_hardware::DiskMediaKind::Unknown => DiskMediaKind::Unknown,
                    },
                    used_mb: disk.used_mb,
                    total_mb: disk.total_mb,
                    read_bytes_per_sec: disk.read_bytes_per_sec,
                    write_bytes_per_sec: disk.write_bytes_per_sec,
                    temp_c: disk.temp_c,
                    temp_age_secs: disk.temp_age_secs,
                })
                .collect(),
            net_rx_bytes: s.net_rx_bytes,
            net_tx_bytes: s.net_tx_bytes,
            gpu_usage: s.gpu_usage,
            gpu_temp: s.gpu_temp,
            gpu_vram_used_mb: s.gpu_vram_used_mb,
            gpu_vram_total_mb: s.gpu_vram_total_mb,
            gpu_clock_mhz: s.gpu_clock_mhz,
            gpu_power_watts: s.gpu_power_watts,
            gpu_power_limit_watts: s.gpu_power_limit_watts,
            cpu_threads_total: s.cpu_threads_total,
            cpu_threads_busy: s.cpu_threads_busy,
        }
    }
}

/// Igual que el `From` de arriba, pero para el snapshot que llega por RED
/// (rol Android recibiendo `MessageV1::HardwareSnapshot` via
/// `nexodeck-transport`) en vez del snapshot leido localmente. Distinta
/// fuente, mismo DTO de salida hacia Dart.
impl From<nexodeck_protocol::HardwareSnapshot> for HardwareSnapshot {
    fn from(s: nexodeck_protocol::HardwareSnapshot) -> Self {
        Self {
            cpu_usage: s.cpu_usage,
            cpu_freq_mhz: s.cpu_freq_mhz,
            cpu_temp: s.cpu_temp,
            ram_used_mb: s.ram_used_mb,
            ram_total_mb: s.ram_total_mb,
            disk_used_mb: s.disk_used_mb,
            disk_total_mb: s.disk_total_mb,
            disks: s
                .disks
                .into_iter()
                .map(|disk| DiskUsage {
                    mount_point: disk.mount_point,
                    label: disk.label,
                    kind: match disk.kind {
                        nexodeck_protocol::DiskKindWire::Ssd => DiskMediaKind::Ssd,
                        nexodeck_protocol::DiskKindWire::Hdd => DiskMediaKind::Hdd,
                        nexodeck_protocol::DiskKindWire::Unknown => DiskMediaKind::Unknown,
                    },
                    used_mb: disk.used_mb,
                    total_mb: disk.total_mb,
                    read_bytes_per_sec: disk.read_bytes_per_sec,
                    write_bytes_per_sec: disk.write_bytes_per_sec,
                    temp_c: disk.temp_c,
                    temp_age_secs: disk.temp_age_secs,
                })
                .collect(),
            net_rx_bytes: s.net_rx_bytes,
            net_tx_bytes: s.net_tx_bytes,
            gpu_usage: s.gpu_usage,
            gpu_temp: s.gpu_temp,
            gpu_vram_used_mb: s.gpu_vram_used_mb,
            gpu_vram_total_mb: s.gpu_vram_total_mb,
            gpu_clock_mhz: s.gpu_clock_mhz,
            gpu_power_watts: s.gpu_power_watts,
            gpu_power_limit_watts: s.gpu_power_limit_watts,
            cpu_threads_total: s.cpu_threads_total,
            cpu_threads_busy: s.cpu_threads_busy,
        }
    }
}

/// Empuja un `HardwareSnapshot` por segundo hacia Dart mientras el stream
/// siga abierto del lado Flutter. Rust empuja los datos (no Dart hace
/// polling), con backpressure manejado por el propio StreamSink -- ver
/// seccion 3.2 del documento de arquitectura.
pub async fn watch_hardware_metrics(sink: StreamSink<HardwareSnapshot>) {
    let mut monitor = HardwareMonitor::new();
    // `interval_at` y no `interval`: el primer tick de `interval` se
    // dispara al instante, y ese snapshot se muestrearia sobre una ventana
    // de ~0 ms contra la linea base de `HardwareMonitor::new()` -- CPU y
    // deltas de red saldrian sin sentido en el primer frame de la UI.
    let mut ticker = tokio::time::interval_at(
        tokio::time::Instant::now() + Duration::from_secs(1),
        Duration::from_secs(1),
    );

    loop {
        ticker.tick().await;
        let snapshot = monitor.snapshot();
        if sink.add(snapshot.into()).is_err() {
            // El lado Dart cerro el stream (pantalla cerrada, dispose del
            // provider, etc.) -- dejamos de generar snapshots.
            break;
        }
    }
}
