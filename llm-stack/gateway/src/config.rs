//! Configuración de la pasarela: dónde escucha y a qué servidor vLLM va cada modelo.
//!
//! Vive en un fichero JSON en el directorio de datos del usuario, junto a `keys.json`. Se crea con
//! valores por defecto la primera vez, para que `serve` funcione sin configurar nada.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use directories::ProjectDirs;
use serde::{Deserialize, Serialize};

/// Dirección por defecto. Solo loopback: la pasarela no se abre a la red sin decidirlo a mano.
/// El puerto es el 8888 que ya citaba la receta (doc 05) para el punto de entrada del stack.
pub const DEFAULT_LISTEN: &str = "127.0.0.1:8888";

/// Tope del cuerpo de una petición. Un prompt de 16 000 tokens ronda los 100 KB; 8 MiB deja margen
/// de sobra y evita que un cliente descuidado (o malicioso) agote la memoria de la pasarela.
pub const DEFAULT_MAX_BODY_BYTES: usize = 8 * 1024 * 1024;

const CONFIG_FILE: &str = "gateway.json";
const KEYS_FILE: &str = "keys.json";
const DECISIONS_FILE: &str = "decisions.jsonl";

/// Como se reenvía a un destino.
///
/// Acepta las dos formas en el JSON para no romper un `gateway.json` que ya
/// existe: una **cadena** (un servidor vLLM local, sin más) o un **objeto** con
/// la URL y, opcional, la autorización y el nombre del modelo río arriba.
///
/// Lo segundo es lo que permite que un slot del perfil sea un servicio por
/// internet: se guarda **la ruta** del fichero de la clave (la que administra
/// Rust), nunca la clave, y `proxy.rs` cambia la cabecera `Authorization` por la
/// del servicio antes de reenviar.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum BackendConfig {
    /// Forma corta: solo la URL base.
    Simple(String),
    /// Forma completa.
    Detailed(BackendDetails),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackendDetails {
    pub url: String,
    /// Fichero del que se lee la clave del servicio, en texto plano. Es la ruta
    /// que produce `nexodeck_ai::remote::api_key_path`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub api_key_file: Option<String>,
    /// Alternativa a `api_key_file`: el nombre de una variable de entorno.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub api_key_env: Option<String>,
    /// Nombre real del modelo en el servicio si difiere de la clave del backend
    /// (p. ej. la clave `fast` apunta a `deepseek-chat`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upstream_model: Option<String>,
}

impl BackendConfig {
    pub fn url(&self) -> &str {
        match self {
            Self::Simple(url) => url,
            Self::Detailed(details) => &details.url,
        }
    }

    /// URL base sin barra final, para componer el endpoint.
    pub fn base_url(&self) -> &str {
        self.url().trim_end_matches('/')
    }

    pub fn upstream_model(&self) -> Option<&str> {
        match self {
            Self::Simple(_) => None,
            Self::Detailed(details) => details.upstream_model.as_deref(),
        }
    }

    /// Un backend con autorización propia es un servicio externo: no se sondea
    /// cada 2 s (no tiene por qué exponer `/health`, y sondearlo gastaría cuota).
    pub fn is_external(&self) -> bool {
        match self {
            Self::Simple(_) => false,
            Self::Detailed(details) => {
                details.api_key_file.is_some() || details.api_key_env.is_some()
            }
        }
    }

    /// La clave del servicio, si este backend tiene una. Un fichero vacío o
    /// ausente cuenta como "sin clave", igual que en `nexodeck_ai::remote`.
    pub fn api_key(&self) -> Option<String> {
        let Self::Detailed(details) = self else {
            return None;
        };
        let raw = if let Some(file) = &details.api_key_file {
            std::fs::read_to_string(file).ok()
        } else if let Some(name) = &details.api_key_env {
            std::env::var(name).ok()
        } else {
            None
        }?;
        let trimmed = raw.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// `host:puerto` donde escucha la pasarela.
    pub listen: String,
    /// Tamaño máximo del cuerpo de una petición, en bytes.
    pub max_body_bytes: usize,
    /// Modelo (campo `model` de la petición) -> destino: un servidor vLLM local
    /// o un servicio por internet.
    pub backends: BTreeMap<String, BackendConfig>,
    /// Reglas del modelo virtual `auto`. Opcional: un `gateway.json` anterior, sin este bloque,
    /// sigue leyéndose con los valores por defecto.
    #[serde(default)]
    pub auto: AutoConfig,
}

/// Reglas del modelo virtual `auto` (ver `route.rs`). Los umbrales y las palabras clave son los del
/// doc 05, más sus equivalentes en español.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AutoConfig {
    /// Modelo del nivel ligero (el Router).
    pub light: String,
    /// Modelos candidatos del nivel trabajador, por orden de preferencia: se usa el primero que
    /// esté levantado. Con el perfil B es `complex`; con el A, `fast`.
    pub workers: Vec<String>,
    /// Por debajo de estos caracteres una petición es `simple`.
    pub simple_max_chars: usize,
    /// Por encima de estos caracteres una petición es `complex`.
    pub long_min_chars: usize,
    /// Palabras que mandan la petición al nivel ligero (decisión `meta`).
    pub meta_keywords: Vec<String>,
    /// Palabras que mandan la petición al trabajador (decisión `complex_keywords`).
    pub complex_keywords: Vec<String>,
    /// Enrutado por dominio: si el trabajador levantado es un especialista de código, solo recibe
    /// lo que parece código; el resto va al ligero (generalista). Doc 11, 7.25: el Complejo saca
    /// 37 % en MMLU frente al 70 % del Router. Con `false` se ignora todo lo de abajo.
    pub code_routing: bool,
    /// Modelos que son especialistas de código. Con un trabajador que no está aquí (el Rápido, un
    /// generalista) el enrutado por dominio no interviene.
    pub specialists: Vec<String>,
    /// Marcas de que una petición trata de código. Subcadenas, sin distinguir mayúsculas.
    pub code_markers: Vec<String>,
}

fn to_strings(words: &[&str]) -> Vec<String> {
    words.iter().map(|word| word.to_string()).collect()
}

impl Default for AutoConfig {
    fn default() -> Self {
        Self {
            light: "router".to_string(),
            workers: to_strings(&["complex", "fast"]),
            simple_max_chars: 150,
            long_min_chars: 800,
            // La lista de la receta (doc 05, 6.2) más lo que es evidente en español. Se busca como
            // subcadena y sin distinguir mayúsculas.
            meta_keywords: to_strings(&[
                "classify",
                "clasifica",
                "route",
                "which model",
                "qué modelo",
                "tool",
                "function call",
                "llamada a función",
            ]),
            complex_keywords: to_strings(&[
                "refactor",
                "architecture",
                "arquitectura",
                "design pattern",
                "patrón de diseño",
                "debug complex",
                "optimize",
                "optimiza",
                "multi-file",
                "varios ficheros",
                "varios archivos",
                "system design",
                "diseño de sistemas",
            ]),
            code_routing: true,
            specialists: to_strings(&["complex"]),
            // Marcas fuertes a propósito: palabras sueltas como "class", "function" o "import" salen
            // en cualquier texto (química, matemáticas, historia) y mandarían al especialista lo que
            // peor sabe. Se validó contra HumanEval y MMLU (scripts/check-code-detector.py).
            code_markers: to_strings(&[
                "```",
                "def ",
                "#include",
                "fn main",
                "public static",
                "console.log",
                "traceback",
                "stack trace",
                "syntaxerror",
                "typeerror",
                "pytest",
                "unit test",
                "prueba unitaria",
                "python",
                " rust",
                "javascript",
                "typescript",
                "c++",
                "golang",
                "java ",
                " sql",
                "regex",
                // Español. «código» a secas no vale (código moral, código civil): va con determinante.
                "este código",
                "mi código",
                "tu código",
                "este codigo",
                "mi codigo",
                "el código fuente",
                "una función que",
                "una función en",
                "una función para",
                "una función de python",
                "un método que",
                "un método para",
                "una clase que",
                "crea una clase",
                "un script",
                "un algoritmo",
                "el algoritmo para",
                "búsqueda binaria",
                "expresión regular",
                "test unitario",
                "segmentation fault",
                "no compila",
                "bucle infinito",
                "recursiva",
                "commit ", // con espacio: «committee» no es código
                "callback",
                " cron ",
                "printf",
                "print(",
                "int main",
                "undefined is not",
                " csv",
                "source code",
                "programming",
                "escribe un programa",
                "un programa que",
                "un programa en",
                "write a program",
                "compiler",
                "compilation error",
                "compile error",
                "write a function",
                "escribe una función",
                "implement a function",
                "implementa una función",
                " git ",
                "docker",
                " api ",
                "endpoint",
                "json",
                " bug",
                "debug",
            ]),
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        // Los puertos son los de `serve-model.sh`: 8000 complex, 8001 fast, 8002 router, 8003 writer.
        // Los servidores vLLM van atados a 127.0.0.1 y WSL2 los reenvía a Windows.
        let backends = [
            ("complex", "http://127.0.0.1:8000"),
            ("fast", "http://127.0.0.1:8001"),
            ("router", "http://127.0.0.1:8002"),
            ("writer", "http://127.0.0.1:8003"),
        ]
        .into_iter()
        .map(|(model, url)| (model.to_string(), BackendConfig::Simple(url.to_string())))
        .collect();

        Self {
            listen: DEFAULT_LISTEN.to_string(),
            max_body_bytes: DEFAULT_MAX_BODY_BYTES,
            backends,
            auto: AutoConfig::default(),
        }
    }
}

impl Config {
    pub fn load(path: &Path) -> io::Result<Self> {
        let text = fs::read_to_string(path)?;
        serde_json::from_str(&text).map_err(|error| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("{} no es un JSON válido: {error}", path.display()),
            )
        })
    }

    /// El destino que sirve `model`, sin barra final.
    pub fn backend(&self, model: &str) -> Option<&BackendConfig> {
        self.backends.get(model)
    }

    /// Crea el fichero con los valores por defecto si no existe. Devuelve `true` si lo creó.
    pub fn write_default_if_missing(path: &Path) -> io::Result<bool> {
        if path.exists() {
            return Ok(false);
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let text = serde_json::to_string_pretty(&Self::default())
            .expect("la configuración por defecto siempre se serializa");
        fs::write(path, text + "\n")?;
        Ok(true)
    }
}

/// Rutas de los ficheros de la pasarela dentro de un directorio de datos.
#[derive(Debug, Clone)]
pub struct Paths {
    pub dir: PathBuf,
    pub config: PathBuf,
    pub keys: PathBuf,
    /// Registro de las decisiones del modelo `auto` (una línea JSON por petición).
    pub decisions: PathBuf,
}

impl Paths {
    pub fn in_dir(dir: PathBuf) -> Self {
        Self {
            config: dir.join(CONFIG_FILE),
            keys: dir.join(KEYS_FILE),
            decisions: dir.join(DECISIONS_FILE),
            dir,
        }
    }

    /// Directorio por defecto: `NEXODECK_GATEWAY_DIR` si está definida, y si no el directorio de
    /// datos locales del usuario, igual que hace NexoDeck (`directories::ProjectDirs`). Nunca una
    /// ruta fija: cambia por máquina y por usuario.
    pub fn default_dir() -> Option<PathBuf> {
        if let Some(dir) = std::env::var_os("NEXODECK_GATEWAY_DIR") {
            return Some(PathBuf::from(dir));
        }
        ProjectDirs::from("dev", "nexodeck", "LlmGateway").map(|dirs| dirs.data_local_dir().to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn el_backend_corto_sigue_leyendose() {
        // Compatibilidad: un gateway.json de antes de los remotos.
        let config: Config = serde_json::from_str(
            r#"{
                "listen": "127.0.0.1:8888",
                "max_body_bytes": 8388608,
                "backends": { "fast": "http://127.0.0.1:8001" }
            }"#,
        )
        .unwrap();
        let backend = config.backend("fast").unwrap();
        assert_eq!(backend.base_url(), "http://127.0.0.1:8001");
        assert!(!backend.is_external());
        assert_eq!(backend.upstream_model(), None);
        assert_eq!(backend.api_key(), None);
    }

    #[test]
    fn el_backend_remoto_trae_autorizacion_y_modelo_rio_arriba() {
        let config: Config = serde_json::from_str(
            r#"{
                "listen": "127.0.0.1:8888",
                "max_body_bytes": 8388608,
                "backends": {
                    "fast": {
                        "url": "https://api.deepseek.com/",
                        "api_key_file": "C:\\datos\\remote-fast.key",
                        "upstream_model": "deepseek-chat"
                    }
                }
            }"#,
        )
        .unwrap();
        let backend = config.backend("fast").unwrap();
        assert_eq!(backend.base_url(), "https://api.deepseek.com");
        assert!(backend.is_external());
        assert_eq!(backend.upstream_model(), Some("deepseek-chat"));
    }

    #[test]
    fn una_clave_vacia_o_ausente_cuenta_como_sin_clave() {
        let dir = std::env::temp_dir().join(format!("llm-gateway-key-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("vacia.key");
        std::fs::write(&path, "   ").unwrap();

        let backend = BackendConfig::Detailed(BackendDetails {
            url: "https://x".into(),
            api_key_file: Some(path.to_string_lossy().into_owned()),
            api_key_env: None,
            upstream_model: None,
        });
        assert_eq!(backend.api_key(), None);

        std::fs::write(&path, "  sk-123  ").unwrap();
        assert_eq!(backend.api_key().as_deref(), Some("sk-123"));

        let missing = BackendConfig::Detailed(BackendDetails {
            url: "https://x".into(),
            api_key_file: Some(dir.join("no-existe.key").to_string_lossy().into_owned()),
            api_key_env: None,
            upstream_model: None,
        });
        assert_eq!(missing.api_key(), None);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
