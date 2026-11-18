//! El buzon de documentacion, visto desde Dart.
//!
//! Dart no guarda nada del buzon: pide una foto ([`docs_inbox_snapshot`]) y la
//! vuelve a pedir cada vez que llega un aviso por [`watch_docs_inbox_events`].
//! La unica fuente de verdad son los ficheros que escribe `nexodeck-docs`, asi
//! que perder un aviso no desincroniza nada.
//!
//! Solo escritorio, con las firmas presentes en los tres targets y el cuerpo
//! cfg-gateado: mismo criterio que `api/control.rs`.
//!
//! Los estados cruzan como texto (`"queued"`, `"needs_review"`...) y no como
//! enums con datos: la UI solo necesita el nombre y un detalle legible, y asi
//! el esquema de disco puede crecer sin regenerar el puente.

use crate::frb_generated::StreamSink;

#[cfg(not(target_os = "android"))]
use std::sync::{Arc, OnceLock};

#[cfg(not(target_os = "android"))]
static SERVICE: OnceLock<Arc<nexodeck_docs::DocsService>> = OnceLock::new();

#[cfg(target_os = "android")]
const DESKTOP_ONLY: &str = "el buzon de documentacion es solo de escritorio";

#[derive(Debug, Clone)]
pub struct DocsInboxSnapshot {
    pub root: String,
    pub worker_enabled: bool,
    pub working: bool,
    pub last_error: Option<String>,
    /// `modelo (proveedor)`, o `None` si no hay remoto configurado.
    pub remote_label: Option<String>,
    pub local_fallback: bool,
    pub projects: Vec<DocProjectItem>,
    pub findings: Vec<DocFindingItem>,
    pub proposals: Vec<DocProposalItem>,
}

#[derive(Debug, Clone)]
pub struct DocProjectItem {
    pub id: String,
    pub name: String,
    pub repo_root: String,
    pub documents: Vec<DocDocumentItem>,
}

#[derive(Debug, Clone)]
pub struct DocDocumentItem {
    pub path: String,
    pub role: String,
    pub answers: String,
}

#[derive(Debug, Clone)]
pub struct DocEvidenceItem {
    /// `M` o `S`.
    pub label: String,
    pub text: String,
    pub source: Option<String>,
}

#[derive(Debug, Clone)]
pub struct DocFindingItem {
    pub id: String,
    pub batch_id: String,
    pub project: String,
    pub from: Option<String>,
    pub created_at: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub evidence: Vec<DocEvidenceItem>,
    pub supersedes: Option<String>,
    /// `queued`, `proposing`, `proposed`, `applied`, `rejected`, `failed` o
    /// `waiting_model`.
    pub state: String,
    /// El motivo de un fallo o de una espera, o la nota de un rechazo.
    pub state_detail: Option<String>,
    pub proposal_id: Option<String>,
    pub retry_at: Option<String>,
}

#[derive(Debug, Clone)]
pub struct DocOperationItem {
    /// `insert_section_top`, `set_last_updated`, `replace_exact` o
    /// `append_under_heading`.
    pub kind: String,
    pub file: String,
    /// Lo que resume la operacion: el encabezado, la fecha o el motivo.
    pub title: String,
    pub line: u32,
    pub before: String,
    pub after: String,
    pub removed_lines: u32,
    pub added_lines: u32,
    pub destructive: bool,
}

#[derive(Debug, Clone)]
pub struct DocUnresolvedItem {
    pub finding_id: String,
    pub why: String,
}

#[derive(Debug, Clone)]
pub struct DocProposalItem {
    pub id: String,
    pub project: String,
    /// La que se pasa al aprobar. Sube cada vez que la propuesta cambia, para
    /// que no se pueda aprobar algo distinto de lo que se vio.
    pub revision: u32,
    pub created_at: String,
    pub updated_at: String,
    pub from: Option<String>,
    pub summary: String,
    /// `ready`, `needs_review`, `stale`, `applied`, `rejected`, `failed` o
    /// `undone`.
    pub state: String,
    pub state_detail: Option<String>,
    pub stale_reasons: Vec<String>,
    pub model_label: String,
    pub local_model: bool,
    pub warnings: Vec<String>,
    pub finding_ids: Vec<String>,
    /// `findings` (hallazgos de Claude Code) o `note_digest` (una nota de la
    /// boveda procesada por el asistente de notas).
    pub origin: String,
    /// La nota y su digest, si `origin` es `note_digest`.
    pub note: Option<String>,
    pub digest_id: Option<String>,
    pub unresolved: Vec<DocUnresolvedItem>,
    pub operations: Vec<DocOperationItem>,
}

/// Aviso de que algo cambio en el buzon. Lleva un contador para que dos avisos
/// seguidos nunca sean `==`: Riverpod descartaria el segundo.
#[derive(Debug, Clone)]
pub struct DocsInboxChanged {
    pub seq: u32,
}

/// Tambien la usa `api/notes.rs`: el asistente de notas vive en este servicio.
#[cfg(not(target_os = "android"))]
pub(crate) fn service() -> Result<Arc<nexodeck_docs::DocsService>, String> {
    SERVICE
        .get()
        .cloned()
        .ok_or_else(|| "el buzon de documentacion no esta inicializado".to_string())
}

/// Abre el buzon, arranca el trabajador y lo engancha al servidor de control.
/// Idempotente: una segunda llamada solo actualiza si la IA local esta
/// encendida. Devuelve la carpeta del buzon.
///
/// **Es `async` por obligacion**: el trabajador se lanza con `tokio::spawn`, y
/// solo hay runtime dentro de las funciones `async` de frb.
pub async fn docs_inbox_init(ai_enabled: bool) -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        if let Some(existing) = SERVICE.get() {
            existing.set_ai_enabled(ai_enabled);
            return Ok(existing.inbox().root().to_string_lossy().into_owned());
        }
        let root = nexodeck_docs::Inbox::default_root().map_err(|e| e.to_string())?;
        let inbox = nexodeck_docs::Inbox::open(&root).map_err(|e| e.to_string())?;
        let service = nexodeck_docs::DocsService::new(inbox, nexodeck_docs::Backends::Live);
        service.set_ai_enabled(ai_enabled);

        // Dos llamadas casi a la vez: gana la primera y la segunda usa esa.
        let service = SERVICE.get_or_init(|| service).clone();
        service.spawn();
        nexodeck_control::control().set_docs(Some(Arc::clone(&service)));
        // Y el telefono: la misma boveda, resuelta por el transporte. Registrar
        // aca y en `start_transport_host` cubre los dos ordenes posibles, porque
        // cual de los dos arranca antes no esta garantizado.
        super::notes_vault::register(&service);
        super::notes_vault::spawn_change_notifier(&service);
        Ok(root.to_string_lossy().into_owned())
    }
    #[cfg(target_os = "android")]
    {
        let _ = ai_enabled;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// El interruptor de la IA de la app. Apagada, el modelo local ni se consulta.
pub fn docs_set_ai_enabled(enabled: bool) {
    #[cfg(not(target_os = "android"))]
    {
        if let Some(service) = SERVICE.get() {
            service.set_ai_enabled(enabled);
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = enabled;
    }
}

pub fn docs_inbox_snapshot() -> Result<DocsInboxSnapshot, String> {
    #[cfg(not(target_os = "android"))]
    {
        let service = service()?;
        let snapshot = service.snapshot().map_err(|e| e.to_string())?;
        Ok(convert::snapshot(service.inbox().root(), snapshot))
    }
    #[cfg(target_os = "android")]
    {
        Err(DESKTOP_ONLY.to_string())
    }
}

/// La configuracion en JSON, para el editor de proyectos.
pub fn docs_inbox_config_json() -> Result<String, String> {
    #[cfg(not(target_os = "android"))]
    {
        let config = service()?.inbox().config().map_err(|e| e.to_string())?;
        serde_json::to_string_pretty(&config).map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Guarda la configuracion. El `Err` trae todos los problemas, uno por linea,
/// para enseñarlos en el editor.
pub fn save_docs_inbox_config(json: String) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        let service = service()?;
        let config: nexodeck_docs::InboxConfig =
            serde_json::from_str(&json).map_err(|e| format!("no es JSON valido: {e}"))?;
        service.inbox().save_config(&config).map_err(|e| e.to_string())?;
        service.poke();
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        let _ = json;
        Err(DESKTOP_ONLY.to_string())
    }
}

pub fn set_docs_worker_enabled(enabled: bool) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        let service = service()?;
        let mut config = service.inbox().config().map_err(|e| e.to_string())?;
        config.worker_enabled = enabled;
        service.inbox().save_config(&config).map_err(|e| e.to_string())?;
        service.poke();
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        let _ = enabled;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Al abrir el detalle: revalida contra los documentos de ahora.
pub async fn check_docs_proposal(id: String) -> Result<DocProposalItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let proposal = service()?
            .check(&id, jiff::Timestamp::now())
            .await
            .map_err(|e| e.to_string())?;
        Ok(convert::proposal(proposal))
    }
    #[cfg(target_os = "android")]
    {
        let _ = id;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Aplica la propuesta si sigue siendo la revision que vio el usuario. Si los
/// documentos cambiaron, no escribe nada y devuelve la propuesta en
/// `needs_review` o `stale`: el `state` del resultado dice que paso.
pub async fn approve_docs_proposal(id: String, revision: u32) -> Result<DocProposalItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let outcome = service()?
            .approve(&id, revision, jiff::Timestamp::now())
            .await
            .map_err(|e| e.to_string())?;
        let proposal = match outcome {
            nexodeck_docs::ApproveOutcome::Applied(p)
            | nexodeck_docs::ApproveOutcome::NeedsReview(p)
            | nexodeck_docs::ApproveOutcome::Stale(p) => p,
        };
        Ok(convert::proposal(proposal))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (id, revision);
        Err(DESKTOP_ONLY.to_string())
    }
}

pub async fn reject_docs_proposal(id: String, note: Option<String>) -> Result<DocProposalItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let proposal = service()?
            .reject(&id, note, jiff::Timestamp::now())
            .await
            .map_err(|e| e.to_string())?;
        Ok(convert::proposal(proposal))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (id, note);
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Puede tardar un minuto: llama al modelo. Si falla, la propuesta anterior
/// queda como estaba.
pub async fn regenerate_docs_proposal(
    id: String,
    note: Option<String>,
) -> Result<DocProposalItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let proposal = service()?
            .regenerate(&id, note, jiff::Timestamp::now())
            .await
            .map_err(|e| e.to_string())?;
        Ok(convert::proposal(proposal))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (id, note);
        Err(DESKTOP_ONLY.to_string())
    }
}

pub async fn undo_docs_proposal(id: String) -> Result<DocProposalItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let proposal = service()?
            .undo(&id, jiff::Timestamp::now())
            .await
            .map_err(|e| e.to_string())?;
        Ok(convert::proposal(proposal))
    }
    #[cfg(target_os = "android")]
    {
        let _ = id;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Un aviso por cada cambio. Se consume con **suscripcion directa al
/// `Stream`**, nunca con `ref.listen`, y en cada aviso se vuelve a pedir la foto.
pub async fn watch_docs_inbox_events(sink: StreamSink<DocsInboxChanged>) {
    #[cfg(not(target_os = "android"))]
    {
        let Ok(service) = service() else {
            return;
        };
        let mut events = service.subscribe();
        let mut seq: u32 = 0;
        // Atrasarse (`Lagged`) no pierde nada: la foto siempre esta al dia, asi
        // que un solo aviso vale por todos los que se saltaron. Solo `Closed`
        // corta el bucle.
        while let Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) =
            events.recv().await
        {
            seq = seq.wrapping_add(1);
            if sink.add(DocsInboxChanged { seq }).is_err() {
                break;
            }
        }
    }
    #[cfg(target_os = "android")]
    {
        let _ = sink;
    }
}

#[cfg(not(target_os = "android"))]
mod convert {
    use super::*;
    use nexodeck_docs::{
        EvidenceLabel, Finding, FindingStatus, Operation, Proposal, ProposalOrigin, ProposalStatus,
    };

    pub(super) fn snapshot(
        root: &std::path::Path,
        snapshot: nexodeck_docs::InboxSnapshot,
    ) -> DocsInboxSnapshot {
        let config = snapshot.config;
        DocsInboxSnapshot {
            root: root.to_string_lossy().into_owned(),
            worker_enabled: config.worker_enabled,
            working: snapshot.working,
            last_error: snapshot.last_error,
            remote_label: config
                .remote
                .as_ref()
                .map(|r| format!("{} ({})", r.model, r.provider_id)),
            local_fallback: config.local_fallback,
            projects: config
                .projects
                .into_iter()
                .map(|p| DocProjectItem {
                    id: p.id,
                    name: p.name,
                    repo_root: p.repo_root,
                    documents: p
                        .documents
                        .into_iter()
                        .map(|d| DocDocumentItem {
                            path: d.path,
                            role: d.role.as_str().to_string(),
                            answers: d.answers,
                        })
                        .collect(),
                })
                .collect(),
            findings: snapshot.findings.into_iter().map(finding).collect(),
            proposals: snapshot.proposals.into_iter().map(proposal).collect(),
        }
    }

    fn finding(f: Finding) -> DocFindingItem {
        let (state, detail, proposal_id, retry_at) = match f.status {
            FindingStatus::Queued => ("queued", None, None, None),
            FindingStatus::Proposing => ("proposing", None, None, None),
            FindingStatus::Proposed { proposal_id } => ("proposed", None, Some(proposal_id), None),
            FindingStatus::Applied { proposal_id } => ("applied", None, Some(proposal_id), None),
            FindingStatus::Rejected { proposal_id, note } => ("rejected", note, Some(proposal_id), None),
            FindingStatus::Failed { reason } => ("failed", Some(reason), None, None),
            FindingStatus::WaitingModel { reason, retry_at, .. } => {
                ("waiting_model", Some(reason), None, retry_at)
            }
        };
        let content = f.content;
        DocFindingItem {
            id: f.id,
            batch_id: f.batch_id,
            project: f.project,
            from: f.from,
            created_at: f.created_at,
            kind: serde_json::to_value(content.kind)
                .ok()
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_default(),
            title: content.title,
            body: content.body,
            evidence: content
                .evidence
                .into_iter()
                .map(|e| DocEvidenceItem {
                    label: match e.label {
                        EvidenceLabel::M => "M",
                        EvidenceLabel::S => "S",
                    }
                    .to_string(),
                    text: e.text,
                    source: e.source,
                })
                .collect(),
            supersedes: content.supersedes,
            state: state.to_string(),
            state_detail: detail,
            proposal_id,
            retry_at,
        }
    }

    pub(super) fn proposal(p: Proposal) -> DocProposalItem {
        let (state, detail, stale_reasons) = match p.status {
            ProposalStatus::Ready => ("ready", None, Vec::new()),
            ProposalStatus::NeedsReview { reason } => ("needs_review", Some(reason), Vec::new()),
            ProposalStatus::Stale { reasons } => ("stale", None, reasons),
            ProposalStatus::Applied => ("applied", None, Vec::new()),
            ProposalStatus::Rejected { note } => ("rejected", note, Vec::new()),
            ProposalStatus::Failed { reason } => ("failed", Some(reason), Vec::new()),
            ProposalStatus::Undone => ("undone", None, Vec::new()),
        };
        DocProposalItem {
            id: p.id,
            project: p.project,
            revision: p.revision,
            created_at: p.created_at,
            updated_at: p.updated_at,
            from: p.from,
            summary: p.summary,
            state: state.to_string(),
            state_detail: detail,
            stale_reasons,
            model_label: p.model_label,
            local_model: p.local_model,
            warnings: p.warnings,
            finding_ids: p.finding_ids,
            origin: match &p.origin {
                ProposalOrigin::Findings => "findings",
                ProposalOrigin::NoteDigest { .. } => "note_digest",
            }
            .to_string(),
            note: match &p.origin {
                ProposalOrigin::NoteDigest { note, .. } => Some(note.clone()),
                ProposalOrigin::Findings => None,
            },
            digest_id: match &p.origin {
                ProposalOrigin::NoteDigest { digest_id, .. } => Some(digest_id.clone()),
                ProposalOrigin::Findings => None,
            },
            unresolved: p
                .unresolved
                .into_iter()
                .map(|u| DocUnresolvedItem {
                    finding_id: u.finding_id,
                    why: u.why,
                })
                .collect(),
            operations: p
                .operations
                .into_iter()
                .map(|o| {
                    let title = match &o.operation {
                        Operation::InsertSectionTop { heading, .. } => heading.clone(),
                        Operation::SetLastUpdated { date, .. } => date.clone(),
                        Operation::ReplaceExact { reason, .. } => reason.clone(),
                        Operation::AppendUnderHeading { heading, .. } => heading.clone(),
                        Operation::AddSection { heading, .. } => heading.clone(),
                        Operation::SetFrontmatterKey { key, value, .. } => {
                            format!("{key}: {value}")
                        }
                    };
                    DocOperationItem {
                        kind: o.operation.name().to_string(),
                        file: o.operation.file().to_string(),
                        title,
                        line: o.preview.line as u32,
                        before: o.preview.before,
                        after: o.preview.after,
                        removed_lines: o.preview.removed_lines as u32,
                        added_lines: o.preview.added_lines as u32,
                        destructive: o.destructive,
                    }
                })
                .collect(),
        }
    }
}
