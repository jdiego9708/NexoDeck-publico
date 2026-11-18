//! A que modelo se le pide la propuesta.
//!
//! Primero el remoto configurado, despues el local **si ya esta levantado**. El
//! orden no es por calidad sino por la GPU: una tanda de ODM la ocupa durante
//! horas, y levantar llama-server en medio le quitaria memoria a lo que de verdad
//! importa. Por eso el local nunca se arranca desde aca.

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use nexodeck_ai::openai::{self, types::{ChatMessage, ChatRequest}};
use nexodeck_ai::AiError;

use crate::config::InboxConfig;

/// Una propuesta con una seccion entera no entra en los 2048 del chat.
const MAX_TOKENS: u32 = 8_192;
/// Bajo: aca se quiere fidelidad a los hallazgos, no creatividad.
const TEMPERATURE: f32 = 0.2;

/// Temperatura y tope de una llamada. El valor por defecto es el del buzon.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CompletionOptions {
    pub temperature: f32,
    pub max_tokens: u32,
}

impl Default for CompletionOptions {
    fn default() -> Self {
        CompletionOptions {
            temperature: TEMPERATURE,
            max_tokens: MAX_TOKENS,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelErrorKind {
    /// No hubo respuesta: red caida, DNS, timeout de conexion.
    Network,
    RateLimited,
    Server,
    /// Clave invalida o sin permiso. Reintentar no lo arregla.
    Auth,
    NoCredit,
    Cancelled,
    Other,
}

impl ModelErrorKind {
    /// Se arregla solo con esperar.
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            ModelErrorKind::Network
                | ModelErrorKind::RateLimited
                | ModelErrorKind::Server
                | ModelErrorKind::Cancelled
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{detail}")]
pub struct ModelError {
    pub kind: ModelErrorKind,
    pub detail: String,
}

impl ModelError {
    pub fn new(kind: ModelErrorKind, detail: impl Into<String>) -> Self {
        ModelError {
            kind,
            detail: detail.into(),
        }
    }
}

/// Un modelo de mentira para los tests: recibe los mensajes y contesta.
pub type FakeModel = Arc<dyn Fn(&[ChatMessage]) -> Result<String, ModelError> + Send + Sync>;

#[derive(Clone)]
pub enum ModelBackend {
    OpenAiCompatible {
        base_url: String,
        model: String,
        api_key: Option<String>,
        label: String,
        local: bool,
        disable_thinking: bool,
    },
    Fake {
        label: String,
        local: bool,
        respond: FakeModel,
    },
}

impl std::fmt::Debug for ModelBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Sin la clave: un Debug que acaba en un log no puede llevarla.
        f.debug_struct("ModelBackend")
            .field("label", &self.label())
            .field("local", &self.is_local())
            .finish()
    }
}

impl ModelBackend {
    pub fn label(&self) -> &str {
        match self {
            ModelBackend::OpenAiCompatible { label, .. } | ModelBackend::Fake { label, .. } => label,
        }
    }

    pub fn is_local(&self) -> bool {
        match self {
            ModelBackend::OpenAiCompatible { local, .. } | ModelBackend::Fake { local, .. } => *local,
        }
    }

    /// Cuanto documento se le enseña. El local tiene un contexto mucho mas
    /// chico, y llenarlo entero deja sin sitio a la respuesta.
    pub fn context_budget(&self) -> usize {
        if self.is_local() {
            24_000
        } else {
            120_000
        }
    }

    pub async fn complete(
        &self,
        messages: Vec<ChatMessage>,
        cancel: Arc<AtomicBool>,
    ) -> Result<String, ModelError> {
        self.complete_with(messages, CompletionOptions::default(), cancel)
            .await
    }

    /// Como [`complete`](Self::complete), con la temperatura y el tope de cada
    /// llamada. Los agentes de las notas no piden lo mismo: el que lee una nota
    /// contesta en pocas lineas, el que redacta la propuesta necesita sitio.
    pub async fn complete_with(
        &self,
        messages: Vec<ChatMessage>,
        options: CompletionOptions,
        cancel: Arc<AtomicBool>,
    ) -> Result<String, ModelError> {
        match self {
            ModelBackend::OpenAiCompatible {
                base_url,
                model,
                api_key,
                disable_thinking,
                ..
            } => {
                let mut request = ChatRequest::new(model.clone(), messages)
                    .with_max_tokens(options.max_tokens)
                    .with_temperature(options.temperature)
                    .with_response_format(serde_json::json!({ "type": "json_object" }));
                if *disable_thinking {
                    request = request.without_thinking();
                }
                let client = openai::chat_client();
                let completion = openai::stream_chat(
                    &client,
                    base_url,
                    api_key.as_deref(),
                    &request,
                    cancel,
                    |_| {},
                )
                .await
                .map_err(|e| classify(&e))?;
                Ok(completion.content)
            }
            ModelBackend::Fake { respond, .. } => respond(&messages),
        }
    }
}

/// `stream_chat` devuelve los errores HTTP como `"<status>: <cuerpo>"` y los de
/// red con el texto de reqwest, que nunca empieza por un codigo.
fn classify(error: &AiError) -> ModelError {
    let kind = match error {
        AiError::Cancelled => ModelErrorKind::Cancelled,
        AiError::BadResponse(_) => ModelErrorKind::Server,
        AiError::Provider(detail) => {
            match detail.get(..3).and_then(|code| code.parse::<u16>().ok()) {
                Some(401 | 403) => ModelErrorKind::Auth,
                Some(402) => ModelErrorKind::NoCredit,
                Some(429) => ModelErrorKind::RateLimited,
                Some(500..=599) => ModelErrorKind::Server,
                Some(_) => ModelErrorKind::Other,
                None => ModelErrorKind::Network,
            }
        }
        _ => ModelErrorKind::Other,
    };
    ModelError::new(kind, error.to_string())
}

/// Los modelos disponibles ahora mismo, en orden de preferencia, y por que falta
/// cada uno de los que no estan. Lo segundo es lo que ve el usuario cuando un
/// hallazgo queda esperando: "no hay modelo" a secas no dice que arreglar.
pub async fn live_candidates(config: &InboxConfig, ai_enabled: bool) -> (Vec<ModelBackend>, Vec<String>) {
    let mut found = Vec::new();
    let mut missing = Vec::new();

    match &config.remote {
        None => missing.push("no hay ningun modelo remoto configurado".to_string()),
        Some(remote) => match nexodeck_ai::remote::load_api_key(&remote.provider_id) {
            Ok(Some(key)) => {
                let base_url = nexodeck_ai::remote::normalize_base_url(&remote.base_url)
                    .unwrap_or_else(|_| remote.base_url.clone());
                found.push(ModelBackend::OpenAiCompatible {
                    base_url,
                    model: remote.model.clone(),
                    api_key: Some(key),
                    label: format!("{} ({})", remote.model, remote.provider_id),
                    local: false,
                    disable_thinking: false,
                });
            }
            Ok(None) => missing.push(format!(
                "no hay clave guardada para '{}'",
                remote.provider_id
            )),
            Err(e) => missing.push(format!(
                "no se pudo leer la clave de '{}': {e}",
                remote.provider_id
            )),
        },
    }

    if !config.local_fallback {
        missing.push("el respaldo local esta apagado".to_string());
    } else if !ai_enabled {
        // Con la IA apagada ni se consulta el motor.
        missing.push("la IA local esta apagada en NexoDeck".to_string());
    } else {
        match nexodeck_ai::engine::engine().local_endpoint().await {
            Some((_, true)) => missing.push("el modelo local esta ocupado con el chat".to_string()),
            Some((endpoint, false)) => found.push(ModelBackend::OpenAiCompatible {
                base_url: endpoint.base_url,
                model: endpoint.model,
                api_key: None,
                label: endpoint.label,
                local: true,
                disable_thinking: endpoint.disable_thinking,
            }),
            None => missing.push("no hay ningun modelo local levantado".to_string()),
        }
    }

    (found, missing)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn http_errors_are_classified_by_their_status() {
        let kind = |detail: &str| classify(&AiError::Provider(detail.into())).kind;
        assert_eq!(kind("401 Unauthorized: bad key"), ModelErrorKind::Auth);
        assert_eq!(kind("402 Payment Required: {}"), ModelErrorKind::NoCredit);
        assert_eq!(kind("429 Too Many Requests: slow down"), ModelErrorKind::RateLimited);
        assert_eq!(kind("503 Service Unavailable: "), ModelErrorKind::Server);
        assert_eq!(kind("400 Bad Request: context too long"), ModelErrorKind::Other);
        assert_eq!(
            kind("error sending request for url (https://api.deepseek.com)"),
            ModelErrorKind::Network
        );
        assert_eq!(classify(&AiError::Cancelled).kind, ModelErrorKind::Cancelled);
    }

    #[test]
    fn debug_never_prints_the_api_key() {
        let backend = ModelBackend::OpenAiCompatible {
            base_url: "https://api.deepseek.com".into(),
            model: "deepseek-chat".into(),
            api_key: Some("sk-secreta".into()),
            label: "deepseek".into(),
            local: false,
            disable_thinking: false,
        };
        assert!(!format!("{backend:?}").contains("sk-secreta"));
    }
}
