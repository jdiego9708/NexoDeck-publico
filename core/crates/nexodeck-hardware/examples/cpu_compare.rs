/// Imprime, una vez por segundo, el uso de CPU tal como lo calcula cada fuente,
/// para compararlo contra el Administrador de tareas **abierto al lado y en el
/// mismo momento**. Sin eso la comparacion no sirve: la carga cambia de un
/// segundo a otro mucho mas que la diferencia entre formulas.
///
/// Columnas:
/// - `snapshot`: lo que muestra hoy la app (`HardwareMonitor::snapshot`).
/// - `time`: `% Processor Time`, que en la practica es lo que calcula `sysinfo`.
/// - `utility`: `% Processor Utility`, recortado a 100 como lo recorta el
///   Administrador de tareas; entre parentesis el valor crudo.
/// - `perf` y `frecuencia`: `% Processor Performance` y la frecuencia actual
///   que sale de el.
#[cfg(target_os = "windows")]
fn main() {
    use std::time::Duration;

    use nexodeck_hardware::HardwareMonitor;
    use nexodeck_hardware::cpu_counters::CpuCounters;

    let seconds: u32 = std::env::args()
        .nth(1)
        .and_then(|arg| arg.parse().ok())
        .unwrap_or(30);

    let mut monitor = HardwareMonitor::new();
    let counters = CpuCounters::new().expect("PDH no pudo abrir los contadores de CPU");

    // La hora (epoch en ms) es para cruzar las filas con otra fuente que
    // tambien la guarde, como la tabla `hardware_history` de la app.
    println!(" seg |   epoch_ms    | snapshot |  time  |     utility      |  perf  | frecuencia");
    for second in 1..=seconds {
        std::thread::sleep(Duration::from_secs(1));
        let snapshot = monitor.snapshot();
        let epoch_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_millis());
        match counters.sample() {
            Some(sample) => println!(
                " {second:>3} | {epoch_ms} |  {:>5.1}%  | {:>5.1}% | {:>5.1}% ({:>5.1}%) | {:>5.1}% | {}",
                snapshot.cpu_usage,
                sample.processor_time,
                sample.processor_utility.min(100.0),
                sample.processor_utility,
                sample.performance_percent,
                sample
                    .current_mhz()
                    .map_or_else(|| "-".to_owned(), |mhz| format!("{:.2} GHz", mhz as f64 / 1000.0)),
            ),
            None => println!(" {second:>3} |  {:>5.1}%  | (sin muestra de PDH)", snapshot.cpu_usage),
        }
    }
}

#[cfg(not(target_os = "windows"))]
fn main() {
    eprintln!("cpu_compare solo tiene sentido en Windows: compara contra el Administrador de tareas.");
}
