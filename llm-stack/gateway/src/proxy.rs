//! Las rutas de la pasarela y el reenvío hacia los servidores vLLM.
//!
//! **Superficie deliberadamente mínima**: solo `/v1/chat/completions`, `/v1/completions`,
//! `/v1/models` y `/health`. Cualquier otra ruta —`/sleep`, `/wake_up`, `/collective_rpc`,
//! `/metrics`…— responde 404 aunque la clave sea válida. Esos endpoints de administración de vLLM
//! son justo lo que `VLLM_SERVER_DEV_MODE=1` abre y lo que no debe llegar a ningún cliente.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, RwLock, Weak};
use std::time::{Duration, Instant, SystemTime};

use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{header, HeaderMap, HeaderName, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use futures_util::future::join_all;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::auth::KeyStore;
use crate::config::Config;
use crate::decisions::{new_request_id, DecisionLog, OutcomeResult};
use crate::logging;
use crate::route::{self, Tier, AUTO_MODEL};

/// Lo último que se sabe de un servidor vLLM.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    /// Todavía no ha terminado el primer sondeo (los primeros instantes tras arrancar).
    Unknown,
    Up,
    Down,
}

impl Availability {
    fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Up => "up",
            Self::Down => "down",
        }
    }
}

pub struct AppState {
    /// La configuración vigente, para poder **recargarla en caliente** cuando
    /// NexoDeck guarda un perfil con otro destino (el stack no reinicia la
    /// pasarela al cambiar de perfil). Se guarda tras un candado y se lee como
    /// `Arc`, que es barato por petición.
    config: RwLock<Arc<Config>>,
    pub keys: KeyStore,
    pub client: reqwest::Client,
    /// Resultado del último sondeo por modelo. Lo rellena `monitor` en segundo plano.
    availability: RwLock<BTreeMap<String, Availability>>,
    /// Registro de las decisiones del modelo `auto`.
    decisions: DecisionLog,
    /// Fichero `gateway.json`, si se sirvió desde uno. Sin él no hay recarga.
    config_path: Option<PathBuf>,
    /// Fecha de modificación de la configuración la última vez que se leyó.
    config_mtime: Mutex<Option<SystemTime>>,
}

impl AppState {
    /// La configuración vigente. Clonar el `Arc` es baratísimo; si el candado
    /// estuviera envenenado (un panic con otro hilo dentro), se recupera el
    /// valor igual en vez de tumbar la pasarela.
    fn config(&self) -> Arc<Config> {
        match self.config.read() {
            Ok(guard) => Arc::clone(&guard),
            Err(poisoned) => Arc::clone(&poisoned.into_inner()),
        }
    }

    /// Relee `gateway.json` si cambió en disco. No hace nada sin ruta o si la
    /// fecha no cambió; un fallo de lectura se deja pasar en silencio (la
    /// configuración vigente sigue siendo válida).
    fn maybe_reload(&self) {
        let Some(path) = &self.config_path else { return };
        let Ok(metadata) = std::fs::metadata(path) else { return };
        let Ok(modified) = metadata.modified() else { return };

        {
            let mut known = match self.config_mtime.lock() {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
            if known.is_some_and(|previous| previous >= modified) {
                return;
            }
            *known = Some(modified);
        }

        if let Ok(config) = Config::load(path) {
            logging::line(&format!(
                "configuración recargada de {}: {} destino(s)",
                path.display(),
                config.backends.len()
            ));
            if let Ok(mut current) = self.config.write() {
                *current = Arc::new(config);
            }
        }
    }
}

/// Cada cuánto se sondea `/health` de cada servidor vLLM.
const PROBE_INTERVAL: Duration = Duration::from_secs(2);

/// Cliente HTTP hacia los servidores vLLM.
///
/// - `no_proxy`: el destino es loopback; un proxy del sistema no tiene nada que hacer ahí.
/// - Solo hay tiempo de conexión, no tiempo total: una generación larga es legítima y cortarla a
///   mitad de un flujo SSE dejaría al cliente con la respuesta truncada.
pub fn build_client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(3))
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()
        .expect("el cliente HTTP se construye con valores fijos")
}

/// Construye la aplicación. **Debe llamarse dentro de un runtime de Tokio**: lanza el sondeo de los
/// servidores en segundo plano, que termina solo cuando la aplicación se descarta.
pub fn build_app(config: Config, keys: KeyStore) -> Router {
    build_app_with(config, keys, DecisionLog::disabled())
}

/// Como `build_app`, pero guardando las decisiones del modelo `auto` en `decisions`.
pub fn build_app_with(config: Config, keys: KeyStore, decisions: DecisionLog) -> Router {
    build_app_full(config, keys, decisions, None)
}

/// Como `build_app_with`, pero **vigilando `gateway.json`**: cuando NexoDeck
/// guarda un perfil con otro destino, la pasarela recarga la configuración sin
/// reiniciarse (el cambio de perfil no reinicia la pasarela hoy).
pub fn build_app_with_reload(
    config: Config,
    keys: KeyStore,
    decisions: DecisionLog,
    config_path: PathBuf,
) -> Router {
    build_app_full(config, keys, decisions, Some(config_path))
}

fn build_app_full(
    config: Config,
    keys: KeyStore,
    decisions: DecisionLog,
    config_path: Option<PathBuf>,
) -> Router {
    let max_body_bytes = config.max_body_bytes;
    let config_mtime = config_path
        .as_ref()
        .and_then(|path| std::fs::metadata(path).ok())
        .and_then(|metadata| metadata.modified().ok());
    let state = Arc::new(AppState {
        config: RwLock::new(Arc::new(config)),
        keys,
        client: build_client(),
        availability: RwLock::new(BTreeMap::new()),
        decisions,
        config_path,
        config_mtime: Mutex::new(config_mtime),
    });
    tokio::spawn(monitor(Arc::downgrade(&state)));

    Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(models))
        .route("/v1/chat/completions", post(completion))
        .route("/v1/completions", post(completion))
        // Un aviso de resultado son unos pocos campos: el tope propio evita gastar el de 8 MiB.
        .route("/v1/feedback", post(feedback).layer(DefaultBodyLimit::max(FEEDBACK_MAX_BODY_BYTES)))
        .fallback(not_found)
        .layer(DefaultBodyLimit::max(max_body_bytes))
        .with_state(state)
}

/// Respuesta de error con el formato de OpenAI, que es el que esperan los clientes.
fn error_response(status: StatusCode, kind: &str, message: &str) -> Response {
    (status, Json(json!({ "error": { "message": message, "type": kind } }))).into_response()
}

fn unauthorized() -> Response {
    let mut response = error_response(
        StatusCode::UNAUTHORIZED,
        "invalid_api_key",
        "Falta la clave de API o no es válida. Envíala como `Authorization: Bearer <clave>`.",
    );
    response
        .headers_mut()
        .insert(header::WWW_AUTHENTICATE, "Bearer".parse().expect("valor fijo válido"));
    response
}

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let value = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    scheme.eq_ignore_ascii_case("bearer").then(|| token.trim())
}

/// Devuelve el nombre de la clave. Quien llama responde con `unauthorized()` si es `None`: una
/// clave ausente y una incorrecta dan exactamente la misma respuesta, para no decirle a quien
/// prueba cuál de las dos cosas falló.
fn authorize(state: &AppState, headers: &HeaderMap) -> Option<String> {
    bearer_token(headers).and_then(|token| state.keys.verify(token))
}

async fn backend_is_up(client: &reqwest::Client, base_url: &str) -> bool {
    client
        .get(format!("{base_url}/health"))
        .timeout(Duration::from_secs(2))
        .send()
        .await
        .map(|response| response.status().is_success())
        .unwrap_or(false)
}

/// Sondea todos los servidores a la vez y guarda el resultado.
///
/// **Un backend externo (servicio por internet) no se sondea**: se da por
/// disponible, porque puede no exponer `/health` y sondearlo cada 2 s gastaría
/// cuota. Si no contesta, la petición misma devuelve el error del servicio.
async fn refresh_availability(state: &AppState) {
    let config = state.config();
    let probes = config.backends.iter().map(|(model, backend)| {
        let client = state.client.clone();
        let model = model.clone();
        let backend = backend.clone();
        async move {
            if backend.is_external() {
                (model, true)
            } else {
                (model, backend_is_up(&client, backend.base_url()).await)
            }
        }
    });
    let results = join_all(probes).await;
    if let Ok(mut availability) = state.availability.write() {
        for (model, up) in results {
            availability.insert(model, if up { Availability::Up } else { Availability::Down });
        }
    }
}

/// Bucle de sondeo. Guarda solo una referencia débil: cuando la aplicación se descarta, termina.
async fn monitor(state: Weak<AppState>) {
    loop {
        let Some(strong) = state.upgrade() else { return };
        strong.maybe_reload();
        refresh_availability(&strong).await;
        drop(strong);
        tokio::time::sleep(PROBE_INTERVAL).await;
    }
}

/// Lo último que se sabe de cada modelo configurado (`Unknown` si aún no hubo ningún sondeo).
fn availability_snapshot(state: &AppState) -> BTreeMap<String, Availability> {
    let config = state.config();
    let cached = state.availability.read();
    config
        .backends
        .keys()
        .map(|model| {
            let known = cached
                .as_ref()
                .ok()
                .and_then(|map| map.get(model).copied())
                .unwrap_or(Availability::Unknown);
            (model.clone(), known)
        })
        .collect()
}

/// Estado de cada modelo. Sin autenticación a propósito: lo usan los scripts de arranque para saber
/// si el stack está listo, y solo dice `up`/`down`/`unknown` por nombre de modelo.
///
/// **Responde al instante**, con lo que sabe el sondeo de fondo. Antes sondeaba en la propia
/// petición y, con los modelos apagados, tardaba ≥ 2 s (el tiempo de espera de cada sondeo): más de
/// lo que espera un healthcheck, así que el script de arranque nunca la veía sana y abortaba antes
/// de arrancar los modelos.
async fn health(State(state): State<Arc<AppState>>) -> Json<Value> {
    let backends: serde_json::Map<String, Value> = availability_snapshot(&state)
        .into_iter()
        .map(|(model, availability)| (model, Value::from(availability.as_str())))
        .collect();
    Json(json!({ "status": "ok", "backends": backends }))
}

/// Lista solo los modelos que ahora mismo están levantados: el perfil activo decide cuáles son.
async fn models(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    if authorize(&state, &headers).is_none() {
        return unauthorized();
    }
    let mut data: Vec<Value> = availability_snapshot(&state)
        .into_iter()
        .filter(|(_, availability)| *availability == Availability::Up)
        .map(|(model, _)| json!({ "id": model, "object": "model", "owned_by": "nexodeck" }))
        .collect();
    // El modelo virtual solo se ofrece si hay algo detrás que responda.
    if !data.is_empty() {
        data.push(json!({ "id": AUTO_MODEL, "object": "model", "owned_by": "nexodeck" }));
    }
    Json(json!({ "object": "list", "data": data })).into_response()
}

/// Elige el modelo concreto para un nivel, según lo que esté levantado. Devuelve el nombre y si
/// hubo que **conmutar** al otro nivel porque el pedido estaba apagado.
///
/// - Trabajador: el primero de `workers` que esté `Up`; si no hay ninguno, el ligero (conmuta).
/// - Ligero: el Router; si está apagado, el trabajador (conmuta).
/// - Si no hay nada `Up` (o todavía no se sabe) se devuelve el que se pedía y ya fallará la
///   conexión con un 503 claro: mejor eso que inventar un destino.
fn resolve_target(
    config: &Config,
    availability: &BTreeMap<String, Availability>,
    tier: Tier,
) -> (String, bool) {
    let is_up = |model: &str| availability.get(model) == Some(&Availability::Up);
    let light = config.auto.light.clone();
    let worker = config.auto.workers.iter().find(|model| is_up(model)).cloned();
    let first_worker = config.auto.workers.first().cloned().unwrap_or_else(|| light.clone());

    match tier {
        Tier::Worker => match worker {
            Some(model) => (model, false),
            None if is_up(&light) => (light, true),
            None => (first_worker, false),
        },
        Tier::Light => {
            if is_up(&light) {
                (light, false)
            } else if let Some(model) = worker {
                (model, true)
            } else {
                (light, false)
            }
        }
    }
}

/// Tope del cuerpo de `POST /v1/feedback`.
const FEEDBACK_MAX_BODY_BYTES: usize = 4096;

/// Lo que se sabe de una petición enrutada por `auto`, para el registro y las cabeceras.
struct Routing {
    /// Identificador con el que quien verifique la respuesta informa de su resultado.
    id: String,
    decision: &'static str,
    prompt_chars: usize,
    has_tools: bool,
    fallback: bool,
}

fn record_decision(
    state: &AppState,
    key_name: &str,
    routing: &Routing,
    model: &str,
    status: StatusCode,
    started: Instant,
) {
    let now = logging::now_unix();
    state.decisions.record(&json!({
        "type": "decision",
        "id": routing.id,
        "unix": now,
        "time": logging::utc_timestamp(now),
        "key": key_name,
        "decision": routing.decision,
        "model": model,
        "prompt_chars": routing.prompt_chars,
        "has_tools": routing.has_tools,
        "fallback": routing.fallback,
        "status": status.as_u16(),
        "first_byte_ms": started.elapsed().as_millis() as u64,
    }));
}

async fn not_found() -> Response {
    error_response(StatusCode::NOT_FOUND, "not_found", "Ruta no disponible en esta pasarela.")
}

/// Cuerpo de `POST /v1/feedback`: el resultado verificado de una petición enrutada por `auto`.
#[derive(Deserialize)]
struct Feedback {
    /// El `x-nexodeck-request-id` que devolvió la petición.
    request_id: String,
    /// ¿Pasó la verificación? (los tests, la compilación, la revisión… lo que use quien informa).
    verified: bool,
    /// Con qué se verificó, para poder separar después los resultados por tipo de verificador.
    #[serde(default)]
    verifier: Option<String>,
    /// Nota opcional de 0 a 1 cuando la verificación no es binaria (p. ej. la fracción de tests).
    #[serde(default)]
    score: Option<f64>,
}

fn is_plain_token(text: &str, max_len: usize, allow_dot: bool) -> bool {
    !text.is_empty()
        && text.len() <= max_len
        && text
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || (allow_dot && c == '.'))
}

/// Informa del resultado verificado de una petición `auto` (ver `decisions.rs`).
///
/// Solo guarda medidas: nunca texto libre (un campo de notas sería justo por donde se colaría el
/// contenido de un prompt). Solo puede informar la clave que hizo la petición, una sola vez.
async fn feedback(State(state): State<Arc<AppState>>, headers: HeaderMap, body: Bytes) -> Response {
    let Some(key_name) = authorize(&state, &headers) else {
        return unauthorized();
    };
    let Ok(report) = serde_json::from_slice::<Feedback>(&body) else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_request_error",
            "El cuerpo debe ser un JSON con `request_id` (texto) y `verified` (true o false); opcionales: `verifier` (texto corto) y `score` (0 a 1).",
        );
    };
    if !is_plain_token(&report.request_id, 64, false) {
        return error_response(StatusCode::BAD_REQUEST, "invalid_request_error", "`request_id` no tiene el formato esperado.");
    }
    if let Some(verifier) = &report.verifier {
        if !is_plain_token(verifier, 40, true) {
            return error_response(
                StatusCode::BAD_REQUEST,
                "invalid_request_error",
                "`verifier` admite hasta 40 caracteres entre letras, números, `_`, `-` y `.`.",
            );
        }
    }
    if let Some(score) = report.score {
        if !score.is_finite() || !(0.0..=1.0).contains(&score) {
            return error_response(StatusCode::BAD_REQUEST, "invalid_request_error", "`score` tiene que estar entre 0 y 1.");
        }
    }

    let now = logging::now_unix();
    let entry = json!({
        "type": "outcome",
        "id": report.request_id,
        "verified": report.verified,
        "verifier": report.verifier,
        "score": report.score,
        "key": key_name,
        "unix": now,
        "time": logging::utc_timestamp(now),
    });
    match state.decisions.record_outcome(&report.request_id, &key_name, &entry) {
        OutcomeResult::Recorded => Json(json!({ "recorded": true })).into_response(),
        OutcomeResult::UnknownId => error_response(
            StatusCode::NOT_FOUND,
            "unknown_request_id",
            "No hay ninguna petición reciente con ese `request_id` hecha con esta clave (solo se recuerdan las últimas 10 000).",
        ),
        OutcomeResult::AlreadyRecorded => error_response(
            StatusCode::CONFLICT,
            "outcome_already_recorded",
            "Esa petición ya tiene un resultado registrado.",
        ),
        OutcomeResult::Disabled => error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "decision_log_disabled",
            "El registro de decisiones no está activo en esta pasarela: no se puede guardar el resultado.",
        ),
        OutcomeResult::WriteFailed => {
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "write_failed", "No se pudo escribir el resultado.")
        }
    }
}

/// Cabeceras de la respuesta de vLLM que sí se devuelven al cliente. El resto (incluidas las que
/// identifican el servidor) se descarta.
const FORWARDED_RESPONSE_HEADERS: [HeaderName; 2] = [header::CONTENT_TYPE, header::CACHE_CONTROL];

async fn completion(
    State(state): State<Arc<AppState>>,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    let started = Instant::now();
    let Some(key_name) = authorize(&state, &headers) else {
        logging::line(&format!("{} sin clave válida -> 401", uri.path()));
        return unauthorized();
    };
    // Foto de la configuración para toda la petición: si el monitor la recarga a
    // mitad, esta petición sigue con la que empezo.
    let config = state.config();

    // Solo se lee `model` del cuerpo; el cuerpo original se reenvía intacto, salvo para `auto`.
    let parsed = serde_json::from_slice::<Value>(&body).ok();
    let requested = parsed
        .as_ref()
        .and_then(|value| value.get("model"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let Some(requested) = requested else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_request_error",
            "El cuerpo debe ser un JSON con el campo `model`.",
        );
    };

    // `auto` es un modelo virtual: se elige uno real y se REESCRIBE el campo `model` del cuerpo,
    // porque vLLM solo conoce los nombres de los modelos que sirve y contestaría 404 a `auto`.
    let mut routing: Option<Routing> = None;
    let (model, body) = if requested == AUTO_MODEL {
        let mut value = parsed.expect("`requested` sale de `parsed`");
        let features = route::features_from_request(&value);
        let availability = availability_snapshot(&state);
        let worker = config
            .auto
            .workers
            .iter()
            .find(|model| availability.get(*model) == Some(&Availability::Up))
            .map(String::as_str);
        let decision = route::decide(&config.auto, &features);
        let decision = route::apply_domain(&config.auto, decision, &features, worker);
        let (chosen, fallback) = resolve_target(&config, &availability, decision.tier);
        value["model"] = Value::String(chosen.clone());
        let rewritten = serde_json::to_vec(&value).map(Bytes::from).unwrap_or(body);
        // El id se recuerda ANTES de responder: el cliente puede informar del resultado en cuanto
        // termine de leer la respuesta.
        let id = new_request_id();
        state.decisions.register(&id, &key_name);
        routing = Some(Routing {
            id,
            decision: decision.name,
            prompt_chars: features.prompt_chars,
            has_tools: features.has_tools,
            fallback,
        });
        (chosen, rewritten)
    } else {
        (requested, body)
    };

    let Some(backend) = config.backend(&model) else {
        let known: Vec<&str> = config.backends.keys().map(String::as_str).collect();
        return error_response(
            StatusCode::NOT_FOUND,
            "model_not_found",
            &format!("El modelo '{model}' no existe. Modelos: {}.", known.join(", ")),
        );
    };

    // Si el destino es un servicio por internet con otro nombre de modelo, se
    // reescribe el campo `model` (el cliente pidió `fast`, el servicio espera
    // `deepseek-chat`). El resto del cuerpo se reenvía intacto.
    let body = match backend.upstream_model() {
        Some(upstream) if upstream != model => {
            let mut value: Value =
                serde_json::from_slice(&body).unwrap_or_else(|_| json!({ "model": upstream }));
            value["model"] = Value::String(upstream.to_string());
            serde_json::to_vec(&value).map(Bytes::from).unwrap_or(body)
        }
        _ => body,
    };

    let mut request = state
        .client
        .post(format!("{}{}", backend.base_url(), uri.path()))
        .body(body);
    if let Some(content_type) = headers.get(header::CONTENT_TYPE) {
        request = request.header(header::CONTENT_TYPE, content_type);
    }
    // La clave del servicio reemplaza a la de la pasarela: el servicio externo
    // no conoce `ndk_...`. Sin clave (un vLLM local) no se manda ninguna.
    if let Some(api_key) = backend.api_key() {
        request = request.bearer_auth(api_key);
    }

    let upstream = match request.send().await {
        Ok(upstream) => upstream,
        Err(error) => {
            let (status, kind, message) = if error.is_connect() {
                (
                    StatusCode::SERVICE_UNAVAILABLE,
                    "backend_unavailable",
                    format!("El modelo '{model}' no está levantado ahora mismo (perfil activo distinto o arrancando)."),
                )
            } else if error.is_timeout() {
                (StatusCode::GATEWAY_TIMEOUT, "backend_timeout", format!("El modelo '{model}' no respondió a tiempo."))
            } else {
                (StatusCode::BAD_GATEWAY, "backend_error", format!("Error hablando con el modelo '{model}'."))
            };
            logging::line(&format!("clave={key_name} modelo={model} {} -> {}", uri.path(), status.as_u16()));
            if let Some(routing) = &routing {
                record_decision(&state, &key_name, routing, &model, status, started);
            }
            return error_response(status, kind, &message);
        }
    };

    let status = upstream.status();
    let decision_note = routing.as_ref().map(|r| format!(" decision={}", r.decision)).unwrap_or_default();
    logging::line(&format!(
        "clave={key_name} modelo={model}{decision_note} {} -> {} ({} ms hasta la primera respuesta)",
        uri.path(),
        status.as_u16(),
        started.elapsed().as_millis()
    ));
    if let Some(routing) = &routing {
        record_decision(&state, &key_name, routing, &model, status, started);
    }

    let mut builder = Response::builder().status(status);
    for name in &FORWARDED_RESPONSE_HEADERS {
        if let Some(value) = upstream.headers().get(name) {
            builder = builder.header(name, value);
        }
    }
    // Para `auto`, el cliente puede saber qué se eligió sin leer el registro.
    if let Some(routing) = &routing {
        builder = builder.header("x-nexodeck-decision", routing.decision);
        if let Ok(value) = axum::http::HeaderValue::from_str(&routing.id) {
            builder = builder.header("x-nexodeck-request-id", value);
        }
        if let Ok(value) = axum::http::HeaderValue::from_str(&model) {
            builder = builder.header("x-nexodeck-model", value);
        }
    }
    // El cuerpo se reenvía como flujo, sin acumularlo: así el SSE (`stream: true`) llega token a
    // token y una respuesta larga no ocupa memoria de la pasarela.
    builder
        .body(Body::from_stream(upstream.bytes_stream()))
        .unwrap_or_else(|_| error_response(StatusCode::BAD_GATEWAY, "backend_error", "Respuesta ilegible."))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn up(models: &[&str]) -> BTreeMap<String, Availability> {
        ["router", "fast", "complex"]
            .iter()
            .map(|model| {
                let state = if models.contains(model) { Availability::Up } else { Availability::Down };
                (model.to_string(), state)
            })
            .collect()
    }

    fn resolve(models: &[&str], tier: Tier) -> (String, bool) {
        resolve_target(&Config::default(), &up(models), tier)
    }

    #[test]
    fn with_profile_b_the_worker_is_the_complex_model() {
        assert_eq!(resolve(&["router", "complex"], Tier::Worker), ("complex".to_string(), false));
        assert_eq!(resolve(&["router", "complex"], Tier::Light), ("router".to_string(), false));
    }

    #[test]
    fn with_profile_a_the_worker_is_the_fast_model() {
        assert_eq!(resolve(&["router", "fast"], Tier::Worker), ("fast".to_string(), false));
    }

    #[test]
    fn the_first_worker_that_is_up_wins() {
        // No deberían convivir, pero si lo hicieran manda el orden de `workers`.
        assert_eq!(resolve(&["router", "fast", "complex"], Tier::Worker).0, "complex");
    }

    #[test]
    fn a_worker_request_falls_back_to_the_light_model_when_no_worker_is_up() {
        assert_eq!(resolve(&["router"], Tier::Worker), ("router".to_string(), true));
    }

    #[test]
    fn a_light_request_falls_back_to_the_worker_when_the_router_is_down() {
        assert_eq!(resolve(&["complex"], Tier::Light), ("complex".to_string(), true));
    }

    #[test]
    fn with_nothing_up_the_requested_tier_is_kept_so_the_503_is_clear() {
        assert_eq!(resolve(&[], Tier::Worker), ("complex".to_string(), false));
        assert_eq!(resolve(&[], Tier::Light), ("router".to_string(), false));
    }

    #[test]
    fn unknown_availability_is_not_treated_as_up() {
        let unknown: BTreeMap<String, Availability> =
            [("router".to_string(), Availability::Unknown)].into_iter().collect();
        assert_eq!(resolve_target(&Config::default(), &unknown, Tier::Light), ("router".to_string(), false));
        assert!(!resolve_target(&Config::default(), &unknown, Tier::Worker).1);
    }
}
