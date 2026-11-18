//! Lectura de GPU en Windows para tarjetas no-NVIDIA (probado en una AMD
//! Radeon RX 580). No hay crate maduro tipo `nvml-wrapper` para AMD, asi
//! que esto combina 3 fuentes independientes, cada una con su propio
//! fallback a `None`:
//!
//! - **Uso % y VRAM usada**: PDH (`\GPU Engine(*)\Utilization Percentage`
//!   y `\GPU Adapter Memory(*)\Dedicated Usage`), vendor-agnostico -- la
//!   misma fuente que usa el Administrador de Tareas. Nota: se probo
//!   primero `IDXGIAdapter3::QueryVideoMemoryInfo` para VRAM usada, pero
//!   esa API mide el consumo del proceso que llama, no el total del
//!   sistema (siempre da 0 aqui, ya que este proceso no renderiza nada) --
//!   PDH si agrega todos los procesos.
//! - **VRAM total**: DXGI (`DXGI_ADAPTER_DESC.DedicatedVideoMemory`), una
//!   propiedad estatica del hardware por lo que si es correcto leerla asi
//!   -- y mas confiable que `Win32_VideoController.AdapterRAM` de WMI
//!   (tiene un bug conocido de overflow en tarjetas con VRAM alta).
//! - **Temperatura**: no tiene ruta vendor-agnostica. Unica via
//!   documentada por AMD: ADL (`ADL_Overdrive5_Temperature_Get`), cargado
//!   dinamicamente desde `atiadlxx.dll`/`atiadlxy.dll` en runtime (mismo
//!   patron que `nvml-wrapper` usa para NVML) -- las firmas se verificaron
//!   contra el codigo fuente publico de AMD en
//!   github.com/GPUOpen-LibrariesAndSDKs/display-library (adlutil/main.c,
//!   adl_structures.h, adl_sdk.h), no hay SDK de AMD instalado en esta
//!   maquina ni hace falta.

use std::ffi::{c_int, c_void};
use std::mem;

use libloading::{Library, Symbol};
use windows::Win32::Graphics::Dxgi::{CreateDXGIFactory1, IDXGIFactory1};
use windows::Win32::System::Performance::PDH_HCOUNTER;

use crate::pdh::{self, PdhQuery};

const ADL_MAX_PATH: usize = 256;
const ADL_OK: c_int = 0;
/// Vendor ID PCI de AMD en hex (formato estandar) -- lo usa DXGI
/// (`DXGI_ADAPTER_DESC.VendorId`).
const AMD_VENDOR_ID: u32 = 0x1002;
/// El campo `iVendorID` de ADL usa por convencion propia el valor decimal
/// "1002" en vez del hex 0x1002 (=4098) -- confirmado en vivo contra esta
/// maquina: los 7 adaptadores AMD reportados por
/// `ADL_Adapter_AdapterInfo_Get` tenian `iVendorID == 1002` decimal, no
/// 4098. Es una peculiaridad historica de ADL, no un error de esta
/// implementacion.
const ADL_AMD_VENDOR_ID: c_int = 1002;

// ---------------------------------------------------------------------
// Uso de GPU y VRAM via PDH (vendor-agnostico)
// ---------------------------------------------------------------------

/// `IDXGIAdapter3::QueryVideoMemoryInfo` en un principio parecia la fuente
/// obvia para VRAM usada, pero mide el consumo *del proceso que llama*, no
/// el total del sistema -- en este proceso (que no renderiza nada) siempre
/// da 0. El contador PDH `GPU Adapter Memory\Dedicated Usage` tiene una
/// instancia por proceso que usa el adaptador; sumando todas las
/// instancias se obtiene el mismo numero que muestra el Administrador de
/// Tareas. Confirmado en vivo contra esta maquina (una RX 580 real).
pub struct PdhCounters {
    query: PdhQuery,
    engine_usage: PDH_HCOUNTER,
    adapter_memory: PDH_HCOUNTER,
}

// SAFETY: `PdhQuery` declara su propio `Send`, pero los `PDH_HCOUNTER` son
// punteros crudos y arrastran a toda la struct. Los handles de PDH no son
// thread-affine; `HardwareMonitor` los usa desde un solo hilo y necesita ser
// `Send` para que el servidor pueda spawnear su tarea de metricas -- si esto
// falta, el error aparece lejos, en `tokio::spawn` de `server.rs`.
unsafe impl Send for PdhCounters {}

impl PdhCounters {
    pub fn new() -> Option<Self> {
        let query = PdhQuery::open()?;
        let engine_usage = query.add_counter(pdh::GPU_ENGINE_USAGE)?;
        let adapter_memory = query.add_counter(r"\GPU Adapter Memory(*)\Dedicated Usage")?;

        Some(Self {
            query,
            engine_usage,
            adapter_memory,
        })
    }

    /// Requiere haber sido llamado al menos una vez antes (PDH calcula el
    /// % / la tasa a partir de dos muestras) -- igual que sysinfo con el
    /// uso de CPU, la primera lectura tras `new()` no es confiable.
    pub fn collect_and_read(&self) -> (Option<f32>, Option<f64>) {
        const BYTES_PER_MB: f64 = 1024.0 * 1024.0;

        if !self.query.collect() {
            return (None, None);
        }

        // SAFETY: los contadores salen de `PdhQuery::add_counter` sobre la
        // query que sigue viva en `self`, y acaba de tomarse una muestra.
        unsafe {
            // Cada instancia es un (proceso, adaptador, motor). El uso de la
            // GPU es la suma de cada tipo de motor sobre todos los procesos,
            // quedandose con el mayor -- ver `pdh::aggregate_gpu_percent`,
            // que es donde vive el porque y donde estan los tests.
            let usage = pdh::read_counter_array(self.engine_usage)
                .and_then(|items| pdh::aggregate_gpu_percent(&items));

            // VRAM: se suman TODAS las instancias (una por proceso que usa
            // el adaptador), no solo la nuestra.
            let vram_used_mb = pdh::read_counter_array(self.adapter_memory)
                .map(|items| items.iter().map(|(_, v)| v).sum::<f64>() / BYTES_PER_MB);

            (usage, vram_used_mb)
        }
    }
}

// ---------------------------------------------------------------------
// VRAM total via DXGI (vendor-agnostico, propiedad estatica del
// hardware -- a diferencia del uso, si es correcto leerla por proceso)
// ---------------------------------------------------------------------

/// Bit `DXGI_ADAPTER_FLAG_SOFTWARE` de `DXGI_ADAPTER_DESC1::Flags`. Windows
/// siempre enumera al menos un adaptador software (el "Microsoft Basic Render
/// Driver" / WARP), que reporta 0 MB de VRAM dedicada y no sirve para nada de
/// lo que hacemos: hay que descartarlo o el probe cree que hay una GPU mas.
const DXGI_ADAPTER_FLAG_SOFTWARE: u32 = 2;

/// Un adaptador grafico tal como lo ve DXGI. Datos **estaticos** del hardware
/// (a diferencia del uso y la VRAM ocupada, que son dinamicos y salen de PDH).
#[derive(Debug, Clone)]
pub struct DxgiAdapter {
    /// Vendor ID PCI en hex estandar: 0x10DE NVIDIA, 0x1002 AMD, 0x8086 Intel.
    pub vendor_id: u32,
    pub name: String,
    pub vram_total_mb: f64,
}

/// Enumera **todos** los adaptadores no-software, de cualquier vendor.
///
/// Es la generalizacion de `read_dxgi_vram_total_mb()`, que filtraba solo AMD
/// porque en su momento era el unico caso que le interesaba al snapshot
/// dinamico. El probe estatico (`capabilities`) necesita ver la lista completa
/// con nombre y vendor para decidir que backend de llama.cpp descargar.
///
/// Se usa `GetDesc1()` y no `GetDesc()` porque `DXGI_ADAPTER_DESC1` es la
/// unica que trae el campo `Flags`, sin el cual no hay forma de distinguir el
/// adaptador software.
pub fn read_dxgi_adapters() -> Vec<DxgiAdapter> {
    const BYTES_PER_MB: f64 = 1024.0 * 1024.0;
    let mut adapters = Vec::new();

    unsafe {
        let Ok(factory) = CreateDXGIFactory1::<IDXGIFactory1>() else {
            return adapters;
        };

        let mut index = 0;
        while let Ok(adapter1) = factory.EnumAdapters1(index) {
            index += 1;
            let Ok(desc) = adapter1.GetDesc1() else {
                continue;
            };
            if desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE != 0 {
                continue;
            }

            // `Description` es un array fijo de UTF-16 rellenado con NULs.
            let name_len = desc
                .Description
                .iter()
                .position(|&c| c == 0)
                .unwrap_or(desc.Description.len());
            let name = String::from_utf16_lossy(&desc.Description[..name_len]);

            adapters.push(DxgiAdapter {
                vendor_id: desc.VendorId,
                name: name.trim().to_string(),
                vram_total_mb: desc.DedicatedVideoMemory as f64 / BYTES_PER_MB,
            });
        }
    }

    adapters
}

/// VRAM total de la primera AMD encontrada. Envoltorio sobre
/// `read_dxgi_adapters()` para no cambiar el camino del snapshot dinamico
/// (`WindowsGpuMonitor`), que solo cae aca cuando NVML no inicializo.
pub fn read_dxgi_vram_total_mb() -> Option<f64> {
    read_dxgi_adapters()
        .into_iter()
        .find(|adapter| adapter.vendor_id == AMD_VENDOR_ID)
        .map(|adapter| adapter.vram_total_mb)
}

// ---------------------------------------------------------------------
// Temperatura via ADL (unico camino documentado por AMD; sin crate
// maduro disponible, shim casero via dlopen)
// ---------------------------------------------------------------------

#[repr(C)]
struct AdlAdapterInfo {
    i_size: c_int,
    i_adapter_index: c_int,
    str_udid: [i8; ADL_MAX_PATH],
    i_bus_number: c_int,
    i_device_number: c_int,
    i_function_number: c_int,
    i_vendor_id: c_int,
    str_adapter_name: [i8; ADL_MAX_PATH],
    str_display_name: [i8; ADL_MAX_PATH],
    i_present: c_int,
    i_exist: c_int,
    str_driver_path: [i8; ADL_MAX_PATH],
    str_driver_path_ext: [i8; ADL_MAX_PATH],
    str_pnp_string: [i8; ADL_MAX_PATH],
    i_os_display_index: c_int,
}

impl Default for AdlAdapterInfo {
    fn default() -> Self {
        unsafe { mem::zeroed() }
    }
}

#[repr(C)]
#[derive(Default)]
struct AdlTemperature {
    i_size: c_int,
    /// Milesimas de grado Celsius (ej. 45000 = 45.0 C).
    i_temperature: c_int,
}

type AdlMainMallocCallback = unsafe extern "system" fn(c_int) -> *mut c_void;
type AdlMainControlCreateFn =
    unsafe extern "system" fn(AdlMainMallocCallback, c_int) -> c_int;
type AdlMainControlDestroyFn = unsafe extern "system" fn() -> c_int;
type AdlAdapterNumberOfAdaptersGetFn = unsafe extern "system" fn(*mut c_int) -> c_int;
type AdlAdapterAdapterInfoGetFn = unsafe extern "system" fn(*mut AdlAdapterInfo, c_int) -> c_int;
type AdlOverdrive5TemperatureGetFn =
    unsafe extern "system" fn(c_int, c_int, *mut AdlTemperature) -> c_int;

/// Callback de asignacion de memoria que ADL exige pasarle a
/// `ADL_Main_Control_Create` -- firma exacta tomada de
/// `adl_sdk.h::ADL_MAIN_MALLOC_CALLBACK`.
unsafe extern "system" fn adl_alloc(size: c_int) -> *mut c_void {
    if size <= 0 {
        return std::ptr::null_mut();
    }
    match std::alloc::Layout::from_size_align(size as usize, 8) {
        Ok(layout) => unsafe { std::alloc::alloc(layout) as *mut c_void },
        Err(_) => std::ptr::null_mut(),
    }
}

pub struct AdlTemperatureReader {
    _library: Library,
    control_destroy: AdlMainControlDestroyFn,
    temperature_get: AdlOverdrive5TemperatureGetFn,
    adapter_index: c_int,
}

impl AdlTemperatureReader {
    pub fn new() -> Option<Self> {
        unsafe {
            let library = Library::new("atiadlxx.dll")
                .or_else(|_| Library::new("atiadlxy.dll"))
                .ok()?;

            let control_create: Symbol<AdlMainControlCreateFn> =
                library.get(b"ADL_Main_Control_Create\0").ok()?;
            let control_destroy: Symbol<AdlMainControlDestroyFn> =
                library.get(b"ADL_Main_Control_Destroy\0").ok()?;
            let num_adapters_get: Symbol<AdlAdapterNumberOfAdaptersGetFn> =
                library.get(b"ADL_Adapter_NumberOfAdapters_Get\0").ok()?;
            let adapter_info_get: Symbol<AdlAdapterAdapterInfoGetFn> =
                library.get(b"ADL_Adapter_AdapterInfo_Get\0").ok()?;
            let temperature_get: Symbol<AdlOverdrive5TemperatureGetFn> =
                library.get(b"ADL_Overdrive5_Temperature_Get\0").ok()?;

            if control_create(adl_alloc, 1) != ADL_OK {
                return None;
            }

            let mut num_adapters: c_int = 0;
            if num_adapters_get(&mut num_adapters) != ADL_OK || num_adapters <= 0 {
                control_destroy();
                return None;
            }

            let mut adapters: Vec<AdlAdapterInfo> = (0..num_adapters)
                .map(|_| AdlAdapterInfo {
                    i_size: mem::size_of::<AdlAdapterInfo>() as c_int,
                    ..Default::default()
                })
                .collect();
            if adapter_info_get(
                adapters.as_mut_ptr(),
                (num_adapters as usize * mem::size_of::<AdlAdapterInfo>()) as c_int,
            ) != ADL_OK
            {
                control_destroy();
                return None;
            }

            // ADL enumera varias entradas "logicas" por cada GPU fisica
            // (confirmado en vivo: 7 entradas para una sola RX 580); la
            // primera que sea AMD y este presente ya sirve para leer
            // temperatura.
            let Some(adapter_index) = adapters
                .iter()
                .find(|a| a.i_vendor_id == ADL_AMD_VENDOR_ID && a.i_present != 0)
                .map(|a| a.i_adapter_index)
            else {
                control_destroy();
                return None;
            };

            // Los `Symbol` toman prestado de `library`; se guardan como
            // funciones libres (Rust las trata como punteros planos una
            // vez copiadas) para no cargar con el lifetime del `Symbol`.
            let temperature_get = *temperature_get;
            let control_destroy = *control_destroy;

            Some(Self {
                _library: library,
                control_destroy,
                temperature_get,
                adapter_index,
            })
        }
    }

    pub fn read(&self) -> Option<f32> {
        unsafe {
            let mut temp = AdlTemperature {
                i_size: mem::size_of::<AdlTemperature>() as c_int,
                ..Default::default()
            };
            // Indice 0 del controlador termico -- suficiente para GPUs de
            // un solo chip como la RX 580 (no hay multi-GPU en un mismo
            // adaptador aqui).
            if (self.temperature_get)(self.adapter_index, 0, &mut temp) != ADL_OK {
                return None;
            }
            Some(temp.i_temperature as f32 / 1000.0)
        }
    }
}

impl Drop for AdlTemperatureReader {
    fn drop(&mut self) {
        unsafe {
            (self.control_destroy)();
        }
    }
}

// SAFETY: ver nota en `pdh::PdhQuery` -- un solo hilo accede a esto en la
// practica, pero `HardwareMonitor` necesita que sus campos sean `Send`.
unsafe impl Send for AdlTemperatureReader {}

// ---------------------------------------------------------------------
// Punto de entrada combinado
// ---------------------------------------------------------------------

pub struct WindowsGpuMonitor {
    pdh: Option<PdhCounters>,
    adl: Option<AdlTemperatureReader>,
    vram_total_mb: Option<f64>,
}

impl WindowsGpuMonitor {
    pub fn new() -> Self {
        Self {
            pdh: PdhCounters::new(),
            adl: AdlTemperatureReader::new(),
            // Propiedad estatica del hardware -- se lee una sola vez, no
            // en cada snapshot.
            vram_total_mb: read_dxgi_vram_total_mb(),
        }
    }

    pub fn snapshot(&self) -> (Option<f32>, Option<f32>, Option<f64>, Option<f64>) {
        let (usage, vram_used_mb) = self
            .pdh
            .as_ref()
            .map(PdhCounters::collect_and_read)
            .unwrap_or((None, None));
        let temp = self.adl.as_ref().and_then(AdlTemperatureReader::read);
        (usage, temp, vram_used_mb, self.vram_total_mb)
    }
}

impl Default for WindowsGpuMonitor {
    fn default() -> Self {
        Self::new()
    }
}
