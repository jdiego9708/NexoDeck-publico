//! Helpers compartidos de PDH (Performance Data Helper) y el parseo de los
//! nombres de instancia del contador `\GPU Engine(*)`.
//!
//! Existe como modulo aparte porque hay **dos** consumidores de la misma
//! lectura, con dos preguntas distintas: `gpu_windows.rs` quiere el uso
//! agregado de la GPU, y `processes::gpu_usage` quiere el uso por proceso.
//! Duplicar el patron de dos llamadas de PDH --que es `unsafe` y tiene un
//! sizing de buffer facil de equivocar-- es exactamente lo que diverge en la
//! primera modificacion.
//!
//! Lo que decide el numero que ve el usuario vive en las funciones **seguras
//! y puras** del final ([`parse_gpu_engine_instance`], [`gpu_percent_per_pid`]
//! y [`aggregate_gpu_percent`]): a que proceso pertenece cada instancia y
//! como se combinan sus motores. Es la parte testeable sin hardware, y la que
//! ya tuvo un bug mudo (ver [`parse_gpu_engine_instance`]).

use std::collections::HashMap;
use std::mem;

use windows::Win32::System::Performance::{
    PDH_FMT_COUNTERVALUE_ITEM_W, PDH_FMT_DOUBLE, PDH_HCOUNTER, PDH_HQUERY, PdhAddEnglishCounterW,
    PdhCloseQuery, PdhCollectQueryData, PdhGetFormattedCounterArrayW, PdhOpenQueryW,
};
use windows::core::PCWSTR;

/// Una query de PDH con su `PdhCloseQuery` atado al `Drop`.
pub(crate) struct PdhQuery {
    handle: PDH_HQUERY,
}

impl PdhQuery {
    pub(crate) fn open() -> Option<Self> {
        unsafe {
            let mut handle = PDH_HQUERY::default();
            if PdhOpenQueryW(PCWSTR::null(), 0, &mut handle) != 0 {
                return None;
            }
            Some(Self { handle })
        }
    }

    pub(crate) fn add_counter(&self, path: &str) -> Option<PDH_HCOUNTER> {
        unsafe {
            let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
            let mut counter = PDH_HCOUNTER::default();
            if PdhAddEnglishCounterW(self.handle, PCWSTR(wide.as_ptr()), 0, &mut counter) != 0 {
                return None;
            }
            Some(counter)
        }
    }

    /// Toma una muestra de todos los contadores de la query; `false` si PDH
    /// la rechazo.
    ///
    /// Los valores no sirven hasta la segunda llamada: los contadores de
    /// tasa (como `Utilization Percentage`) se calculan entre dos muestras,
    /// igual que el uso de CPU de sysinfo.
    pub(crate) fn collect(&self) -> bool {
        unsafe { PdhCollectQueryData(self.handle) == 0 }
    }
}

impl Drop for PdhQuery {
    fn drop(&mut self) {
        unsafe {
            let _ = PdhCloseQuery(self.handle);
        }
    }
}

// SAFETY: los handles PDH no son thread-affine. Cada dueno usa el suyo desde
// un solo hilo, pero Rust exige el marcador explicito para poder guardarlos
// en structs que tienen que ser `Send`.
unsafe impl Send for PdhQuery {}

/// Lee todas las instancias de un contador tipo array (los de ruta con
/// comodin `(*)`), como pares (nombre de instancia, valor).
///
/// Maneja el patron de dos llamadas de PDH: la primera con buffer nulo solo
/// para saber el tamano necesario.
pub(crate) unsafe fn read_counter_array(counter: PDH_HCOUNTER) -> Option<Vec<(String, f64)>> {
    unsafe {
        let mut buffer_size: u32 = 0;
        let mut item_count: u32 = 0;
        let _ = PdhGetFormattedCounterArrayW(
            counter,
            PDH_FMT_DOUBLE,
            &mut buffer_size,
            &mut item_count,
            None,
        );
        if buffer_size == 0 || item_count == 0 {
            return None;
        }

        let item_size = mem::size_of::<PDH_FMT_COUNTERVALUE_ITEM_W>();
        let capacity = (buffer_size as usize).div_ceil(item_size);
        let mut items: Vec<PDH_FMT_COUNTERVALUE_ITEM_W> = Vec::with_capacity(capacity);
        let status = PdhGetFormattedCounterArrayW(
            counter,
            PDH_FMT_DOUBLE,
            &mut buffer_size,
            &mut item_count,
            Some(items.as_mut_ptr()),
        );
        if status != 0 {
            return None;
        }
        items.set_len(item_count as usize);

        Some(
            items
                .iter()
                .filter(|item| !item.szName.is_null())
                .map(|item| {
                    (
                        item.szName.to_string().unwrap_or_default(),
                        item.FmtValue.Anonymous.doubleValue,
                    )
                })
                .collect(),
        )
    }
}

/// Ruta del contador de uso de GPU. Tiene una instancia por (proceso,
/// adaptador, motor); en el equipo principal son ~620 a la vez.
pub(crate) const GPU_ENGINE_USAGE: &str = "\\GPU Engine(*)\\Utilization Percentage";

/// Contadores de actividad de disco, uno por **letra de unidad** (no por
/// disco fisico): `LogicalDisk` y no `PhysicalDisk` a proposito, porque
/// matchea directo contra `DiskUsage.mount_point` ("C:", "D:"...) sin tener
/// que mapear disco fisico -> volumen.
pub(crate) const LOGICAL_DISK_READ_BYTES: &str = "\\LogicalDisk(*)\\Disk Read Bytes/sec";
pub(crate) const LOGICAL_DISK_WRITE_BYTES: &str = "\\LogicalDisk(*)\\Disk Write Bytes/sec";

/// A que letra de unidad pertenece una instancia de `LogicalDisk`, o `None`
/// para la instancia sintetica `_Total` (la suma de todas, que no es un
/// disco).
///
/// Windows publica el nombre de instancia ya como la letra ("C:"), asi que
/// no hace falta parsear nada -- solo descartar `_Total` y normalizar
/// mayusculas para que el merge contra `DiskUsage.mount_point` no dependa de
/// la capitalizacion.
pub(crate) fn parse_logical_disk_instance(name: &str) -> Option<String> {
    if name.eq_ignore_ascii_case("_Total") {
        return None;
    }
    Some(name.to_ascii_uppercase())
}

/// A que proceso y a que tipo de motor pertenece una instancia del contador.
///
/// Los nombres tienen la forma
/// `pid_10352_luid_0x00000000_0x00010117_phys_0_eng_0_engtype_3d`, y a veces
/// un `#1` al final (asi desambigua PDH dos instancias homonimas).
///
/// **El tipo de motor sale siempre en minusculas, a proposito.** Windows los
/// publica asi (`engtype_3d`), y comparar contra `"engtype_3D"` con D
/// mayuscula --como se hacia antes-- no matchea **ninguna** de las 620
/// instancias de esta maquina: el uso de GPU quedaba en `None` sin ningun
/// error. No se noto nunca porque este equipo tiene una NVIDIA y
/// `gpu_snapshot()` prefiere NVML; el sintoma solo aparece en una maquina
/// AMD/Intel, que es justo donde esta ruta es la unica que hay.
pub(crate) fn parse_gpu_engine_instance(name: &str) -> Option<(u32, String)> {
    let name = name.to_ascii_lowercase();
    let rest = name.strip_prefix("pid_")?;
    let (pid, rest) = rest.split_once('_')?;
    let pid: u32 = pid.parse().ok()?;

    let engtype = rest.rsplit_once("engtype_")?.1;
    // PDH agrega `#1`, `#2`... a las instancias con nombre repetido.
    let engtype = engtype.split('#').next().unwrap_or(engtype);
    if engtype.is_empty() {
        return None;
    }
    Some((pid, engtype.to_owned()))
}

/// Uso de GPU por proceso, en porcentaje 0-100.
///
/// Dos reglas, y ninguna es arbitraria:
///
/// - **Se SUMA dentro del mismo tipo de motor.** Un proceso tiene una
///   instancia por cada motor fisico (`eng_0`, `eng_1`, ...) y por cada
///   adaptador: todas son el mismo trabajo, partido.
/// - **Se toma el MAXIMO entre tipos de motor**, no la suma. Un proceso que
///   decodifica video y renderiza a la vez tiene `videodecode` y `3d`
///   ocupados en paralelo; sumarlos da cosas como 250%, ilegible al lado de
///   una metrica de GPU topeada en 100. El maximo responde "que tan ocupada
///   esta la GPU por culpa de esta app", que es la pregunta.
///
/// No se filtra por tipo de motor: un proceso que solo hace `videodecode`
/// esta usando la GPU igual.
pub(crate) fn gpu_percent_per_pid(instances: &[(String, f64)]) -> HashMap<u32, f32> {
    let mut per_engine: HashMap<(u32, String), f64> = HashMap::new();
    for (name, value) in instances {
        let Some((pid, engtype)) = parse_gpu_engine_instance(name) else {
            continue;
        };
        *per_engine.entry((pid, engtype)).or_insert(0.0) += value;
    }

    let mut per_pid: HashMap<u32, f32> = HashMap::new();
    for ((pid, _), value) in per_engine {
        let value = value.clamp(0.0, 100.0) as f32;
        per_pid
            .entry(pid)
            .and_modify(|current| *current = current.max(value))
            .or_insert(value);
    }
    per_pid
}

/// Uso agregado de la GPU, como lo muestra el Administrador de tareas: se
/// suma cada tipo de motor sobre todos los procesos y se toma el mayor.
///
/// Antes esto tomaba el maximo entre instancias 3D sueltas, con el comentario
/// "por si hay varios adaptadores". Pero las instancias son una por
/// **proceso**, no una por adaptador: el resultado era el uso del proceso que
/// mas consumia, no el de la GPU. Verificado en vivo con `Get-Counter`: el
/// maximo por instancia daba 3.5% mientras la suma del motor 3D --y el
/// Administrador de tareas-- marcaban 5.5%.
pub(crate) fn aggregate_gpu_percent(instances: &[(String, f64)]) -> Option<f32> {
    let mut per_engine: HashMap<String, f64> = HashMap::new();
    for (name, value) in instances {
        let Some((_, engtype)) = parse_gpu_engine_instance(name) else {
            continue;
        };
        *per_engine.entry(engtype).or_insert(0.0) += value;
    }

    per_engine
        .into_values()
        .map(|value| value.clamp(0.0, 100.0) as f32)
        .fold(None, |acc: Option<f32>, v| Some(acc.map_or(v, |a| a.max(v))))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Nombre real, copiado de una lectura de esta maquina.
    const REAL: &str = "pid_10352_luid_0x00000000_0x00010117_phys_0_eng_0_engtype_3d";

    fn instance(pid: u32, engtype: &str, index: u32) -> String {
        format!("pid_{pid}_luid_0x00000000_0x00010117_phys_0_eng_{index}_engtype_{engtype}")
    }

    #[test]
    fn parsea_un_nombre_real() {
        assert_eq!(
            parse_gpu_engine_instance(REAL),
            Some((10352, "3d".to_owned()))
        );
    }

    /// El bug que motivo este modulo: comparar contra "3D" en mayuscula no
    /// matcheaba ninguna instancia real.
    #[test]
    fn el_tipo_de_motor_sale_siempre_en_minusculas() {
        let (_, engtype) =
            parse_gpu_engine_instance("PID_44_luid_0x0_0x0_phys_0_eng_0_ENGTYPE_3D")
                .expect("deberia parsear");
        assert_eq!(engtype, "3d");
    }

    #[test]
    fn tolera_el_sufijo_de_desambiguacion_de_pdh() {
        assert_eq!(
            parse_gpu_engine_instance(&format!("{REAL}#2")),
            Some((10352, "3d".to_owned()))
        );
    }

    #[test]
    fn descarta_lo_que_no_es_una_instancia_de_gpu_engine() {
        assert_eq!(parse_gpu_engine_instance(""), None);
        assert_eq!(parse_gpu_engine_instance("_Total"), None);
        assert_eq!(parse_gpu_engine_instance("pid_abc_engtype_3d"), None);
        // Sin tipo de motor no se puede decidir nada.
        assert_eq!(parse_gpu_engine_instance("pid_10_luid_0_phys_0"), None);
    }

    #[test]
    fn suma_los_motores_del_mismo_tipo_y_toma_el_maximo_entre_tipos() {
        let instances = vec![
            // El mismo proceso repartido en dos motores 3D fisicos: 4 + 6.
            (instance(100, "3d", 0), 4.0),
            (instance(100, "3d", 1), 6.0),
            // Y ademas decodificando video al mismo tiempo.
            (instance(100, "videodecode", 0), 30.0),
        ];

        let per_pid = gpu_percent_per_pid(&instances);
        // 10 (3d) contra 30 (videodecode): gana el mayor, NO se suman a 40.
        assert_eq!(per_pid.get(&100).copied(), Some(30.0));
    }

    #[test]
    fn un_proceso_sin_instancias_no_aparece() {
        let per_pid = gpu_percent_per_pid(&[(instance(7, "3d", 0), 1.5)]);
        assert_eq!(per_pid.len(), 1);
        assert!(per_pid.get(&999).is_none());
    }

    #[test]
    fn el_agregado_suma_por_motor_y_no_devuelve_el_pico_de_un_proceso() {
        let instances = vec![
            (instance(1, "3d", 0), 3.5),
            (instance(2, "3d", 0), 1.8),
            (instance(3, "3d", 0), 0.2),
            (instance(1, "copy", 0), 0.1),
        ];
        // 3.5 + 1.8 + 0.2 = 5.5 del motor 3D, contra 0.1 de copy.
        let aggregate = aggregate_gpu_percent(&instances).expect("deberia haber valor");
        assert!(
            (aggregate - 5.5).abs() < 0.001,
            "esperaba 5.5, dio {aggregate}"
        );
    }

    #[test]
    fn sin_instancias_no_hay_agregado() {
        assert_eq!(aggregate_gpu_percent(&[]), None);
    }

    #[test]
    fn la_instancia_de_disco_logico_es_la_letra_en_mayusculas() {
        assert_eq!(
            parse_logical_disk_instance("C:"),
            Some("C:".to_owned())
        );
        assert_eq!(
            parse_logical_disk_instance("d:"),
            Some("D:".to_owned())
        );
    }

    #[test]
    fn el_total_sintetico_de_disco_se_descarta() {
        assert_eq!(parse_logical_disk_instance("_Total"), None);
        assert_eq!(parse_logical_disk_instance("_total"), None);
    }
}
