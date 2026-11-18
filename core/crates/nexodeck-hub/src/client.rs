//! La conexion viva de una suscripcion: negotiate + handshake + invocacion
//! para SignalR, o solo conectar y leer para un WebSocket crudo. Corre en su
//! propia tarea de tokio (ver `manager.rs::start_subscription`), y solo se
//! comunica hacia afuera mandando `HubEvent`s al broadcast compartido -- no
//! hay ningun estado que otro modulo lea directo de aca.

use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use tokio::sync::{broadcast, oneshot};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::Connector;

use crate::protocol::{self, HubMessage};
use crate::{HubEvent, SubscriptionKind};

pub(crate) async fn run_connection(
    subscription_id: String,
    base_url: String,
    kind: SubscriptionKind,
    allow_invalid_cert: bool,
    events: broadcast::Sender<HubEvent>,
    cancel: oneshot::Receiver<()>,
) {
    match kind {
        SubscriptionKind::RawWebSocket => {
            run_raw(subscription_id, base_url, allow_invalid_cert, events, cancel).await;
        }
        SubscriptionKind::SignalR {
            hub_path,
            invoke_method,
            invoke_args,
        } => {
            run_signalr(
                subscription_id,
                base_url,
                hub_path,
                invoke_method,
                invoke_args,
                allow_invalid_cert,
                events,
                cancel,
            )
            .await;
        }
    }
}

/// `None` = usar el default de `tokio-tungstenite` (valida contra las raices
/// de `webpki-roots`, via el feature `rustls-tls-webpki-roots`). `Some` solo
/// cuando el usuario prendio el toggle de certificado invalido a mano.
fn connector_for(allow_invalid_cert: bool) -> Option<Connector> {
    allow_invalid_cert.then(|| Connector::Rustls(Arc::new(crate::tls::insecure_client_config())))
}

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn connect_ws(url: &str, allow_invalid_cert: bool) -> Result<WsStream, String> {
    let connector = connector_for(allow_invalid_cert);
    let (stream, _response) =
        tokio_tungstenite::connect_async_tls_with_config(url, None, false, connector)
            .await
            .map_err(|e| e.to_string())?;
    Ok(stream)
}

// ---------------------------------------------------------------------
// WebSocket crudo
// ---------------------------------------------------------------------

async fn run_raw(
    subscription_id: String,
    ws_url: String,
    allow_invalid_cert: bool,
    events: broadcast::Sender<HubEvent>,
    mut cancel: oneshot::Receiver<()>,
) {
    let stream = match connect_ws(&ws_url, allow_invalid_cert).await {
        Ok(s) => s,
        Err(error) => {
            let _ = events.send(HubEvent::Failed {
                subscription_id,
                error: format!("conexion: {error}"),
            });
            return;
        }
    };
    let (mut write, mut read) = stream.split();
    let _ = events.send(HubEvent::Connected {
        subscription_id: subscription_id.clone(),
    });

    loop {
        tokio::select! {
            _ = &mut cancel => {
                let _ = write.send(Message::Close(None)).await;
                let _ = events.send(HubEvent::Stopped { subscription_id });
                return;
            }
            msg = read.next() => match msg {
                Some(Ok(Message::Text(text))) => {
                    let _ = events.send(HubEvent::MessageReceived {
                        subscription_id: subscription_id.clone(),
                        event_name: "message".to_string(),
                        payload_json: text,
                    });
                }
                Some(Ok(Message::Binary(bytes))) => {
                    // No se decodifica: un WS crudo puede mandar cualquier
                    // cosa. Se deja constancia del tamano en vez de
                    // silenciarlo.
                    let _ = events.send(HubEvent::MessageReceived {
                        subscription_id: subscription_id.clone(),
                        event_name: "binary".to_string(),
                        payload_json: format!("\"<{} bytes binarios>\"", bytes.len()),
                    });
                }
                Some(Ok(Message::Close(_))) | None => {
                    let _ = events.send(HubEvent::Disconnected {
                        subscription_id,
                        reason: "conexion cerrada".to_string(),
                    });
                    return;
                }
                Some(Ok(_)) => {} // ping/pong/frame, ignorar
                Some(Err(e)) => {
                    let _ = events.send(HubEvent::Disconnected {
                        subscription_id,
                        reason: e.to_string(),
                    });
                    return;
                }
            },
        }
    }
}

// ---------------------------------------------------------------------
// SignalR
// ---------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
async fn run_signalr(
    subscription_id: String,
    base_url: String,
    hub_path: String,
    invoke_method: String,
    invoke_args: Vec<serde_json::Value>,
    allow_invalid_cert: bool,
    events: broadcast::Sender<HubEvent>,
    mut cancel: oneshot::Receiver<()>,
) {
    let origin = base_url.trim_end_matches('/');
    let path = if hub_path.starts_with('/') {
        hub_path.clone()
    } else {
        format!("/{hub_path}")
    };

    let http_client = match reqwest::Client::builder()
        .danger_accept_invalid_certs(allow_invalid_cert)
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            let _ = events.send(HubEvent::Failed {
                subscription_id,
                error: format!("cliente http: {e}"),
            });
            return;
        }
    };

    let negotiate_url = format!("{origin}{path}/negotiate?negotiateVersion=1");
    let connection_id = match negotiate(&http_client, &negotiate_url).await {
        Ok(id) => id,
        Err(error) => {
            let _ = events.send(HubEvent::Failed {
                subscription_id,
                error: format!("negotiate: {error}"),
            });
            return;
        }
    };

    // http(s) -> ws(s), mismo host y puerto.
    let ws_scheme = if origin.starts_with("https") {
        "wss"
    } else {
        "ws"
    };
    let host_and_rest = origin.splitn(2, "://").nth(1).unwrap_or(origin);
    let ws_url = format!("{ws_scheme}://{host_and_rest}{path}?id={connection_id}");

    let stream = match connect_ws(&ws_url, allow_invalid_cert).await {
        Ok(s) => s,
        Err(error) => {
            let _ = events.send(HubEvent::Failed {
                subscription_id,
                error: format!("conexion ws: {error}"),
            });
            return;
        }
    };
    let (mut write, mut read) = stream.split();

    if let Err(e) = write.send(Message::Text(protocol::handshake_message())).await {
        let _ = events.send(HubEvent::Failed {
            subscription_id,
            error: format!("no se pudo mandar el handshake: {e}"),
        });
        return;
    }

    // El primer registro que llega es SIEMPRE la respuesta del handshake --
    // no se invoca nada hasta confirmarlo.
    let handshake_result = loop {
        match read.next().await {
            Some(Ok(Message::Text(text))) => {
                let records = protocol::split_records(&text);
                let Some(first) = records.first() else {
                    continue;
                };
                break protocol::parse_record(first, true);
            }
            Some(Ok(_)) => continue,
            Some(Err(e)) => {
                let _ = events.send(HubEvent::Failed {
                    subscription_id,
                    error: format!("handshake: {e}"),
                });
                return;
            }
            None => {
                let _ = events.send(HubEvent::Failed {
                    subscription_id,
                    error: "la conexion se cerro durante el handshake".to_string(),
                });
                return;
            }
        }
    };
    if let HubMessage::HandshakeError(err) = handshake_result {
        let _ = events.send(HubEvent::Failed {
            subscription_id,
            error: format!("el servidor rechazo el handshake: {err}"),
        });
        return;
    }

    if let Err(e) = write
        .send(Message::Text(protocol::invocation_message(
            &invoke_method,
            &invoke_args,
        )))
        .await
    {
        let _ = events.send(HubEvent::Failed {
            subscription_id,
            error: format!("no se pudo invocar {invoke_method}: {e}"),
        });
        return;
    }

    let _ = events.send(HubEvent::Connected {
        subscription_id: subscription_id.clone(),
    });

    loop {
        tokio::select! {
            _ = &mut cancel => {
                let _ = write.send(Message::Close(None)).await;
                let _ = events.send(HubEvent::Stopped { subscription_id });
                return;
            }
            msg = read.next() => match msg {
                Some(Ok(Message::Text(text))) => {
                    for record in protocol::split_records(&text) {
                        match protocol::parse_record(record, false) {
                            HubMessage::Invocation { target, arguments_json } => {
                                let _ = events.send(HubEvent::MessageReceived {
                                    subscription_id: subscription_id.clone(),
                                    event_name: target,
                                    payload_json: arguments_json,
                                });
                            }
                            HubMessage::Close { error } => {
                                let _ = events.send(HubEvent::Disconnected {
                                    subscription_id: subscription_id.clone(),
                                    reason: error.unwrap_or_else(|| "el servidor cerro la conexion".to_string()),
                                });
                                return;
                            }
                            // Ping y el resto (StreamItem/Completion/etc.):
                            // nada que hacer, no los usamos.
                            _ => {}
                        }
                    }
                }
                Some(Ok(Message::Close(_))) | None => {
                    let _ = events.send(HubEvent::Disconnected {
                        subscription_id,
                        reason: "conexion cerrada".to_string(),
                    });
                    return;
                }
                Some(Ok(_)) => {}
                Some(Err(e)) => {
                    let _ = events.send(HubEvent::Disconnected {
                        subscription_id,
                        reason: e.to_string(),
                    });
                    return;
                }
            },
        }
    }
}

async fn negotiate(client: &reqwest::Client, url: &str) -> Result<String, String> {
    let response = client.post(url).send().await.map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("status {}", response.status()));
    }
    let body: serde_json::Value = response.json().await.map_err(|e| e.to_string())?;
    body.get("connectionId")
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| "la respuesta de negotiate no trae connectionId".to_string())
}
