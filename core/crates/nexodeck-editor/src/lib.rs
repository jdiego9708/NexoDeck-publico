//! Editor de notas: una ventana nativa con WebView2 (wry) y CodeMirror 6.
//!
//! La pagina (`web/`, TypeScript) se construye a `assets/` y va embebida en el
//! binario: se sirve por un protocolo propio, sin tocar el disco ni la red.
//! Pagina y Rust hablan por mensajes JSON (`protocol.rs`, y su gemelo
//! `web/src/protocol.ts`).
//!
//! El crate no sabe nada de la boveda: lee y guarda a traves de
//! [`EditorBackend`], que implementa la FFI sobre `nexodeck-docs`. Asi se prueba
//! con un backend falso y no arrastra el buzon.
//!
//! La logica (que hacer con cada mensaje, cuando cerrar, cuando guardar antes de
//! cambiar de nota) vive en `session.rs` y no depende de la ventana; `host.rs`
//! solo aplica sus efectos.

// Fuera de Windows no hay ventana que use los assets ni la sesion, pero se
// compilan igual para que sus tests corran en cualquier maquina.
#[cfg_attr(not(windows), allow(dead_code))]
mod assets;
mod backend;
mod protocol;
#[cfg_attr(not(windows), allow(dead_code))]
mod session;

#[cfg(windows)]
mod host;

pub use backend::{EditorBackend, EditorEvent, EventSink, SaveResult};
#[cfg(windows)]
pub use host::Editor;
pub use protocol::{
    AgentStepDto, CandidateDto, DetailsDto, DigestDto, FolderDto, GroupDto, HitDto, HostMessage, LinkTargetDto, NoteDto,
    NoteSummaryDto, OverviewDto, PageMessage, SaveReason, TaskDto, ThemeDto,
};

/// Si el editor se puede abrir en esta maquina, y si no, por que.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Availability {
    pub available: bool,
    /// La version de WebView2 Runtime instalada.
    pub version: Option<String>,
    pub reason: Option<String>,
}

pub fn availability() -> Availability {
    #[cfg(windows)]
    {
        match wry::webview_version() {
            Ok(version) => Availability {
                available: true,
                version: Some(version),
                reason: None,
            },
            Err(error) => Availability {
                available: false,
                version: None,
                reason: Some(format!(
                    "Falta Microsoft Edge WebView2 Runtime ({error}). Viene con Windows 11; \
                     en Windows 10 se instala desde la web de Microsoft."
                )),
            },
        }
    }
    #[cfg(not(windows))]
    {
        Availability {
            available: false,
            version: None,
            reason: Some("El editor de notas solo existe en Windows.".to_string()),
        }
    }
}
