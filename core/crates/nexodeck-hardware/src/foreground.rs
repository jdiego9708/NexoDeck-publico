//! Que aplicacion tiene el foco ahora mismo.
//!
//! Vive en `nexodeck-hardware` y no en un crate nuevo porque es la misma
//! clase de cosa que ya hace este crate: leer el estado de la maquina local
//! con `sysinfo` + una API nativa por plataforma. Lo consume la
//! auto-deteccion de perfiles (Fase 9): `profiles.auto_detect_process`
//! guarda un nombre de ejecutable (ej. `obs64.exe`) y la app cambia sola de
//! perfil cuando ese proceso pasa a primer plano.
//!
//! Devuelve `None` (nunca un error) cuando no se puede saber: no hay
//! ventana en foco, el proceso murio entre que se leyo el pid y se resolvio
//! el nombre, o la plataforma no esta soportada. Para el unico consumidor
//! que tiene, "no se" y "ninguno" se tratan igual: no cambiar de perfil.

use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

/// La aplicacion en primer plano, ya resuelta a algo comparable contra
/// `profiles.auto_detect_process`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForegroundApp {
    /// Nombre del ejecutable, tal como lo reporta el SO (`obs64.exe`,
    /// `Code.exe`). El match contra el perfil se hace **sin distinguir
    /// mayusculas**: Windows no las distingue en nombres de archivo, y
    /// nadie va a escribir `Code.exe` con la capitalizacion exacta en un
    /// campo de texto.
    pub process_name: String,
    pub pid: u32,
}

/// Lector con estado: `sysinfo::System` se reusa entre llamadas para no
/// reconstruir la tabla de procesos cada vez (esto se consulta ~1/s).
pub struct ForegroundWatcher {
    system: System,
}

impl ForegroundWatcher {
    pub fn new() -> Self {
        Self {
            system: System::new(),
        }
    }

    /// Aplicacion en primer plano, o `None` si no se puede determinar.
    pub fn current(&mut self) -> Option<ForegroundApp> {
        let pid = platform::foreground_pid()?;
        // Se refresca SOLO ese pid, no la tabla entera: un
        // `refresh_processes` completo recorre cientos de procesos y esto
        // se llama una vez por segundo.
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[sysinfo::Pid::from_u32(pid)]),
            true,
            ProcessRefreshKind::nothing(),
        );
        let process = self.system.process(sysinfo::Pid::from_u32(pid))?;
        Some(ForegroundApp {
            process_name: process.name().to_string_lossy().into_owned(),
            pid,
        })
    }
}

impl Default for ForegroundWatcher {
    fn default() -> Self {
        Self::new()
    }
}

// El match del nombre contra `profiles.auto_detect_process` NO vive aca:
// su unico consumidor es la UI (Dart), asi que esta en
// `features/profiles/domain/profile_matching.dart`, con sus tests. Tenerlo
// en los dos lados serian dos definiciones de la misma regla, divergiendo
// en cuanto alguien tocara una.

#[cfg(target_os = "windows")]
mod platform {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId,
    };

    pub(super) fn foreground_pid() -> Option<u32> {
        // SAFETY: `GetForegroundWindow` no toma parametros y devuelve un
        // HWND que puede ser nulo (sin ventana en foco, o la ventana
        // pertenece a otro escritorio); `GetWindowThreadProcessId` solo
        // escribe en el `u32` que se le pasa.
        unsafe {
            let hwnd: HWND = GetForegroundWindow();
            if hwnd.0.is_null() {
                return None;
            }
            let mut pid: u32 = 0;
            // Devuelve el id del THREAD (0 si el handle es invalido); el
            // pid sale por el parametro de salida.
            let thread_id = GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if thread_id == 0 || pid == 0 {
                return None;
            }
            Some(pid)
        }
    }
}

/// Sin implementacion todavia: en Linux depende del servidor de ventanas
/// (X11 con `_NET_ACTIVE_WINDOW` vs. Wayland, donde directamente no hay una
/// API portable para esto), y no hay maquina Linux disponible para probarlo
/// -- misma situacion que la ruta de GPU AMD en Linux. Degrada a `None`, o
/// sea: sin auto-deteccion de perfil, con el cambio manual funcionando
/// igual.
#[cfg(not(target_os = "windows"))]
mod platform {
    pub(super) fn foreground_pid() -> Option<u32> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Contra la maquina real: en Windows tiene que haber SIEMPRE alguna
    /// ventana en foco cuando corre el test (aunque sea la consola), asi
    /// que devolver algo con nombre no vacio es una expectativa razonable.
    /// En CI headless puede no haberla, por eso solo se afirma la forma.
    #[test]
    fn current_returns_a_plausible_app_or_none() {
        let mut watcher = ForegroundWatcher::new();
        if let Some(app) = watcher.current() {
            assert!(!app.process_name.is_empty());
            assert!(app.pid > 0);
        }
    }
}
