use crate::frb_generated::StreamSink;

/// Espejo de `nexodeck_hub::SubscriptionKind`. `SignalR` necesita el camino
/// completo (negotiate + handshake + invocar un metodo del hub);
/// `RawWebSocket` es solo conectar y leer -- sin metodo que invocar.
#[derive(Debug, Clone)]
pub enum HubSubscriptionKind {
    SignalR {
        /// Ej. `/hubs/plant-training-progress`.
        hub_path: String,
        /// Metodo del hub a invocar apenas conecta, ej. `SubscribeToJob`.
        invoke_method: String,
        /// Cada argumento ya serializado a JSON (`"job-123"`, `42`, `true`) --
        /// el lado Dart arma la lista, este archivo solo la reparsea para
        /// mandarla como `serde_json::Value` real y no como texto plano.
        invoke_args_json: Vec<String>,
    },
    RawWebSocket,
}

impl HubSubscriptionKind {
    fn into_core(self) -> Result<nexodeck_hub::SubscriptionKind, String> {
        Ok(match self {
            HubSubscriptionKind::RawWebSocket => nexodeck_hub::SubscriptionKind::RawWebSocket,
            HubSubscriptionKind::SignalR {
                hub_path,
                invoke_method,
                invoke_args_json,
            } => {
                let invoke_args = invoke_args_json
                    .iter()
                    .map(|arg| serde_json::from_str(arg).map_err(|e| format!("argumento invalido {arg:?}: {e}")))
                    .collect::<Result<Vec<serde_json::Value>, String>>()?;
                nexodeck_hub::SubscriptionKind::SignalR {
                    hub_path,
                    invoke_method,
                    invoke_args,
                }
            }
        })
    }
}

#[derive(Debug, Clone)]
pub enum HubSubscriptionEvent {
    Connected {
        subscription_id: String,
    },
    MessageReceived {
        subscription_id: String,
        event_name: String,
        payload_json: String,
    },
    Disconnected {
        subscription_id: String,
        reason: String,
    },
    Stopped {
        subscription_id: String,
    },
    Failed {
        subscription_id: String,
        error: String,
    },
}

impl From<nexodeck_hub::HubEvent> for HubSubscriptionEvent {
    fn from(value: nexodeck_hub::HubEvent) -> Self {
        use nexodeck_hub::HubEvent as E;
        match value {
            E::Connected { subscription_id } => HubSubscriptionEvent::Connected { subscription_id },
            E::MessageReceived {
                subscription_id,
                event_name,
                payload_json,
            } => HubSubscriptionEvent::MessageReceived {
                subscription_id,
                event_name,
                payload_json,
            },
            E::Disconnected {
                subscription_id,
                reason,
            } => HubSubscriptionEvent::Disconnected {
                subscription_id,
                reason,
            },
            E::Stopped { subscription_id } => HubSubscriptionEvent::Stopped { subscription_id },
            E::Failed {
                subscription_id,
                error,
            } => HubSubscriptionEvent::Failed {
                subscription_id,
                error,
            },
        }
    }
}

/// Arranca una suscripcion (SignalR o WebSocket crudo). `subscription_id` lo
/// elige el lado Dart (el UUID de la fila que ya creo en Drift) -- Rust no
/// genera uno propio, porque `MessageReceived` tiene que llegar identificado
/// con el mismo id que la fila persistida. El resultado real (conecto,
/// fallo, mensajes) llega por `watch_hub_events`; este archivo no toca
/// SQLite.
///
/// `async` por la misma razon que `start_captured_command`: frb corre las
/// funciones `async` dentro de su propio runtime de tokio, y `start_subscription`
/// hace `tokio::spawn` adentro.
pub async fn start_hub_subscription(
    subscription_id: String,
    base_url: String,
    kind: HubSubscriptionKind,
    allow_invalid_cert: bool,
) -> Result<(), String> {
    let kind = kind.into_core()?;
    nexodeck_hub::manager().start_subscription(subscription_id, base_url, kind, allow_invalid_cert);
    Ok(())
}

/// `false` si el id no existe o ya estaba detenida.
pub async fn stop_hub_subscription(subscription_id: String) -> bool {
    nexodeck_hub::manager().stop_subscription(&subscription_id)
}

/// Repite el flujo de conexion entero con la misma configuracion (incluido
/// un `negotiate` nuevo para SignalR). `false` si el id no existe.
pub async fn restart_hub_subscription(subscription_id: String) -> bool {
    nexodeck_hub::manager().restart_subscription(&subscription_id)
}

/// Se olvida de la suscripcion del lado Rust (detiene la conexion si seguia
/// viva). Se llama al borrar la suscripcion en Drift.
pub async fn remove_hub_subscription(subscription_id: String) {
    nexodeck_hub::manager().remove_subscription(&subscription_id);
}

/// Stream global de eventos de **todas** las suscripciones, multiplexado por
/// `subscription_id` -- mismo patron que `watch_command_runs`. Del lado Dart
/// se consume con suscripcion directa al `Stream`, nunca con `ref.listen`
/// (ver la seccion "Eventos del bridge" de `CLAUDE.md`).
pub async fn watch_hub_events(sink: StreamSink<HubSubscriptionEvent>) {
    let mut events = nexodeck_hub::manager().subscribe();
    loop {
        match events.recv().await {
            Ok(event) => {
                if sink.add(event.into()).is_err() {
                    break; // Dart cerro el stream
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
}
