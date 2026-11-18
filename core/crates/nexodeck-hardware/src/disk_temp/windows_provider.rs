//! Sondeo de temperatura por disco en Windows, via IOCTL directos al
//! dispositivo. Ver el encabezado de `disk_temp` para el porque de cada
//! fuente y de la cadencia.

use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
};
use windows::Win32::System::IO::DeviceIoControl;
use windows::core::PCWSTR;

use super::{DiskTempReading, DiskTemps, now_epoch_secs};

/// Cada cuanto se relee. Espaciado a proposito: la temperatura de un disco se
/// mueve despacio, y **cada consulta despierta un disco mecanico** -- a la
/// cadencia del snapshot los HDD no bajarian a reposo nunca.
const POLL_INTERVAL: Duration = Duration::from_secs(30);

/// Granularidad con la que el hilo mira la bandera de parada. Dormir los 30 s
/// de una haria que cerrar la app se quede esperando al hilo.
const STOP_CHECK_STEP: Duration = Duration::from_millis(250);

// CTL_CODE(IOCTL_STORAGE_BASE=0x2d, 0x0500, METHOD_BUFFERED, FILE_ANY_ACCESS)
const IOCTL_STORAGE_QUERY_PROPERTY: u32 = 0x002D_1400;
// CTL_CODE(IOCTL_STORAGE_BASE=0x2d, 0x0440, METHOD_BUFFERED, FILE_ANY_ACCESS).
// **`FILE_ANY_ACCESS` es la razon** de que esto ande con el handle abierto sin
// pedir accesos, y por lo tanto sin UAC.
const IOCTL_STORAGE_PREDICT_FAILURE: u32 = 0x002D_1100;
// CTL_CODE(IOCTL_VOLUME_BASE=0x56, 0, METHOD_BUFFERED, FILE_ANY_ACCESS)
const IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS: u32 = 0x0056_0000;

/// `STORAGE_PROPERTY_ID::StorageDeviceProperty`: modelo, numero de serie y
/// tipo de bus.
const STORAGE_DEVICE_PROPERTY: u32 = 0;
/// `STORAGE_PROPERTY_ID::StorageDeviceProtocolSpecificProperty`: la puerta a
/// las log pages de NVMe.
const STORAGE_DEVICE_PROTOCOL_SPECIFIC_PROPERTY: u32 = 50;
/// `STORAGE_PROPERTY_ID::StorageDeviceTemperatureProperty`: la via de PRIMERA
/// PARTE de Windows para temperatura de disco, sin pasar por SMART ni por el
/// estandar NVMe.
///
/// Se prueba primero porque cuando esta, esta bien: la sirve la pila de
/// almacenamiento y trae ademas los umbrales de aviso y critico del propio
/// disco. Pero **no es universal**: en el equipo principal la soportan 2 de
/// los 4 discos y los otros dos devuelven ERROR_INVALID_FUNCTION, asi que las
/// dos vias de abajo siguen siendo necesarias.
const STORAGE_DEVICE_TEMPERATURE_PROPERTY: u32 = 52;
/// `STORAGE_PROTOCOL_TYPE::ProtocolTypeNvme`.
const PROTOCOL_TYPE_NVME: u32 = 3;
/// `STORAGE_PROTOCOL_NVME_DATA_TYPE::NVMeDataTypeLogPage`.
const NVME_DATA_TYPE_LOG_PAGE: u32 = 2;
/// Log page 0x02 del estandar NVMe: SMART / Health Information.
const NVME_LOG_PAGE_HEALTH: u32 = 0x02;
/// `STORAGE_BUS_TYPE::BusTypeNvme`.
const BUS_TYPE_NVME: u8 = 0x11;

/// Los IOCTL de NVMe devuelven Kelvin enteros.
const KELVIN_OFFSET: f32 = 273.15;

/// Atributo SMART 194 (`Temperature_Celsius`), el estandar de facto.
const SMART_ATTR_TEMPERATURE: u8 = 194;
/// Atributo SMART 190 (`Airflow_Temperature_Cel`). Algunos SSD --sobre todo
/// Intel y Crucial-- publican **solo** este; se usa como respaldo del 194.
const SMART_ATTR_AIRFLOW_TEMPERATURE: u8 = 190;

/// Rango en el que una lectura se acepta. Un disco a 0 °C o a 200 °C no es
/// una temperatura real: es un atributo que no era el que creiamos, o un
/// campo sin llenar. Es preferible no mostrar nada a mostrar un numero falso
/// -- mismo criterio que `cpu_temp` con las etiquetas que descarta.
const PLAUSIBLE_RANGE_C: std::ops::RangeInclusive<f32> = 1.0..=110.0;

pub(super) struct SensorProvider {
    last: Arc<Mutex<DiskTemps>>,
    stop: Arc<AtomicBool>,
}

impl SensorProvider {
    pub(super) fn start() -> Self {
        let last = Arc::new(Mutex::new(HashMap::new()));
        let stop = Arc::new(AtomicBool::new(false));

        let thread_last = Arc::clone(&last);
        let thread_stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("nexodeck-disk-temp".to_owned())
            .spawn(move || poll_loop(&thread_last, &thread_stop))
            // Que no se pueda crear el hilo no puede tumbar el monitor entero:
            // sin el, las temperaturas quedan vacias igual que en una
            // plataforma que no sabe medirlas.
            .ok();

        Self { last, stop }
    }

    pub(super) fn last_values(&self) -> DiskTemps {
        // `lock()` solo falla si otro hilo panickeo con el mutex tomado; ahi
        // tambien preferimos "sin dato" a propagar el panic al stream de
        // metricas.
        self.last.lock().map(|map| map.clone()).unwrap_or_default()
    }
}

impl Drop for SensorProvider {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn poll_loop(last: &Arc<Mutex<DiskTemps>>, stop: &Arc<AtomicBool>) {
    // Se arranca con lo que quedo de la sesion anterior: sin esto, abrir la
    // app con los discos ya dormidos deja la lista sin temperaturas hasta que
    // algo los use, que en un disco secundario puede no pasar en todo el dia.
    let mut previous = persistence::load();
    if let Ok(mut slot) = last.lock() {
        *slot = previous.clone();
    }

    while !stop.load(Ordering::Relaxed) {
        let reading = sample(&previous);
        if reading != previous {
            persistence::save(&reading);
        }
        previous = reading.clone();
        if let Ok(mut slot) = last.lock() {
            *slot = reading;
        }
        sleep_interruptible(POLL_INTERVAL, stop);
    }
}

fn sleep_interruptible(total: Duration, stop: &Arc<AtomicBool>) {
    let mut left = total;
    while left > Duration::ZERO && !stop.load(Ordering::Relaxed) {
        let step = left.min(STOP_CHECK_STEP);
        thread::sleep(step);
        left -= step;
    }
}

/// Una pasada completa: temperatura de cada disco fisico, reproyectada sobre
/// las letras de unidad que viven en el.
///
/// Se parte de las letras y no de enumerar `PhysicalDrive0..N` a ciegas: solo
/// interesan los discos que respaldan un volumen montado, que son exactamente
/// los que `disks::collect` pone en la lista. Un disco sin letra no tendria
/// donde mostrarse, y sondearlo solo lo despertaria para nada.
fn sample(previous: &DiskTemps) -> DiskTemps {
    let letters_by_drive = drive_letters_by_physical_drive();
    let readings = letters_by_drive
        .keys()
        .map(|&drive_number| (drive_number, read_drive_temperature(drive_number)))
        .collect();
    merge_sample(&letters_by_drive, &readings, previous)
}

/// Combina la pasada nueva con la anterior, que es donde vive la unica regla
/// interesante: **un disco que sigue montado pero no contesto conserva su
/// ultima lectura**; uno que ya no aparece la pierde.
///
/// No es prolijidad. Un disco inactivo entra en bajo consumo y ahi la consulta
/// SMART **falla en vez de despertarlo** -- comprobado en vivo en el equipo
/// principal: `E:` e `I:` dejaron de contestar tras un rato de reposo y
/// volvieron apenas algo los toco. Que falle esta BIEN (despertar un disco
/// cada 30 s es justo lo que este modulo evita), pero sin esta regla la
/// temperatura de la fila desaparecia y reaparecia sola.
///
/// El valor conservado envejece, si: un disco dormido lleva horas sin cambiar
/// de temperatura y su ultima lectura sigue siendo la mejor verdad disponible
/// -- justamente porque esta dormido y no se esta calentando.
///
/// Pura y separada de los IOCTL para poder testear esa regla sin hardware.
fn merge_sample(
    letters_by_drive: &HashMap<u32, Vec<String>>,
    readings: &HashMap<u32, Option<f32>>,
    previous: &DiskTemps,
) -> DiskTemps {
    let mut temps = HashMap::new();
    let now = now_epoch_secs();

    for (drive_number, letters) in letters_by_drive {
        let fresh = readings.get(drive_number).copied().flatten();
        for letter in letters {
            // Solo se mira `previous` para las letras que SIGUEN montadas: un
            // disco desconectado desaparece del mapa de letras y con el su
            // temperatura, que es lo correcto.
            let reading = match fresh {
                Some(celsius) => Some(DiskTempReading {
                    celsius,
                    measured_at_epoch_secs: now,
                }),
                None => previous.get(letter).copied(),
            };
            if let Some(reading) = reading {
                temps.insert(letter.clone(), reading);
            }
        }
    }

    temps
}

/// Que letras de unidad viven en cada disco fisico.
///
/// El puente es necesario porque las dos mitades estan indexadas distinto: la
/// temperatura se pide por disco **fisico** (`PhysicalDrive3`) y la lista que
/// dibuja la UI esta indexada por punto de **montaje** (`C:`). Un disco con
/// varias particiones aparece varias veces en la lista, y las tres comparten
/// la misma temperatura: es un solo sensor, el del disco.
fn drive_letters_by_physical_drive() -> HashMap<u32, Vec<String>> {
    let mut map: HashMap<u32, Vec<String>> = HashMap::new();

    for letter in 'A'..='Z' {
        let path = format!(r"\\.\{letter}:");
        let Some(handle) = open_device(&path) else {
            continue;
        };
        // VOLUME_DISK_EXTENTS: `NumberOfDiskExtents` (u32) y despues el array
        // de `DISK_EXTENT`. El array arranca en el byte 8 y no en el 4 por el
        // relleno de alineacion: `DISK_EXTENT` contiene un `LARGE_INTEGER`,
        // asi que se alinea a 8. Un volumen repartido (spanned/striped) tiene
        // mas de un extent; se toma el primero, que es donde la UI espera
        // encontrar "el disco" de esa letra.
        let mut buffer = [0u8; 256];
        let ok = device_io_control(handle, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, &[], &mut buffer);
        close(handle);
        if !ok {
            continue;
        }
        if u32::from_le_bytes(buffer[0..4].try_into().unwrap_or_default()) == 0 {
            continue;
        }
        let drive_number = u32::from_le_bytes(buffer[8..12].try_into().unwrap_or_default());
        map.entry(drive_number)
            .or_default()
            .push(format!("{letter}:"));
    }

    map
}

/// Temperatura de un disco fisico, por la via que corresponda a su bus.
fn read_drive_temperature(drive_number: u32) -> Option<f32> {
    let path = format!(r"\\.\PhysicalDrive{drive_number}");
    let handle = open_device(&path)?;
    let bus_type = read_bus_type(handle);
    // Los NVMe **no** contestan `IOCTL_STORAGE_PREDICT_FAILURE` (devuelven
    // ERROR_INVALID_FUNCTION, verificado en vivo) y los SATA no entienden la
    // consulta de log page: cada bus tiene una sola puerta, no hay que
    // intentar las dos.
    // Orden: primero la via de primera parte, y solo si el disco no la
    // soporta se cae a la especifica de su bus.
    let temp = read_storage_temperature_property(handle).or_else(|| {
        if bus_type == Some(BUS_TYPE_NVME) {
            read_nvme_composite_temperature(handle)
        } else {
            read_smart_temperature(handle)
        }
    });
    close(handle);
    temp.filter(|value| PLAUSIBLE_RANGE_C.contains(value))
}

/// `STORAGE_DEVICE_DESCRIPTOR.BusType`, en el byte 28 del descriptor.
fn read_bus_type(handle: HANDLE) -> Option<u8> {
    let mut query = [0u8; 12];
    query[0..4].copy_from_slice(&STORAGE_DEVICE_PROPERTY.to_le_bytes());
    // `PropertyStandardQuery` = 0; los 4 bytes restantes son
    // `AdditionalParameters`, que esta consulta no usa.
    let mut buffer = [0u8; 512];
    if !device_io_control(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query, &mut buffer) {
        return None;
    }
    Some(buffer[28])
}

/// Temperatura por `StorageDeviceTemperatureProperty`.
///
/// `STORAGE_TEMPERATURE_DATA_DESCRIPTOR`: `Version` (4), `Size` (4),
/// `CriticalTemperature` (2), `WarningTemperature` (2), `InfoCount` (2),
/// reservados (10) y despues el array de `STORAGE_TEMPERATURE_INFO`, donde
/// cada entrada empieza con `Index` (2) y `Temperature` (2), en grados
/// Celsius con signo.
fn read_storage_temperature_property(handle: HANDLE) -> Option<f32> {
    const INFO_ARRAY_OFFSET: usize = 24;

    let mut query = [0u8; 12];
    query[0..4].copy_from_slice(&STORAGE_DEVICE_TEMPERATURE_PROPERTY.to_le_bytes());
    let mut buffer = [0u8; 512];
    if !device_io_control(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query, &mut buffer) {
        return None;
    }

    let count = u16::from_le_bytes(buffer[12..14].try_into().ok()?);
    if count == 0 {
        return None;
    }
    // Se toma el PRIMER sensor. En un NVMe los siguientes son sensores
    // secundarios del controlador --y en el equipo principal el segundo
    // devuelve 0-- que no representan "la temperatura del disco".
    let celsius = i16::from_le_bytes(buffer.get(INFO_ARRAY_OFFSET + 2..INFO_ARRAY_OFFSET + 4)?.try_into().ok()?);
    Some(f32::from(celsius))
}

/// Temperatura compuesta de la log page 0x02 de NVMe.
///
/// El buffer hace de entrada y de salida y tiene tres tramos: la
/// `STORAGE_PROPERTY_QUERY` (8 bytes), la `STORAGE_PROTOCOL_SPECIFIC_DATA`
/// (40) y los datos de la log page (512). A la vuelta los primeros 8 bytes
/// son el encabezado de `STORAGE_PROTOCOL_DATA_DESCRIPTOR` y el
/// `ProtocolDataOffset` que trae el descriptor es **relativo al comienzo de
/// la `STORAGE_PROTOCOL_SPECIFIC_DATA`**, no al del buffer.
fn read_nvme_composite_temperature(handle: HANDLE) -> Option<f32> {
    const HEADER_LEN: usize = 8;
    const PROTOCOL_DATA_LEN: usize = 40;
    const LOG_PAGE_LEN: usize = 512;

    let mut buffer = [0u8; HEADER_LEN + PROTOCOL_DATA_LEN + LOG_PAGE_LEN];
    let mut put = |offset: usize, value: u32| {
        buffer[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    };
    put(0, STORAGE_DEVICE_PROTOCOL_SPECIFIC_PROPERTY);
    put(4, 0); // PropertyStandardQuery
    put(8, PROTOCOL_TYPE_NVME);
    put(12, NVME_DATA_TYPE_LOG_PAGE);
    put(16, NVME_LOG_PAGE_HEALTH);
    put(20, 0); // ProtocolDataRequestSubValue
    put(24, PROTOCOL_DATA_LEN as u32); // ProtocolDataOffset
    put(28, LOG_PAGE_LEN as u32); // ProtocolDataLength

    let input = buffer;
    if !device_io_control(
        handle,
        IOCTL_STORAGE_QUERY_PROPERTY,
        &input,
        &mut buffer,
    ) {
        return None;
    }

    let data_offset =
        HEADER_LEN + u32::from_le_bytes(buffer[24..28].try_into().ok()?) as usize;
    nvme_composite_temperature(buffer.get(data_offset..)?)
}

/// La temperatura compuesta dentro de la log page ya extraida.
///
/// Pura y separada del IOCTL para poder testear el parseo con una pagina
/// grabada: que el offset o el orden de bytes esten mal se veria como una
/// temperatura absurda, no como un error.
fn nvme_composite_temperature(log_page: &[u8]) -> Option<f32> {
    // Byte 0: Critical Warning. Bytes 1-2: Composite Temperature, en Kelvin y
    // little endian.
    let kelvin = u16::from_le_bytes([*log_page.get(1)?, *log_page.get(2)?]);
    if kelvin == 0 {
        return None;
    }
    Some(f32::from(kelvin) - KELVIN_OFFSET)
}

/// Temperatura por `IOCTL_STORAGE_PREDICT_FAILURE` (todo lo que no es NVMe).
fn read_smart_temperature(handle: HANDLE) -> Option<f32> {
    // STORAGE_PREDICT_FAILURE: `PredictFailure` (u32) y 512 bytes
    // `VendorSpecific`, que en la practica son la salida de `SMART READ DATA`.
    let mut buffer = [0u8; 4 + 512];
    if !device_io_control(handle, IOCTL_STORAGE_PREDICT_FAILURE, &[], &mut buffer) {
        return None;
    }
    smart_temperature(&buffer[4..])
}

/// La temperatura dentro de los 512 bytes de `SMART READ DATA`.
///
/// Pura por el mismo motivo que `nvme_composite_temperature`: el recorrido de
/// atributos es exactamente donde un offset mal puesto produce un numero
/// plausible pero falso.
fn smart_temperature(vendor_specific: &[u8]) -> Option<f32> {
    // 2 bytes de version y despues 30 atributos de 12 bytes: id (1), flags
    // (2), valor normalizado (1), peor valor (1), raw (6), reservado (1). La
    // temperatura en Celsius es el primer byte del raw.
    const ATTRIBUTE_COUNT: usize = 30;
    const ATTRIBUTE_LEN: usize = 12;
    const RAW_OFFSET: usize = 5;

    let mut airflow = None;
    for index in 0..ATTRIBUTE_COUNT {
        let base = 2 + index * ATTRIBUTE_LEN;
        let id = *vendor_specific.get(base)?;
        let raw = f32::from(*vendor_specific.get(base + RAW_OFFSET)?);
        match id {
            SMART_ATTR_TEMPERATURE => return Some(raw),
            // Se guarda pero no se devuelve todavia: si el disco publica los
            // dos, gana el 194, que es el que mide el propio disco y no el
            // aire que lo rodea. Los atributos no vienen ordenados por id.
            SMART_ATTR_AIRFLOW_TEMPERATURE => airflow = Some(raw),
            _ => {}
        }
    }
    airflow
}

/// Abre el dispositivo **sin pedir ningun acceso**. Es lo que evita el UAC:
/// con `GENERIC_READ` el `CreateFileW` sobre un disco crudo falla con
/// ERROR_ACCESS_DENIED en un proceso sin elevar.
fn open_device(path: &str) -> Option<HANDLE> {
    let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: `wide` termina en NUL y vive hasta el final de la llamada.
    unsafe {
        CreateFileW(
            PCWSTR(wide.as_ptr()),
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            None,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            None,
        )
    }
    .ok()
}

fn device_io_control(handle: HANDLE, code: u32, input: &[u8], output: &mut [u8]) -> bool {
    let mut returned = 0u32;
    // SAFETY: el handle sale de `open_device` y sigue abierto; los dos buffers
    // se pasan con su largo real. `DeviceIoControl` solo escribe dentro de
    // `output`, hasta `returned` bytes.
    unsafe {
        DeviceIoControl(
            handle,
            code,
            if input.is_empty() {
                None
            } else {
                Some(input.as_ptr() as *const c_void)
            },
            input.len() as u32,
            Some(output.as_mut_ptr() as *mut c_void),
            output.len() as u32,
            Some(&mut returned),
            None,
        )
    }
    .is_ok()
}

fn close(handle: HANDLE) {
    // SAFETY: el handle sale de `open_device` y no se vuelve a usar.
    unsafe {
        let _ = CloseHandle(handle);
    }
}

/// Guarda y recupera las lecturas entre sesiones.
///
/// **Por que persistir algo tan volatil.** Un disco secundario esta dormido
/// casi siempre, y dormido no contesta. Sin esto, abrir NexoDeck con los
/// discos en reposo deja la lista sin temperaturas hasta que algo los use --y
/// en un disco de archivo eso puede no pasar en todo el dia--, que es
/// exactamente el sintoma que se reporto. Con el archivo, la app abre
/// mostrando la ultima lectura conocida, marcada como vieja.
///
/// Todo es best-effort: un fallo de escritura o un archivo corrupto degradan a
/// "sin lecturas previas", nunca a un error visible.
mod persistence {
    use std::collections::HashMap;
    use std::path::PathBuf;

    use serde_json::Value;

    use super::{DiskTempReading, DiskTemps};

    /// Mas viejo que esto no se carga. Una temperatura de la semana pasada no
    /// dice nada sobre el disco de hoy, y mostrarla seria peor que no mostrar
    /// nada.
    const MAX_AGE_SECS: u64 = 24 * 60 * 60;

    fn file_path() -> Option<PathBuf> {
        let directories = directories::ProjectDirs::from("com", "NexoDeck", "NexoDeck")?;
        let directory = directories.cache_dir();
        std::fs::create_dir_all(directory).ok()?;
        Some(directory.join("disk_temps.json"))
    }

    pub(super) fn load() -> DiskTemps {
        let Some(path) = file_path() else {
            return HashMap::new();
        };
        let Ok(text) = std::fs::read_to_string(path) else {
            return HashMap::new();
        };
        let Ok(value) = serde_json::from_str::<Value>(&text) else {
            return HashMap::new();
        };
        let Some(entries) = value.as_object() else {
            return HashMap::new();
        };

        let now = super::now_epoch_secs();
        entries
            .iter()
            .filter_map(|(mount_point, entry)| {
                let celsius = entry.get("celsius")?.as_f64()? as f32;
                let measured_at_epoch_secs = entry.get("measuredAt")?.as_u64()?;
                let reading = DiskTempReading {
                    celsius,
                    measured_at_epoch_secs,
                };
                (reading.age_secs(now) <= MAX_AGE_SECS)
                    .then(|| (mount_point.clone(), reading))
            })
            .collect()
    }

    pub(super) fn save(temps: &DiskTemps) {
        let Some(path) = file_path() else {
            return;
        };
        let entries: serde_json::Map<String, Value> = temps
            .iter()
            .map(|(mount_point, reading)| {
                (
                    mount_point.clone(),
                    serde_json::json!({
                        "celsius": reading.celsius,
                        "measuredAt": reading.measured_at_epoch_secs,
                    }),
                )
            })
            .collect();
        if let Ok(text) = serde_json::to_string(&Value::Object(entries)) {
            let _ = std::fs::write(path, text);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Bytes 1-2 en Kelvin y little endian. 315 K = 41.85 C, que es lo que la
    /// UI redondea a 42 -- el mismo numero que imprimio el disco real del
    /// equipo principal.
    #[test]
    fn la_pagina_de_nvme_se_lee_en_kelvin_little_endian() {
        let mut page = [0u8; 512];
        page[0] = 0; // Critical Warning
        page[1..3].copy_from_slice(&315u16.to_le_bytes());
        let temp = nvme_composite_temperature(&page).expect("hay temperatura");
        assert!((temp - 41.85).abs() < 0.01, "{temp}");
    }

    /// Una pagina en cero no es "0 K": es un disco que no lleno el campo.
    #[test]
    fn una_pagina_de_nvme_vacia_no_inventa_temperatura() {
        assert_eq!(nvme_composite_temperature(&[0u8; 512]), None);
    }

    #[test]
    fn una_pagina_de_nvme_truncada_no_panickea() {
        assert_eq!(nvme_composite_temperature(&[0u8; 1]), None);
        assert_eq!(nvme_composite_temperature(&[]), None);
    }

    fn smart_data(attributes: &[(u8, u8)]) -> Vec<u8> {
        let mut data = vec![0u8; 512];
        for (index, (id, raw)) in attributes.iter().enumerate() {
            let base = 2 + index * 12;
            data[base] = *id;
            data[base + 5] = *raw;
        }
        data
    }

    #[test]
    fn el_atributo_194_es_la_temperatura() {
        let data = smart_data(&[(9, 200), (194, 40), (5, 0)]);
        assert_eq!(smart_temperature(&data), Some(40.0));
    }

    /// El 190 sirve solo si el disco no publica el 194, y **el orden en que
    /// aparecen no decide**: los atributos no vienen ordenados por id.
    #[test]
    fn el_190_es_respaldo_del_194_aunque_venga_antes() {
        let solo_190 = smart_data(&[(190, 38)]);
        assert_eq!(smart_temperature(&solo_190), Some(38.0));

        let ambos = smart_data(&[(190, 38), (194, 41)]);
        assert_eq!(smart_temperature(&ambos), Some(41.0));
    }

    #[test]
    fn sin_atributo_de_temperatura_no_hay_dato() {
        assert_eq!(smart_temperature(&smart_data(&[(9, 200), (5, 0)])), None);
    }

    fn letters(pairs: &[(u32, &str)]) -> HashMap<u32, Vec<String>> {
        let mut map: HashMap<u32, Vec<String>> = HashMap::new();
        for (drive, letter) in pairs {
            map.entry(*drive).or_default().push((*letter).to_owned());
        }
        map
    }

    fn reading(celsius: f32, measured_at_epoch_secs: u64) -> DiskTempReading {
        DiskTempReading {
            celsius,
            measured_at_epoch_secs,
        }
    }

    /// El caso real: el disco sigue montado pero se durmio y no contesta.
    #[test]
    fn un_disco_dormido_conserva_su_ultima_lectura() {
        let mapa = letters(&[(0, "E:"), (2, "G:")]);
        let previa = DiskTemps::from([
            ("E:".to_owned(), reading(40.0, 1_000)),
            ("G:".to_owned(), reading(41.0, 1_000)),
        ]);
        let readings = HashMap::from([(0, None), (2, Some(42.0))]);

        let temps = merge_sample(&mapa, &readings, &previa);

        let dormido = temps.get("E:").expect("el dormido conserva");
        assert_eq!(dormido.celsius, 40.0);
        assert_eq!(
            dormido.measured_at_epoch_secs, 1_000,
            "conservar NO refresca la marca de tiempo: si la refrescara, un              disco dormido se veria eternamente recien medido"
        );

        let despierto = temps.get("G:").expect("el que contesta se actualiza");
        assert_eq!(despierto.celsius, 42.0);
        assert!(despierto.measured_at_epoch_secs > 1_000);
    }

    /// Y el caso opuesto, que es el que justifica no conservar siempre: un
    /// disco desconectado desaparece del mapa de letras y pierde su valor.
    #[test]
    fn un_disco_desconectado_pierde_su_temperatura() {
        let previa = DiskTemps::from([("E:".to_owned(), reading(40.0, 1_000))]);
        let temps = merge_sample(&letters(&[]), &HashMap::new(), &previa);
        assert!(temps.is_empty(), "{temps:?}");
    }

    /// Las dos particiones de un mismo disco comparten sensor, tambien al
    /// conservar.
    #[test]
    fn las_dos_letras_de_un_disco_comparten_la_lectura() {
        let mapa = letters(&[(3, "C:"), (3, "D:")]);
        let temps = merge_sample(&mapa, &HashMap::from([(3, Some(44.0))]), &DiskTemps::new());
        assert_eq!(temps.get("C:"), temps.get("D:"));
        assert_eq!(temps.get("C:").map(|entry| entry.celsius), Some(44.0));
    }

    /// La lista real cambia por equipo, asi que lo unico que se puede afirmar
    /// es que las lecturas que devuelva sean plausibles y esten indexadas por
    /// letra de unidad.
    #[test]
    fn la_lectura_real_es_coherente() {
        let temps = sample(&DiskTemps::new());
        for (mount_point, reading) in &temps {
            let temp = &reading.celsius;
            assert!(
                mount_point.len() == 2 && mount_point.ends_with(':'),
                "punto de montaje raro: {mount_point}"
            );
            assert!(
                PLAUSIBLE_RANGE_C.contains(temp),
                "temperatura fuera de rango en {mount_point}: {temp}"
            );
        }
    }
}
