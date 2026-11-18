//! Inventario de volumenes de almacenamiento, uno por disco montado.
//!
//! Existe aparte del agregado `disk_used_mb`/`disk_total_mb` de
//! [`crate::HardwareSnapshot`] porque son dos preguntas distintas: el
//! agregado alimenta la barra unica de la metrica "Disco", y esta lista es
//! la que la UI dibuja disco por disco. El agregado se calcula **sobre esta
//! misma lista** para que los dos numeros no puedan discrepar.

use sysinfo::{DiskKind, Disks};

const BYTES_PER_MB: f64 = 1024.0 * 1024.0;

/// Tipo de medio, tal como lo reporta el SO. `Unknown` no es un error: hay
/// controladoras (RAID, maquinas virtuales, LVM) que no contestan la
/// consulta de penalizacion de busqueda.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiskMediaKind {
    Ssd,
    Hdd,
    Unknown,
}

/// Un volumen montado con su capacidad y su ocupacion.
#[derive(Debug, Clone, PartialEq)]
pub struct DiskUsage {
    /// Lo que identifica al volumen para el usuario: `C:` en Windows, el
    /// punto de montaje (`/`, `/home`) en Unix. Sin la barra final, que en
    /// Windows solo agrega ruido.
    pub mount_point: String,
    /// Etiqueta del volumen. Puede venir vacia (un `C:` recien instalado no
    /// tiene ninguna), y en ese caso la UI cae al punto de montaje.
    pub label: String,
    pub kind: DiskMediaKind,
    pub used_mb: f64,
    pub total_mb: f64,
    /// Bytes/segundo de lectura y escritura, para la senal de vida de la UI.
    /// `None` fuera de Windows (o si PDH fallo) y para un volumen sin letra
    /// de unidad -- ver `HardwareMonitor::snapshot` en `lib.rs`, que es quien
    /// mergea esto sobre la lista despues de `collect()`. No es un dato que
    /// esta funcion pueda calcular: no sabe nada de PDH.
    pub read_bytes_per_sec: Option<f64>,
    pub write_bytes_per_sec: Option<f64>,
    /// Temperatura del disco **fisico** que respalda este volumen, en grados
    /// Celsius. Dos particiones del mismo disco traen el mismo numero: es un
    /// solo sensor. `None` fuera de Windows, y tambien cuando el disco no
    /// publica ningun atributo de temperatura (algunos USB y varios RAID).
    ///
    /// Igual que las tasas de actividad, esta funcion no puede calcularla: se
    /// mergea sobre la lista en `HardwareMonitor::snapshot`, porque la fuente
    /// es un hilo de sondeo con su propia cadencia (ver `disk_temp`).
    pub temp_c: Option<f32>,
    /// Hace cuantos segundos se tomo [`Self::temp_c`].
    ///
    /// **No es contabilidad.** Un disco dormido no contesta la consulta de
    /// temperatura y conserva su ultima lectura (ver `disk_temp`), asi que sin
    /// esto la UI no puede distinguir un dato de hace dos segundos de uno de
    /// hace horas. Con esto lo puede atenuar y decirlo.
    pub temp_age_secs: Option<u64>,
}

/// Arma la lista a partir de los discos ya refrescados por `sysinfo`,
/// descartando lo que no es un disco de verdad (ver `is_physical_volume`) y
/// lo que reporta capacidad cero (unidades opticas vacias, montajes
/// fantasma).
///
/// Sale ordenada por punto de montaje: la UI la dibuja en ese orden y una
/// lista que se reordena sola cada segundo es ilegible -- `sysinfo` no
/// garantiza un orden estable entre refrescos.
pub fn collect(disks: &Disks) -> Vec<DiskUsage> {
    let mut list: Vec<DiskUsage> = disks
        .list()
        .iter()
        .filter(|disk| disk.total_space() > 0)
        .filter(|disk| is_physical_volume(&disk.mount_point().to_string_lossy()))
        .map(|disk| {
            let total = disk.total_space();
            let used = total.saturating_sub(disk.available_space());
            DiskUsage {
                mount_point: normalize_mount_point(&disk.mount_point().to_string_lossy()),
                label: disk.name().to_string_lossy().trim().to_owned(),
                kind: match disk.kind() {
                    DiskKind::SSD => DiskMediaKind::Ssd,
                    DiskKind::HDD => DiskMediaKind::Hdd,
                    _ => DiskMediaKind::Unknown,
                },
                used_mb: used as f64 / BYTES_PER_MB,
                total_mb: total as f64 / BYTES_PER_MB,
                read_bytes_per_sec: None,
                write_bytes_per_sec: None,
                temp_c: None,
                temp_age_secs: None,
            }
        })
        .collect();

    // El mismo volumen puede aparecer dos veces (bind mounts en Linux, un
    // volumen montado ademas en una carpeta en Windows). Se queda la
    // primera aparicion de cada punto de montaje ya normalizado.
    list.sort_by(|a, b| a.mount_point.cmp(&b.mount_point));
    list.dedup_by(|a, b| a.mount_point == b.mount_point);
    list
}

/// Suma de la lista. Se calcula aca y no sobre `Disks` directamente para que
/// el total que muestra la metrica agregada sea exactamente la suma de las
/// filas que se listan -- si no, el usuario ve un total que no le cierra con
/// los discos que tiene enfrente.
pub fn totals(list: &[DiskUsage]) -> (f64, f64) {
    list.iter().fold((0.0, 0.0), |(used, total), disk| {
        (used + disk.used_mb, total + disk.total_mb)
    })
}

/// En Windows recorta la barra final; en Unix deja la ruta tal cual.
fn normalize_mount_point(mount_point: &str) -> String {
    let trimmed = mount_point.trim_end_matches(['\\', '/']);
    if trimmed.is_empty() {
        mount_point.to_owned()
    } else {
        trimmed.to_owned()
    }
}

/// En Windows, si el punto de montaje corresponde a un volumen respaldado
/// por un disco fisico.
///
/// **No alcanza con `GetDriveType`**: Google Drive para escritorio monta sus
/// unidades como `DRIVE_FIXED` con sistema de archivos FAT32, asi que se
/// hace pasar por un disco local y su cuota entraba al total del deck
/// (verificado en vivo: dos unidades de nube inflaban el agregado en cientos
/// de GB). Tampoco alcanza con el tipo de medio de `sysinfo`, que devuelve
/// `Unknown` tanto para esas unidades como para RAIDs y discos virtuales
/// legitimos.
///
/// Lo que si los separa es a donde apunta el enlace del espacio de nombres
/// NT: el administrador de volumenes crea `\Device\HarddiskVolumeN` para
/// toda particion de un disco real (incluidos los USB), mientras que un
/// montaje de nube queda en `\Device\Volume{GUID}`, uno de red en
/// `\Device\LanmanRedirector\...` y una unidad optica en `\Device\CdRom0`.
#[cfg(target_os = "windows")]
fn is_physical_volume(mount_point: &str) -> bool {
    use windows::Win32::Storage::FileSystem::QueryDosDeviceW;
    use windows::core::PCWSTR;

    // Solo se sabe consultar unidades con letra. Un volumen montado en una
    // carpeta no tiene enlace en el espacio de nombres DOS: se acepta en vez
    // de descartarlo, porque perder un disco real es peor que colar uno de
    // nube.
    let Some(drive) = dos_drive_name(mount_point) else {
        return true;
    };

    let wide: Vec<u16> = drive.encode_utf16().chain(std::iter::once(0)).collect();
    let mut target = [0u16; 512];
    // SAFETY: `wide` termina en NUL y `target` se pasa con su largo real.
    let len = unsafe { QueryDosDeviceW(PCWSTR(wide.as_ptr()), Some(&mut target)) };
    if len == 0 {
        return false;
    }

    // El buffer trae una lista de strings terminados en NUL; alcanza con el
    // primero, que es el destino actual del enlace.
    let target = String::from_utf16_lossy(&target[..len as usize]);
    let first = target.split('\0').next().unwrap_or_default();
    first.starts_with(r"\Device\Harddisk")
}

/// Devuelve `None` si el punto de montaje no es una unidad con letra.
#[cfg(target_os = "windows")]
fn dos_drive_name(mount_point: &str) -> Option<String> {
    let mut chars = mount_point.chars();
    let letter = chars.next()?;
    if !letter.is_ascii_alphabetic() || chars.next()? != ':' {
        return None;
    }
    Some(format!("{}:", letter.to_ascii_uppercase()))
}

/// Fuera de Windows no hace falta filtrar: `sysinfo` ya deja afuera los
/// sistemas de archivos pseudo (`tmpfs`, `proc`, `overlay`...) al armar la
/// lista, y no existe el caso de la unidad de nube disfrazada de disco local
/// que motiva el filtro de Windows.
#[cfg(not(target_os = "windows"))]
fn is_physical_volume(_mount_point: &str) -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn disk(mount_point: &str, used_mb: f64, total_mb: f64) -> DiskUsage {
        DiskUsage {
            mount_point: mount_point.to_owned(),
            label: String::new(),
            kind: DiskMediaKind::Unknown,
            used_mb,
            total_mb,
            read_bytes_per_sec: None,
            write_bytes_per_sec: None,
            temp_c: None,
            temp_age_secs: None,
        }
    }

    #[test]
    fn totals_suma_todos_los_discos() {
        let (used, total) = totals(&[disk("C:", 100.0, 500.0), disk("D:", 200.0, 1000.0)]);
        assert_eq!(used, 300.0);
        assert_eq!(total, 1500.0);
    }

    #[test]
    fn totals_de_una_lista_vacia_es_cero() {
        assert_eq!(totals(&[]), (0.0, 0.0));
    }

    #[test]
    fn normaliza_la_barra_final_solo_cuando_sobra() {
        assert_eq!(normalize_mount_point("C:\\"), "C:");
        assert_eq!(normalize_mount_point("/home"), "/home");
        // La raiz de Unix es la unica barra que NO se puede recortar: sin
        // este caso especial quedaria en la cadena vacia.
        assert_eq!(normalize_mount_point("/"), "/");
    }

    /// La lista real de la maquina no se puede afirmar (cambia por equipo),
    /// pero si que sea coherente: nada con capacidad cero, sin puntos de
    /// montaje repetidos, y el usado nunca por encima del total.
    #[test]
    fn la_lista_real_es_coherente() {
        let disks = Disks::new_with_refreshed_list();
        let list = collect(&disks);

        let mut seen = std::collections::HashSet::new();
        for entry in &list {
            assert!(entry.total_mb > 0.0, "disco sin capacidad: {entry:?}");
            assert!(entry.used_mb <= entry.total_mb, "usado > total: {entry:?}");
            assert!(
                seen.insert(entry.mount_point.clone()),
                "punto de montaje repetido: {}",
                entry.mount_point
            );
        }
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn solo_reconoce_unidades_con_letra() {
        assert_eq!(dos_drive_name("C:\\"), Some("C:".to_owned()));
        assert_eq!(dos_drive_name("g:/"), Some("G:".to_owned()));
        assert_eq!(dos_drive_name("\\\\servidor\\recurso"), None);
        assert_eq!(dos_drive_name(""), None);
    }
}
