//! Pruebas de integración: servidores vLLM de mentira + la pasarela real, hablando por HTTP.

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::body::{Body, Bytes};
use axum::http::{header, HeaderMap};
use axum::response::Response;
use axum::routing::{get, post};
use axum::Router;
use futures_util::StreamExt;
use llm_gateway::auth::KeyStore;
use llm_gateway::config::{BackendConfig, BackendDetails, Config};
use llm_gateway::decisions::DecisionLog;
use llm_gateway::{build_app, build_app_with};
use tokio::net::TcpListener;

async fn spawn(app: Router) -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    address
}

/// Un puerto en el que seguro no escucha nadie (se reserva y se suelta).
async fn closed_port() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    listener.local_addr().unwrap()
}

/// Servidor vLLM de mentira. Contesta con un flujo SSE de tres trozos separados por 60 ms, el
/// primero con su nombre y el cuerpo que recibió, y cuenta las visitas a `/sleep`.
fn fake_vllm(name: &'static str, admin_hits: Arc<AtomicUsize>) -> Router {
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route(
            "/v1/chat/completions",
            post(move |body: Bytes| async move {
                let received = String::from_utf8_lossy(&body).to_string();
                let chunks = futures_util::stream::iter(0..3).then(move |index| {
                    let received = received.clone();
                    async move {
                        tokio::time::sleep(Duration::from_millis(60)).await;
                        let text = if index == 0 {
                            format!("data: {name} recibido={received}\n\n")
                        } else {
                            format!("data: {name} trozo {index}\n\n")
                        };
                        Ok::<_, Infallible>(Bytes::from(text))
                    }
                });
                Response::builder()
                    .header(header::CONTENT_TYPE, "text/event-stream")
                    .body(Body::from_stream(chunks))
                    .unwrap()
            }),
        )
        .route(
            "/sleep",
            post(move || {
                let admin_hits = admin_hits.clone();
                async move {
                    admin_hits.fetch_add(1, Ordering::SeqCst);
                    "dormido"
                }
            }),
        )
}

struct Gateway {
    address: SocketAddr,
    key: String,
    keys_path: std::path::PathBuf,
    _directory: tempfile::TempDir,
}

impl Gateway {
    fn url(&self, path: &str) -> String {
        format!("http://{}{path}", self.address)
    }
}

async fn start_gateway(backends: &[(&str, SocketAddr)], max_body_bytes: usize) -> Gateway {
    let directory = tempfile::tempdir().unwrap();
    let keys_path = directory.path().join("keys.json");
    let store = KeyStore::new(keys_path.clone());
    let key = store.add("pruebas").unwrap();

    let config = Config {
        max_body_bytes,
        backends: backends
            .iter()
            .map(|(model, address)| {
                (model.to_string(), BackendConfig::Simple(format!("http://{address}")))
            })
            .collect(),
        ..Config::default()
    };

    let address = spawn(build_app(config, KeyStore::new(keys_path.clone()))).await;
    Gateway { address, key, keys_path, _directory: directory }
}

/// Como `start_gateway`, pero guardando las decisiones de `auto` en `log_path`.
async fn start_gateway_logged(backends: &[(&str, SocketAddr)], log_path: &std::path::Path) -> Gateway {
    let directory = tempfile::tempdir().unwrap();
    let keys_path = directory.path().join("keys.json");
    let key = KeyStore::new(keys_path.clone()).add("pruebas").unwrap();
    let config = Config {
        backends: backends
            .iter()
            .map(|(model, address)| {
                (model.to_string(), BackendConfig::Simple(format!("http://{address}")))
            })
            .collect(),
        ..Config::default()
    };
    let decisions = DecisionLog::to_file(log_path).unwrap();
    let address = spawn(build_app_with(config, KeyStore::new(keys_path.clone()), decisions)).await;
    Gateway { address, key, keys_path, _directory: directory }
}

fn client() -> reqwest::Client {
    reqwest::Client::new()
}

/// Espera a que el sondeo de fondo haya visto todos los modelos (deja de haber `unknown`) y
/// devuelve el cuerpo de `/health`.
async fn wait_for_probe(gateway: &Gateway) -> String {
    for _ in 0..50 {
        let text = client().get(gateway.url("/health")).send().await.unwrap().text().await.unwrap();
        if !text.contains("unknown") {
            return text;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    panic!("el sondeo de fondo no terminó en 5 s");
}

async fn post_completion(gateway: &Gateway, key: Option<&str>, body: &str) -> reqwest::Response {
    let mut request = client()
        .post(gateway.url("/v1/chat/completions"))
        .header("content-type", "application/json")
        .body(body.to_string());
    if let Some(key) = key {
        request = request.header("authorization", format!("Bearer {key}"));
    }
    request.send().await.unwrap()
}

#[tokio::test]
async fn health_needs_no_key_and_reports_which_models_are_up() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up), ("fast", closed_port().await)], 1 << 20).await;

    let response = client().get(gateway.url("/health")).send().await.unwrap();
    assert_eq!(response.status(), 200, "sin clave debe responder");

    let text = wait_for_probe(&gateway).await;
    assert!(text.contains(r#""router":"up""#), "{text}");
    assert!(text.contains(r#""fast":"down""#), "{text}");
}

#[tokio::test]
async fn health_answers_at_once_even_when_a_model_accepts_connections_but_never_replies() {
    // Un servidor que acepta la conexión y no contesta es lo peor para un sondeo: aguanta hasta su
    // tiempo de espera (2 s). `/health` no puede depender de eso: lo usa el script de arranque con
    // un tiempo de espera propio y, si la pasarela tardaba, abortaba sin arrancar los modelos.
    let stalled = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let gateway = start_gateway(&[("complex", stalled.local_addr().unwrap())], 1 << 20).await;

    tokio::time::sleep(Duration::from_millis(300)).await; // que el sondeo de fondo ya esté colgado
    let started = Instant::now();
    let response = client().get(gateway.url("/health")).send().await.unwrap();
    assert_eq!(response.status(), 200);
    assert!(
        started.elapsed() < Duration::from_millis(500),
        "/health tardó {:?}: no debe esperar a los servidores",
        started.elapsed()
    );
    drop(stalled);
}

#[tokio::test]
async fn a_request_without_key_is_refused_with_401() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    let response = post_completion(&gateway, None, r#"{"model":"router"}"#).await;
    assert_eq!(response.status(), 401);
    assert_eq!(response.headers()["www-authenticate"], "Bearer");
}

#[tokio::test]
async fn a_missing_key_and_a_wrong_key_get_the_same_answer() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    let missing = post_completion(&gateway, None, r#"{"model":"router"}"#).await;
    let wrong = post_completion(&gateway, Some("ndk_incorrecta"), r#"{"model":"router"}"#).await;
    assert_eq!(missing.status(), wrong.status());
    assert_eq!(missing.text().await.unwrap(), wrong.text().await.unwrap());
}

#[tokio::test]
async fn the_bearer_scheme_is_case_insensitive_but_a_malformed_header_is_refused() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    let lowercase = client()
        .post(gateway.url("/v1/chat/completions"))
        .header("authorization", format!("bearer {}", gateway.key))
        .body(r#"{"model":"router"}"#)
        .send()
        .await
        .unwrap();
    assert_eq!(lowercase.status(), 200);

    let no_scheme = client()
        .post(gateway.url("/v1/chat/completions"))
        .header("authorization", gateway.key.clone())
        .body(r#"{"model":"router"}"#)
        .send()
        .await
        .unwrap();
    assert_eq!(no_scheme.status(), 401);
}

#[tokio::test]
async fn a_valid_key_routes_by_model_and_forwards_the_body_intact() {
    let router = spawn(fake_vllm("ROUTER", Arc::default())).await;
    let fast = spawn(fake_vllm("FAST", Arc::default())).await;
    let gateway = start_gateway(&[("router", router), ("fast", fast)], 1 << 20).await;

    let body = r#"{"model":"fast","messages":[{"role":"user","content":"hola ñandú"}]}"#;
    let text = post_completion(&gateway, Some(&gateway.key), body).await.text().await.unwrap();
    assert!(text.contains("data: FAST"), "tenía que ir al servidor rápido: {text}");
    assert!(!text.contains("ROUTER"));
    assert!(text.contains("hola ñandú"), "el cuerpo debe llegar intacto: {text}");
}

#[tokio::test]
async fn the_stream_arrives_piece_by_piece_and_not_all_at_the_end() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    let started = Instant::now();
    let response = post_completion(&gateway, Some(&gateway.key), r#"{"model":"router"}"#).await;
    assert_eq!(response.headers()["content-type"], "text/event-stream");

    let mut stream = response.bytes_stream();
    let first = stream.next().await.unwrap().unwrap();
    let first_at = started.elapsed();
    assert!(!first.is_empty());
    while stream.next().await.is_some() {}
    let total = started.elapsed();

    // Tres trozos separados por 60 ms: el primero llega mucho antes de que acabe el último.
    assert!(
        total.saturating_sub(first_at) >= Duration::from_millis(80),
        "el flujo llegó de golpe: primer trozo a {first_at:?}, final a {total:?}"
    );
}

#[tokio::test]
async fn an_unknown_model_is_404_and_lists_the_known_ones() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    let response = post_completion(&gateway, Some(&gateway.key), r#"{"model":"gpt-99"}"#).await;
    assert_eq!(response.status(), 404);
    let text = response.text().await.unwrap();
    assert!(text.contains("gpt-99") && text.contains("router"), "{text}");
}

#[tokio::test]
async fn a_body_without_model_is_a_400() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    assert_eq!(post_completion(&gateway, Some(&gateway.key), r#"{"messages":[]}"#).await.status(), 400);
    assert_eq!(post_completion(&gateway, Some(&gateway.key), "esto no es json").await.status(), 400);
}

#[tokio::test]
async fn a_model_that_is_not_running_gives_503_with_a_clear_message() {
    let gateway = start_gateway(&[("complex", closed_port().await)], 1 << 20).await;

    let response = post_completion(&gateway, Some(&gateway.key), r#"{"model":"complex"}"#).await;
    assert_eq!(response.status(), 503);
    assert!(response.text().await.unwrap().contains("no está levantado"));
}

#[tokio::test]
async fn vllm_admin_routes_are_not_reachable_even_with_a_valid_key() {
    let admin_hits = Arc::new(AtomicUsize::new(0));
    let up = spawn(fake_vllm("A", admin_hits.clone())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;

    for path in ["/sleep", "/wake_up", "/collective_rpc", "/metrics", "/is_sleeping", "/v1/embeddings"] {
        let response = client()
            .post(gateway.url(path))
            .header("authorization", format!("Bearer {}", gateway.key))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), 404, "{path} no debería existir en la pasarela");
    }
    assert_eq!(admin_hits.load(Ordering::SeqCst), 0, "ninguna petición debe llegar a /sleep de vLLM");
}

#[tokio::test]
async fn models_lists_only_what_is_running_and_needs_a_key() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up), ("complex", closed_port().await)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    assert_eq!(client().get(gateway.url("/v1/models")).send().await.unwrap().status(), 401);

    let text = client()
        .get(gateway.url("/v1/models"))
        .header("authorization", format!("Bearer {}", gateway.key))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(text.contains(r#""id":"router""#), "{text}");
    assert!(!text.contains("complex"), "un modelo apagado no debe aparecer: {text}");
}

#[tokio::test]
async fn an_oversized_body_is_refused_with_413() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1024).await;

    let huge = format!(r#"{{"model":"router","padding":"{}"}}"#, "x".repeat(4096));
    let response = post_completion(&gateway, Some(&gateway.key), &huge).await;
    assert_eq!(response.status(), 413);
}

// ---------------------------------------------------------------------------------------------
// Modelo virtual `auto`
// ---------------------------------------------------------------------------------------------

fn auto_request(text: &str) -> String {
    serde_json::json!({ "model": "auto", "messages": [{ "role": "user", "content": text }] }).to_string()
}

/// Un texto largo y sin palabras clave (decisión `complex` por longitud). Menciona `python` para
/// que además cuente como código: con el Complejo como trabajador, lo que no es código no llega a él.
fn long_text() -> String {
    "la casa es azul y el sol brilla en python. ".repeat(40)
}

/// Lo mismo pero sin nada de código.
fn long_plain_text() -> String {
    "la casa es azul y el sol brilla. ".repeat(40)
}

async fn spawn_profile_b() -> (SocketAddr, SocketAddr) {
    let router = spawn(fake_vllm("ROUTER", Arc::default())).await;
    let complex = spawn(fake_vllm("COMPLEX", Arc::default())).await;
    (router, complex)
}

#[tokio::test]
async fn auto_sends_a_short_prompt_to_the_light_model_and_a_long_one_to_the_worker() {
    let (router, complex) = spawn_profile_b().await;
    let gateway = start_gateway(&[("router", router), ("complex", complex)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let short = post_completion(&gateway, Some(&gateway.key), &auto_request("Cuanto es 17 + 25?")).await;
    assert_eq!(short.headers()["x-nexodeck-decision"], "simple");
    assert_eq!(short.headers()["x-nexodeck-model"], "router");
    assert!(short.text().await.unwrap().contains("data: ROUTER"));

    let long = post_completion(&gateway, Some(&gateway.key), &auto_request(&long_text())).await;
    assert_eq!(long.headers()["x-nexodeck-decision"], "complex");
    assert_eq!(long.headers()["x-nexodeck-model"], "complex");
    assert!(long.text().await.unwrap().contains("data: COMPLEX"));
}

#[tokio::test]
async fn with_the_code_specialist_up_auto_sends_only_code_to_it() {
    let (router, complex) = spawn_profile_b().await;
    let gateway = start_gateway(&[("router", router), ("complex", complex)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    // Un texto largo que no es código iría al Complejo por longitud; por dominio va al Router.
    let plain = post_completion(&gateway, Some(&gateway.key), &auto_request(&long_plain_text())).await;
    assert_eq!(plain.headers()["x-nexodeck-decision"], "not_code");
    assert_eq!(plain.headers()["x-nexodeck-model"], "router");
    plain.text().await.unwrap();

    // Un prompt de código corto iría al Router por longitud; por dominio va al Complejo.
    let code = post_completion(&gateway, Some(&gateway.key), &auto_request("Write a function in Python")).await;
    assert_eq!(code.headers()["x-nexodeck-decision"], "code");
    assert_eq!(code.headers()["x-nexodeck-model"], "complex");
    code.text().await.unwrap();
}

#[tokio::test]
async fn with_a_generalist_worker_only_the_code_is_redirected() {
    // Perfil A: el trabajador es `fast`, que no es un especialista.
    let router = spawn(fake_vllm("ROUTER", Arc::default())).await;
    let fast = spawn(fake_vllm("FAST", Arc::default())).await;
    let gateway = start_gateway(&[("router", router), ("fast", fast)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let plain = post_completion(&gateway, Some(&gateway.key), &auto_request(&long_plain_text())).await;
    assert_eq!(plain.headers()["x-nexodeck-decision"], "complex");
    assert_eq!(plain.headers()["x-nexodeck-model"], "fast");
    plain.text().await.unwrap();

    // El código corto iría al Router por longitud; va a Gemma, que en código rinde mucho más.
    let code = post_completion(&gateway, Some(&gateway.key), &auto_request("Write a function in Python")).await;
    assert_eq!(code.headers()["x-nexodeck-decision"], "code");
    assert_eq!(code.headers()["x-nexodeck-model"], "fast");
    code.text().await.unwrap();
}

#[tokio::test]
async fn auto_rewrites_the_model_field_but_keeps_the_rest_of_the_body() {
    let (router, complex) = spawn_profile_b().await;
    let gateway = start_gateway(&[("router", router), ("complex", complex)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let body = serde_json::json!({
        "model": "auto", "temperature": 0.25, "max_tokens": 7,
        "messages": [{ "role": "user", "content": "hola ñandú" }]
    })
    .to_string();
    let text = post_completion(&gateway, Some(&gateway.key), &body).await.text().await.unwrap();

    assert!(text.contains(r#""model":"router""#), "vLLM solo conoce nombres reales: {text}");
    assert!(!text.contains(r#""model":"auto""#), "`auto` no debe llegar a vLLM: {text}");
    assert!(text.contains("hola ñandú") && text.contains("0.25") && text.contains(r#""max_tokens":7"#), "{text}");
}

#[tokio::test]
async fn an_explicit_model_is_forwarded_untouched_and_gets_no_routing_headers() {
    let (router, complex) = spawn_profile_b().await;
    let gateway = start_gateway(&[("router", router), ("complex", complex)], 1 << 20).await;

    let response = post_completion(&gateway, Some(&gateway.key), r#"{"model":"complex","x":1}"#).await;
    assert!(response.headers().get("x-nexodeck-decision").is_none());
    assert!(response.text().await.unwrap().contains(r#"recibido={"model":"complex","x":1}"#));
}

#[tokio::test]
async fn auto_falls_back_to_the_light_model_when_no_worker_is_up() {
    let router = spawn(fake_vllm("ROUTER", Arc::default())).await;
    let gateway = start_gateway(&[("router", router), ("complex", closed_port().await)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let response = post_completion(&gateway, Some(&gateway.key), &auto_request(&long_text())).await;
    assert_eq!(response.headers()["x-nexodeck-decision"], "complex", "la decisión sigue siendo la de la longitud");
    assert_eq!(response.headers()["x-nexodeck-model"], "router", "pero se conmuta al que está levantado");
    assert!(response.text().await.unwrap().contains("data: ROUTER"));
}

#[tokio::test]
async fn auto_falls_back_to_the_worker_when_the_router_is_down() {
    let complex = spawn(fake_vllm("COMPLEX", Arc::default())).await;
    let gateway = start_gateway(&[("router", closed_port().await), ("complex", complex)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let response = post_completion(&gateway, Some(&gateway.key), &auto_request("hola")).await;
    assert_eq!(response.headers()["x-nexodeck-model"], "complex");
    assert!(response.text().await.unwrap().contains("data: COMPLEX"));
}

#[tokio::test]
async fn auto_uses_the_fast_model_as_worker_with_profile_a() {
    let router = spawn(fake_vllm("ROUTER", Arc::default())).await;
    let fast = spawn(fake_vllm("FAST", Arc::default())).await;
    let gateway = start_gateway(&[("router", router), ("fast", fast)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let response = post_completion(&gateway, Some(&gateway.key), &auto_request("Refactor this module")).await;
    assert_eq!(response.headers()["x-nexodeck-decision"], "complex_keywords");
    assert_eq!(response.headers()["x-nexodeck-model"], "fast");
}

#[tokio::test]
async fn auto_with_nothing_running_gives_a_clear_503() {
    let gateway = start_gateway(&[("router", closed_port().await), ("complex", closed_port().await)], 1 << 20).await;
    wait_for_probe(&gateway).await;

    let response = post_completion(&gateway, Some(&gateway.key), &auto_request("hola")).await;
    assert_eq!(response.status(), 503);
}

#[tokio::test]
async fn auto_is_listed_in_models_only_when_something_is_running() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let with_model = start_gateway(&[("router", up)], 1 << 20).await;
    wait_for_probe(&with_model).await;
    let text = client()
        .get(with_model.url("/v1/models"))
        .header("authorization", format!("Bearer {}", with_model.key))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(text.contains(r#""id":"auto""#), "{text}");

    let empty = start_gateway(&[("router", closed_port().await)], 1 << 20).await;
    wait_for_probe(&empty).await;
    let text = client()
        .get(empty.url("/v1/models"))
        .header("authorization", format!("Bearer {}", empty.key))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(!text.contains("auto"), "{text}");
}

#[tokio::test]
async fn every_auto_decision_is_logged_without_the_prompt_text() {
    let (router, complex) = spawn_profile_b().await;
    let directory = tempfile::tempdir().unwrap();
    let log_path = directory.path().join("decisions.jsonl");
    let gateway = start_gateway_logged(&[("router", router), ("complex", complex)], &log_path).await;
    wait_for_probe(&gateway).await;

    let secret = "SECRETO-QUE-NO-DEBE-QUEDAR-EN-EL-REGISTRO";
    let with_tools = serde_json::json!({
        "model": "auto",
        "tools": [{ "type": "function", "function": { "name": "f" } }],
        "messages": [{ "role": "user", "content": format!("hola {secret}") }]
    })
    .to_string();
    post_completion(&gateway, Some(&gateway.key), &with_tools).await.text().await.unwrap();
    post_completion(&gateway, Some(&gateway.key), &auto_request(&long_text())).await.text().await.unwrap();
    // Una petición con modelo explícito NO se registra: el registro es del enrutado.
    post_completion(&gateway, Some(&gateway.key), r#"{"model":"router"}"#).await.text().await.unwrap();

    let content = std::fs::read_to_string(&log_path).unwrap();
    assert!(!content.contains(secret), "el registro no puede guardar el texto de la petición: {content}");
    assert!(!content.contains(&gateway.key), "ni la clave");

    let lines: Vec<serde_json::Value> = content.lines().map(|line| serde_json::from_str(line).unwrap()).collect();
    assert_eq!(lines.len(), 2, "solo las peticiones `auto`: {content}");
    assert_eq!(lines[0]["type"], "decision");
    assert!(lines[0]["id"].as_str().unwrap().starts_with("req_"));
    assert_eq!(lines[0]["decision"], "simple");
    assert_eq!(lines[0]["model"], "router");
    assert_eq!(lines[0]["has_tools"], true);
    assert_eq!(lines[0]["key"], "pruebas");
    assert_eq!(lines[0]["status"], 200);
    assert_eq!(lines[0]["fallback"], false);
    assert_eq!(lines[1]["decision"], "complex");
    assert_eq!(lines[1]["model"], "complex");
    assert!(lines[1]["prompt_chars"].as_u64().unwrap() > 800);
    assert!(lines[1]["unix"].as_u64().unwrap() > 1_700_000_000);
    assert!(lines[1]["time"].as_str().unwrap().ends_with('Z'));
}

// ---------------------------------------------------------------------------------------------
// Resultado verificado de una decision (`POST /v1/feedback`)
// ---------------------------------------------------------------------------------------------

async fn post_feedback(gateway: &Gateway, key: Option<&str>, body: &str) -> reqwest::Response {
    let mut request = client()
        .post(gateway.url("/v1/feedback"))
        .header("content-type", "application/json")
        .body(body.to_string());
    if let Some(key) = key {
        request = request.header("authorization", format!("Bearer {key}"));
    }
    request.send().await.unwrap()
}

/// Hace una peticion `auto` y devuelve su `x-nexodeck-request-id`.
async fn auto_request_id(gateway: &Gateway, key: &str) -> String {
    let response = post_completion(gateway, Some(key), &auto_request("hola")).await;
    let id = response.headers()["x-nexodeck-request-id"].to_str().unwrap().to_string();
    response.text().await.unwrap();
    id
}

async fn logged_gateway() -> (Gateway, tempfile::TempDir, std::path::PathBuf) {
    let (router, complex) = spawn_profile_b().await;
    let directory = tempfile::tempdir().unwrap();
    let log_path = directory.path().join("decisions.jsonl");
    let gateway = start_gateway_logged(&[("router", router), ("complex", complex)], &log_path).await;
    wait_for_probe(&gateway).await;
    (gateway, directory, log_path)
}

#[tokio::test]
async fn an_auto_response_carries_a_request_id_and_its_outcome_is_linked_in_the_log() {
    let (gateway, _directory, log_path) = logged_gateway().await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    assert!(id.starts_with("req_") && id.len() == 20, "{id}");

    let body = serde_json::json!({ "request_id": id, "verified": true, "verifier": "humaneval-tests", "score": 1.0 });
    let response = post_feedback(&gateway, Some(&gateway.key), &body.to_string()).await;
    assert_eq!(response.status(), 200);

    let lines: Vec<serde_json::Value> = std::fs::read_to_string(&log_path)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(lines.len(), 2, "una decision y su resultado");
    assert_eq!(lines[0]["type"], "decision");
    assert_eq!(lines[1]["type"], "outcome");
    assert_eq!(lines[0]["id"], lines[1]["id"], "unidos por el id");
    assert_eq!(lines[1]["verified"], true);
    assert_eq!(lines[1]["verifier"], "humaneval-tests");
    assert_eq!(lines[1]["score"], 1.0);
    assert_eq!(lines[1]["key"], "pruebas");
}

#[tokio::test]
async fn a_failed_verification_is_recorded_too() {
    let (gateway, _directory, log_path) = logged_gateway().await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    let body = serde_json::json!({ "request_id": id, "verified": false }).to_string();
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 200);
    let content = std::fs::read_to_string(&log_path).unwrap();
    assert!(content.contains(r#""verified":false"#), "{content}");
}

#[tokio::test]
async fn feedback_needs_a_key() {
    let (gateway, _directory, _log) = logged_gateway().await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    let body = serde_json::json!({ "request_id": id, "verified": true }).to_string();
    assert_eq!(post_feedback(&gateway, None, &body).await.status(), 401);
    assert_eq!(post_feedback(&gateway, Some("ndk_incorrecta"), &body).await.status(), 401);
}

#[tokio::test]
async fn feedback_for_an_unknown_request_is_404_and_writes_nothing() {
    let (gateway, _directory, log_path) = logged_gateway().await;
    let body = serde_json::json!({ "request_id": "req_0000000000000000", "verified": true }).to_string();
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 404);
    assert!(std::fs::read_to_string(&log_path).unwrap().is_empty());
}

#[tokio::test]
async fn an_outcome_cannot_be_reported_twice() {
    let (gateway, _directory, log_path) = logged_gateway().await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    let body = serde_json::json!({ "request_id": id, "verified": true }).to_string();
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 200);
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 409);
    let outcomes = std::fs::read_to_string(&log_path).unwrap().lines().filter(|l| l.contains("outcome")).count();
    assert_eq!(outcomes, 1, "el segundo aviso no debe escribir nada");
}

#[tokio::test]
async fn another_key_cannot_report_the_outcome_of_a_request_it_did_not_make() {
    let (gateway, _directory, _log) = logged_gateway().await;
    let other_key = KeyStore::new(gateway.keys_path.clone()).add("otro-cliente").unwrap();
    tokio::time::sleep(Duration::from_millis(30)).await; // que la pasarela relea keys.json

    let id = auto_request_id(&gateway, &gateway.key).await;
    let body = serde_json::json!({ "request_id": id, "verified": false }).to_string();
    assert_eq!(
        post_feedback(&gateway, Some(&other_key), &body).await.status(),
        404,
        "se responde como si no existiera: no se revela que es de otra clave"
    );
    // Y el intento ajeno no ha gastado el resultado de la dueña.
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 200);
}

#[tokio::test]
async fn feedback_rejects_malformed_bodies_with_400() {
    let (gateway, _directory, log_path) = logged_gateway().await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    let bad = [
        "esto no es json".to_string(),
        r#"{"request_id":"req_x"}"#.to_string(),                                     // falta `verified`
        format!(r#"{{"request_id":"{id}","verified":"si"}}"#),                       // `verified` no es booleano
        r#"{"request_id":"con espacios y ../","verified":true}"#.to_string(),        // id con caracteres raros
        format!(r#"{{"request_id":"{id}","verified":true,"verifier":"tiene espacios"}}"#),
        format!(r#"{{"request_id":"{id}","verified":true,"verifier":"{}"}}"#, "x".repeat(41)),
        format!(r#"{{"request_id":"{id}","verified":true,"score":1.5}}"#),
        format!(r#"{{"request_id":"{id}","verified":true,"score":-0.1}}"#),
    ];
    for body in &bad {
        assert_eq!(post_feedback(&gateway, Some(&gateway.key), body).await.status(), 400, "{body}");
    }
    let outcomes = std::fs::read_to_string(&log_path).unwrap().lines().filter(|l| l.contains("outcome")).count();
    assert_eq!(outcomes, 0, "ningun cuerpo malformado debe llegar al registro");
}

#[tokio::test]
async fn feedback_bodies_are_capped_at_four_kilobytes() {
    let (gateway, _directory, _log) = logged_gateway().await;
    let huge = format!(r#"{{"request_id":"req_x","verified":true,"verifier":"{}"}}"#, "x".repeat(8000));
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &huge).await.status(), 413);
}

#[tokio::test]
async fn feedback_without_a_decision_log_says_so_instead_of_silently_doing_nothing() {
    let (router, complex) = spawn_profile_b().await;
    let gateway = start_gateway(&[("router", router), ("complex", complex)], 1 << 20).await; // sin registro
    wait_for_probe(&gateway).await;
    let id = auto_request_id(&gateway, &gateway.key).await;
    let body = serde_json::json!({ "request_id": id, "verified": true }).to_string();
    assert_eq!(post_feedback(&gateway, Some(&gateway.key), &body).await.status(), 503);
}

#[tokio::test]
async fn feedback_only_accepts_post() {
    let (gateway, _directory, _log) = logged_gateway().await;
    let response = client()
        .get(gateway.url("/v1/feedback"))
        .header("authorization", format!("Bearer {}", gateway.key))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 405);
}

#[tokio::test]
async fn an_older_gateway_json_without_the_auto_block_still_loads() {
    let text = r#"{ "listen": "127.0.0.1:8888", "max_body_bytes": 1024, "backends": { "router": "http://127.0.0.1:8002" } }"#;
    let config: Config = serde_json::from_str(text).expect("un gateway.json anterior debe seguir leyéndose");
    assert_eq!(config.auto.light, "router");
    assert_eq!(config.auto.simple_max_chars, 150);
}

#[tokio::test]
async fn a_revoked_key_stops_working_while_the_gateway_keeps_running() {
    let up = spawn(fake_vllm("A", Arc::default())).await;
    let gateway = start_gateway(&[("router", up)], 1 << 20).await;
    assert_eq!(post_completion(&gateway, Some(&gateway.key), r#"{"model":"router"}"#).await.status(), 200);

    tokio::time::sleep(Duration::from_millis(30)).await;
    assert!(KeyStore::new(gateway.keys_path.clone()).remove("pruebas").unwrap());

    assert_eq!(post_completion(&gateway, Some(&gateway.key), r#"{"model":"router"}"#).await.status(), 401);
}

/// Servicio por internet de mentira: guarda la cabecera `Authorization` y el
/// cuerpo que recibió, y contesta un JSON simple.
fn fake_remote(seen: Arc<std::sync::Mutex<(String, String)>>) -> Router {
    Router::new().route(
        "/v1/chat/completions",
        post(move |headers: HeaderMap, body: Bytes| {
            let seen = seen.clone();
            async move {
                let auth = headers
                    .get(header::AUTHORIZATION)
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or_default()
                    .to_string();
                let received = String::from_utf8_lossy(&body).to_string();
                *seen.lock().unwrap() = (auth, received);
                axum::Json(serde_json::json!({ "ok": true }))
            }
        }),
    )
}

/// Un destino externo recibe **la clave del servicio** (no la de la pasarela) y
/// el nombre real del modelo, no la clave del backend.
#[tokio::test]
async fn un_backend_remoto_recibe_su_clave_y_el_modelo_rio_arriba() {
    let seen = Arc::new(std::sync::Mutex::new((String::new(), String::new())));
    let remote = spawn(fake_remote(seen.clone())).await;

    // La clave vive en un fichero: es lo que hace NexoDeck con `ai_remote_key_path`.
    let key_file = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(key_file.path(), "sk-remota\n").unwrap();

    let mut backends = std::collections::BTreeMap::new();
    backends.insert(
        "fast".to_string(),
        BackendConfig::Detailed(BackendDetails {
            url: format!("http://{remote}"),
            api_key_file: Some(key_file.path().to_string_lossy().into_owned()),
            api_key_env: None,
            upstream_model: Some("deepseek-chat".into()),
        }),
    );

    let directory = tempfile::tempdir().unwrap();
    let keys_path = directory.path().join("keys.json");
    let key = KeyStore::new(keys_path.clone()).add("pruebas").unwrap();
    let config = Config { backends, ..Config::default() };
    let address = spawn(build_app(config, KeyStore::new(keys_path.clone()))).await;

    let response = reqwest::Client::new()
        .post(format!("http://{address}/v1/chat/completions"))
        .header(header::AUTHORIZATION, format!("Bearer {key}"))
        .header(header::CONTENT_TYPE, "application/json")
        .body(r#"{"model":"fast","messages":[{"role":"user","content":"hola"}]}"#)
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);

    let (auth, received) = seen.lock().unwrap().clone();
    assert_eq!(auth, "Bearer sk-remota");
    assert!(
        received.contains("\"model\":\"deepseek-chat\""),
        "el servicio no recibió el modelo río arriba: {received}"
    );
    // La clave de la pasarela no llegó al servicio.
    assert!(!received.contains(&key));
}
