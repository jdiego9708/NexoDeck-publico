//! Cliente de suscripciones en vivo: SignalR (hubs de ASP.NET Core, como los
//! de ExampleApi) o WebSocket crudo. NexoDeck se conecta de SALIDA -- no
//! abre ningun puerto nuevo, evita el problema de CGNAT que ya bloquea
//! cualquier conexion ENTRANTE fuera de la LAN (ver `CLAUDE.md`).
//!
//! Mismo esqueleto que `nexodeck_actions::runner::CommandRunner`: singleton
//! (`OnceLock`), estado por suscripcion en un `HashMap`, y un
//! `broadcast::Sender` compartido que `nexodeck-ffi` reenvia a Dart. La
//! diferencia de fondo es la duracion: una ejecucion de comando termina
//! sola, una suscripcion sigue viva hasta que alguien la detiene.
//!
//! **Este crate NO toca SQLite.** Guardar la suscripcion y su historial de
//! mensajes es responsabilidad del lado Dart (ver `hub_subscriptions_repository.dart`),
//! que escucha `watch_hub_events()` y escribe en Drift -- misma regla que el
//! resto de la arquitectura ("solo nexodeck-ffi se expone a Dart", y de ahi
//! para abajo nada de este crate sabe que existe una base de datos).

mod client;
mod protocol;
mod tls;

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::sync::{broadcast, oneshot};

const BROADCAST_CAPACITY: usize = 512;

pub type SubscriptionId = String;

/// Que tipo de conexion abrir. `SignalR` necesita el camino completo
/// (negotiate + handshake + invocar un metodo); `RawWebSocket` es solo
/// conectar y leer.
#[derive(Debug, Clone)]
pub enum SubscriptionKind {
    SignalR {
        /// Ej. `/hubs/plant-training-progress`.
        hub_path: String,
        /// Metodo del hub a invocar apenas conecta, ej. `SubscribeToJob`.
        invoke_method: String,
        invoke_args: Vec<serde_json::Value>,
    },
    RawWebSocket,
}

#[derive(Debug, Clone)]
pub enum HubEvent {
    /// La conexion quedo lista (handshake + invocacion resueltos para
    /// SignalR; solo el connect para WebSocket crudo).
    Connected { subscription_id: SubscriptionId },
    /// Un mensaje nuevo. `event_name` es el `target` invocado (SignalR) o
    /// `"message"`/`"binary"` (WebSocket crudo); `payload_json` es SIEMPRE
    /// JSON valido (un array para SignalR, el texto/tamano envuelto en
    /// comillas para WS crudo) para que Dart lo pueda persistir y mostrar
    /// sin tener que adivinar el formato.
    MessageReceived {
        subscription_id: SubscriptionId,
        event_name: String,
        payload_json: String,
    },
    /// El servidor cerro la conexion, o se cayo. No es un pedido del
    /// usuario -- eso es `Stopped`.
    Disconnected {
        subscription_id: SubscriptionId,
        reason: String,
    },
    /// El usuario pidio detenerla (`stop_subscription`).
    Stopped { subscription_id: SubscriptionId },
    /// Nunca llego a conectar (negotiate fallo, handshake rechazado, URL
    /// invalida). Distinto de `Disconnected`: aca nunca hubo conexion viva.
    Failed {
        subscription_id: SubscriptionId,
        error: String,
    },
}

impl HubEvent {
    pub fn subscription_id(&self) -> &str {
        match self {
            HubEvent::Connected { subscription_id }
            | HubEvent::MessageReceived { subscription_id, .. }
            | HubEvent::Disconnected { subscription_id, .. }
            | HubEvent::Stopped { subscription_id, .. }
            | HubEvent::Failed { subscription_id, .. } => subscription_id,
        }
    }
}

/// Lo que hace falta para (re)lanzar la conexion de una suscripcion --
/// `restart_subscription` guarda esto para poder repetir el flujo entero
/// (incluido un `negotiate` nuevo si es SignalR) sin que quien llama tenga
/// que volver a mandar todos los parametros.
#[derive(Debug, Clone)]
struct SubscriptionConfig {
    base_url: String,
    kind: SubscriptionKind,
    allow_invalid_cert: bool,
}

struct SubscriptionSlot {
    config: SubscriptionConfig,
    /// `None` si ya se pidio detenerla (evita mandar la señal dos veces).
    cancel: Option<oneshot::Sender<()>>,
}

pub struct HubManager {
    events: broadcast::Sender<HubEvent>,
    slots: Mutex<HashMap<SubscriptionId, SubscriptionSlot>>,
}

static MANAGER: OnceLock<std::sync::Arc<HubManager>> = OnceLock::new();

/// Singleton, mismo motivo que `nexodeck_actions::runner()`: el stream que
/// escucha Dart se abre una sola vez al arrancar la app y tiene que seguir
/// sirviendo a todas las suscripciones que se creen despues.
pub fn manager() -> std::sync::Arc<HubManager> {
    MANAGER
        .get_or_init(|| {
            let (events, _) = broadcast::channel(BROADCAST_CAPACITY);
            std::sync::Arc::new(HubManager {
                events,
                slots: Mutex::new(HashMap::new()),
            })
        })
        .clone()
}

impl HubManager {
    pub fn subscribe(&self) -> broadcast::Receiver<HubEvent> {
        self.events.subscribe()
    }

    /// Arranca la conexion. El id lo elige QUIEN LLAMA (el lado Dart, que ya
    /// creo la fila en Drift con su propio UUID antes de pedir la conexion)
    /// -- a diferencia de `CommandRunner::start`, este id no lo genera Rust,
    /// porque tiene que coincidir con la fila persistida para que
    /// `MessageReceived` se pueda escribir contra la suscripcion correcta.
    /// El resultado real (conecto, fallo, recibio algo) llega por
    /// `subscribe()`. Tiene que llamarse desde dentro de un runtime de
    /// tokio (lo garantiza la capa FFI).
    pub fn start_subscription(
        self: &std::sync::Arc<Self>,
        id: SubscriptionId,
        base_url: String,
        kind: SubscriptionKind,
        allow_invalid_cert: bool,
    ) {
        let config = SubscriptionConfig {
            base_url,
            kind,
            allow_invalid_cert,
        };
        self.spawn_connection(id, config);
    }

    fn spawn_connection(self: &std::sync::Arc<Self>, id: SubscriptionId, config: SubscriptionConfig) {
        let (cancel_tx, cancel_rx) = oneshot::channel();
        {
            let mut slots = self.slots.lock().unwrap_or_else(|p| p.into_inner());
            slots.insert(
                id.clone(),
                SubscriptionSlot {
                    config: config.clone(),
                    cancel: Some(cancel_tx),
                },
            );
        }
        let events = self.events.clone();
        tokio::spawn(client::run_connection(
            id,
            config.base_url,
            config.kind,
            config.allow_invalid_cert,
            events,
            cancel_rx,
        ));
    }

    /// Corta la conexion viva, si la hay. `false` si el id no existe o ya
    /// estaba detenida.
    pub fn stop_subscription(&self, id: &str) -> bool {
        let mut slots = self.slots.lock().unwrap_or_else(|p| p.into_inner());
        let Some(slot) = slots.get_mut(id) else {
            return false;
        };
        match slot.cancel.take() {
            Some(cancel) => {
                let _ = cancel.send(());
                true
            }
            None => false,
        }
    }

    /// Repite el flujo de conexion entero con la MISMA configuracion
    /// (incluido un `negotiate` nuevo para SignalR). `false` si el id no
    /// existe.
    pub fn restart_subscription(self: &std::sync::Arc<Self>, id: &str) -> bool {
        let config = {
            let mut slots = self.slots.lock().unwrap_or_else(|p| p.into_inner());
            let Some(slot) = slots.get_mut(id) else {
                return false;
            };
            // Si seguia conectada, cortarla primero: dos tareas mandando
            // eventos para el mismo id confundiria a quien escucha.
            if let Some(cancel) = slot.cancel.take() {
                let _ = cancel.send(());
            }
            slot.config.clone()
        };
        self.spawn_connection(id.to_string(), config);
        true
    }

    /// Se olvida de la suscripcion (detiene la conexion si seguia viva).
    /// El historial de mensajes ya persistido en Drift no se toca aca --
    /// eso lo borra el repositorio Dart junto con la fila.
    pub fn remove_subscription(&self, id: &str) {
        let mut slots = self.slots.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(mut slot) = slots.remove(id) {
            if let Some(cancel) = slot.cancel.take() {
                let _ = cancel.send(());
            }
        }
    }
}
