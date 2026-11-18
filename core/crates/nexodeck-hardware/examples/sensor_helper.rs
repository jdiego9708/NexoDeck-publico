//! Estado del servicio de sensores, sin la app de por medio.
//!
//! Es la forma rapida de distinguir los tres casos que la UI tiene que saber
//! comunicar: no instalado (instalacion por usuario), instalado pero detenido,
//! y corriendo. Con `--install` dispara el UAC de instalacion.

fn main() {
    let status = nexodeck_hardware::sensor_helper_status();
    println!("estado del ayudante de sensores: {status:?}");

    if std::env::args().any(|argument| argument == "--install") {
        println!("lanzando el instalador (va a pedir permiso de administrador)...");
        match nexodeck_hardware::install_sensor_helper() {
            Ok(()) => println!("el usuario acepto; consultando de nuevo en 8 s"),
            Err(error) => {
                println!("no se instalo: {error}");
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_secs(8));
        println!("estado ahora: {:?}", nexodeck_hardware::sensor_helper_status());
    }
}
