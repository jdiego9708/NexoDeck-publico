//! Temperatura del CPU, que es el unico dato del snapshot que el SO **no**
//! regala en Windows.
//!
//! Hay dos fuentes, en este orden:
//!
//! 1. Los sensores que expone el SO via `sysinfo` (`Components`). Es la ruta
//!    normal en Linux/Android: `k10temp` (AMD) y `coretemp` (Intel) publican
//!    ahi el Tctl/Tdie y la temperatura del paquete.
//! 2. Solo en Windows, el **sidecar de sensores propio**
//!    (`sensors/NexoDeckSensors`), un servicio de Windows que arranca con el
//!    sistema; aca solo se abre su pipe -- ver `cpu_temp/windows_provider.rs`.
//!
//! **Por que hace falta una segunda fuente:** en Windows la temperatura del
//! CPU no se puede leer desde espacio de usuario. Los Ryzen la publican en el
//! registro SMN `0x00059800`, alcanzable solo por el espacio de configuracion
//! PCI, que es exclusivo de kernel-mode; los Intel, en un MSR, igual de
//! inalcanzable. La via generica del SO (`MSAcpi_ThermalZoneTemperature` y el
//! contador PDH `\Thermal Zone Information`) depende de que la placa
//! implemente zonas termicas ACPI, y en un desktop tipico no existe --
//! re-verificado en el equipo principal (Ryzen 7 5700X): la clase WMI responde
//! "Incompatible", el objeto de PDH no tiene ni una instancia, y
//! `Win32_TemperatureProbe` tampoco. La unica salida es un driver de kernel, y
//! por eso el sidecar existe.
//!
//! **Esto antes dependia de que el usuario instalara LibreHardwareMonitor** y
//! lo dejara abierto con su servidor web encendido. Ya no: el motor viaja
//! dentro de NexoDeck.
//!
//! Por eso esta fuente **degrada a `None` en silencio** y la UI simplemente
//! no dibuja el badge de °C, igual que ya hacia con una maquina sin sensores.

use sysinfo::Components;

/// Etiquetas de sensor que seguro NO son el CPU. Se descartan antes del
/// ultimo recurso (quedarse con el primer sensor que haya): sin esto, en una
/// maquina que solo expone el sensor del NVMe, la metrica "CPU" mostraria la
/// temperatura del disco sin ninguna senal de que no es lo que dice.
const NOT_CPU_HINTS: [&str; 7] = ["nvme", "gpu", "wifi", "battery", "bat", "drive", "ambient"];

/// Prioridad de una etiqueta de sensor termico como "temperatura del CPU".
/// Numero mas bajo = mejor. `None` = descartada.
///
/// Es una funcion pura y separada porque es la unica parte de este modulo
/// que se puede testear sin hardware: que sensor se elige entre varios es
/// justamente lo que decide si el numero que ve el usuario es el correcto.
pub(crate) fn label_priority(label: &str) -> Option<u8> {
    let label = label.to_ascii_lowercase();

    // El descarte se evalua ANTES del ranking, pero solo si la etiqueta no
    // nombra al CPU de forma inequivoca: "GPU Core" contiene "core" y sin
    // este orden entraria como sensor de CPU de baja prioridad.
    let names_the_cpu = ["tctl", "tdie", "k10temp", "coretemp", "cpu"]
        .iter()
        .any(|hint| label.contains(hint));
    if !names_the_cpu && NOT_CPU_HINTS.iter().any(|hint| label.contains(hint)) {
        return None;
    }

    // Un sensor que nombra un die concreto (`CCD1 (Tdie)`) mide UNA porcion
    // del procesador, no el paquete. Se rankea aparte y por debajo del
    // control global: un Ryzen de dos CCD expone `CCD1` y `CCD2`, y sin esta
    // distincion las dos --y tambien el Tctl del paquete-- empataban en la
    // misma prioridad, con lo que cual ganaba lo decidia el orden en que el
    // proveedor los enumerara. Encontrado en el equipo principal, que expone
    // `Core (Tctl/Tdie)` a 53 C y `CCD1 (Tdie)` a 58 C al mismo tiempo.
    let names_one_die = label.contains("ccd") || label.contains("ccx");

    // Tctl/Tdie (AMD) y "package" (Intel) son las lecturas que reportan las
    // herramientas de monitoreo como "temperatura del CPU".
    if (label.contains("tctl") || label.contains("tdie")) && !names_one_die {
        return Some(0);
    }
    if label.contains("package") {
        return Some(1);
    }
    if label.contains("tctl") || label.contains("tdie") {
        return Some(2);
    }
    if label.contains("k10temp") || label.contains("coretemp") {
        return Some(3);
    }
    if label.contains("cpu") {
        return Some(4);
    }
    if label.contains("core") {
        return Some(5);
    }
    // Ultimo recurso: un sensor generico (`acpitz`, `Thermal zone 0`). Es lo
    // que hacia la version anterior con TODOS los sensores, incluido el del
    // disco.
    Some(9)
}

/// El mejor sensor de los que expone el SO, o `None` si no hay ninguno
/// utilizable.
pub(crate) fn from_components(components: &Components) -> Option<f32> {
    components
        .list()
        .iter()
        .filter_map(|component| {
            let priority = label_priority(component.label())?;
            let temperature = component.temperature()?;
            Some((priority, temperature))
        })
        // `total_cmp` y no `partial_cmp`: las temperaturas son f32 y un NaN
        // haria panickear a un comparador que devuelva Ordering a la fuerza.
        .min_by(|a, b| a.0.cmp(&b.0).then(a.1.total_cmp(&b.1)))
        .map(|(_, temperature)| temperature)
}

#[cfg(target_os = "windows")]
mod windows_provider;

/// Lector con estado. Fuera de Windows no guarda nada (los sensores del SO
/// se leen del `Components` que ya refresca `HardwareMonitor`); en Windows
/// ademas mantiene vivo el sondeo del proveedor WMI.
pub(crate) struct CpuTempReader {
    #[cfg(target_os = "windows")]
    provider: windows_provider::SensorProvider,
}

impl CpuTempReader {
    pub(crate) fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            provider: windows_provider::SensorProvider::start(),
        }
    }

    /// `components` tiene que venir ya refrescado por quien llama.
    pub(crate) fn read(&self, components: &Components) -> Option<f32> {
        if let Some(temperature) = from_components(components) {
            return Some(temperature);
        }
        #[cfg(target_os = "windows")]
        {
            return self.provider.last_value();
        }
        #[cfg(not(target_os = "windows"))]
        {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tctl_le_gana_a_cualquier_otro_sensor() {
        assert!(label_priority("k10temp Tctl") < label_priority("coretemp Core 0"));
        // El control del paquete le gana al die suelto, y los dos le ganan a
        // un sensor generico. Son las dos etiquetas reales del equipo
        // principal (Ryzen 7 5700X).
        assert!(label_priority("Core (Tctl/Tdie)") < label_priority("CCD1 (Tdie)"));
        assert!(label_priority("CCD1 (Tdie)") < label_priority("acpitz"));
        assert!(label_priority("Package id 0") < label_priority("acpitz temp1"));
    }

    #[test]
    fn descarta_los_sensores_que_seguro_no_son_el_cpu() {
        assert_eq!(label_priority("nvme Composite"), None);
        assert_eq!(label_priority("Battery"), None);
        assert_eq!(label_priority("amdgpu edge"), None);
    }

    /// La red de seguridad: un sensor generico se acepta, porque es lo que
    /// hay en las maquinas que no etiquetan nada.
    #[test]
    fn un_sensor_generico_sigue_sirviendo() {
        assert_eq!(label_priority("acpitz"), Some(9));
        assert_eq!(label_priority(""), Some(9));
    }

    /// El caso que obliga a evaluar el descarte antes del ranking generico:
    /// "GPU Core" contiene "core" y se colaria como sensor de CPU.
    #[test]
    fn el_descarte_le_gana_al_match_generico_de_core() {
        assert_eq!(label_priority("GPU Core"), None);
        // Pero una etiqueta que nombra al CPU sobrevive aunque comparta
        // texto con la lista de descarte.
        assert_eq!(label_priority("CPU on drive board"), Some(4));
    }
}
