use nexodeck_hardware::probe_host_components;

/// Nombres y caracteristicas de las piezas del equipo, para poner un modelo
/// concreto al lado de cada metrica ("CPU" contra "Ryzen 7 5700X").
///
/// DTO propio, como todo lo que cruza el puente. Ningun `u64`: las velocidades
/// van en `u32` y la VRAM en `f64` de MB, igual que el resto del snapshot.
///
/// Todo opcional a proposito: en una maquina que no expone un dato, la UI no
/// dibuja esa linea en vez de mostrar un "desconocido" que no ayuda a nadie.
#[derive(Debug, Clone)]
pub struct HostComponents {
    pub cpu_name: Option<String>,
    pub ram_vendor: Option<String>,
    pub ram_part_number: Option<String>,
    /// Velocidad **configurada** de la memoria en MT/s: la que esta corriendo
    /// de verdad, no la que el modulo declara poder alcanzar.
    pub ram_speed_mts: Option<u32>,
    /// Velocidad de la etiqueta del modulo. Si difiere de `ram_speed_mts`, la
    /// memoria no esta corriendo a lo que promete (XMP/DOCP sin activar).
    pub ram_speed_rated_mts: Option<u32>,
    pub ram_module_count: Option<u32>,
    pub gpu_name: Option<String>,
    pub gpu_vram_total_mb: Option<f64>,
    pub network_adapter: Option<String>,
}

impl From<nexodeck_hardware::HostComponents> for HostComponents {
    fn from(c: nexodeck_hardware::HostComponents) -> Self {
        Self {
            cpu_name: c.cpu_name,
            ram_vendor: c.ram_vendor,
            ram_part_number: c.ram_part_number,
            ram_speed_mts: c.ram_speed_mts,
            ram_speed_rated_mts: c.ram_speed_rated_mts,
            ram_module_count: c.ram_module_count,
            gpu_name: c.gpu_name,
            gpu_vram_total_mb: c.gpu_vram_total_mb,
            network_adapter: c.network_adapter,
        }
    }
}

/// Lee las piezas del equipo. Se llama **una vez** por sesion: nada de esto
/// cambia mientras la app corre, y varias de las consultas (WMI para los
/// modulos de memoria, NVML para la GPU) son demasiado caras para el tick de
/// 1 s del stream de metricas.
///
/// `async` porque WMI y NVML bloquean: asi frb la corre en su pool en vez de
/// clavar el hilo de UI de Dart.
pub async fn host_components() -> HostComponents {
    probe_host_components().into()
}

/// Rol PC -> rol Android: mismos campos, dos tipos porque uno es el DTO del
/// bridge (este archivo, lo consume Dart en la PC) y el otro es lo que cruza
/// el cable (`nexodeck-protocol`). Nunca se mezclan a proposito -- ver el
/// comentario grande de `HubSubscriptionSummary` en `api/connection.rs` sobre
/// por que esta separacion no es duplicacion sin sentido.
impl From<HostComponents> for nexodeck_protocol::HostComponentsWire {
    fn from(c: HostComponents) -> Self {
        Self {
            cpu_name: c.cpu_name,
            ram_vendor: c.ram_vendor,
            ram_part_number: c.ram_part_number,
            ram_speed_mts: c.ram_speed_mts,
            ram_speed_rated_mts: c.ram_speed_rated_mts,
            ram_module_count: c.ram_module_count,
            gpu_name: c.gpu_name,
            gpu_vram_total_mb: c.gpu_vram_total_mb,
            network_adapter: c.network_adapter,
        }
    }
}

impl From<nexodeck_protocol::HostComponentsWire> for HostComponents {
    fn from(c: nexodeck_protocol::HostComponentsWire) -> Self {
        Self {
            cpu_name: c.cpu_name,
            ram_vendor: c.ram_vendor,
            ram_part_number: c.ram_part_number,
            ram_speed_mts: c.ram_speed_mts,
            ram_speed_rated_mts: c.ram_speed_rated_mts,
            ram_module_count: c.ram_module_count,
            gpu_name: c.gpu_name,
            gpu_vram_total_mb: c.gpu_vram_total_mb,
            network_adapter: c.network_adapter,
        }
    }
}
