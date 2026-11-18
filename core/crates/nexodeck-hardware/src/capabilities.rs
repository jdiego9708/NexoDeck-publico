//! Probe **estatico** del equipo: los hechos que no cambian mientras la app
//! corre (que GPU hay, cuanta VRAM, cuantos nucleos fisicos, si el CPU tiene
//! AVX2, cuanto disco libre queda).
//!
//! Es deliberadamente lo opuesto a [`crate::HardwareSnapshot`], que se muestrea
//! una vez por segundo para el dashboard. Aca nada se refresca: se llama una
//! vez, se cachea del lado del consumidor y listo. El motivo de existir es
//! decidir **que modelo de IA y que build de llama.cpp puede correr este
//! equipo**, una decision que se toma una sola vez en el wizard de setup.
//!
//! Ninguna via de deteccion es obligatoria: todo degrada a `None`/`false`/lista
//! vacia. Un equipo sin NVML, sin Vulkan y sin DXGI simplemente cae al camino
//! de CPU, que siempre funciona.

use std::path::Path;

use nvml_wrapper::Nvml;
use sysinfo::{Disks, System};

const BYTES_PER_MB: u64 = 1024 * 1024;

/// Vendor IDs PCI en hex estandar (los mismos que reporta
/// `DXGI_ADAPTER_DESC1::VendorId`). Ojo: ADL usa otra convencion para AMD,
/// ver `gpu_windows.rs`.
const VENDOR_NVIDIA: u32 = 0x10DE;
const VENDOR_AMD: u32 = 0x1002;
const VENDOR_INTEL: u32 = 0x8086;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostOs {
    Windows,
    Linux,
    Android,
    Other,
}

impl HostOs {
    pub fn current() -> Self {
        #[cfg(target_os = "windows")]
        {
            HostOs::Windows
        }
        #[cfg(target_os = "android")]
        {
            HostOs::Android
        }
        #[cfg(all(target_os = "linux", not(target_os = "android")))]
        {
            HostOs::Linux
        }
        #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "android")))]
        {
            HostOs::Other
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            HostOs::Windows => "windows",
            HostOs::Linux => "linux",
            HostOs::Android => "android",
            HostOs::Other => "other",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuVendor {
    Nvidia,
    Amd,
    Intel,
    Unknown,
}

impl GpuVendor {
    fn from_pci_id(vendor_id: u32) -> Self {
        match vendor_id {
            VENDOR_NVIDIA => GpuVendor::Nvidia,
            VENDOR_AMD => GpuVendor::Amd,
            VENDOR_INTEL => GpuVendor::Intel,
            _ => GpuVendor::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            GpuVendor::Nvidia => "NVIDIA",
            GpuVendor::Amd => "AMD",
            GpuVendor::Intel => "Intel",
            GpuVendor::Unknown => "desconocido",
        }
    }
}

/// De donde salio la informacion de una GPU. Importa porque las dos fuentes no
/// son igual de confiables: NVML habla directo con el driver de NVIDIA, DXGI
/// lee una propiedad estatica del adaptador.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuInfoSource {
    Nvml,
    Dxgi,
}

#[derive(Debug, Clone)]
pub struct GpuInfo {
    pub vendor: GpuVendor,
    pub name: String,
    /// VRAM **dedicada** en MB. Una iGPU normalmente reporta muy poca (o cero)
    /// porque usa memoria compartida del sistema: ese es justamente el dato que
    /// la descalifica como acelerador para un modelo de lenguaje.
    pub vram_total_mb: u64,
    /// Compute capability CUDA `(major, minor)`, solo en NVIDIA via NVML.
    ///
    /// No es un dato de vitrina: decide **que build de CUDA descargar**. Los
    /// binarios de CUDA 12.x no traen codigo para Blackwell (sm_120, las
    /// RTX 50xx) y los de CUDA 13.x dejaron afuera Pascal y anteriores
    /// (sm_61 y abajo, las GTX 10xx). Elegir mal no da un error claro: da una
    /// GPU que "no acelera" sin explicacion.
    pub cuda_compute_capability: Option<(u32, u32)>,
    pub source: GpuInfoSource,
}

#[derive(Debug, Clone)]
pub struct CpuInfo {
    pub brand: String,
    /// `None` cuando el SO no lo expone. En ese caso hay que caer a
    /// `logical_cores`, aceptando que sobreestima (hyperthreading).
    pub physical_cores: Option<u32>,
    pub logical_cores: u32,
    pub avx2: bool,
    pub avx512: bool,
}

impl CpuInfo {
    /// Nucleos que conviene pasarle a `llama-server --threads`.
    ///
    /// Son los **fisicos**, no los logicos: con hyperthreading, dos hilos de
    /// inferencia sobre el mismo nucleo fisico se pelean por las mismas
    /// unidades SIMD y el throughput baja en vez de subir. Es una
    /// recomendacion vieja y estable de llama.cpp.
    pub fn recommended_threads(&self) -> u32 {
        self.physical_cores
            .unwrap_or_else(|| (self.logical_cores / 2).max(1))
            .max(1)
    }
}

#[derive(Debug, Clone)]
pub struct HostCapabilities {
    pub os: HostOs,
    pub cpu: CpuInfo,
    pub ram_total_mb: u64,
    /// Disco libre en la particion donde van a vivir los modelos.
    pub free_disk_mb: u64,
    /// Todas las GPUs no-software detectadas, sin filtrar por vendor.
    pub gpus: Vec<GpuInfo>,
    /// NVML inicializo. Implica driver NVIDIA presente y, por lo tanto, que la
    /// build CUDA de llama.cpp tiene sentido.
    pub nvml_available: bool,
    /// Dispositivos que ve Vulkan. `None` = no hay loader o no se pudo crear
    /// una instancia; `Some(0)` = hay loader pero ninguna GPU compatible.
    pub vulkan_device_count: Option<u32>,
}

impl HostCapabilities {
    /// La GPU con mas VRAM dedicada. Es la que hay que mirar para decidir
    /// gama: en un portatil con iGPU + dGPU, la iGPU aparece primero en la
    /// enumeracion y tomar "la primera" daria la respuesta equivocada.
    pub fn best_gpu(&self) -> Option<&GpuInfo> {
        self.gpus.iter().max_by_key(|gpu| gpu.vram_total_mb)
    }

    pub fn has_nvidia(&self) -> bool {
        self.gpus.iter().any(|gpu| gpu.vendor == GpuVendor::Nvidia)
    }

    pub fn vulkan_usable(&self) -> bool {
        matches!(self.vulkan_device_count, Some(count) if count > 0)
    }
}

/// Corre el probe completo. Cuesta unos cientos de milisegundos (inicializar
/// NVML y crear una instancia de Vulkan no son gratis), asi que **cachealo**:
/// nada de lo que devuelve cambia mientras la app este abierta.
pub fn probe_host_capabilities(model_storage_dir: &Path) -> HostCapabilities {
    let mut system = System::new();
    system.refresh_memory();
    system.refresh_cpu_all();

    let cpu = probe_cpu(&system);
    let nvml = Nvml::init().ok();
    let gpus = probe_gpus(nvml.as_ref());

    HostCapabilities {
        os: HostOs::current(),
        cpu,
        ram_total_mb: system.total_memory() / BYTES_PER_MB,
        free_disk_mb: free_disk_mb(model_storage_dir),
        gpus,
        nvml_available: nvml.is_some(),
        vulkan_device_count: crate::vulkan::physical_device_count(),
    }
}

fn probe_cpu(system: &System) -> CpuInfo {
    let brand = system
        .cpus()
        .first()
        .map(|cpu| cpu.brand().trim().to_string())
        .filter(|brand| !brand.is_empty())
        .unwrap_or_else(|| "CPU desconocida".to_string());

    CpuInfo {
        brand,
        physical_cores: System::physical_core_count().map(|count| count as u32),
        logical_cores: system.cpus().len().max(1) as u32,
        avx2: detect_avx2(),
        avx512: detect_avx512(),
    }
}

/// Enumera GPUs combinando las dos fuentes disponibles.
///
/// En Windows DXGI ya devuelve la lista completa de adaptadores fisicos de
/// cualquier vendor, asi que es la base; NVML solo se usa para **enriquecer**
/// las entradas NVIDIA (nombre y VRAM salidos del driver, mas fiables que los
/// de DXGI). Fuera de Windows no hay DXGI, asi que NVML es lo unico que hay —
/// AMD e Intel en Linux quedan sin detectar por ahora, igual que en el snapshot
/// dinamico.
fn probe_gpus(nvml: Option<&Nvml>) -> Vec<GpuInfo> {
    let nvidia_from_nvml = nvml.map(nvidia_gpus_from_nvml).unwrap_or_default();

    #[cfg(target_os = "windows")]
    {
        let mut nvidia_queue = nvidia_from_nvml.into_iter();
        let adapters = crate::gpu_windows::read_dxgi_adapters();

        if adapters.is_empty() {
            return nvidia_queue.collect();
        }

        return adapters
            .into_iter()
            .map(|adapter| {
                let vendor = GpuVendor::from_pci_id(adapter.vendor_id);
                if vendor == GpuVendor::Nvidia {
                    if let Some(from_nvml) = nvidia_queue.next() {
                        return from_nvml;
                    }
                }
                GpuInfo {
                    vendor,
                    name: adapter.name,
                    vram_total_mb: adapter.vram_total_mb as u64,
                    cuda_compute_capability: None,
                    source: GpuInfoSource::Dxgi,
                }
            })
            .collect();
    }

    #[cfg(not(target_os = "windows"))]
    {
        nvidia_from_nvml
    }
}

fn nvidia_gpus_from_nvml(nvml: &Nvml) -> Vec<GpuInfo> {
    let Ok(count) = nvml.device_count() else {
        return Vec::new();
    };

    (0..count)
        .filter_map(|index| {
            let device = nvml.device_by_index(index).ok()?;
            let name = device
                .name()
                .unwrap_or_else(|_| "GPU NVIDIA".to_string());
            let vram_total_mb = device
                .memory_info()
                .map(|memory| memory.total / BYTES_PER_MB)
                .unwrap_or(0);
            let cuda_compute_capability = device
                .cuda_compute_capability()
                .ok()
                .map(|cc| (cc.major.max(0) as u32, cc.minor.max(0) as u32));
            Some(GpuInfo {
                vendor: GpuVendor::Nvidia,
                name,
                vram_total_mb,
                cuda_compute_capability,
                source: GpuInfoSource::Nvml,
            })
        })
        .collect()
}

/// Espacio libre en la particion que contiene `path`.
///
/// `path` puede no existir todavia (es justamente el directorio que vamos a
/// crear para guardar los modelos), asi que se resuelve buscando el punto de
/// montaje **mas largo** que sea prefijo de la ruta. Quedarse con el primero
/// que matchee daria `C:\` para una ruta en `C:\datos\...` aunque `C:\datos`
/// fuera su propio volumen.
pub fn free_disk_mb(path: &Path) -> u64 {
    let disks = Disks::new_with_refreshed_list();

    let best = disks
        .list()
        .iter()
        .filter(|disk| path.starts_with(disk.mount_point()))
        .max_by_key(|disk| disk.mount_point().as_os_str().len());

    match best {
        Some(disk) => disk.available_space() / BYTES_PER_MB,
        // Sin match (ruta rara, o `Disks` vacio en algun contenedor) se usa el
        // volumen mas grande como aproximacion, que es mejor que devolver 0 y
        // bloquear al usuario por un dato que no pudimos leer.
        None => disks
            .list()
            .iter()
            .map(|disk| disk.available_space())
            .max()
            .unwrap_or(0)
            / BYTES_PER_MB,
    }
}

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
fn detect_avx2() -> bool {
    std::arch::is_x86_feature_detected!("avx2")
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn detect_avx2() -> bool {
    false
}

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
fn detect_avx512() -> bool {
    std::arch::is_x86_feature_detected!("avx512f")
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn detect_avx512() -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    /// El probe nunca puede entrar en panico ni devolver algo absurdo, aunque
    /// no haya GPU ni Vulkan: en CI corre en una maquina pelada.
    #[test]
    fn probe_returns_plausible_values() {
        let caps = probe_host_capabilities(std::env::temp_dir().as_path());

        assert!(caps.ram_total_mb > 0, "RAM total no puede ser 0");
        assert!(caps.cpu.logical_cores >= 1);
        assert!(caps.cpu.recommended_threads() >= 1);
        assert!(!caps.cpu.brand.is_empty());

        for gpu in &caps.gpus {
            assert!(!gpu.name.is_empty(), "una GPU sin nombre no sirve para la UI");
        }
    }

    /// `best_gpu` tiene que elegir por VRAM, no por orden de enumeracion: en un
    /// portatil la iGPU suele venir primero.
    #[test]
    fn best_gpu_picks_the_largest_vram_not_the_first() {
        let caps = HostCapabilities {
            os: HostOs::Windows,
            cpu: CpuInfo {
                brand: "test".into(),
                physical_cores: Some(8),
                logical_cores: 16,
                avx2: true,
                avx512: false,
            },
            ram_total_mb: 32768,
            free_disk_mb: 100_000,
            gpus: vec![
                GpuInfo {
                    vendor: GpuVendor::Intel,
                    name: "Intel UHD Graphics".into(),
                    vram_total_mb: 128,
                    cuda_compute_capability: None,
                    source: GpuInfoSource::Dxgi,
                },
                GpuInfo {
                    vendor: GpuVendor::Nvidia,
                    name: "NVIDIA GeForce RTX 5060 Ti".into(),
                    vram_total_mb: 16311,
                    cuda_compute_capability: Some((12, 0)),
                    source: GpuInfoSource::Nvml,
                },
            ],
            nvml_available: true,
            vulkan_device_count: Some(2),
        };

        assert_eq!(caps.best_gpu().unwrap().vendor, GpuVendor::Nvidia);
        assert!(caps.has_nvidia());
        assert!(caps.vulkan_usable());
    }

    #[test]
    fn recommended_threads_falls_back_to_half_the_logical_cores() {
        let cpu = CpuInfo {
            brand: "test".into(),
            physical_cores: None,
            logical_cores: 16,
            avx2: true,
            avx512: false,
        };
        assert_eq!(cpu.recommended_threads(), 8);

        let single = CpuInfo {
            physical_cores: None,
            logical_cores: 1,
            ..cpu
        };
        assert_eq!(single.recommended_threads(), 1);
    }

    #[test]
    fn vulkan_with_zero_devices_is_not_usable() {
        let caps = HostCapabilities {
            os: HostOs::Linux,
            cpu: CpuInfo {
                brand: "test".into(),
                physical_cores: Some(4),
                logical_cores: 8,
                avx2: false,
                avx512: false,
            },
            ram_total_mb: 8192,
            free_disk_mb: 50_000,
            gpus: Vec::new(),
            nvml_available: false,
            vulkan_device_count: Some(0),
        };

        assert!(!caps.vulkan_usable());
        assert!(caps.best_gpu().is_none());
    }
}
