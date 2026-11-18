mod focus;
mod runner;
mod terminal;

pub use focus::{paste_into_active_window, start_focus_tracking};
pub use runner::{
    CommandRunner, OutputStream, RunEvent, RunId, RunOutcome, RunSpec, RunStatus, RunSummary,
    runner,
};
pub use terminal::{TerminalType, run_in_terminal};

#[derive(Debug, thiserror::Error)]
pub enum ActionError {
    #[cfg(not(target_os = "android"))]
    #[error("no se pudo acceder al portapapeles: {0}")]
    Clipboard(#[from] arboard::Error),
    #[error("no se pudo lanzar el proceso: {0}")]
    Spawn(#[from] std::io::Error),
    #[error("plataforma no soportada para ejecutar comandos de terminal")]
    UnsupportedPlatform,
    /// Falla al devolverle el foco a la ventana de destino o al mandarle las
    /// teclas -- ver `focus.rs`. Lleva el detalle adentro porque cada motivo
    /// (ventana cerrada, foco denegado, UIPI) pide una accion distinta del
    /// usuario.
    #[error("no se pudo pegar en la ventana activa: {0}")]
    Focus(String),
}

/// Copia texto al portapapeles del sistema. Usado por acciones con
/// `actionType = clipboard`, ya con los placeholders `{{variable}}` del
/// `commandTemplate` reemplazados por el llamador.
///
/// `arboard` no tiene backend de Android (el crate no expone ningun modulo
/// `platform` para ese target_os) -- en Android esto siempre falla con
/// `UnsupportedPlatform`. No es una limitacion real en la practica: en el
/// rol Android (Fase 4), las acciones se disparan del lado PC via
/// `ExecuteAction` sobre la red, nunca localmente.
#[cfg(not(target_os = "android"))]
pub fn paste_to_clipboard(text: &str) -> Result<(), ActionError> {
    let mut clipboard = arboard::Clipboard::new()?;
    clipboard.set_text(text)?;
    Ok(())
}

#[cfg(target_os = "android")]
pub fn paste_to_clipboard(_text: &str) -> Result<(), ActionError> {
    Err(ActionError::UnsupportedPlatform)
}

/// Copia `text` al portapapeles y, si `paste_into_active_window` es `true`,
/// ademas le devuelve el foco a la ventana que lo tenia antes de NexoDeck y le
/// manda Ctrl+V.
///
/// El portapapeles se escribe **siempre primero**: si el pegado falla (la
/// ventana se cerro, es de un proceso elevado), el texto igual quedo copiado y
/// el usuario puede pegarlo a mano. Al reves seria perder las dos cosas.
pub fn run_clipboard_action(text: &str, paste_into_active_window: bool) -> Result<(), ActionError> {
    paste_to_clipboard(text)?;
    if paste_into_active_window {
        return crate::paste_into_active_window();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(not(target_os = "android"))]
    fn clipboard_roundtrip() {
        // Puede fallar en un entorno headless de CI sin servidor de
        // portapapeles (ej. Linux sin X11/Wayland) -- se ignora el error en
        // ese caso especifico en vez de fallar el test.
        let mut clipboard = match arboard::Clipboard::new() {
            Ok(c) => c,
            Err(_) => return,
        };
        paste_to_clipboard("nexodeck-test").expect("set_text");
        assert_eq!(clipboard.get_text().unwrap(), "nexodeck-test");
    }
}
