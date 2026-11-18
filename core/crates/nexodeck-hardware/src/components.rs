//! Nombres y caracteristicas de las piezas del equipo: que CPU, que memoria,
//! que GPU y por que adaptador sale la red.
//!
//! **Se lee una sola vez, no en cada snapshot.** Nada de esto cambia mientras
//! la app corre --el modelo de la RAM no se mueve-- y varias de las consultas
//! son caras: WMI para los modulos de memoria, NVML para la GPU. Meterlas en
//! el tick de 1 s seria pagar todos los segundos por un dato que no cambia, y
//! ademas mandaria los mismos strings por el cable una y otra vez.
//!
//! Todo es `Option`: en una maquina que no expone un dato, la UI simplemente
//! no dibuja esa linea. Es el mismo criterio que la temperatura del CPU.

use sysinfo::{Networks, System};

/// Lo que se sabe de las piezas del equipo.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct HostComponents {
    /// Modelo del procesador, tal como lo reporta el SO
    /// (`AMD Ryzen 7 5700X 8-Core Processor`).
    pub cpu_name: Option<String>,
    /// Marca del primer modulo de memoria. Va **separada** del numero de
    /// parte porque la UI las prioriza distinto: "Corsair" identifica la
    /// pieza en una palabra, mientras que `CM4X16GD3600C18K2D` se come la
    /// linea entera sin decir mucho mas.
    ///
    /// Los equipos suelen tener todos los modulos iguales, asi que se informa
    /// el primero y no una lista de cuatro veces lo mismo.
    pub ram_vendor: Option<String>,
    pub ram_part_number: Option<String>,
    /// Velocidad configurada de la memoria en MT/s (lo que se anuncia como
    /// "3200 MHz"). Es la **configurada**, no la maxima del modulo: es la que
    /// esta corriendo de verdad.
    pub ram_speed_mts: Option<u32>,
    /// Velocidad que declara el modulo en su SPD (la de la etiqueta). Si no
    /// coincide con `ram_speed_mts`, la memoria **no esta corriendo a lo que
    /// promete**: tipicamente, el perfil XMP/DOCP no esta activo en la BIOS.
    pub ram_speed_rated_mts: Option<u32>,
    /// Cuantos modulos hay instalados.
    pub ram_module_count: Option<u32>,
    pub gpu_name: Option<String>,
    pub gpu_vram_total_mb: Option<f64>,
    /// Interfaz por la que sale el trafico (`Ethernet`, `Wi-Fi`).
    pub network_adapter: Option<String>,
}

/// Lee todo lo que se pueda. Cada fuente falla por su cuenta sin arrastrar al
/// resto.
pub fn probe_host_components() -> HostComponents {
    let mut system = System::new();
    system.refresh_cpu_all();

    HostComponents {
        cpu_name: system
            .cpus()
            .first()
            .map(|cpu| cpu.brand().trim().to_owned())
            .filter(|brand| !brand.is_empty()),
        ram_vendor: memory_field(MemoryField::Vendor),
        ram_part_number: memory_field(MemoryField::PartNumber),
        ram_speed_mts: memory_speed_mts(),
        ram_speed_rated_mts: memory_rated_speed_mts(),
        ram_module_count: memory_module_count(),
        gpu_name: gpu_name(),
        gpu_vram_total_mb: gpu_vram_total_mb(),
        network_adapter: busiest_adapter(),
    }
}

/// La interfaz por la que de verdad sale el trafico: la que mas bytes lleva
/// recibidos desde que arranco el equipo.
///
/// No se puede preguntar "cual es la interfaz de internet" de forma portable,
/// y elegir la primera de la lista suele dar un adaptador virtual (Hyper-V,
/// WSL, VPN) o uno apagado. El volumen acumulado, en cambio, distingue sin
/// ambiguedad la que se usa de las que estan ahi sin hacer nada.
fn busiest_adapter() -> Option<String> {
    let networks = Networks::new_with_refreshed_list();
    networks
        .iter()
        .filter(|(_, data)| data.total_received() > 0)
        .max_by_key(|(_, data)| data.total_received())
        .map(|(name, _)| name.clone())
}

// ---------------------------------------------------------------------
// GPU: NVML si hay NVIDIA, y si no lo que ya sabe `capabilities`
// ---------------------------------------------------------------------

fn gpu_name() -> Option<String> {
    if let Some(name) = nvml_device(|device| device.name().ok()) {
        return Some(name);
    }
    first_dxgi_adapter().map(|adapter| adapter.name)
}

fn gpu_vram_total_mb() -> Option<f64> {
    if let Some(total) = nvml_device(|device| device.memory_info().ok().map(|m| m.total)) {
        return Some(total as f64 / (1024.0 * 1024.0));
    }
    first_dxgi_adapter().map(|adapter| adapter.vram_total_mb)
}

/// El primer adaptador que enumera DXGI, para las maquinas sin NVIDIA.
///
/// Se va directo a DXGI en vez de a `probe_host_capabilities`: ese probe pide
/// una ruta de almacenamiento que aca no viene al caso, e inicializa NVML y
/// crea una instancia de Vulkan --cientos de milisegundos-- para responder
/// algo que DXGI ya sabe.
#[cfg(target_os = "windows")]
fn first_dxgi_adapter() -> Option<crate::gpu_windows::DxgiAdapter> {
    crate::gpu_windows::read_dxgi_adapters().into_iter().next()
}

#[cfg(not(target_os = "windows"))]
fn first_dxgi_adapter() -> Option<DxgiAdapterStub> {
    None
}

/// Fuera de Windows no hay DXGI. El stub existe solo para que las dos ramas
/// de `gpu_name`/`gpu_vram_total_mb` tengan la misma forma.
#[cfg(not(target_os = "windows"))]
struct DxgiAdapterStub {
    name: String,
    vram_total_mb: f64,
}

/// Abre NVML, toma el dispositivo 0 y aplica `read`. Devuelve `None` ante
/// cualquier fallo: sin NVIDIA, sin driver, o si esa consulta puntual no esta
/// soportada por la tarjeta.
fn nvml_device<T>(
    read: impl FnOnce(&nvml_wrapper::Device<'_>) -> Option<T>,
) -> Option<T> {
    let nvml = nvml_wrapper::Nvml::init().ok()?;
    let device = nvml.device_by_index(0).ok()?;
    read(&device)
}

// ---------------------------------------------------------------------
// Memoria: WMI en Windows, nada en el resto
// ---------------------------------------------------------------------

#[cfg(target_os = "windows")]
mod memory_windows {
    use std::collections::HashMap;

    use wmi::{Variant, WMIConnection};

    /// Una consulta por llamada y no una conexion guardada: esto corre una
    /// sola vez por sesion (ver el encabezado del modulo), asi que no vale la
    /// pena mantener viva una `WMIConnection` --que ademas es `!Send` y
    /// obligaria a un hilo propio, como en `cpu_temp`--.
    fn query(fields: &str) -> Option<Vec<HashMap<String, Variant>>> {
        let connection = WMIConnection::new().ok()?;
        connection
            .raw_query(format!("SELECT {fields} FROM Win32_PhysicalMemory"))
            .ok()
    }

    /// Un campo del primer modulo, ya limpio.
    ///
    /// Windows rellena estos campos con espacios y, cuando el modulo no los
    /// declara, con literales como "Unknown" o el clasico
    /// "Manufacturer00000000" del SPD sin programar. Devolver eso seria peor
    /// que no mostrar nada.
    pub(super) fn field(name: &str) -> Option<String> {
        let rows = query(name)?;
        clean(rows.first()?.get(name))
    }

    pub(super) fn rated_speed_mts() -> Option<u32> {
        let rows = query("Speed")?;
        number(rows.first()?.get("Speed"))
    }

    pub(super) fn speed_mts() -> Option<u32> {
        let rows = query("ConfiguredClockSpeed, Speed")?;
        let row = rows.first()?;
        // `ConfiguredClockSpeed` es a la que esta corriendo; `Speed`, la que
        // el modulo declara. Se prefiere la primera: un kit de 3600 corriendo
        // a 2133 porque no se activo el perfil XMP tiene que decir 2133, que
        // es justo el caso en el que uno mira este dato.
        number(row.get("ConfiguredClockSpeed")).or_else(|| number(row.get("Speed")))
    }

    pub(super) fn module_count() -> Option<u32> {
        Some(query("Tag")?.len() as u32)
    }

    fn clean(value: Option<&Variant>) -> Option<String> {
        let Some(Variant::String(text)) = value else {
            return None;
        };
        let text = text.trim();
        if text.is_empty() || text.eq_ignore_ascii_case("unknown") {
            return None;
        }
        // SPD sin programar: "Manufacturer00000000", "PartNum0000000000".
        if text.trim_end_matches('0').ends_with("Manufacturer")
            || text.trim_end_matches('0').ends_with("PartNum")
        {
            return None;
        }
        Some(text.to_owned())
    }

    fn number(value: Option<&Variant>) -> Option<u32> {
        match value? {
            Variant::UI4(v) => Some(*v),
            Variant::UI2(v) => Some(u32::from(*v)),
            Variant::I4(v) => u32::try_from(*v).ok(),
            Variant::I2(v) => u32::try_from(*v).ok(),
            _ => None,
        }
        .filter(|speed| *speed > 0)
    }
}

/// Que campo del modulo de memoria se quiere.
enum MemoryField {
    Vendor,
    PartNumber,
}

#[cfg(target_os = "windows")]
fn memory_field(field: MemoryField) -> Option<String> {
    memory_windows::field(match field {
        MemoryField::Vendor => "Manufacturer",
        MemoryField::PartNumber => "PartNumber",
    })
}

#[cfg(target_os = "windows")]
fn memory_speed_mts() -> Option<u32> {
    memory_windows::speed_mts()
}

#[cfg(target_os = "windows")]
fn memory_rated_speed_mts() -> Option<u32> {
    memory_windows::rated_speed_mts()
}

#[cfg(target_os = "windows")]
fn memory_module_count() -> Option<u32> {
    memory_windows::module_count()
}

/// Fuera de Windows no hay una via portable: en Linux el SPD vive en
/// `/sys/bus/i2c` (root) o en `dmidecode` (root tambien), y en Android no
/// existe el concepto.
#[cfg(not(target_os = "windows"))]
fn memory_field(_field: MemoryField) -> Option<String> {
    None
}

#[cfg(not(target_os = "windows"))]
fn memory_speed_mts() -> Option<u32> {
    None
}

#[cfg(not(target_os = "windows"))]
fn memory_rated_speed_mts() -> Option<u32> {
    None
}

#[cfg(not(target_os = "windows"))]
fn memory_module_count() -> Option<u32> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    /// No se puede afirmar que piezas tiene la maquina, pero si que lo que
    /// se devuelve es presentable: sin espacios de sobra y sin cadenas vacias
    /// disfrazadas de dato.
    #[test]
    fn lo_que_se_devuelve_es_presentable() {
        let components = probe_host_components();

        for text in [
            components.cpu_name.as_ref(),
            components.ram_vendor.as_ref(),
            components.ram_part_number.as_ref(),
            components.gpu_name.as_ref(),
            components.network_adapter.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            assert!(!text.is_empty(), "cadena vacia en vez de None");
            assert_eq!(text.trim(), text, "quedaron espacios sin recortar: {text:?}");
        }

        if let Some(speed) = components.ram_speed_mts {
            assert!(speed > 0, "velocidad de RAM en cero");
        }
    }

    /// El CPU es el unico que tiene que estar siempre: lo reporta el SO sin
    /// permisos ni hardware especial.
    #[test]
    fn el_nombre_del_cpu_siempre_esta() {
        assert!(probe_host_components().cpu_name.is_some());
    }
}
