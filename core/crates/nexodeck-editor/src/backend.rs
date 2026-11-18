//! Lo que la ventana de notas necesita de la boveda, y lo que le cuenta a la app.

use std::sync::Arc;

use crate::protocol::{DetailsDto, DigestDto, HitDto, NoteDto, OverviewDto};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveResult {
    Saved {
        hash: String,
    },
    /// En disco hay otra cosa que lo que abrio el editor. No se escribio nada.
    /// `disk_hash` vacio significa que la nota ya no existe.
    Conflict {
        disk_text: String,
        disk_hash: String,
    },
}

/// Leer, guardar y consultar la boveda. La implementa la FFI sobre
/// `nexodeck-docs`; el crate no depende del buzon.
///
/// Nunca se llama dentro de un runtime de tokio: las implementaciones son
/// sincronas. Abrir, guardar y crear corren en el hilo de la ventana (son
/// lecturas y escrituras de un fichero); `overview`, `search`, `details` y
/// `digest` recorren el indice y a veces corren `git log`, y van en un hilo
/// aparte. Los errores son texto para el usuario.
pub trait EditorBackend: Send + Sync + 'static {
    fn open(&self, path: &str) -> Result<NoteDto, String>;
    /// `base_hash` es el hash con el que se abrio o se guardo por ultima vez;
    /// `None` crea la nota solo si no existe.
    fn save(&self, path: &str, text: &str, base_hash: Option<&str>) -> Result<SaveResult, String>;
    /// Crea la nota si no existe y la abre; si existe, abre la que hay.
    fn create(&self, path: &str, title: &str) -> Result<NoteDto, String>;
    /// La nota del dia, creada si hace falta.
    fn daily(&self) -> Result<NoteDto, String>;
    /// Notas, tareas abiertas y digests: todo lo que enseña la barra lateral.
    fn overview(&self) -> Result<OverviewDto, String>;
    fn search(&self, query: &str) -> Result<Vec<HitDto>, String>;
    /// Enlaces entrantes, notas parecidas y digests de una nota.
    fn details(&self, path: &str) -> Result<DetailsDto, String>;
    /// Manda la nota al asistente. Solo encola: la propuesta llega al buzon.
    fn digest(&self, path: &str) -> Result<DigestDto, String>;
    /// Mueve una nota a otra carpeta de la boveda. `group` vacio la devuelve a
    /// la bandeja; `"privado"` la esconde de los agentes; otro nombre es una
    /// agrupacion. Devuelve la nueva ruta virtual. Por defecto no esta: un
    /// backend de juguete no mueve ficheros de verdad.
    fn move_note(&self, _path: &str, _group: Option<&str>) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// A que nota lleva un `[[enlace]]` escrito en [source], o `None` si no
    /// existe. Hace falta saber desde donde: en una carpeta local,
    /// `[[clientes/acme]]` es relativo a esa carpeta, no a la boveda.
    fn resolve_link(&self, target: &str, source: Option<&str>) -> Result<Option<String>, String>;

    // Carpetas de notas, desde el menu de la barra lateral. Van en un hilo
    // aparte (la exportacion comprime la boveda entera). Devuelven el aviso para
    // el usuario. Por defecto no estan: un backend de pruebas o de juguete no
    // tiene configuracion que cambiar, y lo dice en vez de fingir.

    /// Usar [folder] como carpeta principal. No copia ni mueve nada.
    fn set_vault_folder(&self, _folder: &str) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// Añadir una carpeta de notas locales, leidas en su sitio.
    fn add_local_folder(&self, _folder: &str) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// Quitar una carpeta local. No borra nada del disco.
    fn remove_local_folder(&self, _id: &str) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// Exportar la boveda principal a un zip en [destination].
    fn export_vault(&self, _destination: &str) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// Importar un cuaderno de OneNote (`.one`) a markdown en [folder].
    fn import_onenote(&self, _file: &str, _folder: &str) -> Result<String, String> {
        Err(UNSUPPORTED.to_string())
    }
    /// Lee un adjunto (una imagen) de la boveda: `src` es la ruta escrita en la
    /// nota [note], relativa a ella. Devuelve el mime y los bytes, o `None`.
    fn read_attachment(&self, _note: &str, _src: &str) -> Result<Option<(String, Vec<u8>)>, String> {
        Err(UNSUPPORTED.to_string())
    }
}

const UNSUPPORTED: &str = "esta ventana no puede cambiar las carpetas de notas";

#[cfg(test)]
pub(crate) fn tests_unsupported() -> String {
    UNSUPPORTED.to_string()
}

/// Lo que pasa en la ventana, para la app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditorEvent {
    Opened { path: String },
    Saved { path: String, hash: String },
    Conflict { path: String },
    /// `path` es la nota que habia abierta, si habia alguna.
    Closed { path: Option<String> },
    Error { detail: String },
    /// La pagina pide el buzon: las propuestas se aprueban en la app.
    ShowInbox,
}

/// A quien se le entregan los eventos. Una funcion y no un canal: la FFI los
/// reparte entre varios streams de Dart, y el ejemplo solo los imprime.
pub type EventSink = Arc<dyn Fn(EditorEvent) + Send + Sync>;
