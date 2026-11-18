//! Error unico del crate.
//!
//! Todo camino que pueda fallar termina aca, y el borde FFI lo convierte a
//! `String` (convencion del resto de `nexodeck-ffi`). La regla que importa:
//! **ningun `?` de este crate puede terminar en un silencio** — el proyecto ya
//! perdio tiempo tres veces con fallos de conexion que desaparecian sin dejar
//! rastro (ver "Fallos de conexion" en `CLAUDE.md`), asi que cada variante
//! lleva suficiente contexto como para explicarle al usuario que paso.

use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum AiError {
    #[error("no se pudo resolver el directorio de datos de la aplicacion")]
    NoDataDir,

    #[error("no hay espacio suficiente en disco: hacen falta {needed_mb} MB y hay {free_mb} MB")]
    NotEnoughDisk { needed_mb: u64, free_mb: u64 },

    #[error("no existe un runtime de llama.cpp para {backend} en {os}")]
    NoRuntimeForTarget { backend: String, os: String },

    #[error("no existe un modelo con id '{0}' en el catalogo")]
    UnknownModel(String),

    #[error("fallo la descarga de '{asset}': {detail}")]
    Download { asset: String, detail: String },

    /// El hash no coincide. Se distingue de `Download` a proposito: aca el
    /// archivo bajo entero pero **no es el que esperabamos**, y el remedio
    /// (borrar y reintentar) es distinto.
    #[error("el archivo '{asset}' no coincide con su hash esperado (esperado {expected}, obtenido {actual})")]
    ChecksumMismatch {
        asset: String,
        expected: String,
        actual: String,
    },

    #[error("no se pudo descomprimir '{asset}': {detail}")]
    Unzip { asset: String, detail: String },

    #[error("no se encontro '{0}' dentro del archivo descargado")]
    MissingBinary(String),

    #[error("no se pudo lanzar llama-server ({path}): {detail}")]
    SpawnServer { path: PathBuf, detail: String },

    /// El proceso arranco pero nunca llego a responder `/health`. `stderr_tail`
    /// es lo unico que le podemos mostrar al usuario para que entienda por que
    /// (tipicamente: la VRAM no alcanzo para el `-ngl` pedido).
    #[error("llama-server no respondio /health en {waited_secs}s. Ultimas lineas:\n{stderr_tail}")]
    ServerNeverReady {
        waited_secs: u64,
        stderr_tail: String,
    },

    #[error("el motor de IA no esta iniciado")]
    NotStarted,

    #[error("no se encontro la instalacion de Ollama en este equipo")]
    OllamaNotFound,

    #[error("no se pudo arrancar Ollama ({path}): {detail}")]
    SpawnOllama { path: PathBuf, detail: String },

    #[error("Ollama no respondio en {waited_secs}s")]
    OllamaNeverReady { waited_secs: u64 },

    #[error("Ollama sigue corriendo despues de {waited_secs}s")]
    OllamaNeverStopped { waited_secs: u64 },

    #[error("ya hay un turno en curso")]
    Busy,

    #[error("error hablando con el modelo: {0}")]
    Provider(String),

    /// El SSE llego mal formado o incompleto. Se separa de `Provider` porque
    /// casi siempre significa que el server murio a mitad de la respuesta.
    #[error("respuesta del modelo mal formada: {0}")]
    BadResponse(String),

    #[error("el modelo agoto las {max} rondas de herramientas sin llegar a una propuesta")]
    ToolRoundsExhausted { max: u32 },

    #[error("la ruta '{0}' esta fuera de las carpetas permitidas")]
    PathNotAllowed(PathBuf),

    #[error("el asistente de IA no esta disponible en esta plataforma")]
    UnsupportedPlatform,

    #[error("operacion cancelada")]
    Cancelled,

    #[error("error de entrada/salida: {0}")]
    Io(#[from] std::io::Error),

    #[error("error de serializacion JSON: {0}")]
    Json(#[from] serde_json::Error),
}

impl AiError {
    /// Texto para mostrar en la UI. Hoy es el `Display`, pero existir como
    /// metodo propio deja el lugar donde acortar o traducir mensajes sin tocar
    /// los `#[error]`, que tambien van a los logs.
    pub fn user_message(&self) -> String {
        self.to_string()
    }
}

pub type AiResult<T> = Result<T, AiError>;
