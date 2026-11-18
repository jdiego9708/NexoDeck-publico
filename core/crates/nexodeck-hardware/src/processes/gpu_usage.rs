//! Uso de GPU por proceso.
//!
//! Solo Windows, y a proposito por PDH y no por NVML: `\GPU Engine(*)` es un
//! contador del sistema operativo, asi que da el mismo numero con NVIDIA, AMD
//! o Intel --y es la misma fuente que usa el Administrador de tareas, que es
//! contra lo que el usuario va a comparar--. NVML solo serviria en maquinas
//! NVIDIA y obligaria a mantener dos criterios distintos de "uso de GPU".
//!
//! Todo el trabajo interesante (parseo de instancias, suma por motor, maximo
//! entre motores) vive en `crate::pdh`, en funciones puras con tests. Aca solo
//! queda el manejo del handle.

use std::collections::HashMap;

/// Lector con estado: PDH necesita dos muestras para dar un porcentaje, asi
/// que la query tiene que sobrevivir entre llamadas.
pub(crate) struct GpuUsageReader {
    #[cfg(target_os = "windows")]
    inner: Option<windows_impl::Reader>,
}

impl GpuUsageReader {
    pub(crate) fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            inner: windows_impl::Reader::open(),
        }
    }

    /// Si esta maquina puede informar uso de GPU por proceso.
    ///
    /// Se expone para que la UI distinga "aca no se puede medir" de "ahora
    /// mismo nadie esta usando la GPU". Sin esta diferencia los dos casos son
    /// una lista vacia y el sintoma queda mudo.
    pub(crate) fn is_available(&self) -> bool {
        #[cfg(target_os = "windows")]
        {
            self.inner.is_some()
        }
        #[cfg(not(target_os = "windows"))]
        {
            false
        }
    }

    /// Porcentaje 0-100 por pid. Vacio si no hay datos.
    pub(crate) fn sample(&mut self) -> HashMap<u32, f32> {
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

    use crate::pdh::{self, PdhQuery};

    pub(super) struct Reader {
        query: PdhQuery,
        counter: PDH_HCOUNTER,
    }

    // SAFETY: mismo motivo que en `gpu_windows::PdhCounters` -- el
    // `PDH_HCOUNTER` es un puntero crudo que arrastra a toda la struct, y el
    // colector vive dentro de una tarea de tokio que exige `Send`.
    unsafe impl Send for Reader {}

    impl Reader {
        pub(super) fn open() -> Option<Self> {
            let query = PdhQuery::open()?;
            let counter = query.add_counter(pdh::GPU_ENGINE_USAGE)?;
            // Primera muestra: fija la linea base contra la que se calcula
            // el porcentaje de la siguiente. Sin esto, la primera lectura
            // real daria cero para todo el mundo.
            query.collect();
            Some(Self { query, counter })
        }

        pub(super) fn sample(&self) -> HashMap<u32, f32> {
            if !self.query.collect() {
                return HashMap::new();
            }
            // SAFETY: el contador salio de `add_counter` sobre la query que
            // sigue viva en `self`, y acaba de tomarse una muestra.
            let instances = unsafe { pdh::read_counter_array(self.counter) };
            instances
                .map(|items| pdh::gpu_percent_per_pid(&items))
                .unwrap_or_default()
        }
    }
}
