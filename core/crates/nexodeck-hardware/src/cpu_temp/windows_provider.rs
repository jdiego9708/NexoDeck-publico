//! Lectura de los sensores que publica el sidecar propio de NexoDeck
//! (`sensors/NexoDeckSensors`), por named pipe.
//!
//! **Esto reemplazo al sondeo HTTP de LibreHardwareMonitor.** La version
//! anterior consultaba `http://127.0.0.1:8085/data.json`, o sea que la
//! temperatura del CPU solo aparecia si el usuario habia instalado LHM por su
//! cuenta y lo tenia abierto. Hoy el motor de sensores viaja dentro de
//! NexoDeck como un servicio de Windows que arranca con el sistema; el usuario
//! no abre nada, y si el servicio falta la app ofrece instalarlo.
//!
//! Lo que **no** cambio es el motivo de fondo: en Windows la temperatura del
//! CPU no se puede leer desde espacio de usuario (ver el encabezado de
//! `cpu_temp`), asi que sigue haciendo falta un driver de kernel. La
//! diferencia es de quien es la responsabilidad de tenerlo corriendo.
//!
//! Cosas que no son obvias:
//!
//! - **El sidecar corre elevado y NexoDeck no.** Por eso hablan por un named
//!   pipe con una ACL explicita del lado del sidecar: con la ACL por defecto
//!   el dueño seria el administrador y este proceso recibiria
//!   ACCESS_DENIED al abrirlo, con un sintoma identico al de "no esta
//!   corriendo".
//! - **No hay que lanzarlo**: es un servicio de Windows con arranque
//!   automatico, asi que ya esta corriendo antes que la app. Este modulo solo
//!   abre el pipe y reintenta. Quien se ocupa de que el servicio EXISTA es
//!   `sensor_helper`, que la UI consulta para ofrecer instalarlo.
//!
//!   La version anterior disparaba la tarea programada `NexoDeck-Sensors` con
//!   `schtasks /run`. Se saco junto con la tarea: una tarea solo corre con el
//!   usuario conectado, no se reinicia sola si el proceso muere, y su creacion
//!   dependia de que el instalador se hubiera corrido elevado -- una
//!   instalacion por usuario dejaba la temperatura muerta en silencio.
//! - **Un `0` no es una temperatura**, es "el driver no cargo". El sidecar ya
//!   lo filtra en el origen (ver `MinPlausibleC` en su `Program.cs`), pero el
//!   rango se vuelve a comprobar aca: el que dibuja el badge es este lado.
//! - **Cual de los sensores gana lo decide `super::label_priority`**, la misma
//!   funcion que usa la ruta de Linux. El sidecar manda la lista completa
//!   justamente para no tener esa decision escrita dos veces.
//!
//! Vive en un hilo propio y no en la ruta de `snapshot()` porque el snapshot
//! se toma una vez por segundo y no puede quedarse esperando a un pipe.

use std::io::{BufRead, BufReader};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::Value;

/// Tiene que coincidir con `PipeName` en `sensors/NexoDeckSensors/Program.cs`.
const PIPE_PATH: &str = r"\\.\pipe\nexodeck-sensors";

/// Cada cuanto se reintenta abrir el pipe cuando no esta. Espaciado a
/// proposito: lo normal en una maquina sin el sidecar instalado es que no
/// aparezca nunca, y reintentar seguido solo quema CPU. Que exista el
/// reintento es lo que hace que la temperatura aparezca sola si el sidecar
/// arranca despues, sin reiniciar la app.
const RETRY_INTERVAL: Duration = Duration::from_secs(30);

/// Granularidad con la que el hilo mira la bandera de parada. Dormir los 30 s
/// de una haria que cerrar la app se quede esperando al hilo.
const STOP_CHECK_STEP: Duration = Duration::from_millis(250);

/// Rango en el que una lectura se acepta. Ver la nota del encabezado sobre el
/// `0` que devuelve la libreria cuando el driver no cargo.
const PLAUSIBLE_RANGE_C: std::ops::RangeInclusive<f32> = 1.0..=150.0;

pub(crate) struct SensorProvider {
    last: Arc<Mutex<Option<f32>>>,
    stop: Arc<AtomicBool>,
}

impl SensorProvider {
    pub(crate) fn start() -> Self {
        let last = Arc::new(Mutex::new(None));
        let stop = Arc::new(AtomicBool::new(false));

        let thread_last = Arc::clone(&last);
        let thread_stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("nexodeck-cpu-temp".to_owned())
            .spawn(move || poll_loop(&thread_last, &thread_stop))
            // Que no se pueda crear el hilo no puede tumbar el monitor entero:
            // sin el, la temperatura queda en `None` igual que en una maquina
            // sin sensores.
            .ok();

        Self { last, stop }
    }

    pub(crate) fn last_value(&self) -> Option<f32> {
        // `lock()` solo falla si otro hilo panickeo con el mutex tomado; ahi
        // tambien preferimos `None` a propagar el panic al stream de metricas.
        self.last.lock().map(|value| *value).unwrap_or(None)
    }
}

impl Drop for SensorProvider {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn poll_loop(last: &Arc<Mutex<Option<f32>>>, stop: &Arc<AtomicBool>) {
    while !stop.load(Ordering::Relaxed) {
        if let Some(pipe) = open_pipe() {
            consume(pipe, last, stop);
        }

        // Se llega aca porque el pipe no estaba (el servicio no esta
        // instalado, o esta detenido) o porque se corto. En los dos casos la
        // lectura deja de ser valida: se borra en vez de quedar clavada en el
        // ultimo valor.
        if let Ok(mut slot) = last.lock() {
            *slot = None;
        }
        sleep_interruptible(RETRY_INTERVAL, stop);
    }
}

/// Abre el pipe del sidecar. `None` cuando no esta corriendo (el caso normal
/// en una maquina donde el sidecar no se instalo) o cuando la ACL no deja
/// -- las dos cosas degradan igual, a "sin temperatura".
fn open_pipe() -> Option<std::fs::File> {
    std::fs::OpenOptions::new().read(true).open(PIPE_PATH).ok()
}

/// Lee lineas hasta que el pipe se corta o alguien pide parar.
///
/// `BufReader::lines()` exige UTF-8 valido, que es justo lo que hizo perder
/// tiempo en `nexodeck-actions` con la salida de una consola en cp850. Aca es
/// seguro porque el emisor es nuestro: `System.Text.Json` escapa todo lo no
/// ASCII a `\uXXXX`, asi que la linea siempre es ASCII puro. Aun asi, un `Err`
/// corta el bucle en vez de ignorarse -- que es exactamente lo que faltaba en
/// aquel caso.
fn consume(pipe: std::fs::File, last: &Arc<Mutex<Option<f32>>>, stop: &Arc<AtomicBool>) {
    for line in BufReader::new(pipe).lines() {
        if stop.load(Ordering::Relaxed) {
            return;
        }
        let Ok(line) = line else { return };
        let reading = cpu_temperature_from_line(&line);
        if let Ok(mut slot) = last.lock() {
            // Se escribe siempre, tambien el `None`: una linea sin ningun
            // sensor plausible tiene que borrar el badge, no dejarlo clavado.
            *slot = reading;
        }
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

/// La mejor temperatura de CPU dentro de una linea del sidecar.
///
/// Pura y separada de la lectura del pipe para poder testearla con lineas
/// grabadas: que sensor se elige es lo que decide si el numero que ve el
/// usuario es el correcto, y es el unico pedazo de este modulo que se puede
/// ejercitar sin el sidecar corriendo elevado.
pub(crate) fn cpu_temperature_from_line(line: &str) -> Option<f32> {
    let body: Value = serde_json::from_str(line).ok()?;
    best_temperature(body.get("cpuTemps")?.as_array()?)
}

/// Gana el sensor de menor `label_priority` -- Tctl/Tdie por encima de
/// package, y descarte de lo que seguro no es el CPU. Es la MISMA funcion que
/// rankea los sensores que llegan por sysfs en Linux.
fn best_temperature(readings: &[Value]) -> Option<f32> {
    readings
        .iter()
        .filter_map(|reading| {
            let label = reading.get("label")?.as_str()?;
            let value = reading.get("valueC")?.as_f64()? as f32;
            if !PLAUSIBLE_RANGE_C.contains(&value) {
                return None;
            }
            let priority = super::label_priority(label)?;
            Some((priority, value))
        })
        // Mismo desempate que `from_components`, y por el mismo motivo: dos
        // sensores pueden compartir prioridad (un Ryzen de dos CCD expone
        // `CCD1` y `CCD2`), y ahi el orden de la lista no puede ser quien
        // decida. `total_cmp` y no `partial_cmp`: un NaN haria panickear a un
        // comparador que devuelva `Ordering` a la fuerza.
        .min_by(|a, b| a.0.cmp(&b.0).then(a.1.total_cmp(&b.1)))
        .map(|(_, value)| value)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// La linea real que emite el sidecar en el equipo principal.
    #[test]
    fn elige_tctl_sobre_los_demas_sensores() {
        let line = r#"{"cpuTemps":[
            {"label":"Core Max","valueC":64.0},
            {"label":"Core (Tctl/Tdie)","valueC":61.5},
            {"label":"Core Average","valueC":58.2}
        ]}"#;
        assert_eq!(cpu_temperature_from_line(line), Some(61.5));
    }

    /// Los dos sensores que expone de verdad el Ryzen 7 5700X del equipo
    /// principal. Gana el control del paquete, no el die suelto -- y el orden
    /// en que vengan no puede cambiarlo.
    #[test]
    fn el_control_del_paquete_le_gana_al_ccd() {
        let ordenados = r#"{"cpuTemps":[
            {"label":"Core (Tctl/Tdie)","valueC":53.1},
            {"label":"CCD1 (Tdie)","valueC":58.2}
        ]}"#;
        let al_reves = r#"{"cpuTemps":[
            {"label":"CCD1 (Tdie)","valueC":58.2},
            {"label":"Core (Tctl/Tdie)","valueC":53.1}
        ]}"#;
        assert_eq!(cpu_temperature_from_line(ordenados), Some(53.1));
        assert_eq!(cpu_temperature_from_line(al_reves), Some(53.1));
    }

    /// Un Ryzen de dos CCD: las dos etiquetas comparten prioridad, asi que el
    /// desempate no puede depender del orden de la lista.
    #[test]
    fn con_dos_ccd_el_desempate_es_estable() {
        let ordenados = r#"{"cpuTemps":[
            {"label":"CCD1 (Tdie)","valueC":61.0},
            {"label":"CCD2 (Tdie)","valueC":57.0}
        ]}"#;
        let al_reves = r#"{"cpuTemps":[
            {"label":"CCD2 (Tdie)","valueC":57.0},
            {"label":"CCD1 (Tdie)","valueC":61.0}
        ]}"#;
        assert_eq!(
            cpu_temperature_from_line(ordenados),
            cpu_temperature_from_line(al_reves)
        );
    }

    /// El caso que motiva el filtro: sin elevar, la libreria enumera el sensor
    /// pero devuelve 0. El sidecar ya lo descarta, y aca se vuelve a descartar
    /// porque es este lado el que dibuja el badge.
    #[test]
    fn un_cero_no_es_una_temperatura() {
        let line = r#"{"cpuTemps":[{"label":"Core (Tctl/Tdie)","valueC":0}]}"#;
        assert_eq!(cpu_temperature_from_line(line), None);
    }

    #[test]
    fn una_lista_vacia_no_da_temperatura() {
        assert_eq!(cpu_temperature_from_line(r#"{"cpuTemps":[]}"#), None);
    }

    /// Una linea que no es el JSON esperado no puede panickear el hilo.
    #[test]
    fn una_linea_rota_degrada_a_none() {
        assert_eq!(cpu_temperature_from_line("no soy json"), None);
        assert_eq!(cpu_temperature_from_line("{}"), None);
        assert_eq!(cpu_temperature_from_line(r#"{"cpuTemps":"no es lista"}"#), None);
        assert_eq!(
            cpu_temperature_from_line(r#"{"cpuTemps":[{"label":"Core"}]}"#),
            None
        );
    }

    /// Mismo criterio que la ruta de sysfs: un sensor que seguro no es el CPU
    /// no puede colarse como si lo fuera.
    #[test]
    fn descarta_los_sensores_que_no_son_del_cpu() {
        let line = r#"{"cpuTemps":[{"label":"GPU Core","valueC":70.0}]}"#;
        assert_eq!(cpu_temperature_from_line(line), None);
    }
}
