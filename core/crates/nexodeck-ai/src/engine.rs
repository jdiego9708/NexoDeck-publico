//! Estado vivo del asistente: el singleton que ata todo.
//!
//! Mismo patron que `nexodeck-transport::server`/`client`: un
//! `static OnceLock<Arc<...>>` con un accesor a nivel de modulo, para que las
//! funciones sincronas del FFI puedan alcanzar el estado sin que Dart tenga que
//! guardar un handle.
//!
//! Los eventos salen por dos canales `broadcast` **del engine**, no de la
//! sesion: la sesion se recrea al cambiar de modelo, y si Dart estuviera
//! suscripto a la de adentro se quedaria escuchando un canal muerto sin ningun
//! error visible — exactamente el tipo de fallo mudo que este proyecto ya
//! documento tres veces.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock, RwLock};

use nexodeck_hardware::{HostCapabilities, probe_host_capabilities};
use tokio::sync::{RwLock as AsyncRwLock, broadcast, mpsc};

use crate::agent::{AgentEvent, AgentSession};
use crate::download::DownloadEvent;
use crate::error::{AiError, AiResult};
use crate::plan::{RuntimePlan, plan_runtime};
use crate::provider::ChatProvider;
use crate::setup::{self, SetupPlan};
use crate::sidecar::{LlamaServer, ServerSpec};
use crate::tools::{DeckActionRef, ToolContext, default_allowed_roots};

const EVENT_CHANNEL_CAPACITY: usize = 256;

/// Progreso del setup, ya en terminos de lo que muestra el wizard.
#[derive(Debug, Clone)]
pub enum SetupEvent {
    Probing,
    Downloading {
        asset: String,
        downloaded: u64,
        total_bytes: u64,
        bytes_per_sec: u64,
    },
    Verifying {
        asset: String,
    },
    Extracting {
        asset: String,
    },
    StartingServer,
    Ready {
        model_id: String,
        backend: String,
        gpu_layers: u32,
        provider_label: String,
    },
    Failed {
        detail: String,
    },
}

/// Foto del estado, para que la UI sepa en que pantalla arrancar.
#[derive(Debug, Clone)]
pub struct SetupState {
    /// El runtime y el modelo ya estan en disco y verificados.
    pub installed: bool,
    /// Ademas hay un motor levantado y listo para conversar.
    pub ready: bool,
    pub model_id: Option<String>,
    pub provider_label: Option<String>,
    pub busy: bool,
}

pub struct Engine {
    capabilities: OnceLock<HostCapabilities>,
    setup_events: broadcast::Sender<SetupEvent>,
    chat_events: broadcast::Sender<AgentEvent>,
    session: AsyncRwLock<Option<Arc<AgentSession>>>,
    allowed_roots: RwLock<Vec<PathBuf>>,
    deck: RwLock<Vec<DeckActionRef>>,
    selected_model: RwLock<Option<String>>,
    cancel_setup: Arc<AtomicBool>,
    setting_up: AtomicBool,
}

static ENGINE: OnceLock<Arc<Engine>> = OnceLock::new();

/// Accesor del singleton. Se crea perezosamente en la primera llamada.
pub fn engine() -> Arc<Engine> {
    Arc::clone(ENGINE.get_or_init(|| {
        let (setup_events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (chat_events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);

        Arc::new(Engine {
            capabilities: OnceLock::new(),
            setup_events,
            chat_events,
            session: AsyncRwLock::new(None),
            allowed_roots: RwLock::new(default_allowed_roots()),
            deck: RwLock::new(Vec::new()),
            selected_model: RwLock::new(None),
            cancel_setup: Arc::new(AtomicBool::new(false)),
            setting_up: AtomicBool::new(false),
        })
    }))
}

impl Engine {
    pub fn subscribe_setup(&self) -> broadcast::Receiver<SetupEvent> {
        self.setup_events.subscribe()
    }

    pub fn subscribe_chat(&self) -> broadcast::Receiver<AgentEvent> {
        self.chat_events.subscribe()
    }

    /// Probe del hardware, cacheado. Cuesta unos cientos de milisegundos
    /// (NVML + Vulkan) y nada de lo que devuelve cambia mientras la app corre.
    pub fn capabilities(&self) -> &HostCapabilities {
        self.capabilities.get_or_init(|| {
            let models_dir = crate::paths::models_dir().unwrap_or_else(|_| std::env::temp_dir());
            probe_host_capabilities(&models_dir)
        })
    }

    pub fn plan(&self) -> RuntimePlan {
        plan_runtime(self.capabilities())
    }

    pub fn allowed_roots(&self) -> Vec<PathBuf> {
        self.allowed_roots
            .read()
            .map(|roots| roots.clone())
            .unwrap_or_default()
    }

    /// Cambia las carpetas legibles. Afecta a la sesion en curso: el contexto
    /// de herramientas es compartido, asi que sacar una carpeta la bloquea de
    /// inmediato y no recien en la proxima conversacion.
    pub fn set_allowed_roots(&self, roots: Vec<PathBuf>) {
        if let Ok(mut current) = self.allowed_roots.write() {
            *current = roots;
        }
    }

    pub fn set_deck(&self, deck: Vec<DeckActionRef>) {
        if let Ok(mut current) = self.deck.write() {
            *current = deck;
        }
    }

    pub fn selected_model(&self) -> Option<String> {
        self.selected_model.read().ok().and_then(|m| m.clone())
    }

    /// El modelo local **que ya esta levantado**, con si el chat lo esta usando
    /// en este momento. `None` si no hay sesion o si la sesion es remota.
    ///
    /// Nunca arranca nada, y es a proposito: lo pide el buzon de documentacion
    /// como respaldo, y levantar llama-server por su cuenta durante una tanda de
    /// ODM le quitaria la GPU a lo que de verdad importa.
    pub async fn local_endpoint(&self) -> Option<(crate::provider::ModelEndpoint, bool)> {
        let session = self.session.read().await;
        let session = session.as_ref()?;
        session
            .local_endpoint()
            .map(|endpoint| (endpoint, session.is_busy()))
    }

    /// Resuelve que habria que instalar, sin tocar red ni disco.
    pub fn resolve_setup(&self, model_id: Option<&str>) -> AiResult<SetupPlan> {
        let plan = self.plan();
        let model_id = model_id
            .map(str::to_string)
            .or_else(|| self.selected_model());
        setup::resolve_setup(&plan, self.capabilities().os, model_id.as_deref())
    }

    pub async fn state(&self) -> SetupState {
        let session = self.session.read().await;
        let installed = self
            .resolve_setup(None)
            .ok()
            .and_then(|plan| setup::installed_assets(&plan))
            .is_some();

        SetupState {
            installed,
            ready: session.is_some(),
            model_id: self.selected_model(),
            provider_label: session.as_ref().map(|s| s.provider_label()),
            busy: self.setting_up.load(Ordering::Relaxed)
                || session.as_ref().is_some_and(|s| s.is_busy()),
        }
    }

    pub fn cancel_setup(&self) {
        self.cancel_setup.store(true, Ordering::Relaxed);
    }

    /// Descarga lo que falte, levanta el motor y deja la sesion lista.
    ///
    /// Cada camino de error termina en un [`SetupEvent::Failed`] antes de
    /// devolver: un wizard que se queda en "descargando" para siempre es
    /// indistinguible de un cuelgue.
    pub async fn start_setup(&self, model_id: Option<String>) -> AiResult<()> {
        if self.setting_up.swap(true, Ordering::Relaxed) {
            return Err(AiError::Busy);
        }
        self.cancel_setup.store(false, Ordering::Relaxed);

        let result = self.run_setup(model_id).await;
        self.setting_up.store(false, Ordering::Relaxed);

        if let Err(error) = &result {
            let _ = self.setup_events.send(SetupEvent::Failed {
                detail: error.to_string(),
            });
        }

        result
    }

    /// Descarga (o verifica) el modelo y su runtime, **sin arrancar
    /// `llama-server`**.
    ///
    /// Es lo que usa la pantalla de perfiles para bajar un modelo que todavia
    /// no se va a activar: activar el motor de un perfil que no es el activo
    /// ocuparia la GPU para nada. El progreso sale por los mismos
    /// [`SetupEvent`] y la Future resuelve cuando termina la descarga.
    pub async fn download_model(&self, model_id: Option<String>) -> AiResult<()> {
        if self.setting_up.swap(true, Ordering::Relaxed) {
            return Err(AiError::Busy);
        }
        self.cancel_setup.store(false, Ordering::Relaxed);

        let result = self.prepare_installed(model_id).await.map(|_| ());
        self.setting_up.store(false, Ordering::Relaxed);

        if let Err(error) = &result {
            let _ = self.setup_events.send(SetupEvent::Failed {
                detail: error.to_string(),
            });
        }

        result
    }

    /// Deja el runtime y el modelo en disco y devuelve el plan resuelto, sin
    /// tocar la sesion activa. Comparten este camino `run_setup` (que despues
    /// levanta el servidor) y `download_model`.
    async fn prepare_installed(
        &self,
        model_id: Option<String>,
    ) -> AiResult<(SetupPlan, setup::InstalledAssets)> {
        let _ = self.setup_events.send(SetupEvent::Probing);

        let plan = self.plan();
        let setup_plan = setup::resolve_setup(&plan, self.capabilities().os, model_id.as_deref())?;

        // Reenvia el progreso de descarga al canal del wizard, traduciendo al
        // vocabulario de la UI.
        let (tx, mut rx) = mpsc::channel::<DownloadEvent>(64);
        let setup_events = self.setup_events.clone();
        let forwarder = tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                let translated = match event {
                    DownloadEvent::Started {
                        asset, total_bytes, resumed_from,
                    } => SetupEvent::Downloading {
                        asset,
                        downloaded: resumed_from,
                        total_bytes,
                        bytes_per_sec: 0,
                    },
                    DownloadEvent::Progress {
                        asset,
                        downloaded,
                        total_bytes,
                        bytes_per_sec,
                    } => SetupEvent::Downloading {
                        asset,
                        downloaded,
                        total_bytes,
                        bytes_per_sec,
                    },
                    DownloadEvent::Verifying { asset } => SetupEvent::Verifying { asset },
                    DownloadEvent::Extracting { asset } => SetupEvent::Extracting { asset },
                    // `Finished` no se traduce: el wizard avanza con el
                    // siguiente `Downloading` o con `StartingServer`.
                    DownloadEvent::Finished { .. } => continue,
                    DownloadEvent::Failed { detail, .. } => SetupEvent::Failed { detail },
                };
                let _ = setup_events.send(translated);
            }
        });

        let installed =
            setup::ensure_installed(&setup_plan, &tx, Arc::clone(&self.cancel_setup)).await;
        drop(tx);
        let _ = forwarder.await;

        Ok((setup_plan, installed?))
    }

    async fn run_setup(&self, model_id: Option<String>) -> AiResult<()> {
        let (setup_plan, installed) = self.prepare_installed(model_id).await?;

        let plan = self.plan();
        let _ = self.setup_events.send(SetupEvent::StartingServer);

        let gpu_layers = crate::gpu_layers_for(setup_plan.model, &plan);
        let server = LlamaServer::start(&ServerSpec {
            server_path: installed.server_path,
            model_path: installed.model_path,
            model_alias: setup_plan.model.id.to_string(),
            gpu_layers,
            threads: plan.threads,
            context_size: plan.context_size,
        })
        .await?;

        let effective_layers = server.gpu_layers;
        let provider = ChatProvider::Sidecar {
            server,
            model_id: setup_plan.model.id.to_string(),
            display_name: setup_plan.model.display_name.to_string(),
            supports_thinking: setup_plan.model.supports_thinking,
        };
        let provider_label = provider.label();

        self.install_provider(provider).await;
        if let Ok(mut selected) = self.selected_model.write() {
            *selected = Some(setup_plan.model.id.to_string());
        }

        let _ = self.setup_events.send(SetupEvent::Ready {
            model_id: setup_plan.model.id.to_string(),
            backend: plan.backend.as_str().to_string(),
            gpu_layers: effective_layers,
            provider_label,
        });

        Ok(())
    }

    /// Usa un Ollama ya instalado, sin descargar nada.
    pub async fn use_ollama(&self, model: String) -> AiResult<()> {
        let provider = crate::provider::use_ollama(&model).await?;
        let provider_label = provider.label();

        self.install_provider(provider).await;
        if let Ok(mut selected) = self.selected_model.write() {
            *selected = Some(model.clone());
        }

        let _ = self.setup_events.send(SetupEvent::Ready {
            model_id: model,
            backend: "ollama".to_string(),
            gpu_layers: 0,
            provider_label,
        });

        Ok(())
    }

    /// Instala un proveedor remoto (DeepSeek, OpenAI, un proxy propio).
    ///
    /// La clave se guarda **solo si el proveedor arranco bien**: guardar antes
    /// dejaria una clave invalida en disco que el proximo arranque reusaria en
    /// silencio, y el usuario veria fallar el chat sin saber por que.
    pub async fn use_remote(
        &self,
        provider_id: String,
        base_url: String,
        model: String,
        api_key: String,
        display_name: String,
    ) -> AiResult<()> {
        let provider =
            crate::provider::use_remote(&base_url, &model, &api_key, &display_name).await?;
        let provider_label = provider.label();

        crate::remote::save_api_key(&provider_id, &api_key)?;

        self.install_provider(provider).await;
        if let Ok(mut selected) = self.selected_model.write() {
            *selected = Some(model.clone());
        }

        let _ = self.setup_events.send(SetupEvent::Ready {
            model_id: model,
            backend: provider_id,
            gpu_layers: 0,
            provider_label,
        });

        Ok(())
    }

    /// Reemplaza la sesion activa y engancha el reenvio de sus eventos.
    async fn install_provider(&self, provider: ChatProvider) {
        let context = Arc::new({
            let context = ToolContext::new(self.allowed_roots(), self.capabilities().os);
            context.set_deck(self.deck.read().map(|d| d.clone()).unwrap_or_default());
            context
        });

        let session = Arc::new(AgentSession::new(provider, context));

        // Reenvio al canal del engine: Dart se suscribe una sola vez y
        // sobrevive a los cambios de modelo.
        let mut source = session.subscribe();
        let sink = self.chat_events.clone();
        tokio::spawn(async move {
            while let Ok(event) = source.recv().await {
                if sink.send(event).is_err() {
                    // Nadie escuchando todavia no es motivo para cortar: la UI
                    // puede suscribirse despues.
                    continue;
                }
            }
        });

        let previous = self.session.write().await.replace(session);
        if let Some(previous) = previous {
            // Cambiar de modelo tiene que liberar la VRAM del anterior. Sin
            // esto, el segundo arranque falla por falta de memoria y el motivo
            // no aparece por ningun lado.
            if let Ok(previous) = Arc::try_unwrap(previous) {
                previous.shutdown().await;
            }
        }
    }

    /// Actualiza el deck y las carpetas de la sesion viva sin recrearla.
    pub async fn refresh_session_context(&self) {
        let deck = self.deck.read().map(|d| d.clone()).unwrap_or_default();
        let roots = self.allowed_roots();

        if let Some(session) = self.session.read().await.as_ref() {
            session.update_context(roots, deck);
        }
    }

    pub async fn send_message(&self, text: String) -> AiResult<()> {
        let session = self.session.read().await;
        let session = session.as_ref().ok_or(AiError::NotStarted)?;
        session.send_user_message(text).await
    }

    pub async fn reset_conversation(&self) -> AiResult<()> {
        let session = self.session.read().await;
        let session = session.as_ref().ok_or(AiError::NotStarted)?;
        session.reset().await;
        Ok(())
    }

    pub async fn cancel_turn(&self) {
        if let Some(session) = self.session.read().await.as_ref() {
            session.cancel();
        }
    }

    /// Apaga el motor y libera la VRAM. Lo llama la app al cerrar el asistente.
    pub async fn stop(&self) {
        let previous = self.session.write().await.take();
        if let Some(previous) = previous {
            if let Ok(previous) = Arc::try_unwrap(previous) {
                previous.shutdown().await;
            }
        }
    }
}
