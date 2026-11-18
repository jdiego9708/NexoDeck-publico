//! La capa MCP: JSON-RPC 2.0 sobre un unico POST.
//!
//! Se implementa el transporte **Streamable HTTP** en su forma minima: el
//! cliente manda un mensaje por POST y recibe la respuesta como
//! `application/json`. No hay SSE ni sesiones porque este servidor no inicia
//! nada por su cuenta: solo contesta. El dia que haga falta empujar avisos al
//! cliente (por ejemplo, que un vigilante cambio de estado), ahi entra el GET
//! con `text/event-stream` y no antes.
//!
//! El lote de mensajes (un array JSON) **no se acepta**: se quito de la
//! especificacion en la revision 2025-06-18 y admitirlo solo agregaria un
//! camino que ningun cliente actual usa.

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::extract::Query;
use axum::routing::{get, post};
use axum::Router;
use serde_json::{json, Value};

use crate::auth::{self, Guard};
use crate::{tools, ControlEvent, ControlState};

/// Versiones del protocolo que este servidor entiende, de la mas nueva a la
/// mas vieja. Se contesta la que pidio el cliente si esta en la lista; si no,
/// la preferida, y que el cliente decida si sigue.
const SUPPORTED_PROTOCOL_VERSIONS: &[&str] = &["2025-06-18", "2025-03-26", "2024-11-05"];

const SERVER_NAME: &str = "nexodeck";
const SERVER_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Lo que el cliente lee antes de usar nada. Es el sitio donde decirle lo que
/// no se deduce de los esquemas.
const INSTRUCTIONS: &str = "NexoDeck es el deck de escritorio del usuario y corre en esta misma \
    maquina. Sirve para avisar al usuario cuando no esta delante de la pantalla, y para consultar \
    las ejecuciones de comandos lanzadas desde el deck.\n\n\
    Los avisos llegan a su telefono: son interrupciones. Mandalos pocos, cortos y solo cuando \
    aporten (un hito real, un fallo, el final de algo largo). Comprueba siempre en el resultado \
    que se entregaron de verdad.\n\n\
    Tambien tiene un buzon de documentacion. Si el usuario pide mandar hallazgos a NexoDeck o \
    actualizar la documentacion de un proyecto que NexoDeck conoce, llama a list_doc_projects y \
    despues a submit_findings, y NO edites esos documentos a mano: NexoDeck prepara la propuesta \
    y el usuario la aprueba ahi.\n\n\
    Y tiene la boveda de notas de trabajo del usuario: search_notes para ver si algo ya se hablo, se \
    decidio o quedo pendiente antes de ponerte con ello, get_note para leer una nota y digest_note \
    para que el asistente de notas la procese y proponga como completarla. Las notas no se editan a \
    mano desde aqui.";

pub(crate) fn router(state: Arc<ControlState>) -> Router {
    Router::new()
        // Las dos rutas van al mismo sitio a proposito: configurar la URL sin
        // `/mcp` es un error facil de cometer y el sintoma seria un 404 mudo en
        // el arranque del cliente.
        .route("/mcp", post(handle))
        .route("/", post(handle))
        // El buzon de salida NO es MCP, y por eso va aparte: lo consulta un
        // script de bash que Claude Code lanza con la herramienta Monitor, y
        // ese script no habla JSON-RPC. Ver `outbox.rs`.
        .route("/outbox", get(outbox))
        .with_state(state)
}

async fn handle(State(state): State<Arc<ControlState>>, headers: HeaderMap, body: Bytes) -> Response {
    match auth::check(&headers, &state.token()) {
        Guard::Allowed => {}
        Guard::Unauthorized(reason) => {
            state.emit(ControlEvent::Rejected {
                reason: reason.to_string(),
            });
            return (
                StatusCode::UNAUTHORIZED,
                [(axum::http::header::WWW_AUTHENTICATE, "Bearer")],
                reason,
            )
                .into_response();
        }
        Guard::Forbidden(reason) => {
            state.emit(ControlEvent::Rejected {
                reason: reason.to_string(),
            });
            return (StatusCode::FORBIDDEN, reason).into_response();
        }
    }

    let Ok(message) = serde_json::from_slice::<Value>(&body) else {
        return json_rpc_error(Value::Null, -32700, "el cuerpo no es JSON valido").into_response();
    };

    if message.is_array() {
        return json_rpc_error(
            Value::Null,
            -32600,
            "este servidor no acepta lotes de mensajes; mandalos de a uno",
        )
        .into_response();
    }

    let method = message.get("method").and_then(|m| m.as_str()).unwrap_or("");
    let params = message.get("params").cloned().unwrap_or(json!({}));

    // Sin `id` es una notificacion: no lleva respuesta, solo acuse.
    let Some(id) = message.get("id").cloned().filter(|id| !id.is_null()) else {
        return StatusCode::ACCEPTED.into_response();
    };

    match method {
        "initialize" => json_rpc_ok(id, initialize(&params)).into_response(),
        "ping" => json_rpc_ok(id, json!({})).into_response(),
        "tools/list" => json_rpc_ok(id, json!({ "tools": tools::definitions() })).into_response(),
        "tools/call" => tools_call(&state, id, &params).await,
        other => json_rpc_error(id, -32601, &format!("metodo desconocido: {other}")).into_response(),
    }
}

/// Parametros del buzon. `since` es la marca de agua del oyente.
#[derive(serde::Deserialize)]
struct OutboxQuery {
    #[serde(default)]
    since: u64,
    /// Hasta donde confirma el oyente haber **emitido ya**. Va aparte de
    /// `since` a proposito: el oyente confirma despues de imprimir, nunca
    /// antes, que es lo que hace que un corte repita en vez de perder.
    #[serde(default)]
    confirm: u64,
    /// Quien pregunta. **La identidad la pone el vigilante**, no Claude Code:
    /// es su pid, unico en la maquina mientras viva. Sin esto no habria forma
    /// de dirigir un mensaje a una terminal concreta.
    #[serde(default)]
    session: String,
    /// Como se llama para el usuario: la carpeta y la rama, o lo que le pasaron
    /// con `--name`.
    #[serde(default)]
    label: String,
    #[serde(default)]
    cwd: String,
}

/// Espera hasta que haya algo que entregar, y lo devuelve como JSON.
///
/// Devolver una lista vacia tras la espera **no es un error**: es como el
/// oyente comprueba que el canal sigue vivo sin mantener una conexion abierta
/// para siempre.
async fn outbox(
    State(state): State<Arc<ControlState>>,
    headers: HeaderMap,
    Query(query): Query<OutboxQuery>,
) -> Response {
    // Las mismas tres guardias que el resto: este endpoint entrega lo que el
    // usuario le dijo a su asistente, que no es menos sensible que una
    // herramienta.
    match auth::check(&headers, &state.token()) {
        Guard::Allowed => {}
        Guard::Unauthorized(reason) => {
            state.emit(ControlEvent::Rejected {
                reason: reason.to_string(),
            });
            return (
                StatusCode::UNAUTHORIZED,
                [(axum::http::header::WWW_AUTHENTICATE, "Bearer")],
                reason,
            )
                .into_response();
        }
        Guard::Forbidden(reason) => {
            state.emit(ControlEvent::Rejected {
                reason: reason.to_string(),
            });
            return (StatusCode::FORBIDDEN, reason).into_response();
        }
    }

    // Sin identidad no se puede dirigir nada. Se rechaza en vez de tragarselo:
    // un oyente sin `session` recibiria solo los avisos generales y ninguna
    // pregunta, y el sintoma seria un puente que "no funciona a veces".
    if query.session.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            "falta 'session': el vigilante tiene que identificarse",
        )
            .into_response();
    }

    // Registrarse y seguir vivo son el mismo acto: esto corre en cada consulta.
    let label = if query.label.trim().is_empty() {
        query.session.clone()
    } else {
        query.label.clone()
    };
    state
        .outbox()
        .register_session(&query.session, &label, &query.cwd);

    if query.confirm > 0 {
        state
            .outbox()
            .confirm_delivered(&query.session, query.confirm);
    }

    let messages = state.outbox().poll(query.since, &query.session).await;
    axum::Json(json!({ "messages": messages })).into_response()
}

fn initialize(params: &Value) -> Value {
    let requested = params.get("protocolVersion").and_then(|v| v.as_str());
    let version = match requested {
        Some(v) if SUPPORTED_PROTOCOL_VERSIONS.contains(&v) => v,
        _ => SUPPORTED_PROTOCOL_VERSIONS[0],
    };

    json!({
        "protocolVersion": version,
        "capabilities": {
            // `listChanged: false` porque el juego de herramientas es fijo: no
            // hay forma de que cambie sin reiniciar la app.
            "tools": { "listChanged": false }
        },
        "serverInfo": {
            "name": SERVER_NAME,
            "title": "NexoDeck",
            "version": SERVER_VERSION
        },
        "instructions": INSTRUCTIONS
    })
}

async fn tools_call(state: &Arc<ControlState>, id: Value, params: &Value) -> Response {
    let Some(name) = params.get("name").and_then(|n| n.as_str()) else {
        return json_rpc_error(id, -32602, "falta 'name' en los parametros").into_response();
    };
    let args = params.get("arguments").cloned().unwrap_or(json!({}));

    let Some(outcome) = tools::call(state, name, &args).await else {
        // Que la herramienta no exista si es un error de protocolo: el cliente
        // pidio algo que `tools/list` nunca ofrecio.
        return json_rpc_error(id, -32602, &format!("no existe la herramienta '{name}'"))
            .into_response();
    };

    state.emit(ControlEvent::ToolCalled {
        tool: name.to_string(),
        summary: outcome.summary,
        ok: !outcome.is_error,
    });

    json_rpc_ok(
        id,
        json!({
            "content": [{ "type": "text", "text": outcome.text }],
            "isError": outcome.is_error
        }),
    )
    .into_response()
}

// ---------------------------------------------------------------------
// JSON-RPC
// ---------------------------------------------------------------------

fn json_rpc_ok(id: Value, result: Value) -> (StatusCode, axum::Json<Value>) {
    (
        StatusCode::OK,
        axum::Json(json!({ "jsonrpc": "2.0", "id": id, "result": result })),
    )
}

/// Un error de JSON-RPC viaja con **HTTP 200**: el fallo es del mensaje, no del
/// transporte. Devolver un 4xx aca hace que algunos clientes reporten "el
/// servidor no responde" en vez de enseñar el motivo real.
fn json_rpc_error(id: Value, code: i32, message: &str) -> (StatusCode, axum::Json<Value>) {
    (
        StatusCode::OK,
        axum::Json(json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": code, "message": message }
        })),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initialize_echoes_a_version_the_client_asked_for() {
        let reply = initialize(&json!({ "protocolVersion": "2024-11-05" }));
        assert_eq!(reply["protocolVersion"], "2024-11-05");
    }

    #[test]
    fn initialize_falls_back_to_our_preferred_version_for_anything_unknown() {
        let reply = initialize(&json!({ "protocolVersion": "1999-01-01" }));
        assert_eq!(reply["protocolVersion"], SUPPORTED_PROTOCOL_VERSIONS[0]);

        let reply = initialize(&json!({}));
        assert_eq!(reply["protocolVersion"], SUPPORTED_PROTOCOL_VERSIONS[0]);
    }

    #[test]
    fn initialize_declares_tools_and_says_how_to_behave() {
        let reply = initialize(&json!({}));
        assert!(reply["capabilities"]["tools"].is_object());
        assert_eq!(reply["serverInfo"]["name"], SERVER_NAME);
        let instructions = reply["instructions"].as_str().unwrap();
        assert!(instructions.contains("telefono"));
    }
}
