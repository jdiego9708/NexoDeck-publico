use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::ActionError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalType {
    /// cmd.exe en Windows, `$SHELL` (o `sh`) en Linux.
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

/// Corre `command`. Si `show_window` es `true`, se abre una ventana de
/// terminal nueva y visible (util para comandos cuya salida el usuario
/// quiere ver, ej. `git status`); si es `false`, corre sin ninguna ventana
/// (para acciones tipo "abrir una app" -- lanzar `notepad.exe` no necesita
/// mostrar la consola intermedia que lo lanzo). Si `requires_admin` es
/// `true` en Windows, dispara el prompt de UAC -- esa ruta no se puede
/// verificar de punta a punta en un entorno sin interaccion humana (alguien
/// tiene que hacer clic en "Si"), a diferencia de la ruta sin admin, que se
/// puede probar viendo la ventana abrirse (o confirmando que el proceso
/// lanzado existe, cuando `show_window` es `false`).
pub fn run_in_terminal(
    command: &str,
    terminal_type: TerminalType,
    requires_admin: bool,
    show_window: bool,
) -> Result<(), ActionError> {
    #[cfg(target_os = "windows")]
    {
        windows::run(command, terminal_type, requires_admin, show_window)
    }
    #[cfg(target_os = "linux")]
    {
        linux::run(command, terminal_type, requires_admin, show_window)
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = (command, terminal_type, requires_admin, show_window);
        Err(ActionError::UnsupportedPlatform)
    }
}

/// Nombre de archivo unico para el script temporal -- evita colisiones si
/// el usuario dispara la misma accion varias veces seguidas.
pub(crate) fn unique_suffix() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{nanos}_{n}")
}

/// Escribe el comando a un script temporal y devuelve su ruta.
///
/// Existe porque `cmd.exe` interpreta `&`, `|`, `%`, comillas, etc. de forma
/// muy quisquillosa cuando el comando va inline como argumento; un archivo
/// evita por completo ese problema de escaping. Lo comparten el modo ventana
/// (este archivo) y el modo capturado (`runner.rs`).
///
/// `redirect_to` solo lo usa la ruta **elevada** del runner: un proceso que
/// pasa por UAC no se puede piped desde el padre, asi que la redireccion se
/// mete adentro del propio script. Ver `runner::spawn_elevated`.
pub(crate) fn write_script(
    command: &str,
    terminal_type: TerminalType,
    redirect_to: Option<&std::path::Path>,
) -> Result<PathBuf, ActionError> {
    let dir = std::env::temp_dir();
    let suffix = unique_suffix();

    let (name, contents) = match terminal_type {
        TerminalType::PowerShell => {
            // El preambulo fuerza UTF-8 en la salida. Sin esto la consola
            // entrega cp850/cp1252 y cualquier tilde llega como basura al
            // modo capturado (`runner.rs`). `SilentlyContinue` saca las
            // barras de progreso, que en un pipe son ruido puro.
            let head = "$ProgressPreference = 'SilentlyContinue'\r\n\
                        [Console]::OutputEncoding = \
                        New-Object System.Text.UTF8Encoding $false\r\n";
            let body = match redirect_to {
                // `*>` redirige TODOS los streams de PowerShell (incluido
                // error), que es el equivalente de `> file 2>&1` de cmd.
                Some(path) => format!("{head}{command} *> \"{}\"\r\n", path.display()),
                None => format!("{head}{command}\r\n"),
            };
            (format!("nexodeck_action_{suffix}.ps1"), body)
        }
        #[cfg(not(target_os = "windows"))]
        _ => {
            let body = match redirect_to {
                Some(path) => format!("#!/bin/sh\n{command} > \"{}\" 2>&1\n", path.display()),
                None => format!("#!/bin/sh\n{command}\n"),
            };
            (format!("nexodeck_action_{suffix}.sh"), body)
        }
        #[cfg(target_os = "windows")]
        _ => {
            // `chcp 65001` por el mismo motivo que el preambulo de
            // PowerShell: que la salida capturada llegue en UTF-8 y no en la
            // codepage OEM de la consola.
            let head = "@echo off\r\nchcp 65001>nul\r\n";
            let body = match redirect_to {
                Some(path) => {
                    format!("{head}{command} > \"{}\" 2>&1\r\n", path.display())
                }
                None => format!("{head}{command}\r\n"),
            };
            (format!("nexodeck_action_{suffix}.bat"), body)
        }
    };

    let path = dir.join(name);
    fs::write(&path, contents)?;
    Ok(path)
}

#[cfg(target_os = "windows")]
mod windows {
    use std::os::windows::process::CommandExt;

    use super::*;

    /// 0x00000010 -- CREATE_NEW_CONSOLE: la ventana visible donde corre el
    /// comando.
    const CREATE_NEW_CONSOLE: u32 = 0x0000_0010;
    /// 0x08000000 -- CREATE_NO_WINDOW: sin ventana en absoluto -- se usa
    /// tanto para el trampolin de PowerShell que dispara la elevacion
    /// (nunca debe mostrar su propia ventana, solo el UAC) como para el
    /// caso `show_window: false` sin admin.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    pub(super) fn run(
        command: &str,
        terminal_type: TerminalType,
        requires_admin: bool,
        show_window: bool,
    ) -> Result<(), ActionError> {
        // Escribimos el comando a un .bat/.ps1 temporal en vez de
        // pasarlo inline como argumento: cmd.exe interpreta `&`, `|`, `%`,
        // comillas, etc. de forma muy quisquillosa, y un archivo evita por
        // completo ese problema de escaping.
        let script_path = write_script(command, terminal_type, None)?;
        let script = script_path.to_string_lossy();

        // `/K` deja la ventana abierta con un prompt despues de correr el
        // script (para que el usuario vea la salida); `/K` no tiene
        // sentido si no hay ventana, asi que ahi se usa `/C` (corre y
        // termina). Mismo criterio para PowerShell con `-NoExit`.
        let (program, args): (&str, Vec<String>) = match terminal_type {
            TerminalType::PowerShell => {
                let mut a = vec!["-File".to_string(), script.into_owned()];
                if show_window {
                    a.insert(0, "-NoExit".into());
                }
                ("powershell", a)
            }
            TerminalType::DefaultShell | TerminalType::Cmd => {
                let flag = if show_window { "/K" } else { "/C" };
                ("cmd", vec![flag.into(), script.into_owned()])
            }
            TerminalType::Bash => {
                let inner = if show_window {
                    format!("{command}; exec bash")
                } else {
                    command.to_string()
                };
                ("wsl", vec!["bash".into(), "-c".into(), inner])
            }
        };

        if requires_admin {
            run_elevated(program, &args, show_window)
        } else {
            let flags = if show_window {
                CREATE_NEW_CONSOLE
            } else {
                CREATE_NO_WINDOW
            };
            Command::new(program).args(&args).creation_flags(flags).spawn()?;
            Ok(())
        }
    }

    fn run_elevated(program: &str, args: &[String], show_window: bool) -> Result<(), ActionError> {
        let arg_list = args
            .iter()
            .map(|a| format!("'{}'", escape_single_quotes(a)))
            .collect::<Vec<_>>()
            .join(", ");
        let window_style = if show_window { "" } else { " -WindowStyle Hidden" };
        let script = format!(
            "Start-Process -FilePath '{}' -ArgumentList {} -Verb RunAs{}",
            escape_single_quotes(program),
            arg_list,
            window_style,
        );

        Command::new("powershell")
            .args(["-NoProfile", "-NonInteractive", "-Command", &script])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()?;
        Ok(())
    }

    pub(crate) fn escape_single_quotes(s: &str) -> String {
        s.replace('\'', "''")
    }
}

#[cfg(target_os = "linux")]
mod linux {
    use super::*;

    /// Best-effort: no hay una API estandar para "abrir una terminal nueva"
    /// en Linux (depende del entorno de escritorio), asi que se prueba una
    /// lista de emuladores comunes en orden. Sin maquina Linux disponible
    /// para probar en esta sesion -- ver nota en CLAUDE.md.
    const TERMINAL_EMULATORS: &[&str] =
        &["x-terminal-emulator", "gnome-terminal", "konsole", "xterm"];

    pub(super) fn run(
        command: &str,
        terminal_type: TerminalType,
        requires_admin: bool,
        show_window: bool,
    ) -> Result<(), ActionError> {
        let shell = match terminal_type {
            TerminalType::Bash | TerminalType::DefaultShell => "bash",
            TerminalType::Cmd | TerminalType::PowerShell => "bash", // sin equivalente nativo
        };

        // Sin ventana: se corre el comando directo (sin `exec $shell` al
        // final, que solo tiene sentido para dejar un prompt visible
        // despues), sin pasar por ningun emulador de terminal.
        if !show_window {
            let inner = if requires_admin {
                format!("pkexec {shell} -c '{}'", command.replace('\'', "'\\''"))
            } else {
                command.to_string()
            };
            Command::new(shell).args(["-c", &inner]).spawn()?;
            return Ok(());
        }

        let inner = if requires_admin {
            format!("pkexec {shell} -c '{}; exec {shell}'", command.replace('\'', "'\\''"))
        } else {
            format!("{shell} -c '{}; exec {shell}'", command.replace('\'', "'\\''"))
        };

        let mut last_error = None;
        for emulator in TERMINAL_EMULATORS {
            match Command::new(emulator).args(["-e", "sh", "-c", &inner]).spawn() {
                Ok(_) => return Ok(()),
                Err(e) => last_error = Some(e),
            }
        }
        Err(last_error.map(ActionError::Spawn).unwrap_or(ActionError::UnsupportedPlatform))
    }
}
