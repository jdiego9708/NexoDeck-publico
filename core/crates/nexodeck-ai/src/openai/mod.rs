//! Cliente de la API OpenAI-compatible que hablan `llama-server` y Ollama.

pub mod stream;
pub mod types;

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use futures_util::StreamExt;

use crate::error::{AiError, AiResult};
use stream::{CompletionAssembler, SseDecoder, StreamDelta};
use types::{ChatCompletion, ChatRequest};

/// Timeout de conexion. El de la respuesta completa **no se pone**: un turno
/// con razonamiento sobre CPU puede tardar minutos de forma legitima, y cortar
/// a mitad de una generacion es peor que esperar.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Cliente HTTP para chat. Separado del de descargas porque los timeouts que
/// necesitan son opuestos.
pub fn chat_client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .user_agent(concat!("NexoDeck/", env!("CARGO_PKG_VERSION")))
        .build()
        .unwrap_or_default()
}

/// Ejecuta un turno en streaming contra `{base_url}/v1/chat/completions`.
///
/// `on_delta` se llama por cada fragmento util (texto, razonamiento, inicio de
/// tool call). El valor de retorno es el turno completo ya reensamblado, listo
/// para que el agente decida si ejecutar herramientas o terminar.
pub async fn stream_chat<F>(
    client: &reqwest::Client,
    base_url: &str,
    api_key: Option<&str>,
    request: &ChatRequest,
    cancel: Arc<AtomicBool>,
    mut on_delta: F,
) -> AiResult<ChatCompletion>
where
    F: FnMut(StreamDelta),
{
    let url = format!("{}/v1/chat/completions", base_url.trim_end_matches('/'));

    let mut builder = client.post(&url).json(request);
    // Solo cuando hay clave: el sidecar y Ollama estan en loopback y no
    // autentican nada, y mandarles un `Bearer` vacio seria ruido.
    if let Some(key) = api_key {
        builder = builder.bearer_auth(key);
    }

    let response = builder
        .send()
        .await
        .map_err(|e| AiError::Provider(e.to_string()))?;

    if !response.status().is_success() {
        let status = response.status();
        // El cuerpo del error trae el motivo real (contexto excedido, plantilla
        // rota, modelo no cargado). Sin el, "400 Bad Request" no le sirve a
        // nadie.
        let body = response.text().await.unwrap_or_default();
        return Err(AiError::Provider(format!("{status}: {body}")));
    }

    let mut decoder = SseDecoder::new();
    let mut assembler = CompletionAssembler::new();
    let mut body = response.bytes_stream();

    while let Some(chunk) = body.next().await {
        if cancel.load(Ordering::Relaxed) {
            return Err(AiError::Cancelled);
        }

        let chunk = chunk.map_err(|e| AiError::Provider(e.to_string()))?;
        let text = String::from_utf8_lossy(&chunk);

        for payload in decoder.push(&text) {
            if SseDecoder::is_done(&payload) {
                return Ok(assembler.finish());
            }
            for delta in assembler.push_payload(&payload) {
                on_delta(delta);
            }
        }
    }

    // Sin `[DONE]`: el server corto la conexion. Igual se devuelve lo que se
    // alcanzo a juntar — si el turno tenia tool calls completos, sirve.
    Ok(assembler.finish())
}

/// Comprueba que haya un servidor OpenAI-compatible escuchando y devuelve los
/// ids de modelo que expone.
pub async fn list_models(
    client: &reqwest::Client,
    base_url: &str,
    api_key: Option<&str>,
) -> AiResult<Vec<String>> {
    #[derive(serde::Deserialize)]
    struct ModelsResponse {
        #[serde(default)]
        data: Vec<ModelEntry>,
    }
    #[derive(serde::Deserialize)]
    struct ModelEntry {
        id: String,
    }

    let url = format!("{}/v1/models", base_url.trim_end_matches('/'));
    let mut builder = client.get(&url).timeout(Duration::from_secs(5));
    if let Some(key) = api_key {
        builder = builder.bearer_auth(key);
    }
    let response = builder
        .send()
        .await
        .map_err(|e| AiError::Provider(e.to_string()))?;

    if !response.status().is_success() {
        return Err(AiError::Provider(format!(
            "{} respondio {}",
            url,
            response.status()
        )));
    }

    let parsed: ModelsResponse = response
        .json()
        .await
        .map_err(|e| AiError::BadResponse(e.to_string()))?;

    Ok(parsed.data.into_iter().map(|model| model.id).collect())
}
