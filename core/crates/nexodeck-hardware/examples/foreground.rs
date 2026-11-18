//! Imprime la aplicacion en primer plano una vez por segundo.
//!
//! Es la unica forma de comprobar la auto-deteccion de perfiles sin la app:
//! se corre esto, se va cambiando de ventana a mano (Alt+Tab, abrir OBS,
//! volver a la terminal) y se mira si el nombre sigue al foco.
//!
//! `cargo run -p nexodeck-hardware --example foreground`

use std::thread::sleep;
use std::time::Duration;

use nexodeck_hardware::ForegroundWatcher;

fn main() {
    let mut watcher = ForegroundWatcher::new();
    println!("Cambia de ventana para ver como sigue el foco. Ctrl+C para salir.\n");

    let mut last = String::new();
    for i in 1..=30 {
        let current = match watcher.current() {
            Some(app) => format!("{} (pid {})", app.process_name, app.pid),
            None => "(sin ventana en foco)".to_string(),
        };
        // Se marca el cambio: leer 30 lineas iguales no dice nada, lo que
        // interesa es que el valor SIGA al foco.
        let marker = if current == last { " " } else { "*" };
        println!("{i:>2} {marker} {current}");
        last = current;
        sleep(Duration::from_secs(1));
    }
}
