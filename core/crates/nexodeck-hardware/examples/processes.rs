use std::time::Instant;

use nexodeck_hardware::processes::{self, ProcessCollector, TopProcesses};

/// Imprime las tres listas de procesos al mismo ritmo que la app, para
/// compararlas contra el Administrador de tareas abierto al lado.
///
/// Dos cosas que hay que mirar y que no se pueden afirmar en un test:
///
/// - **El costo de cada muestra**, que se imprime en ms. Es lo que decide si
///   la cadencia de 2 s es sostenible: un recorrido de ~400 procesos no es
///   gratis, y este panel corre mientras el usuario lo tenga abierto.
/// - **La columna de RAM contra la pestana Detalles**, no contra Procesos:
///   `Process::memory()` es el working set, que no es el mismo numero que la
///   pestana Procesos muestra como "Memoria".
///
/// Uso:
///   cargo run -p nexodeck-hardware --example processes
///   cargo run -p nexodeck-hardware --example processes -- --kill notepad.exe
///   cargo run -p nexodeck-hardware --example processes -- --details chrome.exe
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(index) = args.iter().position(|arg| arg == "--kill") {
        let Some(name) = args.get(index + 1) else {
            eprintln!("--kill necesita el nombre del proceso");
            return;
        };
        kill_by_name(name);
        return;
    }
    if let Some(index) = args.iter().position(|arg| arg == "--details") {
        let Some(name) = args.get(index + 1) else {
            eprintln!("--details necesita el nombre del proceso");
            return;
        };
        print_details(name);
        return;
    }

    let mut collector = ProcessCollector::new();
    println!(
        "Muestras cada {:?} (primera a los {:?}). Ctrl+C para salir.\n",
        processes::SAMPLE_INTERVAL,
        processes::FIRST_SAMPLE_DELAY
    );
    std::thread::sleep(processes::FIRST_SAMPLE_DELAY);

    for round in 1..=10 {
        let started = Instant::now();
        let sample = collector.sample();
        let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;

        println!(
            "===== muestra {round} — {} procesos en {elapsed_ms:.0} ms =====",
            sample.sampled_process_count
        );
        print_list("CPU", &sample, |group| {
            format!("{:>5.1}%", group.cpu_percent)
        });
        print_list("RAM", &sample, |group| {
            format!("{:>7.0} MB", group.memory_mb)
        });
        if sample.gpu_available {
            print_list("GPU", &sample, |group| {
                format!("{:>5.1}%", group.gpu_percent.unwrap_or(0.0))
            });
        } else {
            println!("\n  GPU: esta maquina no informa uso por proceso");
        }
        println!();

        std::thread::sleep(processes::SAMPLE_INTERVAL);
    }
}

fn print_list<F>(title: &str, sample: &TopProcesses, value: F)
where
    F: Fn(&nexodeck_hardware::ProcessGroup) -> String,
{
    let list = match title {
        "CPU" => &sample.by_cpu,
        "RAM" => &sample.by_memory,
        _ => &sample.by_gpu,
    };

    println!("\n  -- {title} --");
    if list.is_empty() {
        println!("     (nadie)");
        return;
    }
    for group in list.iter().take(6) {
        let procesos = if group.pids.len() > 1 {
            format!("({:>2})", group.pids.len())
        } else {
            "    ".to_owned()
        };
        println!(
            "     {:<28} {} {}  {}",
            truncate(&group.name, 28),
            procesos,
            value(group),
            format_run_time(group.run_time_secs),
        );
    }
}

fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_owned();
    }
    text.chars().take(max - 1).collect::<String>() + "…"
}

fn format_run_time(secs: u32) -> String {
    match secs {
        0 => "—".to_owned(),
        s if s < 60 => format!("{s} s"),
        s if s < 3600 => format!("{} min", s / 60),
        s if s < 86400 => format!("{} h {} min", s / 3600, (s % 3600) / 60),
        s => format!("{} d {} h", s / 86400, (s % 86400) / 3600),
    }
}

/// Prueba la terminacion sin la app de por medio. Pensado para un
/// `notepad.exe` abierto a proposito, y para comprobar que un nombre
/// protegido se rechaza sin tocar nada.
///
/// Busca en **toda** la tabla de procesos y no solo en el top: un notepad de
/// prueba no consume lo suficiente como para entrar en ninguna de las tres
/// listas, que es justo lo que lo hace un buen conejillo de indias.
fn kill_by_name(name: &str) {
    use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing(),
    );

    let pids: Vec<u32> = system
        .processes()
        .iter()
        .filter(|(_, process)| {
            process.name().to_string_lossy().eq_ignore_ascii_case(name)
        })
        .map(|(pid, _)| pid.as_u32())
        .collect();

    if pids.is_empty() {
        println!("No hay ningun proceso llamado «{name}».");
        return;
    }

    println!("Cerrando «{name}» ({} procesos)...", pids.len());
    match processes::terminate_process_group(name, &pids) {
        Ok(report) => println!(
            "  pedidos {} · cerrados {} · fallaron {} · ya no estaban {}",
            report.requested, report.killed, report.failed, report.gone
        ),
        Err(error) => println!("  rechazado: {error}"),
    }
}

/// El detalle que le hace falta a la IA (`process_details`), contra un
/// proceso real -- para verificar el proceso padre, la linea de comando, el
/// ejecutable y el dueno sin pasar por la app entera. Mismo criterio que
/// `kill_by_name`: busca en toda la tabla, no solo en el top.
fn print_details(name: &str) {
    use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing(),
    );

    let pids: Vec<u32> = system
        .processes()
        .iter()
        .filter(|(_, process)| {
            process.name().to_string_lossy().eq_ignore_ascii_case(name)
        })
        .map(|(pid, _)| pid.as_u32())
        .collect();

    if pids.is_empty() {
        println!("No hay ningun proceso llamado «{name}».");
        return;
    }

    match processes::process_details(name, &pids) {
        Some(details) => {
            println!("pid representativo: {}", details.pid);
            println!(
                "lanzado por: {}",
                details.parent_name.as_deref().unwrap_or("(desconocido)")
            );
            println!(
                "linea de comando: {}",
                details.command_line.as_deref().unwrap_or("(sin datos)")
            );
            println!(
                "ejecutable: {}",
                details.exe_path.as_deref().unwrap_or("(sin datos)")
            );
            println!("dueno: {}", details.owner.as_deref().unwrap_or("(sin datos)"));
        }
        None => println!("Ninguno de los pids de «{name}» sigue vivo con ese nombre."),
    }
}
