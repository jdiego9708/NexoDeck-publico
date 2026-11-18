//! Dispositivos Android conectados, via `adb devices -l`.
//!
//! Existe por el segundo caso del brief: "que corra mi app en modo debug en el
//! dispositivo Android que tenga disponible". Sin esta herramienta el modelo
//! escribe `flutter run -d android` o inventa un serial, y el boton falla la
//! primera vez que se toca.
//!
//! Correr `adb devices` es de solo lectura: enumera, no toca el telefono.

use std::process::Stdio;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::openai::types::ToolDef;
use crate::tools::{Tool, ToolContext};

const ADB_TIMEOUT: Duration = Duration::from_secs(10);

pub struct ListAndroidDevices;

impl Tool for ListAndroidDevices {
    fn name(&self) -> &'static str {
        "list_android_devices"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "list_android_devices",
            "Lista los dispositivos Android conectados por USB, con su numero de serie y modelo. \
             Llamala SIEMPRE antes de proponer un comando que use 'flutter run -d' o 'adb': \
             hay que usar el serial real, no un placeholder.",
            json!({ "type": "object", "properties": {} }),
        )
    }

    fn call(&self, _args: &Value, ctx: &ToolContext) -> Value {
        if which::which("adb").is_err() {
            ctx.with_facts(|facts| {
                facts.listed_android_devices = true;
                facts.missing_executables.insert("adb".into());
            });
            return json!({
                "ok": true,
                "adb_available": false,
                "devices": [],
                "hint": "adb no esta instalado. Sin adb no se puede saber que telefono hay conectado: \
                         avisale al usuario antes de proponer un comando con '-d <serial>'."
            });
        }

        let Some(output) = run_adb_devices() else {
            ctx.with_facts(|facts| facts.listed_android_devices = true);
            return json!({
                "ok": true,
                "adb_available": true,
                "devices": [],
                "hint": "adb esta instalado pero no respondio. Preguntale al usuario si el telefono \
                         esta conectado y con depuracion USB activada."
            });
        };

        let devices = parse_adb_devices(&output);

        ctx.with_facts(|facts| {
            facts.listed_android_devices = true;
            facts.android_serials = devices.iter().map(|d| d.serial.clone()).collect();
        });

        if devices.is_empty() {
            return json!({
                "ok": true,
                "adb_available": true,
                "devices": [],
                "hint": "No hay ningun dispositivo Android conectado y autorizado. Preguntale al usuario \
                         si quiere el boton igual (usando un parametro para el serial) o si va a conectar el telefono."
            });
        }

        json!({
            "ok": true,
            "adb_available": true,
            "devices": devices.iter().map(|device| json!({
                "serial": device.serial,
                "state": device.state,
                "model": device.model,
            })).collect::<Vec<_>>()
        })
    }
}

#[derive(Debug, PartialEq)]
struct AndroidDevice {
    serial: String,
    state: String,
    model: Option<String>,
}

fn run_adb_devices() -> Option<String> {
    let mut command = std::process::Command::new("adb");
    command
        .args(["devices", "-l"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command.spawn().ok()?;
    let started = Instant::now();

    // `adb devices` puede quedarse esperando al arrancar el servidor.
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if started.elapsed() >= ADB_TIMEOUT => {
                let _ = child.kill();
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(50)),
            Err(_) => return None,
        }
    }

    let output = child.wait_with_output().ok()?;
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Parsea la salida de `adb devices -l`.
///
/// Formato:
/// ```text
/// List of devices attached
/// R5CT30ABCDE            device usb:1-4 product:e1q model:SM_S928B device:e1q
/// emulator-5554          offline
/// ```
///
/// Se descarta todo lo que no este en estado `device`: un `unauthorized` o un
/// `offline` no sirve para `flutter run` y ofrecerlo produce un boton que falla.
fn parse_adb_devices(output: &str) -> Vec<AndroidDevice> {
    output
        .lines()
        .skip_while(|line| !line.contains("List of devices"))
        .skip(1)
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() {
                return None;
            }

            let mut parts = line.split_whitespace();
            let serial = parts.next()?.to_string();
            let state = parts.next()?.to_string();

            if state != "device" {
                return None;
            }

            let model = parts
                .find_map(|part| part.strip_prefix("model:"))
                .map(|model| model.replace('_', " "));

            Some(AndroidDevice {
                serial,
                state,
                model,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn parsea_la_salida_real_de_adb_devices() {
        let output = "List of devices attached\r\n\
                      R5CT30ABCDE            device usb:1-4 product:e1q model:SM_S928B device:e1q transport_id:3\r\n\
                      \r\n";

        let devices = parse_adb_devices(output);
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].serial, "R5CT30ABCDE");
        assert_eq!(devices[0].model.as_deref(), Some("SM S928B"));
    }

    /// Un telefono sin autorizar no sirve para `flutter run`: ofrecerlo
    /// produciria un boton que falla la primera vez que se toca.
    #[test]
    fn los_dispositivos_no_autorizados_o_desconectados_se_descartan() {
        let output = "List of devices attached\n\
                      ABC123      unauthorized\n\
                      emulator-5554  offline\n\
                      DEF456      device model:Pixel_7\n";

        let devices = parse_adb_devices(output);
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].serial, "DEF456");
    }

    #[test]
    fn sin_dispositivos_devuelve_una_lista_vacia() {
        assert!(parse_adb_devices("List of devices attached\n\n").is_empty());
        assert!(parse_adb_devices("").is_empty());
    }

    /// Sin adb la herramienta no falla: informa, y el `hint` empuja a preguntar
    /// en vez de inventar un serial.
    #[test]
    fn la_herramienta_siempre_marca_que_se_consulto_aunque_no_haya_adb() {
        let ctx = ToolContext::new(
            vec![PathBuf::from(std::env::temp_dir())],
            nexodeck_hardware::HostOs::Windows,
        );

        let result = ListAndroidDevices.call(&json!({}), &ctx);

        assert_eq!(result["ok"], true);
        assert!(
            ctx.with_facts(|facts| facts.listed_android_devices),
            "el gate de propose_action depende de esta marca"
        );
    }
}
