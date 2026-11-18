//! Uso y frecuencia del CPU en Windows, leidos de los **mismos contadores PDH
//! que usa el Administrador de tareas**.
//!
//! **Por que no alcanza con `sysinfo`.** Medido en vivo en el equipo principal
//! (Ryzen 7 5700X, 15-sep-2026):
//!
//! - **La frecuencia sale fija en 3401 MHz**, cargado o en reposo. `sysinfo` la
//!   toma de `CallNtPowerInformation(ProcessorInformation).CurrentMhz`, que en
//!   este procesador devuelve la frecuencia nominal y no la actual. La real
//!   --la que muestra el Administrador de tareas, 4.2-4.4 GHz con turbo-- es la
//!   nominal por `% Processor Performance` / 100, y ese contador marcaba
//!   124-133% en el mismo momento.
//! - **El uso es otra formula.** `sysinfo` calcula `100 - % Idle Time`, que en
//!   la practica coincide con `% Processor Time`. El Administrador de tareas
//!   usa `% Processor Utility`, que ademas pondera por el rendimiento del
//!   procesador: con turbo activo los dos numeros se separan varios puntos.
//!
//! Los tres contadores van en **una sola query** y se muestrean juntos: el uso
//! y la frecuencia salen del mismo intervalo, y no hay que repetir la trampa
//! de `sysinfo` con dos recolecciones seguidas (ver `snapshot()`).
//!
//! Publico solo para que el ejemplo `cpu_compare` pueda imprimir cada contador
//! por separado contra el Administrador de tareas.

use std::mem::MaybeUninit;

use windows::Win32::System::Performance::{
    PDH_FMT, PDH_FMT_COUNTERVALUE, PDH_FMT_DOUBLE, PDH_HCOUNTER, PdhGetFormattedCounterValue,
};

use crate::pdh::PdhQuery;

const PROCESSOR_TIME: &str = r"\Processor Information(_Total)\% Processor Time";
const PROCESSOR_UTILITY: &str = r"\Processor Information(_Total)\% Processor Utility";
const PROCESSOR_PERFORMANCE: &str = r"\Processor Information(_Total)\% Processor Performance";
/// La frecuencia **nominal**, no la actual: la actual es esta por el
/// rendimiento. Se lee del contador y no de `sysinfo` para que las dos mitades
/// de la cuenta salgan de la misma fuente que el Administrador de tareas.
const PROCESSOR_FREQUENCY: &str = r"\Processor Information(_Total)\Processor Frequency";

/// Flag de PDH que evita recortar el valor a 100. `% Processor Utility` y
/// `% Processor Performance` pasan de 100 con turbo **por diseno**: recortarlos
/// perderia justo la informacion que los distingue de `% Processor Time`.
const PDH_FMT_NOCAP100: u32 = 0x0000_8000;

/// `PDH_CSTATUS_VALID_DATA` y `PDH_CSTATUS_NEW_DATA`: los dos son lecturas
/// validas. Cualquier otro estado (por ejemplo, la primera muestra sin linea
/// base) no es un numero.
const PDH_CSTATUS_MAX_VALID: u32 = 1;

/// Una muestra de los contadores, en las unidades en que los publica Windows.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CpuCounterSample {
    /// `% Processor Time`: tiempo no ocioso. Es lo que calcula `sysinfo`.
    pub processor_time: f32,
    /// `% Processor Utility`: lo que muestra el Administrador de tareas. Puede
    /// pasar de 100 con turbo; quien lo muestre lo recorta.
    pub processor_utility: f32,
    /// `% Processor Performance`: rendimiento relativo a la frecuencia
    /// nominal. Mayor que 100 significa turbo.
    pub performance_percent: f32,
    /// Frecuencia nominal en MHz.
    pub nominal_mhz: f32,
}

impl CpuCounterSample {
    /// Frecuencia actual en MHz: la nominal por el rendimiento, que es
    /// exactamente la cuenta del Administrador de tareas.
    pub fn current_mhz(&self) -> Option<u64> {
        crate::current_cpu_frequency_mhz(self.nominal_mhz, self.performance_percent)
    }
}

pub struct CpuCounters {
    query: PdhQuery,
    processor_time: PDH_HCOUNTER,
    processor_utility: PDH_HCOUNTER,
    performance: PDH_HCOUNTER,
    frequency: PDH_HCOUNTER,
}

// SAFETY: mismo caso que `gpu_windows::PdhCounters`. Los handles de PDH no son
// thread-affine y `HardwareMonitor` los usa desde un solo hilo, pero tiene que
// ser `Send` para que el servidor pueda spawnear su tarea de metricas.
unsafe impl Send for CpuCounters {}

impl CpuCounters {
    /// `None` si PDH no esta disponible o algun contador no existe en esta
    /// version de Windows; quien llama cae entonces a `sysinfo`.
    pub fn new() -> Option<Self> {
        let query = PdhQuery::open()?;
        let processor_time = query.add_counter(PROCESSOR_TIME)?;
        let processor_utility = query.add_counter(PROCESSOR_UTILITY)?;
        let performance = query.add_counter(PROCESSOR_PERFORMANCE)?;
        let frequency = query.add_counter(PROCESSOR_FREQUENCY)?;
        // Linea base: los contadores de tasa se calculan entre dos muestras,
        // asi que la primera lectura util es la de la siguiente llamada.
        query.collect();

        Some(Self {
            query,
            processor_time,
            processor_utility,
            performance,
            frequency,
        })
    }

    /// Toma una muestra sobre el intervalo desde la anterior. `None` si PDH la
    /// rechazo o algun contador todavia no tiene dato valido.
    pub fn sample(&self) -> Option<CpuCounterSample> {
        if !self.query.collect() {
            return None;
        }
        // SAFETY: los contadores salen de `add_counter` sobre la query que
        // sigue viva en `self`, y acaba de tomarse una muestra.
        unsafe {
            Some(CpuCounterSample {
                processor_time: read_counter(self.processor_time)?,
                processor_utility: read_counter(self.processor_utility)?,
                performance_percent: read_counter(self.performance)?,
                nominal_mhz: read_counter(self.frequency)?,
            })
        }
    }
}

unsafe fn read_counter(counter: PDH_HCOUNTER) -> Option<f32> {
    let mut value = MaybeUninit::<PDH_FMT_COUNTERVALUE>::uninit();
    unsafe {
        let status = PdhGetFormattedCounterValue(
            counter,
            PDH_FMT(PDH_FMT_DOUBLE.0 | PDH_FMT_NOCAP100),
            None,
            value.as_mut_ptr(),
        );
        if status != 0 {
            return None;
        }
        let value = value.assume_init();
        if value.CStatus > PDH_CSTATUS_MAX_VALID {
            return None;
        }
        let number = value.Anonymous.doubleValue;
        number.is_finite().then_some(number as f32)
    }
}
