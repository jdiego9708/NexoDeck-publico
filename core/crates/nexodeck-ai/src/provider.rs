//! De donde sale el modelo: nuestro sidecar, o un Ollama que el usuario ya
//! tenga corriendo.
//!
//! Es un `enum` y no un `trait` a proposito. El conjunto es **cerrado** (y el
//! modo online futuro seria una tercera variante, no un plugin), y las dos
//! opciones hablan exactamente el mismo protocolo: lo unico que cambia es de
//! donde sale la `base_url` y quien es el dueno del ciclo de vida. Un trait
//! con metodos async obligaria a `async_trait` para no ganar nada.

use std::time::Duration;

use crate::error::{AiError, AiResult};
use crate::sidecar::LlamaServer;

/// Puerto por defecto de Ollama. No se hace configurable por ahora: quien lo
/// cambio sabe lo que hace y puede usar el sidecar propio.
const OLLAMA_BASE_URL: &str = "http://127.0.0.1:11434";

/// Timeout de la deteccion. Corto a proposito: corre al abrir el wizard y no
/// puede hacerlo esperar.
const DETECT_TIMEOUT: Duration = Duration::from_millis(800);

pub enum ChatProvider {
    /// El `llama-server` que gestionamos nosotros.
    Sidecar {
        server: LlamaServer,
        model_id: String,
        display_name: String,
        /// El modelo entiende `enable_thinking`. Sale del catalogo.
        supports_thinking: bool,
    },
    /// Un Ollama preexistente. No lo lanzamos ni lo apagamos: es del usuario.
    Ollama { base_url: String, model: String },
    /// Un servicio por internet que habla el dialecto de OpenAI (DeepSeek,
    /// OpenAI, un proxy propio). Ver `crate::remote`.
    ///
    /// Es la "tercera variante" que este mismo comentario anticipaba: no hizo
    /// falta ningun trait ni ningun plugin, porque el protocolo es el mismo.
    Remote {
        base_url: String,
        model: String,
        api_key: String,
        /// Como se llama para el usuario ("DeepSeek", "OpenAI"). No se deriva
        /// de la URL: un proxy propio puede tener cualquier direccion.
        display_name: String,
    },
}

impl ChatProvider {
    pub fn base_url(&self) -> &str {
        match self {
            ChatProvider::Sidecar { server, .. } => server.base_url(),
            ChatProvider::Ollama { base_url, .. } => base_url,
            ChatProvider::Remote { base_url, .. } => base_url,
        }
    }

    /// La clave de API, si el proveedor la necesita. `None` en sidecar y
    /// Ollama: estan en loopback y no autentican nada.
    pub fn api_key(&self) -> Option<&str> {
        match self {
            ChatProvider::Remote { api_key, .. } => Some(api_key.as_str()),
            _ => None,
        }
    }

    /// Si el turno sale de la maquina. Lo usa la UI para avisar de que el
    /// contenido de los ficheros que lea el asistente viaja a un tercero.
    pub fn is_remote(&self) -> bool {
        matches!(self, ChatProvider::Remote { .. })
    }

    /// Id del modelo tal como lo espera el campo `model` de la peticion.
    pub fn model(&self) -> &str {
        match self {
            ChatProvider::Sidecar { model_id, .. } => model_id,
            ChatProvider::Ollama { model, .. } => model,
            ChatProvider::Remote { model, .. } => model,
        }
    }

    /// Texto para la UI.
    pub fn label(&self) -> String {
        match self {
            ChatProvider::Sidecar {
                display_name,
                server,
                ..
            } => {
                if server.gpu_layers == 0 {
                    format!("{display_name} (CPU)")
                } else {
                    format!("{display_name} (GPU)")
                }
            }
            ChatProvider::Ollama { model, .. } => format!("{model} (Ollama)"),
            ChatProvider::Remote {
                model,
                display_name,
                ..
            } => format!("{model} ({display_name})"),
        }
    }

    /// Donde hablarle al modelo **si es local** (sidecar u Ollama). `None` si es
    /// un servicio remoto: quien pide esto quiere el respaldo que ya esta
    /// levantado en la maquina, no una segunda via por internet.
    pub fn local_endpoint(&self) -> Option<ModelEndpoint> {
        match self {
            ChatProvider::Remote { .. } => None,
            _ => Some(ModelEndpoint {
                base_url: self.base_url().to_string(),
                model: self.model().to_string(),
                label: self.label(),
                disable_thinking: self.disable_thinking(),
            }),
        }
    }

    pub fn is_sidecar(&self) -> bool {
        matches!(self, ChatProvider::Sidecar { .. })
    }

    /// ¿Hay que pedirle que no razone en voz alta?
    ///
    /// En Ollama devuelve `false` a proposito: el modelo lo elige el usuario y
    /// no sabemos si su plantilla entiende la bandera. Mandarsela a ciegas
    /// podria romperle la conversacion entera.
    pub fn disable_thinking(&self) -> bool {
        match self {
            ChatProvider::Sidecar {
                supports_thinking, ..
            } => *supports_thinking,
            ChatProvider::Ollama { .. } => false,
            // Los servicios remotos no entienden la bandera de llama.cpp, y el
            // que razona (DeepSeek reasoner) lo decide por modelo, no por
            // peticion. Mandarsela seria un campo desconocido en el cuerpo.
            ChatProvider::Remote { .. } => false,
        }
    }

    /// Marca actividad para el apagado por inactividad. En Ollama no aplica:
    /// el proceso no es nuestro y tiene su propio `keep_alive`.
    pub fn touch(&self) {
        if let ChatProvider::Sidecar { server, .. } = self {
            server.touch();
        }
    }

    pub fn idle_for(&self) -> Option<Duration> {
        match self {
            ChatProvider::Sidecar { server, .. } => Some(server.idle_for()),
            // Ni Ollama ni un servicio remoto son proceso nuestro: no hay
            // nada que apagar por inactividad.
            ChatProvider::Ollama { .. } | ChatProvider::Remote { .. } => None,
        }
    }

    /// Ultimas lineas de stderr del sidecar, para explicar un fallo.
    pub fn diagnostics(&self) -> Option<String> {
        match self {
            ChatProvider::Sidecar { server, .. } => Some(server.stderr_tail()),
            ChatProvider::Ollama { .. } | ChatProvider::Remote { .. } => None,
        }
    }

    /// Apaga lo que sea nuestro. **Nunca** mata el Ollama del usuario: es su
    /// proceso, y cerrarlo porque el pidio una accion en NexoDeck seria una
    /// sorpresa desagradable.
    pub async fn shutdown(self) {
        if let ChatProvider::Sidecar { server, .. } = self {
            server.shutdown().await;
        }
    }
}

/// Lo minimo para mandarle una peticion a un modelo local sin tocar la sesion
/// del chat.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelEndpoint {
    pub base_url: String,
    pub model: String,
    pub label: String,
    pub disable_thinking: bool,
}

#[derive(Debug, Clone)]
pub struct OllamaInstallation {
    pub base_url: String,
    /// Modelos ya descargados. Si esta vacio, Ollama corre pero no tiene nada
    /// que ofrecer todavia, y el wizard tiene que decirlo asi en vez de
    /// presentarlo como una opcion lista.
    pub models: Vec<String>,
}

/// Detecta un Ollama corriendo en el equipo.
///
/// Se consulta `/v1/models` (su capa OpenAI-compatible) y no `/api/tags`
/// porque es exactamente el endpoint que despues vamos a usar: si contesta
/// esto, contesta el chat.
pub async fn detect_ollama() -> AiResult<Option<OllamaInstallation>> {
    let client = reqwest::Client::builder()
        .connect_timeout(DETECT_TIMEOUT)
        .timeout(DETECT_TIMEOUT)
        .build()
        .unwrap_or_default();

    match crate::openai::list_models(&client, OLLAMA_BASE_URL, None).await {
        Ok(models) => Ok(Some(OllamaInstallation {
            base_url: OLLAMA_BASE_URL.to_string(),
            models,
        })),
        // "No esta instalado" no es un error de la aplicacion: es la respuesta
        // normal en la mayoria de los equipos.
        Err(_) => Ok(None),
    }
}

/// Arma un proveedor remoto y **comprueba la clave antes de instalarlo**.
///
/// La comprobacion no es opcional: sin ella, una clave mal pegada se descubre
/// recien al mandar el primer mensaje, y el error llega dentro de la
/// conversacion en vez de en el dialogo donde se puede corregir. Es el mismo
/// criterio que ya sigue `use_ollama` al exigir que el modelo exista.
pub async fn use_remote(
    base_url: &str,
    model: &str,
    api_key: &str,
    display_name: &str,
) -> AiResult<ChatProvider> {
    let base_url = crate::remote::normalize_base_url(base_url)?;
    let key = api_key.trim();
    if key.is_empty() {
        return Err(AiError::Provider("hace falta una clave de API".into()));
    }
    if model.trim().is_empty() {
        return Err(AiError::Provider("hace falta elegir un modelo".into()));
    }

    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(20))
        .build()
        .unwrap_or_default();

    // Un fallo aca casi siempre es la clave. Se dice asi en vez de repetir el
    // codigo HTTP, que no le sirve a nadie.
    let models = crate::openai::list_models(&client, &base_url, Some(key))
        .await
        .map_err(|e| {
            AiError::Provider(format!(
                "no se pudo hablar con {display_name}. Revisa la clave y la direccion: {e}"
            ))
        })?;

    // Que el modelo no este en la lista **no** se rechaza: varios servicios
    // devuelven un catalogo parcial, o ninguno, y bloquear por eso dejaria sin
    // usar un modelo que funciona. Se avisa despues, si el chat falla.
    let _ = models;

    Ok(ChatProvider::Remote {
        base_url,
        model: model.trim().to_string(),
        api_key: key.to_string(),
        display_name: display_name.to_string(),
    })
}

/// Los modelos que ofrece un servicio remoto, para poder elegir de una lista.
pub async fn list_remote_models(base_url: &str, api_key: &str) -> AiResult<Vec<String>> {
    let base_url = crate::remote::normalize_base_url(base_url)?;
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(20))
        .build()
        .unwrap_or_default();
    crate::openai::list_models(&client, &base_url, Some(api_key.trim())).await
}

/// Arma el proveedor Ollama comprobando que el modelo pedido exista.
pub async fn use_ollama(model: &str) -> AiResult<ChatProvider> {
    let installation = detect_ollama()
        .await?
        .ok_or_else(|| AiError::Provider("no se detecto Ollama corriendo".into()))?;

    if !installation.models.iter().any(|m| m == model) {
        return Err(AiError::Provider(format!(
            "Ollama esta corriendo pero no tiene '{model}'. Modelos disponibles: {}",
            if installation.models.is_empty() {
                "ninguno".to_string()
            } else {
                installation.models.join(", ")
            }
        )));
    }

    Ok(ChatProvider::Ollama {
        base_url: installation.base_url,
        model: model.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn el_proveedor_ollama_expone_su_url_y_modelo() {
        let provider = ChatProvider::Ollama {
            base_url: OLLAMA_BASE_URL.into(),
            model: "qwen3:14b".into(),
        };

        assert_eq!(provider.base_url(), OLLAMA_BASE_URL);
        assert_eq!(provider.model(), "qwen3:14b");
        assert!(!provider.is_sidecar());
        assert!(provider.label().contains("Ollama"));
        // No es nuestro proceso: no tiene sentido medirle inactividad ni
        // pedirle diagnostico.
        assert!(provider.idle_for().is_none());
        assert!(provider.diagnostics().is_none());
    }

    /// Sin Ollama corriendo tiene que devolver `Ok(None)`, no `Err`: no
    /// tenerlo instalado es el caso normal, no una falla.
    #[tokio::test]
    async fn detectar_ollama_no_falla_cuando_no_esta() {
        let result = detect_ollama().await;
        assert!(result.is_ok(), "la deteccion nunca puede devolver Err");
    }
}
