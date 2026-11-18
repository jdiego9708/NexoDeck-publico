use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum DocsError {
    #[error("no se encontro el directorio de datos del usuario")]
    NoDataDir,
    #[error("no se pudo leer o escribir {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} no es JSON valido: {source}")]
    Json {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    /// Algo que pidio quien llama no se puede hacer. El texto va tal cual a
    /// Claude Code o a la UI, asi que tiene que explicar que corregir.
    #[error("{0}")]
    Invalid(String),
    #[error("no existe {0}")]
    NotFound(String),
}

pub type DocsResult<T> = Result<T, DocsError>;

impl DocsError {
    pub(crate) fn io(path: impl Into<PathBuf>, source: std::io::Error) -> Self {
        DocsError::Io {
            path: path.into(),
            source,
        }
    }
}
