//! Estado e instalacion del servicio de sensores
//! (`sensors/NexoDeckSensors`), que es lo que da la temperatura del CPU en
//! Windows.
//!
//! **Por que la app tiene que saber de esto.** El servicio necesita
//! privilegios de administrador para cargar su driver, asi que solo puede
//! registrarlo un proceso elevado. El instalador lo hace cuando se instala
//! para todos los usuarios, pero NexoDeck tambien se puede instalar **por
//! usuario** --y ese es el modo por defecto del instalador--, y ahi no hay
//! elevacion en ningun momento. El resultado, verificado en vivo, era que la
//! temperatura del CPU no aparecia nunca y **nada lo explicaba**: ni un error,
//! ni un aviso, solo un hueco donde iban los grados.
//!
//! De ahi estas dos funciones: la UI pregunta el estado y, si falta, ofrece
//! instalarlo con un UAC unico.

/// En que estado esta el ayudante de sensores.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensorHelperStatus {
    /// Registrado y corriendo. Es el unico estado en el que puede haber
    /// temperatura de CPU.
    Running,
    /// Registrado pero detenido. Pasa si alguien lo paro a mano; el arranque
    /// es automatico, asi que se recupera solo al reiniciar.
    Stopped,
    /// No esta registrado. Es el caso de una instalacion por usuario, y el
    /// unico en el que tiene sentido ofrecer instalarlo.
    NotInstalled,
    /// Esta plataforma no lo usa. En Linux y Android la temperatura del CPU la
    /// da el propio SO por sysfs y no hace falta ningun ayudante.
    Unsupported,
}

/// Estado actual del ayudante.
///
/// Barato a proposito: consulta el administrador de servicios en modo lectura,
/// que cualquier usuario puede hacer sin elevar. **No** sirve intentar abrir el
/// pipe para saber si esta vivo: el pipe admite un solo cliente y normalmente
/// lo tiene tomado nuestro propio hilo de sondeo, asi que un fallo al abrirlo
/// no distingue "no esta" de "ya lo estoy leyendo yo".
pub fn sensor_helper_status() -> SensorHelperStatus {
    #[cfg(target_os = "windows")]
    {
        windows_impl::status()
    }
    #[cfg(not(target_os = "windows"))]
    {
        SensorHelperStatus::Unsupported
    }
}

/// Lanza el instalador del servicio con un UAC.
///
/// Devuelve cuando el usuario ya respondio al dialogo de elevacion, **no**
/// cuando el servicio termino de instalarse: quien llama tiene que volver a
/// consultar el estado. `Err` incluye el caso de que el usuario cancele el
/// UAC, que no es un error de programa sino una decision suya.
pub fn install_sensor_helper() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        windows_impl::install()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err("esta plataforma no usa el ayudante de sensores".to_owned())
    }
}

#[cfg(target_os = "windows")]
mod windows_impl {
    use std::path::PathBuf;

    use windows::Win32::System::Services::{
        CloseServiceHandle, OpenSCManagerW, OpenServiceW, QueryServiceStatus, SC_MANAGER_CONNECT,
        SERVICE_QUERY_STATUS, SERVICE_RUNNING, SERVICE_STATUS,
    };
    use windows::Win32::UI::Shell::ShellExecuteW;
    use windows::Win32::UI::WindowsAndMessaging::SW_HIDE;
    use windows::core::PCWSTR;

    use super::SensorHelperStatus;

    /// Tiene que coincidir con `ServiceName` en el `Program.cs` del sidecar.
    const SERVICE_NAME: &str = "NexoDeckSensors";

    /// Donde vive el sidecar respecto del ejecutable de la app. Lo pone ahi el
    /// instalador (`[Files]` con `DestDir: {app}\sensors`).
    const SIDECAR_RELATIVE_PATH: &str = r"sensors\NexoDeckSensors.exe";

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub(super) fn status() -> SensorHelperStatus {
        // SAFETY: los tres handles se cierran en todas las salidas, y
        // `QueryServiceStatus` solo escribe en `status`.
        unsafe {
            let Ok(manager) = OpenSCManagerW(PCWSTR::null(), PCWSTR::null(), SC_MANAGER_CONNECT)
            else {
                return SensorHelperStatus::NotInstalled;
            };

            let name = wide(SERVICE_NAME);
            let service = OpenServiceW(manager, PCWSTR(name.as_ptr()), SERVICE_QUERY_STATUS);
            let Ok(service) = service else {
                let _ = CloseServiceHandle(manager);
                return SensorHelperStatus::NotInstalled;
            };

            let mut service_status = SERVICE_STATUS::default();
            let queried = QueryServiceStatus(service, &mut service_status).is_ok();

            let _ = CloseServiceHandle(service);
            let _ = CloseServiceHandle(manager);

            if !queried {
                // Existe pero no se pudo consultar: se trata como instalado y
                // detenido, que es lo que la UI puede comunicar sin mentir.
                return SensorHelperStatus::Stopped;
            }
            if service_status.dwCurrentState == SERVICE_RUNNING {
                SensorHelperStatus::Running
            } else {
                SensorHelperStatus::Stopped
            }
        }
    }

    pub(super) fn install() -> Result<(), String> {
        let sidecar = sidecar_path()?;
        if !sidecar.exists() {
            return Err(format!(
                "no encontre el ayudante de sensores en {}",
                sidecar.display()
            ));
        }

        let file = wide(&sidecar.to_string_lossy());
        let parameters = wide("--install");
        // El verbo `runas` es lo que dispara el UAC. `SW_HIDE` porque el
        // sidecar con `--install` no tiene nada que mostrar: registra el
        // servicio y sale.
        let verb = wide("runas");

        // SAFETY: los cuatro buffers viven hasta despues de la llamada.
        let result = unsafe {
            ShellExecuteW(
                None,
                PCWSTR(verb.as_ptr()),
                PCWSTR(file.as_ptr()),
                PCWSTR(parameters.as_ptr()),
                PCWSTR::null(),
                SW_HIDE,
            )
        };

        // ShellExecuteW devuelve un HINSTANCE que en realidad es un codigo de
        // error cuando es <= 32. El 5 (SE_ERR_ACCESSDENIED) es el que aparece
        // cuando el usuario cancela el UAC: no es un fallo del programa.
        let code = result.0 as usize;
        match code {
            0..=32 if code == 5 => Err("se cancelo el permiso de administrador".to_owned()),
            0..=32 => Err(format!("no se pudo lanzar el instalador (codigo {code})")),
            _ => Ok(()),
        }
    }

    /// El sidecar vive al lado del ejecutable de la app, no en una ruta fija:
    /// NexoDeck se puede instalar en `Program Files` o en el perfil del
    /// usuario, y hasta correrse sin instalar desde `cargo run`.
    fn sidecar_path() -> Result<PathBuf, String> {
        let exe = std::env::current_exe()
            .map_err(|error| format!("no pude resolver la ruta de la app: {error}"))?;
        let directory = exe
            .parent()
            .ok_or_else(|| "la ruta de la app no tiene directorio".to_owned())?;
        Ok(directory.join(SIDECAR_RELATIVE_PATH))
    }
}
