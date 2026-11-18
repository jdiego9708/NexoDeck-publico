//! Control del Ollama que el usuario ya tiene instalado en el equipo.
//!
//! A diferencia del sidecar (que es un proceso hijo nuestro), Ollama es del
//! usuario: puede estar arrancado por su cuenta, por la bandeja del sistema o
//! por el arranque de Windows. Este modulo permite **encenderlo y apagarlo**
//! desde NexoDeck sin cambiar esa naturaleza.
//!
//! Decision de diseno (23-sep-2026): se controla **la instalacion del
//! usuario**, no un Ollama propio de NexoDeck. Es lo que pidio el usuario, y la
//! contracara es que apagarlo desde aqui apaga el Ollama de toda la maquina, no
//! solo el de NexoDeck. La UI lo dice al lado del interruptor.
//!
//! Lo que NO se hace aca, a proposito:
//! - No se toca el proveedor del chat: encender Ollama no elige Ollama como
//!   destino (eso sigue siendo `use_ollama`).
//! - No se ata el proceso a un Job Object. Un `ollama serve` lanzado desde
//!   aqui sobrevive al cierre de NexoDeck, igual que si lo hubiera arrancado el
//!   usuario: es un servicio de la maquina, no un hijo de la app.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::{Duration, Instant};

use tokio::process::Command;

use crate::error::{AiError, AiResult};
use crate::provider::detect_ollama;

/// Cuanto se espera a que Ollama responda tras pedirle que arranque. Cargar
/// los pesos de un modelo no hace falta: `/v1/models` contesta antes, y lo que
/// aqui se comprueba es que el servidor esta en pie.
const START_TIMEOUT: Duration = Duration::from_secs(20);

/// Cuanto se espera a que el proceso muera tras pedirle que pare.
const STOP_TIMEOUT: Duration = Duration::from_secs(10);

const POLL_INTERVAL: Duration = Duration::from_millis(500);

/// Estado de Ollama en este equipo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OllamaStatus {
    /// Responde en `127.0.0.1:11434`.
    pub running: bool,
    /// Ruta del ejecutable, si se encontro la instalacion. `None` significa
    /// que no hay Ollama instalado (o que no se pudo localizar).
    pub binary: Option<PathBuf>,
}

/// Nombre del ejecutable segun la plataforma.
fn binary_name() -> &'static str {
    if cfg!(windows) { "ollama.exe" } else { "ollama" }
}

/// Localiza el ejecutable de Ollama.
///
/// Se miran primero las rutas de instalacion tipicas y despues el `PATH`. No
/// se busca en el registro ni se enumeran servicios: alcanza con saber donde
/// esta el binario para lanzarlo, y la deteccion de "esta corriendo" la hace
/// `detect_ollama` por HTTP, que no depende de esta ruta.
pub fn find_binary() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            let candidate = PathBuf::from(local)
                .join("Programs")
                .join("Ollama")
                .join("ollama.exe");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        if let Some(program_files) = std::env::var_os("ProgramFiles") {
            let candidate = PathBuf::from(program_files)
                .join("Ollama")
                .join("ollama.exe");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        for candidate in ["/usr/local/bin/ollama", "/usr/bin/ollama", "/bin/ollama"] {
            let path = PathBuf::from(candidate);
            if path.is_file() {
                return Some(path);
            }
        }
    }

    let name = binary_name();
    let path_var = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path_var) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Estado actual: si responde y si hay binario para poder arrancarlo.
pub async fn status() -> AiResult<OllamaStatus> {
    let running = detect_ollama().await?.is_some();
    Ok(OllamaStatus {
        running,
        binary: find_binary(),
    })
}

/// Enciende Ollama si no esta corriendo.
///
/// Si ya responde, no hace nada: encender lo encendido no es un error. Si no
/// hay binario, devuelve `OllamaNotFound` para que la UI diga "no se encontro
/// Ollama" en vez de un fallo generico.
pub async fn start() -> AiResult<OllamaStatus> {
    if detect_ollama().await?.is_some() {
        return Ok(OllamaStatus {
            running: true,
            binary: find_binary(),
        });
    }

    let binary = find_binary().ok_or(AiError::OllamaNotFound)?;

    let mut command = Command::new(&binary);
    command
        .arg("serve")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    apply_platform_flags(&mut command);

    // Sin `kill_on_drop`: el proceso queda desacoplado y sobrevive al cierre de
    // NexoDeck, que es justo lo que se quiere de un servicio de la maquina.
    command.spawn().map_err(|e| AiError::SpawnOllama {
        path: binary,
        detail: e.to_string(),
    })?;

    let started = Instant::now();
    while started.elapsed() < START_TIMEOUT {
        if detect_ollama().await?.is_some() {
            return Ok(OllamaStatus {
                running: true,
                binary: find_binary(),
            });
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    Err(AiError::OllamaNeverReady {
        waited_secs: START_TIMEOUT.as_secs(),
    })
}

/// Apaga Ollama si esta corriendo.
///
/// **Apaga el Ollama de toda la maquina**, no solo el de NexoDeck: es la
/// contracara de controlar la instalacion del usuario. Se matan tanto el
/// servidor (`ollama.exe`) como la aplicacion de bandeja (`ollama app.exe`),
/// porque la bandeja puede volver a levantar el servidor si se deja viva.
pub async fn stop() -> AiResult<OllamaStatus> {
    if detect_ollama().await?.is_none() {
        return Ok(OllamaStatus {
            running: false,
            binary: find_binary(),
        });
    }

    kill_processes().await;

    let started = Instant::now();
    while started.elapsed() < STOP_TIMEOUT {
        if detect_ollama().await?.is_none() {
            return Ok(OllamaStatus {
                running: false,
                binary: find_binary(),
            });
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }

    Err(AiError::OllamaNeverStopped {
        waited_secs: STOP_TIMEOUT.as_secs(),
    })
}

/// Termina los procesos de Ollama. Un fallo se ignora a proposito: si el
/// proceso no existia, `taskkill`/`pkill` devuelven distinto de cero y eso no
/// es un problema (lo que importa es el estado que se comprueba despues).
#[cfg(target_os = "windows")]
async fn kill_processes() {
    for image in ["ollama.exe", "ollama app.exe"] {
        let mut command = Command::new("taskkill");
        command
            .arg("/F")
            .arg("/IM")
            .arg(image)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        apply_platform_flags(&mut command);
        let _ = command.status().await;
    }
}

#[cfg(not(target_os = "windows"))]
async fn kill_processes() {
    let mut command = Command::new("pkill");
    command
        .arg("-f")
        .arg("ollama serve")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let _ = command.status().await;
}

#[cfg(target_os = "windows")]
fn apply_platform_flags(command: &mut Command) {
    // Mismo valor que `sidecar.rs`: sin esto aparece una consola negra.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(target_os = "windows"))]
fn apply_platform_flags(_command: &mut Command) {}

#[cfg(test)]
mod tests {
    use super::*;

    /// La busqueda del binario nunca puede reventar, tenga o no Ollama
    /// instalado el equipo: devuelve `None` cuando no lo encuentra.
    #[test]
    fn find_binary_no_falla_sin_ollama() {
        let _ = find_binary();
    }

    /// Sin Ollama corriendo, el estado tiene que poder consultarse igual: no
    /// tenerlo instalado es el caso normal, no un error.
    #[tokio::test]
    async fn status_no_falla_cuando_no_esta() {
        let result = status().await;
        assert!(result.is_ok(), "consultar el estado nunca puede devolver Err");
    }
}
