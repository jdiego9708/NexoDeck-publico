use nexodeck_hardware::{DiskMediaKind, HardwareMonitor};

/// Imprime varias muestras seguidas, al mismo ritmo (1 s) que usa la app,
/// para poder comparar `cpu_usage` contra el Administrador de tareas de
/// Windows con el monitor abierto al lado. Una sola muestra no sirve: la
/// primera se toma sobre una ventana casi nula respecto de la linea base
/// que fija `HardwareMonitor::new()`.
///
/// Al final lista los discos que quedaron dentro del inventario, que es la
/// forma rapida de verificar el filtro de volumenes de nube/red de
/// `disks.rs` en una maquina concreta: si aparece una unidad de Google Drive
/// o un recurso de red, el filtro no la esta agarrando.
///
/// La columna de temperatura de esa lista sale del hilo de `disk_temp`, que
/// sondea cada 30 s: en la primera muestra puede estar vacia y llenarse en
/// las siguientes. Dos letras del mismo disco fisico comparten el numero.
fn main() {
    let mut monitor = HardwareMonitor::new();

    for i in 1..=10 {
        std::thread::sleep(std::time::Duration::from_secs(1));
        let snapshot = monitor.snapshot();
        println!(
            "[{i:>2}] cpu {:>5.1}%  {:>5} MHz  {:>5}  |  ram {:.0}/{:.0} MB  |  gpu {:>5} {:>11}",
            snapshot.cpu_usage,
            snapshot
                .cpu_freq_mhz
                .map_or_else(|| "-".to_owned(), |f| f.to_string()),
            snapshot
                .cpu_temp
                .map_or_else(|| "-".to_owned(), |t| format!("{t:.0}C")),
            snapshot.ram_used_mb,
            snapshot.ram_total_mb,
            snapshot
                .gpu_usage
                .map_or_else(|| "-".to_owned(), |g| format!("{g:.0}%")),
            // Watts contra el techo, que es como los muestra la app: el
            // numero suelto no dice si la tarjeta esta holgada o al limite.
            match (snapshot.gpu_power_watts, snapshot.gpu_power_limit_watts) {
                (Some(watts), Some(limit)) => format!("{watts:.0}/{limit:.0} W"),
                (Some(watts), None) => format!("{watts:.0} W"),
                _ => "-".to_owned(),
            },
        );
    }

    let snapshot = monitor.snapshot();
    println!(
        "\nDiscos ({}), total {:.1}/{:.1} GB:",
        snapshot.disks.len(),
        snapshot.disk_used_mb / 1024.0,
        snapshot.disk_total_mb / 1024.0,
    );
    for disk in &snapshot.disks {
        println!(
            "  {:<6} {:<8} {:>7.1}/{:>7.1} GB  {:>5}  {}",
            disk.mount_point,
            match disk.kind {
                DiskMediaKind::Ssd => "SSD",
                DiskMediaKind::Hdd => "HDD",
                DiskMediaKind::Unknown => "?",
            },
            disk.used_mb / 1024.0,
            disk.total_mb / 1024.0,
            disk.temp_c
                .map_or_else(|| "-".to_owned(), |t| format!("{t:.0}C")),
            disk.label,
        );
    }
}
