//! Superficie FFI del asistente de IA local.
//!
//! Sigue el patron del resto del crate (ver `pairing.rs` / `connection.rs`):
//! **streams largos para eventos + comandos sueltos que devuelven
//! `Result<T, String>`**. Recordar que una funcion de stream de
//! flutter_rust_bridge no puede devolver error: todo fallo tiene que viajar
//! como variante de evento, y por eso existen `AiSetupEvent::Failed` y
//! `AiChatEvent::Failed`.
//!
//! ## Android
//!
//! `nexodeck-ai` entra en las dependencias bajo
//! `cfg(not(target_os = "android"))`, igual que `nusb` y `arboard`: correr un
//! modelo de 9 GB en un telefono no es el caso de uso, y arrastrar reqwest +
//! zip + tar al `.so` de Android seria exactamente el tipo de cambio que en
//! Fase 4 dejo el APK sin `libnexodeck_ffi.so` sin que el build fallara.
//!
//! Las **funciones existen igual en las tres plataformas**, con el cuerpo
//! gateado: cfg-earlas enteras rompe el link del lado que falta (ver el
//! encabezado de `usb.rs`). En Android devuelven un error claro.

use crate::frb_generated::StreamSink;

// ---------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiBackend {
    Cuda12,
    Cuda13,
    Vulkan,
    CpuAvx2,
    CpuBaseline,
    /// Un Ollama del usuario: el backend lo decide el.
    Ollama,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiTier {
    Light,
    Balanced,
    Performance,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiGpuVendor {
    Nvidia,
    Amd,
    Intel,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiRiskLevel {
    Safe,
    Caution,
    Dangerous,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiDraftActionType {
    Clipboard,
    Terminal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiTerminalType {
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiParamInputType {
    Text,
    Number,
    Select,
}

// ---------------------------------------------------------------------
// Hardware y catalogo
// ---------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct AiGpuInfo {
    pub vendor: AiGpuVendor,
    pub name: String,
    pub vram_total_mb: u64,
}

#[derive(Debug, Clone)]
pub struct AiCapabilities {
    pub os: String,
    pub cpu_brand: String,
    pub physical_cores: Option<u32>,
    pub logical_cores: u32,
    pub avx2: bool,
    pub avx512: bool,
    pub ram_total_mb: u64,
    pub free_disk_mb: u64,
    pub gpus: Vec<AiGpuInfo>,
    pub nvml_available: bool,
    pub vulkan_device_count: Option<u32>,
    /// Lo que el plan recomienda para este equipo.
    pub recommended_backend: AiBackend,
    pub recommended_tier: AiTier,
    pub recommended_model_id: String,
    pub threads: u32,
    pub context_size: u32,
    /// Explicaciones en espanol de cada decision. El wizard las muestra tal
    /// cual: "te toco la gama baja" sin motivo es indistinguible de un bug.
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AiModelOption {
    pub id: String,
    pub display_name: String,
    pub tier: AiTier,
    pub license: String,
    pub source_repo: String,
    pub quantization: String,
    pub params_b: f32,
    pub file_bytes: u64,
    pub min_vram_mb: u64,
    pub is_default: bool,
    pub notes: String,
    /// Total a descargar contando el runtime que falte. Es el numero que hay
    /// que mostrar antes de pedir confirmacion.
    pub total_download_bytes: u64,
    /// Ya esta en disco y verificado.
    pub installed: bool,
    /// Entra entero en la GPU con el plan actual.
    pub fits_in_gpu: bool,
}

#[derive(Debug, Clone)]
pub struct AiSetupState {
    pub installed: bool,
    pub ready: bool,
    pub model_id: Option<String>,
    pub provider_label: Option<String>,
    pub busy: bool,
    pub allowed_roots: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AiOllamaInstallation {
    pub base_url: String,
    pub models: Vec<String>,
}

/// Estado del Ollama instalado en el equipo, para el interruptor del menu
/// "Mas". No es lo mismo que `AiOllamaInstallation`: este dice **si responde y
/// si hay binario**, que es lo que hace falta para poder encenderlo o apagarlo.
#[derive(Debug, Clone)]
pub struct AiOllamaControlStatus {
    pub running: bool,
    /// Ruta del ejecutable si se encontro la instalacion. `None` = no hay
    /// Ollama (o no se pudo localizar), y entonces no se puede encender.
    pub binary_path: Option<String>,
}

// ---------------------------------------------------------------------
// Borrador
// ---------------------------------------------------------------------

/// Accion existente del deck, que Dart le pasa al asistente como contexto.
/// Rust no lee Drift: por la regla de arquitectura, la base vive del lado
/// Flutter.
#[derive(Debug, Clone)]
pub struct AiDeckActionRef {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub description: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AiDraftParam {
    pub key: String,
    pub label: String,
    pub kind: AiParamInputType,
    pub default_value: Option<String>,
    pub options: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AiDraftAutoSubscribe {
    pub base_url: String,
    pub hub_path: String,
    pub invoke_method: String,
    pub json_field: String,
    pub allow_invalid_cert: bool,
}

#[derive(Debug, Clone)]
pub struct AiDraftStep {
    pub name: String,
    pub description: Option<String>,
    pub action_type: AiDraftActionType,
    /// Comando tal como lo escribio el modelo, **sin** el `cd` del directorio
    /// de trabajo. Se muestra asi en la vista previa porque es mas legible.
    pub command: String,
    /// Comando final, ya con el `cd` plegado adentro. Es **este** el que se
    /// guarda en Drift: el esquema de acciones no tiene columna para carpeta
    /// de trabajo.
    pub resolved_command: String,
    pub terminal: AiTerminalType,
    pub requires_admin: bool,
    pub show_terminal_window: bool,
    pub working_directory: Option<String>,
    pub parameters: Vec<AiDraftParam>,
    pub delay_ms_after: u32,
    pub risk: AiRiskLevel,
    pub risk_notes: Vec<String>,
    pub auto_subscribe: Option<AiDraftAutoSubscribe>,
}

#[derive(Debug, Clone)]
pub struct AiActionDraft {
    pub name: String,
    pub description: Option<String>,
    pub icon: String,
    pub color_hex: String,
    /// Por que el comando quedo asi, en espanol. Lo escribe el modelo y es lo
    /// que el usuario lee para decidir si aprobar.
    pub summary: String,
    pub steps: Vec<AiDraftStep>,
    /// Mas de un paso significa que hay que crear las hojas y una macro.
    pub is_macro: bool,
    pub risk: AiRiskLevel,
}

// ---------------------------------------------------------------------
// Eventos
// ---------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum AiSetupEvent {
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

#[derive(Debug, Clone)]
pub enum AiChatEvent {
    /// Fragmento de texto. **Consumir con suscripcion directa al Stream**,
    /// nunca con `ref.listen` sobre un provider: Riverpod descarta el valor
    /// cuando es `==` al anterior, y dos tokens `" "` seguidos son identicos.
    /// Ver la seccion "Eventos del bridge" de `CLAUDE.md`.
    AssistantToken {
        delta: String,
    },
    /// El modelo esta razonando. No se manda el contenido: es monologo interno.
    Thinking,
    AssistantMessage {
        text: String,
    },
    ToolStarted {
        name: String,
        summary: String,
    },
    ToolFinished {
        name: String,
        ok: bool,
        summary: String,
    },
    DraftReady {
        draft: AiActionDraft,
    },
    TurnDone,
    Failed {
        detail: String,
    },
}

// ---------------------------------------------------------------------
// Conversiones (solo donde nexodeck-ai existe)
// ---------------------------------------------------------------------

#[cfg(not(target_os = "android"))]
mod convert {
    use super::*;
    use nexodeck_ai::agent::AgentEvent;
    use nexodeck_ai::draft as d;
    use nexodeck_ai::engine::SetupEvent;
    use nexodeck_ai::plan::{Backend, Tier};
    use nexodeck_ai::safety::RiskLevel;
    use nexodeck_hardware::{GpuInfo, GpuVendor, HostCapabilities};

    impl From<Backend> for AiBackend {
        fn from(backend: Backend) -> Self {
            match backend {
                Backend::Cuda12 => AiBackend::Cuda12,
                Backend::Cuda13 => AiBackend::Cuda13,
                Backend::Vulkan => AiBackend::Vulkan,
                Backend::CpuAvx2 => AiBackend::CpuAvx2,
                Backend::CpuBaseline => AiBackend::CpuBaseline,
            }
        }
    }

    impl From<Tier> for AiTier {
        fn from(tier: Tier) -> Self {
            match tier {
                Tier::Light => AiTier::Light,
                Tier::Balanced => AiTier::Balanced,
                Tier::Performance => AiTier::Performance,
            }
        }
    }

    impl From<AiTier> for Tier {
        fn from(tier: AiTier) -> Self {
            match tier {
                AiTier::Light => Tier::Light,
                AiTier::Balanced => Tier::Balanced,
                AiTier::Performance => Tier::Performance,
            }
        }
    }

    impl From<GpuVendor> for AiGpuVendor {
        fn from(vendor: GpuVendor) -> Self {
            match vendor {
                GpuVendor::Nvidia => AiGpuVendor::Nvidia,
                GpuVendor::Amd => AiGpuVendor::Amd,
                GpuVendor::Intel => AiGpuVendor::Intel,
                GpuVendor::Unknown => AiGpuVendor::Unknown,
            }
        }
    }

    impl From<&GpuInfo> for AiGpuInfo {
        fn from(gpu: &GpuInfo) -> Self {
            AiGpuInfo {
                vendor: gpu.vendor.into(),
                name: gpu.name.clone(),
                vram_total_mb: gpu.vram_total_mb,
            }
        }
    }

    impl From<RiskLevel> for AiRiskLevel {
        fn from(level: RiskLevel) -> Self {
            match level {
                RiskLevel::Safe => AiRiskLevel::Safe,
                RiskLevel::Caution => AiRiskLevel::Caution,
                RiskLevel::Dangerous => AiRiskLevel::Dangerous,
            }
        }
    }

    impl From<d::DraftActionType> for AiDraftActionType {
        fn from(kind: d::DraftActionType) -> Self {
            match kind {
                d::DraftActionType::Clipboard => AiDraftActionType::Clipboard,
                d::DraftActionType::Terminal => AiDraftActionType::Terminal,
            }
        }
    }

    impl From<d::DraftTerminalType> for AiTerminalType {
        fn from(kind: d::DraftTerminalType) -> Self {
            match kind {
                d::DraftTerminalType::DefaultShell => AiTerminalType::DefaultShell,
                d::DraftTerminalType::PowerShell => AiTerminalType::PowerShell,
                d::DraftTerminalType::Bash => AiTerminalType::Bash,
                d::DraftTerminalType::Cmd => AiTerminalType::Cmd,
            }
        }
    }

    impl From<d::DraftParamKind> for AiParamInputType {
        fn from(kind: d::DraftParamKind) -> Self {
            match kind {
                d::DraftParamKind::Text => AiParamInputType::Text,
                d::DraftParamKind::Number => AiParamInputType::Number,
                d::DraftParamKind::Select => AiParamInputType::Select,
            }
        }
    }

    impl From<&d::DraftParam> for AiDraftParam {
        fn from(param: &d::DraftParam) -> Self {
            AiDraftParam {
                key: param.key.clone(),
                label: param.label.clone(),
                kind: param.kind.into(),
                default_value: param.default_value.clone(),
                options: param.options.clone(),
            }
        }
    }

    impl From<&d::DraftAutoSubscribe> for AiDraftAutoSubscribe {
        fn from(config: &d::DraftAutoSubscribe) -> Self {
            AiDraftAutoSubscribe {
                base_url: config.base_url.clone(),
                hub_path: config.hub_path.clone(),
                invoke_method: config.invoke_method.clone(),
                json_field: config.json_field.clone(),
                allow_invalid_cert: config.allow_invalid_cert,
            }
        }
    }

    impl From<&d::DraftStep> for AiDraftStep {
        fn from(step: &d::DraftStep) -> Self {
            // El comando resuelto se calcula **aca** y viaja junto al original.
            // Asi la vista previa muestra lo legible y Drift guarda lo que
            // realmente se ejecuta, sin que el lado Dart tenga que reimplementar
            // el plegado del `cd` (que es distinto por shell).
            let resolved_command = d::fold_working_directory(step);
            let findings = nexodeck_ai::safety::classify_command(&resolved_command);

            AiDraftStep {
                name: step.name.clone(),
                description: step.description.clone(),
                action_type: step.action_type.into(),
                command: step.command.clone(),
                resolved_command,
                terminal: step.terminal.into(),
                requires_admin: step.requires_admin,
                show_terminal_window: step.show_terminal_window,
                working_directory: step.working_directory.clone(),
                parameters: step.parameters.iter().map(AiDraftParam::from).collect(),
                delay_ms_after: step.delay_ms_after,
                risk: findings
                    .iter()
                    .map(|finding| finding.level)
                    .max()
                    .unwrap_or(RiskLevel::Safe)
                    .into(),
                risk_notes: findings
                    .into_iter()
                    .map(|finding| finding.detail)
                    .collect(),
                auto_subscribe: step.auto_subscribe.as_ref().map(AiDraftAutoSubscribe::from),
            }
        }
    }

    impl From<&d::ActionDraft> for AiActionDraft {
        fn from(draft: &d::ActionDraft) -> Self {
            let steps: Vec<AiDraftStep> = draft.steps.iter().map(AiDraftStep::from).collect();
            let risk = steps
                .iter()
                .map(|step| step.risk)
                .max_by_key(|risk| match risk {
                    AiRiskLevel::Safe => 0,
                    AiRiskLevel::Caution => 1,
                    AiRiskLevel::Dangerous => 2,
                })
                .unwrap_or(AiRiskLevel::Safe);

            AiActionDraft {
                name: draft.name.clone(),
                description: draft.description.clone(),
                icon: draft.icon.clone(),
                color_hex: draft.color_hex.clone(),
                summary: draft.summary.clone(),
                is_macro: draft.is_macro(),
                steps,
                risk,
            }
        }
    }

    impl From<SetupEvent> for AiSetupEvent {
        fn from(event: SetupEvent) -> Self {
            match event {
                SetupEvent::Probing => AiSetupEvent::Probing,
                SetupEvent::Downloading {
                    asset,
                    downloaded,
                    total_bytes,
                    bytes_per_sec,
                } => AiSetupEvent::Downloading {
                    asset,
                    downloaded,
                    total_bytes,
                    bytes_per_sec,
                },
                SetupEvent::Verifying { asset } => AiSetupEvent::Verifying { asset },
                SetupEvent::Extracting { asset } => AiSetupEvent::Extracting { asset },
                SetupEvent::StartingServer => AiSetupEvent::StartingServer,
                SetupEvent::Ready {
                    model_id,
                    backend,
                    gpu_layers,
                    provider_label,
                } => AiSetupEvent::Ready {
                    model_id,
                    backend,
                    gpu_layers,
                    provider_label,
                },
                SetupEvent::Failed { detail } => AiSetupEvent::Failed { detail },
            }
        }
    }

    impl From<AgentEvent> for AiChatEvent {
        fn from(event: AgentEvent) -> Self {
            match event {
                AgentEvent::AssistantToken(delta) => AiChatEvent::AssistantToken { delta },
                AgentEvent::Thinking => AiChatEvent::Thinking,
                AgentEvent::AssistantMessage(text) => AiChatEvent::AssistantMessage { text },
                AgentEvent::ToolStarted { name, summary } => {
                    AiChatEvent::ToolStarted { name, summary }
                }
                AgentEvent::ToolFinished { name, ok, summary } => {
                    AiChatEvent::ToolFinished { name, ok, summary }
                }
                AgentEvent::DraftReady { draft, .. } => AiChatEvent::DraftReady {
                    draft: AiActionDraft::from(&draft),
                },
                AgentEvent::TurnDone => AiChatEvent::TurnDone,
                AgentEvent::Failed { detail } => AiChatEvent::Failed { detail },
            }
        }
    }

    pub(super) fn capabilities_dto(caps: &HostCapabilities) -> AiCapabilities {
        let plan = nexodeck_ai::plan_runtime(caps);

        AiCapabilities {
            os: caps.os.as_str().to_string(),
            cpu_brand: caps.cpu.brand.clone(),
            physical_cores: caps.cpu.physical_cores,
            logical_cores: caps.cpu.logical_cores,
            avx2: caps.cpu.avx2,
            avx512: caps.cpu.avx512,
            ram_total_mb: caps.ram_total_mb,
            free_disk_mb: caps.free_disk_mb,
            gpus: caps.gpus.iter().map(AiGpuInfo::from).collect(),
            nvml_available: caps.nvml_available,
            vulkan_device_count: caps.vulkan_device_count,
            recommended_backend: plan.backend.into(),
            recommended_tier: plan.tier.into(),
            recommended_model_id: plan.default_model().id.to_string(),
            threads: plan.threads,
            context_size: plan.context_size,
            reasons: plan.reasons.clone(),
        }
    }
}

// ---------------------------------------------------------------------
// Comandos
// ---------------------------------------------------------------------

/// Mensaje unico de plataforma no soportada, para no repetirlo en cada cuerpo.
#[cfg(target_os = "android")]
const UNSUPPORTED: &str =
    "el asistente de IA local corre en la PC; desde el telefono se usa el de la PC conectada";

/// Probe del hardware y plan recomendado. Cacheado del lado Rust: llamarlo
/// varias veces no re-inicializa NVML ni Vulkan.
pub async fn probe_ai_capabilities() -> Result<AiCapabilities, String> {
    #[cfg(not(target_os = "android"))]
    {
        // El probe bloquea (NVML, DXGI, crear una instancia de Vulkan): fuera
        // del executor async, que ademas mueve el WebSocket y el USB.
        tokio::task::spawn_blocking(|| {
            let engine = nexodeck_ai::engine::engine();
            convert::capabilities_dto(engine.capabilities())
        })
        .await
        .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Modelos de una gama, con lo que costaria instalarlos en este equipo.
pub fn ai_model_options(tier: AiTier) -> Vec<AiModelOption> {
    #[cfg(not(target_os = "android"))]
    {
        use nexodeck_ai::{catalog, plan, setup};

        let engine = nexodeck_ai::engine::engine();
        let caps = engine.capabilities();
        let runtime_plan = plan_for(engine.as_ref());

        catalog::models_for(tier.into())
            .map(|model| {
                let setup_plan = setup::resolve_setup(&runtime_plan, caps.os, Some(model.id));
                let total_download_bytes = setup_plan
                    .as_ref()
                    .map(|setup_plan| setup_plan.total_download_bytes())
                    .unwrap_or(model.file_bytes);
                let installed = setup_plan
                    .as_ref()
                    .ok()
                    .and_then(setup::installed_assets)
                    .is_some();

                AiModelOption {
                    id: model.id.to_string(),
                    display_name: model.display_name.to_string(),
                    tier,
                    license: model.license.to_string(),
                    source_repo: model.source_repo.to_string(),
                    quantization: model.quantization.to_string(),
                    params_b: model.params_b,
                    file_bytes: model.file_bytes,
                    min_vram_mb: model.min_vram_mb,
                    is_default: model.is_default,
                    notes: model.notes.to_string(),
                    total_download_bytes,
                    installed,
                    fits_in_gpu: plan::gpu_layers_for(model, &runtime_plan) >= 999,
                }
            })
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        let _ = tier;
        Vec::new()
    }
}

#[cfg(not(target_os = "android"))]
fn plan_for(engine: &nexodeck_ai::engine::Engine) -> nexodeck_ai::RuntimePlan {
    engine.plan()
}

pub async fn ai_setup_state() -> Result<AiSetupState, String> {
    #[cfg(not(target_os = "android"))]
    {
        let engine = nexodeck_ai::engine::engine();
        let state = engine.state().await;

        Ok(AiSetupState {
            installed: state.installed,
            ready: state.ready,
            model_id: state.model_id,
            provider_label: state.provider_label,
            busy: state.busy,
            allowed_roots: engine
                .allowed_roots()
                .iter()
                .map(|root| root.to_string_lossy().to_string())
                .collect(),
        })
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Descarga lo que falte y deja el motor listo. El progreso sale por
/// `watch_ai_setup_events`.
pub async fn start_ai_setup(model_id: Option<String>) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .start_setup(model_id)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = model_id;
        Err(UNSUPPORTED.to_string())
    }
}

/// Descarga el modelo (y su runtime) **sin arrancar el motor**. Lo usa la
/// pantalla de perfiles para bajar un modelo que todavia no se va a activar.
/// El progreso sale por `watch_ai_setup_events`.
pub async fn download_ai_model(model_id: Option<String>) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .download_model(model_id)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = model_id;
        Err(UNSUPPORTED.to_string())
    }
}

pub fn cancel_ai_setup() -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine().cancel_setup();
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Detecta un Ollama corriendo. `None` (no un error) cuando no lo hay: no
/// tenerlo instalado es el caso normal.
pub async fn detect_ollama() -> Result<Option<AiOllamaInstallation>, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::provider::detect_ollama()
            .await
            .map(|found| {
                found.map(|installation| AiOllamaInstallation {
                    base_url: installation.base_url,
                    models: installation.models,
                })
            })
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

pub async fn use_ollama_provider(model: String) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .use_ollama(model)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = model;
        Err(UNSUPPORTED.to_string())
    }
}

/// Estado de Ollama: si responde y si hay binario instalado.
pub async fn ollama_control_status() -> Result<AiOllamaControlStatus, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::ollama::status()
            .await
            .map(to_ollama_status)
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Enciende Ollama. Si ya estaba corriendo, no hace nada. Si no hay
/// instalacion, el error lo dice con ese motivo.
pub async fn start_ollama() -> Result<AiOllamaControlStatus, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::ollama::start()
            .await
            .map(to_ollama_status)
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Apaga Ollama. **Apaga el Ollama de toda la maquina**, no solo el de
/// NexoDeck: es la contracara de controlar la instalacion del usuario.
pub async fn stop_ollama() -> Result<AiOllamaControlStatus, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::ollama::stop()
            .await
            .map(to_ollama_status)
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

#[cfg(not(target_os = "android"))]
fn to_ollama_status(status: nexodeck_ai::ollama::OllamaStatus) -> AiOllamaControlStatus {
    AiOllamaControlStatus {
        running: status.running,
        binary_path: status.binary.map(|path| path.to_string_lossy().into_owned()),
    }
}

// ---------------------------------------------------------------------
// Proveedores remotos (DeepSeek, OpenAI, un proxy propio)
// ---------------------------------------------------------------------
//
// No es un rediseno: el sidecar y Ollama ya hablaban el dialecto de OpenAI, asi
// que la unica diferencia es la direccion base, el modelo y una cabecera de
// autorizacion. Ver `nexodeck_ai::remote`.

/// Un servicio conocido, para que configurarlo sea elegir de una lista en vez
/// de escribir una URL.
#[derive(Debug, Clone)]
pub struct AiRemotePreset {
    pub id: String,
    pub label: String,
    pub base_url: String,
    pub default_model: String,
    /// Donde saca el usuario su clave. Sin esto, "hace falta una clave" es un
    /// callejon sin salida para quien no sepa de donde sacarla.
    pub api_keys_url: String,
}

pub fn ai_remote_presets() -> Vec<AiRemotePreset> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::remote::presets()
            .into_iter()
            .map(|p| AiRemotePreset {
                id: p.id,
                label: p.label,
                base_url: p.base_url,
                default_model: p.default_model,
                api_keys_url: p.api_keys_url,
            })
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        Vec::new()
    }
}

/// La clave guardada de un proveedor, si la hay. La UI la usa para prellenar el
/// campo y para saber si ya esta configurado.
pub fn ai_remote_api_key(provider_id: String) -> Result<Option<String>, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::remote::load_api_key(&provider_id).map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = provider_id;
        Err(UNSUPPORTED.to_string())
    }
}

/// Ruta del fichero donde vive la clave de un proveedor. La usa la pasarela del
/// stack para reenviar a un servicio remoto **sin duplicar el secreto**: en
/// `gateway.json` viaja la ruta, nunca la clave.
pub fn ai_remote_key_path(provider_id: String) -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::remote::api_key_path(&provider_id)
            .map(|path| path.to_string_lossy().into_owned())
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = provider_id;
        Err(UNSUPPORTED.to_string())
    }
}

pub fn forget_ai_remote_api_key(provider_id: String) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::remote::forget_api_key(&provider_id).map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = provider_id;
        Err(UNSUPPORTED.to_string())
    }
}

/// Los modelos que ofrece el servicio. Para poder elegir de una lista en vez de
/// escribir el nombre exacto a ciegas.
pub async fn list_ai_remote_models(
    base_url: String,
    api_key: String,
) -> Result<Vec<String>, String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::provider::list_remote_models(&base_url, &api_key)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (base_url, api_key);
        Err(UNSUPPORTED.to_string())
    }
}

/// Instala un proveedor remoto. **Comprueba la clave antes**, para que una mal
/// pegada se descubra en el dialogo y no dentro de la conversacion.
///
/// La clave se guarda solo si el proveedor arranco bien.
pub async fn use_remote_provider(
    provider_id: String,
    base_url: String,
    model: String,
    api_key: String,
    display_name: String,
) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .use_remote(provider_id, base_url, model, api_key, display_name)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (provider_id, base_url, model, api_key, display_name);
        Err(UNSUPPORTED.to_string())
    }
}

/// Manda un mensaje del usuario. La respuesta sale por `watch_ai_chat_events`.
///
/// Es `async` porque el turno puede durar minutos: la Future resuelve cuando el
/// turno **termino**, no cuando se envio. Dart lo usa para saber cuando volver
/// a habilitar el campo de texto.
pub async fn send_ai_message(text: String) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .send_message(text)
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let _ = text;
        Err(UNSUPPORTED.to_string())
    }
}

pub async fn reset_ai_conversation() -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine()
            .reset_conversation()
            .await
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

pub async fn cancel_ai_turn() -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine().cancel_turn().await;
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Apaga el motor y libera la VRAM.
pub async fn stop_ai_assistant() -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::engine::engine().stop().await;
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        Err(UNSUPPORTED.to_string())
    }
}

/// Le pasa al asistente los botones que ya existen, para que no proponga
/// duplicados. Se llama cada vez que cambia el deck.
pub async fn set_ai_deck_context(actions: Vec<AiDeckActionRef>) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        use nexodeck_ai::tools::DeckActionRef;

        let engine = nexodeck_ai::engine::engine();
        engine.set_deck(
            actions
                .into_iter()
                .map(|action| DeckActionRef {
                    id: action.id,
                    name: action.name,
                    kind: action.kind,
                    description: action.description,
                })
                .collect(),
        );
        engine.refresh_session_context().await;
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        let _ = actions;
        Err(UNSUPPORTED.to_string())
    }
}

/// Carpetas que el asistente puede **leer**. Nunca escribe ni ejecuta nada.
pub async fn set_ai_allowed_roots(roots: Vec<String>) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        let engine = nexodeck_ai::engine::engine();
        engine.set_allowed_roots(roots.into_iter().map(std::path::PathBuf::from).collect());
        engine.refresh_session_context().await;
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        let _ = roots;
        Err(UNSUPPORTED.to_string())
    }
}

/// Carpetas por defecto (home + unidades fijas), para poder mostrarlas en el
/// wizard antes de que el usuario elija.
pub fn default_ai_allowed_roots() -> Vec<String> {
    #[cfg(not(target_os = "android"))]
    {
        nexodeck_ai::tools::default_allowed_roots()
            .iter()
            .map(|root| root.to_string_lossy().to_string())
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        Vec::new()
    }
}

// ---------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------

/// Progreso del setup. **No puede devolver error** (limitacion de FRB): los
/// fallos llegan como `AiSetupEvent::Failed`.
pub async fn watch_ai_setup_events(sink: StreamSink<AiSetupEvent>) {
    #[cfg(not(target_os = "android"))]
    {
        let mut events = nexodeck_ai::engine::engine().subscribe_setup();
        loop {
            match events.recv().await {
                Ok(event) => {
                    if sink.add(event.into()).is_err() {
                        break;
                    }
                }
                // El canal se atraso: se pierden eventos de progreso, que es
                // aceptable (el siguiente trae el estado actual). Cortar aca
                // dejaria el wizard mudo para siempre.
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink.add(AiSetupEvent::Failed {
            detail: UNSUPPORTED.to_string(),
        });
    }
}

/// Eventos de la conversacion.
///
/// **Del lado Dart se consume con suscripcion directa al `Stream`**, nunca con
/// `ref.listen` sobre un provider: Riverpod no vuelve a notificar cuando el
/// valor nuevo es `==` al anterior, y dos `AssistantToken { delta: " " }`
/// seguidos son identicos. Un stream de tokens es el peor caso posible de ese
/// bug, ya documentado en `CLAUDE.md`.
pub async fn watch_ai_chat_events(sink: StreamSink<AiChatEvent>) {
    #[cfg(not(target_os = "android"))]
    {
        let mut events = nexodeck_ai::engine::engine().subscribe_chat();
        loop {
            match events.recv().await {
                Ok(event) => {
                    if sink.add(event.into()).is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink.add(AiChatEvent::Failed {
            detail: UNSUPPORTED.to_string(),
        });
    }
}
