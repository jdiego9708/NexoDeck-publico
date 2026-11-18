//! Actividad de lectura/escritura por disco, para la senal de vida de la UI.
//!
//! Solo Windows, via PDH y `\LogicalDisk(*)` -- ver los comentarios de
//! `pdh::LOGICAL_DISK_READ_BYTES`/`LOGICAL_DISK_WRITE_BYTES` sobre por que es
//! por letra de unidad y no por disco fisico. Mismo patron que
//! `processes::gpu_usage::GpuUsageReader`: un lector con estado porque PDH
//! necesita dos muestras para dar una tasa, asi que la query tiene que
//! sobrevivir entre snapshots.

use std::collections::HashMap;

/// Bytes/segundo de lectura y escritura por letra de unidad ("C:", "D:"...).
pub(crate) type DiskIoRates = HashMap<String, (f64, f64)>;

pub(crate) struct DiskIoReader {
    #[cfg(target_os = "windows")]
    inner: Option<windows_impl::Reader>,
}

impl DiskIoReader {
    pub(crate) fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            inner: windows_impl::Reader::open(),
        }
    }

    /// Tasas por letra de unidad. Vacio si esta plataforma no sabe medirlo o
    /// PDH fallo -- quien llama lo trata igual que "sin dato" para esa letra.
    pub(crate) fn sample(&mut self) -> DiskIoRates {
        #[cfg(target_os = "windows")]
        {
            return self
                .inner
                .as_ref()
                .map(windows_impl::Reader::sample)
                .unwrap_or_default();
        }
        #[cfg(not(target_os = "windows"))]
        {
            HashMap::new()
        }
    }
}

#[cfg(target_os = "windows")]
mod windows_impl {
    use std::collections::HashMap;

    use windows::Win32::System::Performance::PDH_HCOUNTER;

    use super::DiskIoRates;
    use crate::pdh::{self, PdhQuery};

    pub(super) struct Reader {
        query: PdhQuery,
        read_counter: PDH_HCOUNTER,
        write_counter: PDH_HCOUNTER,
    }

    // SAFETY: mismo motivo que `gpu_usage::windows_impl::Reader` -- los
    // `PDH_HCOUNTER` son punteros crudos, y el monitor que guarda este lector
    // vive dentro de una tarea de tokio que exige `Send`.
    unsafe impl Send for Reader {}

    impl Reader {
        pub(super) fn open() -> Option<Self> {
            let query = PdhQuery::open()?;
            let read_counter = query.add_counter(pdh::LOGICAL_DISK_READ_BYTES)?;
            let write_counter = query.add_counter(pdh::LOGICAL_DISK_WRITE_BYTES)?;
            // Primera muestra: fija la linea base. Sin esto la primera
            // lectura real daria cero para todas las unidades.
            query.collect();
            Some(Self {
                query,
                read_counter,
                write_counter,
            })
        }

        pub(super) fn sample(&self) -> DiskIoRates {
            if !self.query.collect() {
                return HashMap::new();
            }
            // SAFETY: los contadores salieron de `add_counter` sobre `query`,
            // que sigue viva en `self`, y acaba de tomarse una muestra.
            let reads = unsafe { pdh::read_counter_array(self.read_counter) }.unwrap_or_default();
            let writes =
                unsafe { pdh::read_counter_array(self.write_counter) }.unwrap_or_default();

            let mut rates: DiskIoRates = HashMap::new();
            for (instance, value) in reads {
                if let Some(letter) = pdh::parse_logical_disk_instance(&instance) {
                    rates.entry(letter).or_insert((0.0, 0.0)).0 = value;
                }
            }
            for (instance, value) in writes {
                if let Some(letter) = pdh::parse_logical_disk_instance(&instance) {
                    rates.entry(letter).or_insert((0.0, 0.0)).1 = value;
                }
            }
            rates
        }
    }
}
