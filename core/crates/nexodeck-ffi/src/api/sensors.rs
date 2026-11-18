//! Estado e instalacion del ayudante de sensores, expuesto a Dart.
//!
//! Existe porque el servicio que da la temperatura del CPU en Windows necesita
//! privilegios de administrador para registrarse, y NexoDeck se puede instalar
//! **por usuario** --el modo por defecto del instalador-- sin pasar nunca por
//! una elevacion. En ese caso la temperatura no aparecia y nada lo explicaba.
//! Con esto la UI puede decir que falta y ofrecer instalarlo con un UAC unico.

/// En que estado esta el ayudante de sensores. Espejo de
/// `nexodeck_hardware::SensorHelperStatus`, por la regla de que el tipo del
/// dominio no cruza el bridge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensorHelperStatus {
    Running,
    Stopped,
    NotInstalled,
    Unsupported,
}

impl From<nexodeck_hardware::SensorHelperStatus> for SensorHelperStatus {
    fn from(status: nexodeck_hardware::SensorHelperStatus) -> Self {
        match status {
            nexodeck_hardware::SensorHelperStatus::Running => Self::Running,
            nexodeck_hardware::SensorHelperStatus::Stopped => Self::Stopped,
            nexodeck_hardware::SensorHelperStatus::NotInstalled => Self::NotInstalled,
            nexodeck_hardware::SensorHelperStatus::Unsupported => Self::Unsupported,
        }
    }
}

/// Estado actual del ayudante. Barato: consulta el administrador de servicios
/// en modo lectura, sin elevar.
pub fn sensor_helper_status() -> SensorHelperStatus {
    nexodeck_hardware::sensor_helper_status().into()
}

/// Lanza la instalacion del ayudante, que dispara un UAC.
///
/// Devuelve cuando el usuario ya respondio al dialogo, **no** cuando el
/// servicio quedo listo: quien llama tiene que volver a consultar el estado un
/// momento despues. Un `Err` incluye que el usuario haya cancelado el UAC, que
/// no es un fallo del programa sino una decision suya.
pub fn install_sensor_helper() -> Result<(), String> {
    nexodeck_hardware::install_sensor_helper()
}
