use crate::api::hardware::HardwareSnapshot;
use crate::frb_generated::StreamSink;

/// Union de los eventos de sesion (post-pairing) de `nexodeck_transport::
/// server` (rol PC) y `::client` (rol Android). Las variantes `Device*`
/// llevan `device_id` porque el host puede tener varios dispositivos;
/// `Connected`/`Disconnected` (sin id) son del lado cliente, que solo
/// conoce su propia conexion.
#[derive(Debug, Clone)]
pub enum ConnectionEvent {
    // Rol host
    DeviceConnected {
        device_id: String,
    },
    DeviceDisconnected {
        device_id: String,
    },
    ActionExecutionRequested {
        device_id: String,
        action_id: String,
        /// Valores de los `{{placeholders}}` cargados en el dispositivo
        /// remoto -- `main.dart` los pasa tal cual a `renderCommand`, asi
        /// que la accion corre igual que disparada desde el deck local.
        params: Vec<ActionParamValue>,
    },
    /// El telefono escribio esto en el chat del asistente.
    AiMessageRequested {
        device_id: String,
        text: String,
    },
    /// El telefono pide activar el asistente en la PC.
    AiActivateRequested {
        device_id: String,
    },
    /// El telefono pide guardar un borrador como boton nuevo. Los comandos
    /// de cada paso ya vienen resueltos (sin `{{parametros}}`): el telefono
    /// ya los junto con el mismo dialogo que usa la PC.
    AiApplyDraftRequested {
        device_id: String,
        draft: AiRemoteDraft,
    },
    /// El telefono pide correr un borrador ahora, en vivo.
    AiRunDraftRequested {
        device_id: String,
        draft: AiRemoteDraft,
    },
    /// El telefono pide que la IA explique un proceso -- que es, hace
    /// cuanto corre, que esta haciendo, quien lo lanzo.
    AiAskAboutProcessRequested {
        device_id: String,
        group: crate::api::processes::ProcessGroup,
    },
    // Rol cliente
    Connected,
    Disconnected,
    HardwareSnapshotReceived(HardwareSnapshot),
    ActionsCatalogReceived(Vec<RemoteAction>),
    ActionAckReceived {
        action_id: String,
        success: bool,
        error: Option<String>,
    },
    /// Como termino de verdad el comando que este dispositivo mando ejecutar.
    /// Llega **despues** del ack, que solo confirma que la PC lo lanzo.
    /// Rol Android: la PC dice como alcanzarla desde fuera de su red.
    ///
    /// Llega por la sesion ya autenticada, en cada conexion. Dart lo guarda
    /// junto al dispositivo y lo usa como ultimo recurso al reconectar.
    /// `host` vacio significa que la PC apago el tunel y hay que olvidar lo
    /// que estaba guardado.
    RelayOfferReceived {
        host: String,
        port: u16,
        token_hex: String,
    },
    /// Rol Android: lista de procesos de la PC. Reusa el mismo DTO que el
    /// panel local (`api/processes.rs`), asi que el telefono dibuja la tabla
    /// con el mismo widget que el escritorio.
    TopProcessesReceived(crate::api::processes::TopProcesses),
    /// Rol Android: como le fue al pedido de cerrar una aplicacion.
    ProcessTerminatedReceived {
        name: String,
        killed: u32,
        failed: u32,
        /// Con texto cuando la PC rechazo el pedido entero.
        rejected_reason: Option<String>,
    },
    ActionRunUpdateReceived {
        run_id: String,
        action_id: String,
        phase: RunPhase,
        exit_code: Option<i32>,
        elapsed_ms: u32,
        output_tail: String,
    },
    /// Rol Android: estado completo de las suscripciones en vivo de la PC
    /// (SignalR o WebSocket crudo) -- lista entera, no un diff. Solo lectura
    /// de este lado: detener/reiniciar/crear sigue siendo cosa de la PC.
    HubSubscriptionsSnapshotReceived(Vec<HubSubscriptionSummary>),
    /// Rol Android: nombres y caracteristicas de las piezas de la PC (modelo
    /// de CPU, memoria, GPU, adaptador de red), para el subtitulo de cada
    /// tile. Llega una sola vez por sesion, no en cada snapshot -- ver
    /// `crate::api::components::HostComponents`.
    HostComponentsReceived(crate::api::components::HostComponents),
    /// Rol Android: si el asistente de IA esta habilitado y listo en la PC.
    /// El telefono decide que UI mostrar solo con esto.
    AiStatusReceived {
        enabled: bool,
        ready: bool,
    },
    /// Rol Android: un evento de la conversacion con el asistente.
    AiChatEventReceived(AiRemoteChatEvent),
    /// Rol Android: la PC contesto una peticion de notas. El `request_id` es el
    /// que mando este telefono: puede haber varias en vuelo a la vez.
    NotesResponseReceived {
        request_id: String,
        response: NotesReply,
    },
    /// Rol Android: la boveda de la PC cambio. **No viene el cambio**: el
    /// telefono pide el manifiesto y compara contra su copia.
    NotesChanged,
}

/// Lo que la PC contesta sobre las notas. Espejo de
/// `nexodeck_protocol::NotesResponseWire`.
#[derive(Debug, Clone)]
pub enum NotesReply {
    /// Todas las notas con su hash, `privado/` incluido.
    Manifest { notes: Vec<NoteStamp> },
    Fetch { notes: Vec<NoteContent> },
    /// Un resultado por operacion, en el mismo orden que se mandaron.
    Applied { results: Vec<NoteOpResult> },
    /// La peticion entera no se pudo atender.
    Failed { detail: String },
}

/// Una nota de la boveda sin su texto.
#[derive(Debug, Clone)]
pub struct NoteStamp {
    pub path: String,
    pub hash: String,
    /// Segundos desde epoca, como los da el sistema de ficheros de la PC.
    pub modified_secs: Option<i64>,
    pub private: bool,
}

#[derive(Debug, Clone)]
pub struct NoteContent {
    pub path: String,
    pub text: String,
    pub hash: String,
    pub private: bool,
    /// `false` si la nota ya no existe: el telefono la borra de su copia.
    pub exists: bool,
}

/// Que paso con una operacion de la tanda.
#[derive(Debug, Clone)]
pub enum NoteOpResult {
    Saved {
        path: String,
        hash: String,
    },
    Deleted {
        path: String,
    },
    /// Cambio en la PC mientras el telefono estaba sin conexion. **No se
    /// escribio nada**: viaja lo que hay en disco para conservar las dos.
    Conflict {
        path: String,
        disk_text: String,
        disk_hash: String,
    },
    Failed {
        path: String,
        detail: String,
    },
}

/// Un cambio que el telefono quiere aplicar en la PC.
#[derive(Debug, Clone)]
pub enum NoteOp {
    /// `base_hash` es el hash con el que el telefono vio la nota; `None` la crea
    /// y nunca pisa una que ya exista.
    Save {
        path: String,
        text: String,
        base_hash: Option<String>,
    },
    Delete {
        path: String,
        base_hash: Option<String>,
    },
}

impl From<nexodeck_protocol::NotesResponseWire> for NotesReply {
    fn from(wire: nexodeck_protocol::NotesResponseWire) -> Self {
        use nexodeck_protocol::NotesResponseWire as W;
        match wire {
            W::Manifest { notes } => NotesReply::Manifest {
                notes: notes
                    .into_iter()
                    .map(|n| NoteStamp {
                        path: n.path,
                        hash: n.hash,
                        modified_secs: n.modified_secs,
                        private: n.private,
                    })
                    .collect(),
            },
            W::Fetch { notes } => NotesReply::Fetch {
                notes: notes
                    .into_iter()
                    .map(|n| NoteContent {
                        path: n.path,
                        text: n.text,
                        hash: n.hash,
                        private: n.private,
                        exists: n.exists,
                    })
                    .collect(),
            },
            W::Applied { results } => NotesReply::Applied {
                results: results
                    .into_iter()
                    .map(|r| match r {
                        nexodeck_protocol::NoteOpResultWire::Saved { path, hash } => {
                            NoteOpResult::Saved { path, hash }
                        }
                        nexodeck_protocol::NoteOpResultWire::Deleted { path } => {
                            NoteOpResult::Deleted { path }
                        }
                        nexodeck_protocol::NoteOpResultWire::Conflict {
                            path,
                            disk_text,
                            disk_hash,
                        } => NoteOpResult::Conflict {
                            path,
                            disk_text,
                            disk_hash,
                        },
                        nexodeck_protocol::NoteOpResultWire::Failed { path, detail } => {
                            NoteOpResult::Failed { path, detail }
                        }
                    })
                    .collect(),
            },
            W::Failed { detail } => NotesReply::Failed { detail },
        }
    }
}

impl From<NoteOp> for nexodeck_protocol::NoteOpWire {
    fn from(op: NoteOp) -> Self {
        match op {
            NoteOp::Save {
                path,
                text,
                base_hash,
            } => nexodeck_protocol::NoteOpWire::Save {
                path,
                text,
                base_hash,
            },
            NoteOp::Delete { path, base_hash } => {
                nexodeck_protocol::NoteOpWire::Delete { path, base_hash }
            }
        }
    }
}

/// Espejo de `nexodeck_protocol::HubSubscriptionWire` -- resumen de una
/// suscripcion para el panel remoto. Nombrado distinto de
/// `api::hub::HubSubscriptionKind`/`HubSubscriptionEvent` (que son sobre
/// ARRANCAR una suscripcion desde la PC) para no confundir dos conceptos
/// que comparten vocabulario pero no tipo: esto es el RESUMEN de una que ya
/// existe, empujado por la red.
#[derive(Debug, Clone)]
pub struct HubSubscriptionSummary {
    pub id: String,
    pub name: String,
    /// `base_url` + `hub_path` (o la URL entera si es WebSocket crudo) ya
    /// resuelto -- Android no arma el string, solo lo muestra.
    pub target: String,
    pub status: HubSubscriptionSummaryStatus,
    pub last_event_summary: Option<String>,
    /// Unix seconds. `None` si todavia no llego ningun mensaje.
    pub last_event_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HubSubscriptionSummaryStatus {
    Active,
    Stopped,
    Failed,
}

impl From<nexodeck_protocol::HubSubscriptionStatusWire> for HubSubscriptionSummaryStatus {
    fn from(value: nexodeck_protocol::HubSubscriptionStatusWire) -> Self {
        use nexodeck_protocol::HubSubscriptionStatusWire as W;
        match value {
            W::Active => HubSubscriptionSummaryStatus::Active,
            W::Stopped => HubSubscriptionSummaryStatus::Stopped,
            W::Failed => HubSubscriptionSummaryStatus::Failed,
        }
    }
}

impl From<HubSubscriptionSummaryStatus> for nexodeck_protocol::HubSubscriptionStatusWire {
    fn from(value: HubSubscriptionSummaryStatus) -> Self {
        match value {
            HubSubscriptionSummaryStatus::Active => nexodeck_protocol::HubSubscriptionStatusWire::Active,
            HubSubscriptionSummaryStatus::Stopped => nexodeck_protocol::HubSubscriptionStatusWire::Stopped,
            HubSubscriptionSummaryStatus::Failed => nexodeck_protocol::HubSubscriptionStatusWire::Failed,
        }
    }
}

impl From<nexodeck_protocol::HubSubscriptionWire> for HubSubscriptionSummary {
    fn from(value: nexodeck_protocol::HubSubscriptionWire) -> Self {
        Self {
            id: value.id,
            name: value.name,
            target: value.target,
            status: value.status.into(),
            last_event_summary: value.last_event_summary,
            last_event_at: value.last_event_at,
        }
    }
}

impl From<HubSubscriptionSummary> for nexodeck_protocol::HubSubscriptionWire {
    fn from(value: HubSubscriptionSummary) -> Self {
        Self {
            id: value.id,
            name: value.name,
            target: value.target,
            status: value.status.into(),
            last_event_summary: value.last_event_summary,
            last_event_at: value.last_event_at,
        }
    }
}

/// Espejo de `nexodeck_protocol::RunPhaseWire`.
///
/// Enum y no un `bool`: "lanzada" (una app que se abrio y sigue viva) no es
/// ni exito ni fallo, y aplastarlo a un booleano es justo lo que le faltaba
/// a `ActionAck`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunPhase {
    Started,
    Launched,
    Succeeded,
    Failed,
    Cancelled,
}

impl From<nexodeck_protocol::RunPhaseWire> for RunPhase {
    fn from(value: nexodeck_protocol::RunPhaseWire) -> Self {
        use nexodeck_protocol::RunPhaseWire as W;
        match value {
            W::Started => RunPhase::Started,
            W::Launched => RunPhase::Launched,
            W::Succeeded => RunPhase::Succeeded,
            W::Failed => RunPhase::Failed,
            W::Cancelled => RunPhase::Cancelled,
        }
    }
}

impl From<RunPhase> for nexodeck_protocol::RunPhaseWire {
    fn from(value: RunPhase) -> Self {
        use nexodeck_protocol::RunPhaseWire as W;
        match value {
            RunPhase::Started => W::Started,
            RunPhase::Launched => W::Launched,
            RunPhase::Succeeded => W::Succeeded,
            RunPhase::Failed => W::Failed,
            RunPhase::Cancelled => W::Cancelled,
        }
    }
}

/// Espejo de `nexodeck_protocol::RemoteActionKind`.
#[derive(Debug, Clone, Copy)]
pub enum RemoteActionKind {
    Clipboard,
    Terminal,
    Macro,
}

/// Espejo de `nexodeck_protocol::RemoteParamKind`.
#[derive(Debug, Clone, Copy)]
pub enum RemoteParamKind {
    Text,
    Number,
    Select,
}

/// Espejo de `nexodeck_protocol::RemoteActionParam`.
#[derive(Debug, Clone)]
pub struct RemoteActionParam {
    pub key: String,
    pub label: String,
    pub kind: RemoteParamKind,
    pub default_value: Option<String>,
    /// Ya parseadas a lista -- el JSON de `options_json` (Drift) se
    /// convierte del lado Dart, no viaja como JSON (ADR 0001).
    pub options: Vec<String>,
}

/// Espejo de `nexodeck_protocol::ActionParamValue`.
#[derive(Debug, Clone)]
pub struct ActionParamValue {
    pub key: String,
    pub value: String,
}

/// Espejo de `nexodeck_protocol::RemoteAction`.
#[derive(Debug, Clone)]
pub struct RemoteAction {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color_hex: String,
    pub group_id: Option<String>,
    pub group_name: Option<String>,
    pub group_color_hex: Option<String>,
    pub kind: RemoteActionKind,
    pub parameters: Vec<RemoteActionParam>,
    pub step_count: u32,
}

impl From<nexodeck_protocol::RemoteActionKind> for RemoteActionKind {
    fn from(k: nexodeck_protocol::RemoteActionKind) -> Self {
        use nexodeck_protocol::RemoteActionKind as K;
        match k {
            K::Clipboard => RemoteActionKind::Clipboard,
            K::Terminal => RemoteActionKind::Terminal,
            K::Macro => RemoteActionKind::Macro,
        }
    }
}

impl From<RemoteActionKind> for nexodeck_protocol::RemoteActionKind {
    fn from(k: RemoteActionKind) -> Self {
        use nexodeck_protocol::RemoteActionKind as K;
        match k {
            RemoteActionKind::Clipboard => K::Clipboard,
            RemoteActionKind::Terminal => K::Terminal,
            RemoteActionKind::Macro => K::Macro,
        }
    }
}

impl From<nexodeck_protocol::RemoteParamKind> for RemoteParamKind {
    fn from(k: nexodeck_protocol::RemoteParamKind) -> Self {
        use nexodeck_protocol::RemoteParamKind as K;
        match k {
            K::Text => RemoteParamKind::Text,
            K::Number => RemoteParamKind::Number,
            K::Select => RemoteParamKind::Select,
        }
    }
}

impl From<RemoteParamKind> for nexodeck_protocol::RemoteParamKind {
    fn from(k: RemoteParamKind) -> Self {
        use nexodeck_protocol::RemoteParamKind as K;
        match k {
            RemoteParamKind::Text => K::Text,
            RemoteParamKind::Number => K::Number,
            RemoteParamKind::Select => K::Select,
        }
    }
}

impl From<nexodeck_protocol::RemoteActionParam> for RemoteActionParam {
    fn from(p: nexodeck_protocol::RemoteActionParam) -> Self {
        Self {
            key: p.key,
            label: p.label,
            kind: p.kind.into(),
            default_value: p.default_value,
            options: p.options,
        }
    }
}

impl From<RemoteActionParam> for nexodeck_protocol::RemoteActionParam {
    fn from(p: RemoteActionParam) -> Self {
        Self {
            key: p.key,
            label: p.label,
            kind: p.kind.into(),
            default_value: p.default_value,
            options: p.options,
        }
    }
}

impl From<nexodeck_protocol::ActionParamValue> for ActionParamValue {
    fn from(v: nexodeck_protocol::ActionParamValue) -> Self {
        Self {
            key: v.key,
            value: v.value,
        }
    }
}

impl From<ActionParamValue> for nexodeck_protocol::ActionParamValue {
    fn from(v: ActionParamValue) -> Self {
        Self {
            key: v.key,
            value: v.value,
        }
    }
}

impl From<nexodeck_protocol::RemoteAction> for RemoteAction {
    fn from(a: nexodeck_protocol::RemoteAction) -> Self {
        Self {
            id: a.id,
            name: a.name,
            icon: a.icon,
            color_hex: a.color_hex,
            group_id: a.group_id,
            group_name: a.group_name,
            group_color_hex: a.group_color_hex,
            kind: a.kind.into(),
            parameters: a.parameters.into_iter().map(Into::into).collect(),
            step_count: a.step_count,
        }
    }
}

impl From<RemoteAction> for nexodeck_protocol::RemoteAction {
    fn from(a: RemoteAction) -> Self {
        Self {
            id: a.id,
            name: a.name,
            icon: a.icon,
            color_hex: a.color_hex,
            group_id: a.group_id,
            group_name: a.group_name,
            group_color_hex: a.group_color_hex,
            kind: a.kind.into(),
            parameters: a.parameters.into_iter().map(Into::into).collect(),
            step_count: a.step_count,
        }
    }
}

/// Espejo de `nexodeck_protocol::AiChatEventWire` -- un evento de la
/// conversacion con el asistente, tal como cruza el cable. Nombrado
/// `AiRemoteChatEvent` (no `AiChatEvent`, que ya existe en `api::ai` para
/// el stream LOCAL del bridge) para que no haya dos tipos con el mismo
/// nombre en el codigo Dart generado.
#[derive(Debug, Clone)]
pub enum AiRemoteChatEvent {
    UserMessage { text: String },
    Typing,
    AssistantMessage { text: String },
    ToolStarted { name: String, summary: String },
    ToolFinished { name: String, ok: bool, summary: String },
    DraftReady { draft: AiRemoteDraft },
    TurnDone,
    Failed { detail: String },
}

/// Espejo de `nexodeck_protocol::AiDraftWire`.
#[derive(Debug, Clone)]
pub struct AiRemoteDraft {
    pub name: String,
    pub description: Option<String>,
    pub icon: String,
    pub color_hex: String,
    pub summary: String,
    pub steps: Vec<AiRemoteDraftStep>,
    pub is_macro: bool,
    pub risk: AiRemoteRisk,
}

/// Espejo de `nexodeck_protocol::AiDraftStepWire`.
#[derive(Debug, Clone)]
pub struct AiRemoteDraftStep {
    pub name: String,
    pub description: Option<String>,
    pub action_type: RemoteActionKind,
    pub command: String,
    pub resolved_command: String,
    pub terminal: AiRemoteTerminal,
    pub requires_admin: bool,
    pub show_terminal_window: bool,
    pub working_directory: Option<String>,
    pub parameters: Vec<RemoteActionParam>,
    pub delay_ms_after: u32,
    pub risk: AiRemoteRisk,
    pub risk_notes: Vec<String>,
    pub auto_subscribe: Option<AiRemoteAutoSubscribe>,
}

/// Espejo de `nexodeck_protocol::AiTerminalWire`.
#[derive(Debug, Clone, Copy)]
pub enum AiRemoteTerminal {
    DefaultShell,
    PowerShell,
    Bash,
    Cmd,
}

/// Espejo de `nexodeck_protocol::AiRiskWire`.
#[derive(Debug, Clone, Copy)]
pub enum AiRemoteRisk {
    Safe,
    Caution,
    Dangerous,
}

/// Espejo de `nexodeck_protocol::AiAutoSubscribeWire`.
#[derive(Debug, Clone)]
pub struct AiRemoteAutoSubscribe {
    pub base_url: String,
    pub hub_path: String,
    pub invoke_method: String,
    pub json_field: String,
    pub allow_invalid_cert: bool,
}

impl From<nexodeck_protocol::AiTerminalWire> for AiRemoteTerminal {
    fn from(t: nexodeck_protocol::AiTerminalWire) -> Self {
        use nexodeck_protocol::AiTerminalWire as T;
        match t {
            T::DefaultShell => AiRemoteTerminal::DefaultShell,
            T::PowerShell => AiRemoteTerminal::PowerShell,
            T::Bash => AiRemoteTerminal::Bash,
            T::Cmd => AiRemoteTerminal::Cmd,
        }
    }
}

impl From<AiRemoteTerminal> for nexodeck_protocol::AiTerminalWire {
    fn from(t: AiRemoteTerminal) -> Self {
        use nexodeck_protocol::AiTerminalWire as T;
        match t {
            AiRemoteTerminal::DefaultShell => T::DefaultShell,
            AiRemoteTerminal::PowerShell => T::PowerShell,
            AiRemoteTerminal::Bash => T::Bash,
            AiRemoteTerminal::Cmd => T::Cmd,
        }
    }
}

impl From<nexodeck_protocol::AiRiskWire> for AiRemoteRisk {
    fn from(r: nexodeck_protocol::AiRiskWire) -> Self {
        use nexodeck_protocol::AiRiskWire as R;
        match r {
            R::Safe => AiRemoteRisk::Safe,
            R::Caution => AiRemoteRisk::Caution,
            R::Dangerous => AiRemoteRisk::Dangerous,
        }
    }
}

impl From<AiRemoteRisk> for nexodeck_protocol::AiRiskWire {
    fn from(r: AiRemoteRisk) -> Self {
        use nexodeck_protocol::AiRiskWire as R;
        match r {
            AiRemoteRisk::Safe => R::Safe,
            AiRemoteRisk::Caution => R::Caution,
            AiRemoteRisk::Dangerous => R::Dangerous,
        }
    }
}

impl From<nexodeck_protocol::AiAutoSubscribeWire> for AiRemoteAutoSubscribe {
    fn from(v: nexodeck_protocol::AiAutoSubscribeWire) -> Self {
        Self {
            base_url: v.base_url,
            hub_path: v.hub_path,
            invoke_method: v.invoke_method,
            json_field: v.json_field,
            allow_invalid_cert: v.allow_invalid_cert,
        }
    }
}

impl From<AiRemoteAutoSubscribe> for nexodeck_protocol::AiAutoSubscribeWire {
    fn from(v: AiRemoteAutoSubscribe) -> Self {
        Self {
            base_url: v.base_url,
            hub_path: v.hub_path,
            invoke_method: v.invoke_method,
            json_field: v.json_field,
            allow_invalid_cert: v.allow_invalid_cert,
        }
    }
}

impl From<nexodeck_protocol::AiDraftStepWire> for AiRemoteDraftStep {
    fn from(s: nexodeck_protocol::AiDraftStepWire) -> Self {
        Self {
            name: s.name,
            description: s.description,
            action_type: s.action_type.into(),
            command: s.command,
            resolved_command: s.resolved_command,
            terminal: s.terminal.into(),
            requires_admin: s.requires_admin,
            show_terminal_window: s.show_terminal_window,
            working_directory: s.working_directory,
            parameters: s.parameters.into_iter().map(Into::into).collect(),
            delay_ms_after: s.delay_ms_after,
            risk: s.risk.into(),
            risk_notes: s.risk_notes,
            auto_subscribe: s.auto_subscribe.map(Into::into),
        }
    }
}

impl From<AiRemoteDraftStep> for nexodeck_protocol::AiDraftStepWire {
    fn from(s: AiRemoteDraftStep) -> Self {
        Self {
            name: s.name,
            description: s.description,
            action_type: s.action_type.into(),
            command: s.command,
            resolved_command: s.resolved_command,
            terminal: s.terminal.into(),
            requires_admin: s.requires_admin,
            show_terminal_window: s.show_terminal_window,
            working_directory: s.working_directory,
            parameters: s.parameters.into_iter().map(Into::into).collect(),
            delay_ms_after: s.delay_ms_after,
            risk: s.risk.into(),
            risk_notes: s.risk_notes,
            auto_subscribe: s.auto_subscribe.map(Into::into),
        }
    }
}

impl From<nexodeck_protocol::AiDraftWire> for AiRemoteDraft {
    fn from(d: nexodeck_protocol::AiDraftWire) -> Self {
        Self {
            name: d.name,
            description: d.description,
            icon: d.icon,
            color_hex: d.color_hex,
            summary: d.summary,
            steps: d.steps.into_iter().map(Into::into).collect(),
            is_macro: d.is_macro,
            risk: d.risk.into(),
        }
    }
}

impl From<AiRemoteDraft> for nexodeck_protocol::AiDraftWire {
    fn from(d: AiRemoteDraft) -> Self {
        Self {
            name: d.name,
            description: d.description,
            icon: d.icon,
            color_hex: d.color_hex,
            summary: d.summary,
            steps: d.steps.into_iter().map(Into::into).collect(),
            is_macro: d.is_macro,
            risk: d.risk.into(),
        }
    }
}

impl From<nexodeck_protocol::AiChatEventWire> for AiRemoteChatEvent {
    fn from(e: nexodeck_protocol::AiChatEventWire) -> Self {
        use nexodeck_protocol::AiChatEventWire as E;
        match e {
            E::UserMessage { text } => AiRemoteChatEvent::UserMessage { text },
            E::Typing => AiRemoteChatEvent::Typing,
            E::AssistantMessage { text } => AiRemoteChatEvent::AssistantMessage { text },
            E::ToolStarted { name, summary } => AiRemoteChatEvent::ToolStarted { name, summary },
            E::ToolFinished { name, ok, summary } => {
                AiRemoteChatEvent::ToolFinished { name, ok, summary }
            }
            E::DraftReady { draft } => AiRemoteChatEvent::DraftReady {
                draft: draft.into(),
            },
            E::TurnDone => AiRemoteChatEvent::TurnDone,
            E::Failed { detail } => AiRemoteChatEvent::Failed { detail },
        }
    }
}

impl From<AiRemoteChatEvent> for nexodeck_protocol::AiChatEventWire {
    fn from(e: AiRemoteChatEvent) -> Self {
        use nexodeck_protocol::AiChatEventWire as E;
        match e {
            AiRemoteChatEvent::UserMessage { text } => E::UserMessage { text },
            AiRemoteChatEvent::Typing => E::Typing,
            AiRemoteChatEvent::AssistantMessage { text } => E::AssistantMessage { text },
            AiRemoteChatEvent::ToolStarted { name, summary } => E::ToolStarted { name, summary },
            AiRemoteChatEvent::ToolFinished { name, ok, summary } => {
                E::ToolFinished { name, ok, summary }
            }
            AiRemoteChatEvent::DraftReady { draft } => E::DraftReady {
                draft: draft.into(),
            },
            AiRemoteChatEvent::TurnDone => E::TurnDone,
            AiRemoteChatEvent::Failed { detail } => E::Failed { detail },
        }
    }
}

impl From<nexodeck_transport::server::ConnectionEvent> for ConnectionEvent {
    fn from(e: nexodeck_transport::server::ConnectionEvent) -> Self {
        use nexodeck_transport::server::ConnectionEvent as E;
        match e {
            E::DeviceConnected { device_id } => ConnectionEvent::DeviceConnected { device_id },
            E::DeviceDisconnected { device_id } => ConnectionEvent::DeviceDisconnected { device_id },
            E::ActionExecutionRequested {
                device_id,
                action_id,
                params,
            } => ConnectionEvent::ActionExecutionRequested {
                device_id,
                action_id,
                params: params.into_iter().map(Into::into).collect(),
            },
            E::AiMessageRequested { device_id, text } => {
                ConnectionEvent::AiMessageRequested { device_id, text }
            }
            E::AiActivateRequested { device_id } => {
                ConnectionEvent::AiActivateRequested { device_id }
            }
            E::AiApplyDraftRequested { device_id, draft } => {
                ConnectionEvent::AiApplyDraftRequested {
                    device_id,
                    draft: draft.into(),
                }
            }
            E::AiRunDraftRequested { device_id, draft } => ConnectionEvent::AiRunDraftRequested {
                device_id,
                draft: draft.into(),
            },
            E::AiAskAboutProcessRequested { device_id, group } => {
                ConnectionEvent::AiAskAboutProcessRequested {
                    device_id,
                    group: group.into(),
                }
            }
        }
    }
}

impl From<nexodeck_transport::client::ConnectionEvent> for ConnectionEvent {
    fn from(e: nexodeck_transport::client::ConnectionEvent) -> Self {
        use nexodeck_transport::client::ConnectionEvent as E;
        match e {
            E::Connected => ConnectionEvent::Connected,
            E::Disconnected => ConnectionEvent::Disconnected,
            E::NotesResponseReceived {
                request_id,
                response,
            } => ConnectionEvent::NotesResponseReceived {
                request_id,
                response: response.into(),
            },
            E::NotesChanged => ConnectionEvent::NotesChanged,
            E::HardwareSnapshotReceived(s) => ConnectionEvent::HardwareSnapshotReceived(s.into()),
            E::ActionsCatalogReceived(actions) => {
                ConnectionEvent::ActionsCatalogReceived(actions.into_iter().map(Into::into).collect())
            }
            E::ActionAckReceived {
                action_id,
                success,
                error,
            } => ConnectionEvent::ActionAckReceived {
                action_id,
                success,
                error,
            },
            E::ActionRunUpdateReceived {
                run_id,
                action_id,
                phase,
                exit_code,
                elapsed_ms,
                output_tail,
            } => ConnectionEvent::ActionRunUpdateReceived {
                run_id,
                action_id,
                phase: phase.into(),
                exit_code,
                elapsed_ms,
                output_tail,
            },
            E::RelayOfferReceived {
                host,
                port,
                token_hex,
            } => ConnectionEvent::RelayOfferReceived {
                host,
                port,
                token_hex,
            },
            E::HostComponentsReceived(components) => {
                ConnectionEvent::HostComponentsReceived(components.into())
            }
            E::TopProcessesReceived(sample) => {
                ConnectionEvent::TopProcessesReceived(sample.into())
            }
            E::ProcessTerminatedReceived {
                name,
                killed,
                failed,
                rejected_reason,
            } => ConnectionEvent::ProcessTerminatedReceived {
                name,
                killed,
                failed,
                rejected_reason,
            },
            E::HubSubscriptionsSnapshotReceived(subscriptions) => {
                ConnectionEvent::HubSubscriptionsSnapshotReceived(
                    subscriptions.into_iter().map(Into::into).collect(),
                )
            }
            E::AiStatusReceived { enabled, ready } => {
                ConnectionEvent::AiStatusReceived { enabled, ready }
            }
            E::AiChatEventReceived(event) => {
                ConnectionEvent::AiChatEventReceived(event.into())
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct AuthorizedDevice {
    pub id: String,
    pub is_authorized: bool,
}

/// Multiplexa los eventos de sesion del host (si esta iniciado) y del
/// cliente hacia un unico stream -- mismo patron que `watch_pairing_events`.
pub async fn watch_connection_events(sink: StreamSink<ConnectionEvent>) {
    let mut client_rx = nexodeck_transport::client::client().connection_events();
    let mut host_rx = nexodeck_transport::server::host().map(|h| h.connection_events());

    loop {
        let forwarded = tokio::select! {
            ev = client_rx.recv() => ev.ok().map(ConnectionEvent::from),
            ev = recv_optional_connection(&mut host_rx) => ev.map(ConnectionEvent::from),
        };
        match forwarded {
            Some(event) => {
                if sink.add(event).is_err() {
                    break;
                }
            }
            None => continue,
        }
    }
}

async fn recv_optional_connection(
    rx: &mut Option<tokio::sync::broadcast::Receiver<nexodeck_transport::server::ConnectionEvent>>,
) -> Option<nexodeck_transport::server::ConnectionEvent> {
    match rx {
        Some(r) => r.recv().await.ok(),
        None => std::future::pending().await,
    }
}

/// Rol Android: pide a la PC ejecutar una accion ya sembrada en Drift,
/// con los valores que el usuario cargo en el prompt del telefono
/// (`params` vacio si la accion no tiene parametros).
pub fn send_execute_action(
    action_id: String,
    params: Vec<ActionParamValue>,
) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_execute_action(action_id, params.into_iter().map(Into::into).collect())
        .map_err(|e| e.to_string())
}

/// Rol PC: responde con el resultado real de haber ejecutado la accion
/// (via `nexodeck-actions`, el mismo motor que usa `execute_clipboard_action`/
/// `execute_terminal_action` localmente).
pub fn send_action_ack(
    device_id: String,
    action_id: String,
    success: bool,
    error: Option<String>,
) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_action_ack(&device_id, action_id, success, error)
        .map_err(|e| e.to_string())
}

/// Rol PC: le cuenta al dispositivo como le va al comando que mando
/// ejecutar. Se llama al arrancar y al cerrar, no por cada lote de salida:
/// mandar cada linea por WiFi para dibujar una notificacion no se justifica.
pub fn send_action_run_update(
    device_id: String,
    run_id: String,
    action_id: String,
    phase: RunPhase,
    exit_code: Option<i32>,
    elapsed_ms: u32,
    output_tail: String,
) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_action_run_update(
        &device_id,
        nexodeck_protocol::MessageV1::ActionRunUpdate {
            run_id,
            action_id,
            phase: phase.into(),
            exit_code,
            elapsed_ms,
            output_tail,
        },
    )
    .map_err(|e| e.to_string())
}

/// Rol PC: empuja el catalogo de acciones disponibles hacia un dispositivo
/// ya conectado -- se llama al recibir `ConnectionEvent::DeviceConnected`
/// (ver `main.dart`), con la lista actual de `actionsListProvider`.
pub fn send_actions_catalog(device_id: String, actions: Vec<RemoteAction>) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_actions_catalog(&device_id, actions.into_iter().map(Into::into).collect())
        .map_err(|e| e.to_string())
}

/// Rol PC: empuja el estado completo de las suscripciones en vivo hacia un
/// dispositivo ya conectado -- se llama al recibir
/// `ConnectionEvent::DeviceConnected` y de nuevo cada vez que
/// `hubSubscriptionsListProvider` cambia (ver `main.dart`), mismo patron que
/// `send_actions_catalog`.
pub fn send_hub_subscriptions_snapshot(
    device_id: String,
    subscriptions: Vec<HubSubscriptionSummary>,
) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_hub_subscriptions_snapshot(
        &device_id,
        subscriptions.into_iter().map(Into::into).collect(),
    )
    .map_err(|e| e.to_string())
}

/// Rol PC: empuja los nombres de las piezas hacia un dispositivo ya
/// conectado -- se llama al recibir `ConnectionEvent::DeviceConnected` (ver
/// `main.dart`), una sola vez, con el `HostComponents` ya leido (caro de
/// pedir de nuevo: WMI y NVML).
pub fn send_host_components(
    device_id: String,
    components: crate::api::components::HostComponents,
) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_host_components(&device_id, components.into())
        .map_err(|e| e.to_string())
}

/// Rol PC: mantiene la cache de autorizados de `nexodeck-transport`
/// sincronizada con la tabla `devices` de Drift -- se llama cada vez que
/// cambia la lista en la UI (ver `ref.listen(pairedDevicesListProvider)`
/// en `main.dart`).
pub fn sync_authorized_devices(devices: Vec<AuthorizedDevice>) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.sync_authorized_devices(devices.into_iter().map(|d| (d.id, d.is_authorized)).collect());
    Ok(())
}

/// Rol PC: revoca (o restaura) la autorizacion de un dispositivo. Si se
/// revoca y hay una sesion viva, se cierra de inmediato.
pub fn set_device_authorized(device_id: String, is_authorized: bool) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.set_device_authorized(&device_id, is_authorized);
    Ok(())
}

/// Rol Android: pide (o corta) el envio de la lista de procesos de la PC.
///
/// **Es una suscripcion**: la PC solo recorre sus procesos mientras el panel
/// este abierto. Cerrarlo apaga el colector alla y deja de gastar bateria aca.
pub fn send_watch_processes(enabled: bool) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_watch_processes(enabled)
        .map_err(|e| e.to_string())
}

/// Rol Android: pide cerrar una aplicacion en la PC.
///
/// Viajan nombre y pids: la PC cierra solo los que sigan llamandose asi, para
/// que un toque en el telefono no mate un programa distinto si Windows reuso
/// el pid entre la muestra y el toque.
pub fn send_terminate_process_group(
    name: String,
    pids: Vec<u32>,
) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_terminate_process_group(name, pids)
        .map_err(|e| e.to_string())
}

/// Rol PC: empuja si el asistente esta habilitado y listo hacia un
/// dispositivo ya conectado -- se llama al recibir
/// `ConnectionEvent::DeviceConnected` y de nuevo cada vez que cambia el
/// switch de arriba o el motor termina de activarse (ver `main.dart`).
pub fn send_ai_status(device_id: String, enabled: bool, ready: bool) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_ai_status(&device_id, enabled, ready)
        .map_err(|e| e.to_string())
}

/// Rol PC: reenvia un evento de la conversacion con el asistente hacia un
/// dispositivo ya conectado.
pub fn send_ai_chat_event(device_id: String, event: AiRemoteChatEvent) -> Result<(), String> {
    let host = nexodeck_transport::server::host().ok_or("el host de transporte no esta iniciado")?;
    host.send_ai_chat_event(&device_id, event.into())
        .map_err(|e| e.to_string())
}

/// Rol Android: manda un mensaje al chat del asistente que corre en la PC.
pub fn send_ai_message(text: String) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_ai_message(text)
        .map_err(|e| e.to_string())
}

/// Rol Android: pide que la PC active el asistente. Solo tiene sentido si
/// el ultimo `AiStatusReceived` dijo `enabled: true, ready: false`.
pub fn send_ai_activate() -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_ai_activate()
        .map_err(|e| e.to_string())
}

/// Rol Android: pide guardar un borrador como boton nuevo. Los comandos de
/// cada paso ya vienen resueltos -- el telefono ya junto los parametros
/// con el mismo dialogo que usa la PC.
pub fn send_ai_apply_draft(draft: AiRemoteDraft) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_ai_apply_draft(draft.into())
        .map_err(|e| e.to_string())
}

/// Rol Android: pide correr un borrador ahora, en vivo.
pub fn send_ai_run_draft(draft: AiRemoteDraft) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_ai_run_draft(draft.into())
        .map_err(|e| e.to_string())
}

/// Rol Android: pide que la IA explique este proceso.
pub fn send_ai_ask_about_process(group: crate::api::processes::ProcessGroup) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_ai_ask_about_process(group.into())
        .map_err(|e| e.to_string())
}

/// Rol Android: pide el manifiesto de la boveda de la PC (todas las notas con
/// su hash, `privado/` incluido).
///
/// La respuesta llega por `watch_connection_events` como
/// `NotesResponseReceived` con este mismo `request_id`. **No espera**: si no
/// hay sesion, esto falla y el telefono sigue con su copia local.
pub fn send_notes_manifest_request(request_id: String) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_notes_request(request_id, nexodeck_protocol::NotesRequestWire::Manifest)
        .map_err(|e| e.to_string())
}

/// Rol Android: pide el texto de esas notas.
///
/// Varias juntas a proposito: tras un rato sin cobertura suelen ser varias, y
/// una peticion por nota multiplicaria las idas y vueltas por datos moviles.
pub fn send_notes_fetch_request(request_id: String, paths: Vec<String>) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_notes_request(
            request_id,
            nexodeck_protocol::NotesRequestWire::Fetch { paths },
        )
        .map_err(|e| e.to_string())
}

/// Rol Android: manda los cambios que el telefono tenia encolados.
///
/// Van **en una tanda y en orden**: es lo que estaba en la cola, y aplicar la
/// mitad dejaria la copia local diciendo algo distinto de la boveda.
pub fn send_notes_apply_request(request_id: String, ops: Vec<NoteOp>) -> Result<(), String> {
    nexodeck_transport::client::client()
        .send_notes_request(
            request_id,
            nexodeck_protocol::NotesRequestWire::Apply {
                ops: ops.into_iter().map(Into::into).collect(),
            },
        )
        .map_err(|e| e.to_string())
}
