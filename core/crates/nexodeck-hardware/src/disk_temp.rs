//! Temperatura por disco fisico.
//!
//! **Se lee sin privilegios de administrador**, a diferencia de casi todo lo
//! demas que toca SMART. La clave es abrir `\\.\PhysicalDriveN` con
//! `dwDesiredAccess = 0`: sin pedir `GENERIC_READ` no hace falta elevacion, y
//! los dos IOCTL que usamos aceptan igual el handle. Es lo que separa este
//! camino de la via "oficial" de PowerShell (`Get-StorageReliabilityCounter`,
//! o sea la clase WMI `MSFT_StorageReliabilityCounter`), que **si** exige
//! elevacion -- verificado en vivo en el equipo principal: los cuatro discos
//! contestan "El cliente no tenia acceso disponible a un recurso CIM" sin
//! elevar, y los cuatro contestan su temperatura por este otro camino.
//!
//! Dos fuentes segun el bus, porque no hay una sola que sirva para los dos:
//!
//! - **NVMe**: `IOCTL_STORAGE_QUERY_PROPERTY` con
//!   `StorageDeviceProtocolSpecificProperty`, pidiendo la log page 0x02
//!   (SMART / Health Information) del estandar NVMe. La temperatura compuesta
//!   son los bytes 1-2, en Kelvin.
//! - **Todo lo demas (SATA, USB, RAID...)**: `IOCTL_STORAGE_PREDICT_FAILURE`,
//!   que devuelve los 512 bytes crudos de `SMART READ DATA`; ahi el atributo
//!   194 es la temperatura. Este IOCTL es `FILE_ANY_ACCESS`, que es
//!   justamente por que funciona con el handle sin accesos.
//!
//! **No vive en la ruta de `snapshot()`**, y no es por costo de CPU: una
//! consulta SMART **despierta un disco mecanico**. A la cadencia de 1/s del
//! snapshot, los dos HDD del equipo principal no bajarian a reposo nunca. Por
//! eso el sondeo va en un hilo propio y espaciado, igual que `cpu_temp`.
//!
//! La contracara de eso: un disco que ya se durmio **falla la consulta en vez
//! de despertarse**, asi que su lectura desaparece cada tanto. Comprobado en
//! vivo. Por eso una lectura fallida de un disco que sigue montado conserva la
//! anterior en vez de borrarla -- ver `merge_sample` en el proveedor, que es
//! donde vive esa regla y donde esta el porque completo.

use std::collections::HashMap;

#[cfg(target_os = "windows")]
mod windows_provider;

/// Una lectura con **cuando** se tomo.
///
/// La marca de tiempo no es contabilidad: un disco dormido conserva su ultima
/// lectura (ver `merge_sample`), y sin saber de cuando es, la UI no puede
/// distinguir un dato de hace dos segundos de uno de hace tres horas. Con ella
/// puede mostrarlo atenuado y decirlo en el tooltip.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct DiskTempReading {
    pub(crate) celsius: f32,
    /// Segundos de epoch. Se guarda asi --y no un `Instant`-- porque esto se
    /// persiste a disco y tiene que sobrevivir a reiniciar la app.
    pub(crate) measured_at_epoch_secs: u64,
}

impl DiskTempReading {
    pub(crate) fn age_secs(&self, now_epoch_secs: u64) -> u64 {
        now_epoch_secs.saturating_sub(self.measured_at_epoch_secs)
    }
}

/// Lecturas por punto de montaje, ya en mayusculas (`"C:"`, `"D:"`). La clave
/// es el punto de montaje y no el numero de disco fisico porque es lo que
/// `disks::collect` produce y lo que la UI dibuja; el mapeo entre los dos lo
/// resuelve el proveedor.
pub(crate) type DiskTemps = HashMap<String, DiskTempReading>;

/// Ahora, en segundos de epoch. `unwrap_or(0)` cubre un reloj antes de 1970,
/// que solo pasa con la hora del sistema rota; ahi todo se ve como muy viejo,
/// que es preferible a entrar en panico.
pub(crate) fn now_epoch_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

/// Lector con estado: mantiene vivo el hilo de sondeo mientras exista.
pub(crate) struct DiskTempReader {
    #[cfg(target_os = "windows")]
    inner: windows_provider::SensorProvider,
}

impl DiskTempReader {
    pub(crate) fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            inner: windows_provider::SensorProvider::start(),
        }
    }

    /// Ultima lectura conocida. Vacio mientras el primer sondeo no termino, y
    /// vacio para siempre en las plataformas que todavia no saben medirlo --
    /// quien llama lo trata igual que "sin dato" para ese disco.
    pub(crate) fn read(&self) -> DiskTemps {
        #[cfg(target_os = "windows")]
        {
            self.inner.last_values()
        }
        // Linux expone esto por hwmon (`drivetemp` para SATA, `nvme` para
        // NVMe), pero mapear un hwmon a un punto de montaje es otro problema
        // --hay que pasar por el device del bloque y sus particiones-- y no
        // hay maquina Linux para verificarlo. Mismo criterio que `disk_io`,
        // que tambien degrada entero fuera de Windows.
        #[cfg(not(target_os = "windows"))]
        {
            HashMap::new()
        }
    }
}

impl Default for DiskTempReader {
    fn default() -> Self {
        Self::new()
    }
}
