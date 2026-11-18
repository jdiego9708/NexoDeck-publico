//! El trabajador y las decisiones del usuario sobre las propuestas.
//!
//! Un solo trabajo de modelo a la vez (`job`), y **una sola propuesta pendiente
//! por proyecto**: si hubiera dos sobre el mismo diario, aprobar la primera
//! cambiaria el hash base de la segunda y esta nunca se podria aplicar sin
//! regenerarla. Lo que llega mientras tanto espera en la cola y la UI ofrece
//! regenerar incluyendolo.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use jiff::Timestamp;
use tokio::sync::{broadcast, Notify};

use crate::apply::{apply_to_disk, read_documents, undo_on_disk, ApplyError};
use crate::backend::{live_candidates, ModelBackend, ModelErrorKind};
use crate::config::{normalize_rel, DocProject, InboxConfig};
use crate::dates::SpanishDate;
use crate::error::{DocsError, DocsResult};
use crate::generate::{generate_proposal, GenerateError, GenerateRequest, REPAIR_ROUNDS};
use crate::model::{Finding, FindingStatus, NewFinding, Proposal, ProposalStatus};
use crate::ops::Operation;
use crate::store::{sha256_hex, Inbox, SubmitOutcome};
use crate::validate::{validate_operations, ValidationInput};

/// Se espera a que la sesion deje de mandar: varias llamadas seguidas de
/// `submit_findings` salen en una sola propuesta.
pub const CALM_SECS: i64 = 90;
/// ...pero no para siempre, si la sesion no para de mandar.
pub const MAX_WAIT_SECS: i64 = 600;
/// Reintentos cuando no hay modelo o fallo algo pasajero: 5 min, 15 min, y
/// despues cada hora.
pub(crate) const RETRY_STEPS_SECS: [i64; 3] = [300, 900, 3_600];
const IDLE_POLL: Duration = Duration::from_secs(30);

pub enum Backends {
    /// El remoto configurado y el local de `nexodeck-ai` si ya esta levantado.
    Live,
    /// Una lista fija, para los tests.
    Fixed(Vec<ModelBackend>),
}

#[derive(Debug, Clone)]
pub enum ApproveOutcome {
    Applied(Proposal),
    /// Los documentos cambiaron pero la propuesta sigue aplicando: hay que
    /// volver a enseñarsela al usuario con la revision nueva.
    NeedsReview(Proposal),
    Stale(Proposal),
}

#[derive(Debug, Clone)]
pub struct InboxSnapshot {
    pub config: InboxConfig,
    pub findings: Vec<Finding>,
    pub proposals: Vec<Proposal>,
    /// Los digests de notas, del mas viejo al mas nuevo.
    pub digests: Vec<crate::notes::Digest>,
    pub working: bool,
    pub last_error: Option<String>,
}

pub struct DocsService {
    pub(crate) inbox: Inbox,
    backends: Backends,
    ai_enabled: AtomicBool,
    pub(crate) wake: Notify,
    events: broadcast::Sender<()>,
    job: tokio::sync::Mutex<()>,
    working: AtomicBool,
    last_error: Mutex<Option<String>>,
    pub(crate) cancel: Arc<AtomicBool>,
    /// El indice de la boveda del asistente de notas. Vive aca y no en cada
    /// llamada porque leer la boveda entera cuesta; despues solo se relee lo que
    /// cambio.
    pub(crate) notes: Mutex<crate::notes::NotesState>,
}

enum Failure {
    /// Se reintenta sola mas tarde.
    Retry(String),
    Fatal(String),
}

impl Failure {
    fn reason(&self) -> &str {
        match self {
            Failure::Retry(reason) | Failure::Fatal(reason) => reason,
        }
    }
}

impl DocsService {
    pub fn new(inbox: Inbox, backends: Backends) -> Arc<Self> {
        let (events, _) = broadcast::channel(64);
        Arc::new(DocsService {
            inbox,
            backends,
            ai_enabled: AtomicBool::new(false),
            wake: Notify::new(),
            events,
            job: tokio::sync::Mutex::new(()),
            working: AtomicBool::new(false),
            last_error: Mutex::new(None),
            cancel: Arc::new(AtomicBool::new(false)),
            notes: Mutex::new(crate::notes::NotesState::default()),
        })
    }

    pub fn inbox(&self) -> &Inbox {
        &self.inbox
    }

    /// Un aviso por cada cambio, sin detalle: quien escucha vuelve a pedir la
    /// foto. Perder uno no importa, porque la foto siempre esta al dia.
    pub fn subscribe(&self) -> broadcast::Receiver<()> {
        self.events.subscribe()
    }

    /// Lo decide la app (`ai_enabled` en sus ajustes). Apagada, el modelo local
    /// ni se consulta.
    pub fn set_ai_enabled(&self, enabled: bool) {
        self.ai_enabled.store(enabled, Ordering::Relaxed);
        self.wake.notify_one();
    }

    /// Despues de cambiar la configuracion (encender el trabajador, un modelo).
    pub fn poke(&self) {
        self.changed();
        self.wake.notify_one();
    }

    pub(crate) fn changed(&self) {
        let _ = self.events.send(());
    }

    pub(crate) fn set_working(&self, working: bool) {
        self.working.store(working, Ordering::Relaxed);
        self.changed();
    }

    /// Los modelos a los que se puede pedir algo ahora, en orden de preferencia,
    /// y por que falta cada uno de los que no estan. Lo comparten los hallazgos y
    /// los digests de notas.
    pub(crate) async fn model_candidates(
        &self,
        config: &InboxConfig,
    ) -> (Vec<ModelBackend>, Vec<String>) {
        match &self.backends {
            Backends::Fixed(list) => (list.clone(), vec!["no hay ningun modelo".to_string()]),
            Backends::Live => {
                live_candidates(config, self.ai_enabled.load(Ordering::Relaxed)).await
            }
        }
    }

    pub fn snapshot(&self) -> DocsResult<InboxSnapshot> {
        Ok(InboxSnapshot {
            config: self.inbox.config()?,
            findings: self.inbox.findings()?,
            proposals: self.inbox.proposals()?,
            digests: self.inbox.digests()?,
            working: self.working.load(Ordering::Relaxed),
            last_error: self.last_error.lock().ok().and_then(|e| e.clone()),
        })
    }

    pub fn submit(
        &self,
        project: &str,
        from: Option<String>,
        items: Vec<NewFinding>,
        now: Timestamp,
    ) -> DocsResult<SubmitOutcome> {
        let outcome = self.inbox.submit(project, from, items, now)?;
        self.changed();
        self.wake.notify_one();
        Ok(outcome)
    }

    /// El bucle del trabajador. Recupera lo interrumpido y despues procesa un
    /// grupo cada vez; entre vueltas duerme hasta que lo despierten o pasen 30 s.
    pub fn spawn(self: &Arc<Self>) -> tokio::task::JoinHandle<()> {
        let this = Arc::clone(self);
        tokio::spawn(async move {
            if let Err(e) = this.inbox.recover_interrupted() {
                this.remember_error(format!("no se pudo recuperar lo interrumpido: {e}"));
            }
            loop {
                let worked = match this.tick(Timestamp::now()).await {
                    Ok(worked) => worked,
                    // Un fallo del bucle no se traga: queda en la foto, que es
                    // lo que ve el usuario.
                    Err(e) => {
                        this.remember_error(e.to_string());
                        false
                    }
                };
                if !worked {
                    tokio::select! {
                        _ = this.wake.notified() => {}
                        _ = tokio::time::sleep(IDLE_POLL) => {}
                    }
                }
            }
        })
    }

    fn remember_error(&self, error: String) {
        if let Ok(mut last) = self.last_error.lock() {
            *last = Some(error);
        }
        self.changed();
    }

    /// Procesa como mucho un grupo. Devuelve si hizo algo.
    pub async fn tick(&self, now: Timestamp) -> DocsResult<bool> {
        let config = self.inbox.config()?;
        if !config.worker_enabled {
            return Ok(false);
        }
        let _job = self.job.lock().await;

        let findings = self.inbox.findings()?;
        let proposals = self.inbox.proposals()?;
        let Some((project_id, ids)) = ready_group(&findings, &proposals, now) else {
            // Sin hallazgos listos, la vuelta es para las notas.
            return self.tick_notes(&config, now).await;
        };

        let mut batch: Vec<(Finding, u32)> = findings
            .into_iter()
            .filter(|f| ids.contains(&f.id))
            .map(|f| {
                let attempts = match f.status {
                    FindingStatus::WaitingModel { attempts, .. } => attempts,
                    _ => 0,
                };
                (f, attempts)
            })
            .collect();

        let Some(project) = config.project(&project_id).cloned() else {
            for (finding, _) in &mut batch {
                finding.status = FindingStatus::Failed {
                    reason: format!("el proyecto '{project_id}' ya no esta configurado"),
                };
                self.inbox.save_finding(finding)?;
            }
            self.changed();
            return Ok(true);
        };

        for (finding, _) in &mut batch {
            finding.status = FindingStatus::Proposing;
            self.inbox.save_finding(finding)?;
        }
        self.set_working(true);

        let only_findings: Vec<Finding> = batch.iter().map(|(f, _)| f.clone()).collect();
        let proposal_id = new_proposal_id(&project.id, now);
        let result = self
            .generate(&config, &project, &only_findings, None, None, &proposal_id, 1, now)
            .await;
        self.working.store(false, Ordering::Relaxed);

        match result {
            Ok(proposal) => {
                self.inbox.save_proposal(&proposal)?;
                for (finding, _) in &mut batch {
                    finding.status = FindingStatus::Proposed {
                        proposal_id: proposal.id.clone(),
                    };
                    self.inbox.save_finding(finding)?;
                }
            }
            Err(failure) => {
                for (finding, attempts) in &mut batch {
                    finding.status = match &failure {
                        Failure::Retry(reason) => {
                            let delay = RETRY_STEPS_SECS
                                .get(*attempts as usize)
                                .copied()
                                .unwrap_or(RETRY_STEPS_SECS[RETRY_STEPS_SECS.len() - 1]);
                            FindingStatus::WaitingModel {
                                reason: reason.clone(),
                                retry_at: Timestamp::from_second(now.as_second() + delay)
                                    .ok()
                                    .map(|t| t.to_string()),
                                attempts: *attempts + 1,
                            }
                        }
                        Failure::Fatal(reason) => FindingStatus::Failed {
                            reason: reason.clone(),
                        },
                    };
                    self.inbox.save_finding(finding)?;
                }
            }
        }
        self.changed();
        Ok(true)
    }

    #[allow(clippy::too_many_arguments)]
    async fn generate(
        &self,
        config: &InboxConfig,
        project: &DocProject,
        findings: &[Finding],
        previous: Option<&Proposal>,
        note: Option<&str>,
        proposal_id: &str,
        revision: u32,
        now: Timestamp,
    ) -> Result<Proposal, Failure> {
        let (candidates, missing) = self.model_candidates(config).await;
        if candidates.is_empty() {
            return Err(Failure::Retry(format!(
                "sin modelo disponible: {}",
                missing.join("; ")
            )));
        }

        let request = GenerateRequest {
            project,
            findings,
            previous,
            note,
            today: SpanishDate::from_timestamp(now),
            now,
            proposal_id: proposal_id.to_string(),
            revision,
        };

        let mut last = None;
        for backend in &candidates {
            let label = backend.label();
            match generate_proposal(&request, backend, self.cancel.clone()).await {
                Ok(proposal) => return Ok(proposal),
                Err(GenerateError::Model(error)) => {
                    let failure = match error.kind {
                        kind if kind.is_transient() => {
                            Failure::Retry(format!("{label}: {}", error.detail))
                        }
                        ModelErrorKind::Auth => Failure::Fatal(format!(
                            "{label}: la clave no es valida o no tiene permiso ({})",
                            error.detail
                        )),
                        ModelErrorKind::NoCredit => {
                            Failure::Fatal(format!("{label}: la cuenta no tiene saldo"))
                        }
                        _ => {
                            // Un 400 no se arregla cambiando de modelo ni
                            // esperando: el problema es la peticion.
                            return Err(Failure::Fatal(format!("{label}: {}", error.detail)));
                        }
                    };
                    // Pasajero, clave o saldo: el siguiente candidato puede
                    // funcionar.
                    last = Some(failure);
                }
                Err(GenerateError::Invalid(errors)) => {
                    return Err(Failure::Fatal(format!(
                        "{label} no consiguio una propuesta valida en {} intentos: {}",
                        REPAIR_ROUNDS + 1,
                        errors.join("; ")
                    )))
                }
                Err(other) => return Err(Failure::Fatal(other.to_string())),
            }
        }
        Err(last.unwrap_or_else(|| Failure::Retry("sin modelo disponible".to_string())))
    }

    /// Rehace una propuesta pendiente con una nota del usuario, incluyendo lo
    /// que haya llegado a la cola de ese proyecto mientras tanto. Si falla, la
    /// propuesta anterior queda como estaba.
    pub async fn regenerate(
        &self,
        proposal_id: &str,
        note: Option<String>,
        now: Timestamp,
    ) -> DocsResult<Proposal> {
        let _job = self.job.lock().await;
        let old = self.inbox.proposal(proposal_id)?;
        if !old.is_pending() {
            return Err(DocsError::Invalid(
                "solo se puede regenerar una propuesta pendiente".into(),
            ));
        }
        if let crate::model::ProposalOrigin::NoteDigest { digest_id, .. } = &old.origin {
            return self.regenerate_digest(&old, digest_id, note, now).await;
        }
        let config = self.inbox.config()?;
        let project = config.project(&old.project).cloned().ok_or_else(|| {
            DocsError::Invalid(format!("el proyecto '{}' ya no esta configurado", old.project))
        })?;

        let mut ids = old.finding_ids.clone();
        for finding in self.inbox.findings()? {
            let waiting = matches!(
                finding.status,
                FindingStatus::Queued | FindingStatus::WaitingModel { .. }
            );
            if finding.project == old.project && waiting && !ids.contains(&finding.id) {
                ids.push(finding.id);
            }
        }
        let mut batch = ids
            .iter()
            .map(|id| self.inbox.finding(id))
            .collect::<DocsResult<Vec<_>>>()?;

        self.set_working(true);
        let result = self
            .generate(
                &config,
                &project,
                &batch,
                Some(&old),
                note.as_deref(),
                &old.id,
                old.revision + 1,
                now,
            )
            .await;
        self.set_working(false);

        let mut proposal = result.map_err(|f| DocsError::Invalid(f.reason().to_string()))?;
        proposal.created_at = old.created_at.clone();
        self.inbox.save_proposal(&proposal)?;
        for finding in &mut batch {
            finding.status = FindingStatus::Proposed {
                proposal_id: proposal.id.clone(),
            };
            self.inbox.save_finding(finding)?;
        }
        self.changed();
        Ok(proposal)
    }

    /// Al abrir el detalle: si los documentos cambiaron, la propuesta pasa a
    /// `needs_review` o `stale` antes de que el usuario la vea.
    pub async fn check(&self, proposal_id: &str, now: Timestamp) -> DocsResult<Proposal> {
        let _job = self.job.lock().await;
        let mut proposal = self.inbox.proposal(proposal_id)?;
        if !matches!(
            proposal.status,
            ProposalStatus::Ready | ProposalStatus::NeedsReview { .. }
        ) {
            return Ok(proposal);
        }
        let project = self.project_of(&proposal)?;
        if self.revalidate(&mut proposal, &project)?.is_none() {
            proposal.updated_at = now.to_string();
            self.inbox.save_proposal(&proposal)?;
            self.changed();
        }
        Ok(proposal)
    }

    /// `revision` es la que vio el usuario. Si la propuesta cambio desde
    /// entonces, no se aplica: aprobar algo distinto de lo que se reviso es
    /// justo lo que esta pieza existe para impedir.
    pub async fn approve(
        &self,
        proposal_id: &str,
        revision: u32,
        now: Timestamp,
    ) -> DocsResult<ApproveOutcome> {
        let _job = self.job.lock().await;
        let mut proposal = self.inbox.proposal(proposal_id)?;
        if !proposal.is_pending() {
            return Err(DocsError::Invalid("esa propuesta ya no esta pendiente".into()));
        }
        if proposal.revision != revision {
            return Err(DocsError::Invalid(
                "la propuesta cambio desde que la viste; vuelve a revisarla".into(),
            ));
        }
        if matches!(proposal.status, ProposalStatus::Stale { .. }) {
            return Err(DocsError::Invalid(
                "la propuesta ya no aplica sobre los documentos actuales; regenerala".into(),
            ));
        }
        let project = self.project_of(&proposal)?;

        let outcome = match self.revalidate(&mut proposal, &project)? {
            Some(new_bodies) => {
                let originals = self.inbox.originals_dir(&proposal.id)?;
                match apply_to_disk(&project, &new_bodies, &proposal.base_hashes, &originals) {
                    Ok(applied) => {
                        proposal.applied_hashes = applied;
                        proposal.status = ProposalStatus::Applied;
                        self.set_findings(&proposal, |id| FindingStatus::Applied {
                            proposal_id: id.to_string(),
                        })?;
                        self.settle_digest(&proposal)?;
                        None
                    }
                    // Alguien escribio entre revalidar y aplicar.
                    Err(ApplyError::BaseChanged { .. }) => {
                        if self.revalidate(&mut proposal, &project)?.is_some() {
                            proposal.revision += 1;
                            proposal.status = ProposalStatus::NeedsReview {
                                reason: changed_reason(),
                            };
                        }
                        None
                    }
                    Err(ApplyError::Write { detail, rolled_back }) => {
                        let state = if rolled_back {
                            "Los documentos quedaron como estaban."
                        } else {
                            "OJO: no se pudo restaurar todo; revisa los documentos a mano."
                        };
                        Some(DocsError::Invalid(format!("no se pudo escribir: {detail}. {state}")))
                    }
                    Err(ApplyError::Docs(e)) => Some(e),
                }
            }
            None => None,
        };
        if let Some(error) = outcome {
            return Err(error);
        }

        proposal.updated_at = now.to_string();
        self.inbox.save_proposal(&proposal)?;
        self.changed();
        Ok(match proposal.status {
            ProposalStatus::Applied => ApproveOutcome::Applied(proposal),
            ProposalStatus::NeedsReview { .. } => ApproveOutcome::NeedsReview(proposal),
            _ => ApproveOutcome::Stale(proposal),
        })
    }

    pub async fn reject(
        &self,
        proposal_id: &str,
        note: Option<String>,
        now: Timestamp,
    ) -> DocsResult<Proposal> {
        let _job = self.job.lock().await;
        let mut proposal = self.inbox.proposal(proposal_id)?;
        if !proposal.is_pending() {
            return Err(DocsError::Invalid("esa propuesta ya no esta pendiente".into()));
        }
        let note = note.filter(|n| !n.trim().is_empty());
        proposal.status = ProposalStatus::Rejected { note: note.clone() };
        proposal.updated_at = now.to_string();
        self.inbox.save_proposal(&proposal)?;
        self.set_findings(&proposal, |id| FindingStatus::Rejected {
            proposal_id: id.to_string(),
            note: note.clone(),
        })?;
        self.changed();
        self.wake.notify_one();
        Ok(proposal)
    }

    /// Deshace una propuesta aplicada, solo si nadie toco los documentos despues.
    pub async fn undo(&self, proposal_id: &str, now: Timestamp) -> DocsResult<Proposal> {
        let _job = self.job.lock().await;
        let mut proposal = self.inbox.proposal(proposal_id)?;
        if proposal.status != ProposalStatus::Applied {
            return Err(DocsError::Invalid("solo se deshace una propuesta aplicada".into()));
        }
        let project = self.project_of(&proposal)?;
        let originals = self.inbox.originals_dir(&proposal.id)?;
        undo_on_disk(&project, &proposal.applied_hashes, &originals).map_err(|e| match e {
            ApplyError::BaseChanged { files } => DocsError::Invalid(format!(
                "no se deshace: {} cambio despues de aplicar, y deshacer borraria esa edicion",
                files.join(", ")
            )),
            ApplyError::Docs(e) => e,
            other => DocsError::Invalid(other.to_string()),
        })?;

        proposal.status = ProposalStatus::Undone;
        proposal.updated_at = now.to_string();
        self.inbox.save_proposal(&proposal)?;
        self.set_findings(&proposal, |id| FindingStatus::Rejected {
            proposal_id: id.to_string(),
            note: Some("se aplico y despues se deshizo".to_string()),
        })?;
        self.changed();
        Ok(proposal)
    }

    fn project_of(&self, proposal: &Proposal) -> DocsResult<DocProject> {
        self.inbox
            .config()?
            .project(&proposal.project)
            .cloned()
            .ok_or_else(|| {
                DocsError::Invalid(format!(
                    "el proyecto '{}' ya no esta configurado",
                    proposal.project
                ))
            })
    }

    fn set_findings(
        &self,
        proposal: &Proposal,
        status: impl Fn(&str) -> FindingStatus,
    ) -> DocsResult<()> {
        for id in &proposal.finding_ids {
            if let Ok(mut finding) = self.inbox.finding(id) {
                finding.status = status(&proposal.id);
                self.inbox.save_finding(&finding)?;
            }
        }
        Ok(())
    }

    /// Vuelve a validar las operaciones sobre los documentos de ahora.
    ///
    /// `Some(textos finales)` si nada cambio y se puede aplicar. `None` si la
    /// propuesta cambio de estado (`needs_review` o `stale`), con la revision
    /// subida para que la aprobacion anterior ya no valga.
    fn revalidate(
        &self,
        proposal: &mut Proposal,
        project: &DocProject,
    ) -> DocsResult<Option<BTreeMap<String, String>>> {
        let operations: Vec<Operation> = proposal
            .operations
            .iter()
            .map(|o| o.operation.clone())
            .collect();
        let files: BTreeSet<String> = operations.iter().map(|o| normalize_rel(o.file())).collect();
        let snapshots = read_documents(project, files.iter().map(String::as_str))?;
        let bodies: BTreeMap<String, String> = snapshots
            .iter()
            .map(|(path, snap)| (path.clone(), snap.document.body.clone()))
            .collect();

        let findings: Vec<Finding> = proposal
            .finding_ids
            .iter()
            .filter_map(|id| self.inbox.finding(id).ok())
            .collect();
        // La fecha valida es la del dia en que se genero: una propuesta de ayer
        // trae el encabezado de ayer.
        let today = proposal
            .created_at
            .parse::<Timestamp>()
            .map(SpanishDate::from_timestamp)
            .unwrap_or_else(|_| SpanishDate::today());

        let unchanged = snapshots
            .iter()
            .all(|(path, snap)| proposal.base_hashes.get(path) == Some(&snap.hash));
        let validation = validate_operations(
            &operations,
            &ValidationInput {
                project,
                bodies: &bodies,
                visible: None,
                findings: &findings,
                today,
            },
        );

        match (unchanged, validation) {
            (true, Ok(validated)) => Ok(Some(validated.new_bodies)),
            (false, Ok(validated)) => {
                proposal.operations = validated.operations;
                proposal.warnings = validated.warnings;
                for (path, snap) in &snapshots {
                    proposal.base_hashes.insert(path.clone(), snap.hash.clone());
                }
                proposal.revision += 1;
                proposal.status = ProposalStatus::NeedsReview {
                    reason: changed_reason(),
                };
                Ok(None)
            }
            (_, Err(reasons)) => {
                proposal.revision += 1;
                proposal.status = ProposalStatus::Stale { reasons };
                Ok(None)
            }
        }
    }
}

fn changed_reason() -> String {
    "los documentos cambiaron desde la propuesta; las operaciones siguen aplicando, pero revisala otra vez antes de aprobar".to_string()
}

pub(crate) fn new_proposal_id(project: &str, now: Timestamp) -> String {
    let hash = sha256_hex(format!("{project}{}", now.as_nanosecond()).as_bytes());
    format!("p-{}-{}", now.strftime("%Y%m%d-%H%M%S"), &hash[..4])
}

/// El grupo listo mas antiguo: `(proyecto, ids)`.
fn ready_group(
    findings: &[Finding],
    proposals: &[Proposal],
    now: Timestamp,
) -> Option<(String, Vec<String>)> {
    let blocked: HashSet<&str> = proposals
        .iter()
        .filter(|p| p.is_pending())
        .map(|p| p.project.as_str())
        .collect();

    let mut groups: BTreeMap<(&str, Option<&str>), Vec<&Finding>> = BTreeMap::new();
    for finding in findings {
        let eligible = match &finding.status {
            FindingStatus::Queued => true,
            FindingStatus::WaitingModel { retry_at, .. } => retry_at
                .as_deref()
                .and_then(|r| r.parse::<Timestamp>().ok())
                .is_none_or(|at| at <= now),
            _ => false,
        };
        if eligible && !blocked.contains(finding.project.as_str()) {
            groups
                .entry((finding.project.as_str(), finding.from.as_deref()))
                .or_default()
                .push(finding);
        }
    }

    let n = now.as_second();
    groups
        .into_iter()
        .filter_map(|((project, _), list)| {
            let seconds: Vec<i64> = list
                .iter()
                .filter_map(|f| f.created_at.parse::<Timestamp>().ok())
                .map(|t| t.as_second())
                .collect();
            let newest = *seconds.iter().max()?;
            let oldest = *seconds.iter().min()?;
            let retrying = list
                .iter()
                .any(|f| matches!(f.status, FindingStatus::WaitingModel { .. }));
            let ready = retrying || n - newest >= CALM_SECS || n - oldest >= MAX_WAIT_SECS;
            ready.then(|| {
                (
                    oldest,
                    project.to_string(),
                    list.iter().map(|f| f.id.clone()).collect::<Vec<_>>(),
                )
            })
        })
        .min_by_key(|(oldest, _, _)| *oldest)
        .map(|(_, project, ids)| (project, ids))
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::path::PathBuf;

    use super::*;
    use crate::backend::ModelError;
    use crate::config::{DocRole, DocTarget};
    use crate::model::{Evidence, EvidenceLabel, FindingKind};

    const JOURNAL: &str = "# Estado\n\n> Última actualización: **14 de septiembre de 2026**. Entrada.\n\n## 14-sep: algo\n\ntexto viejo\n";

    struct Setup {
        service: Arc<DocsService>,
        repo: PathBuf,
        calls: Arc<Mutex<usize>>,
    }

    fn scripted(label: &str, local: bool, answers: Vec<Result<String, ModelError>>) -> (ModelBackend, Arc<Mutex<usize>>) {
        let queue = Arc::new(Mutex::new(VecDeque::from(answers)));
        let calls = Arc::new(Mutex::new(0));
        let counter = Arc::clone(&calls);
        let backend = ModelBackend::Fake {
            label: label.into(),
            local,
            respond: Arc::new(move |_| {
                *counter.lock().unwrap() += 1;
                queue
                    .lock()
                    .unwrap()
                    .pop_front()
                    .unwrap_or_else(|| Err(ModelError::new(ModelErrorKind::Other, "sin mas respuestas")))
            }),
        };
        (backend, calls)
    }

    fn setup(name: &str, backends: Vec<ModelBackend>, calls: Arc<Mutex<usize>>) -> Setup {
        let repo = crate::test_support::temp_dir(&format!("{name}-repo"));
        std::fs::create_dir_all(repo.join("docs")).unwrap();
        std::fs::write(repo.join("docs/estado.md"), JOURNAL).unwrap();

        let inbox = Inbox::open(crate::test_support::temp_dir(&format!("{name}-inbox"))).unwrap();
        inbox
            .save_config(&InboxConfig {
                worker_enabled: true,
                projects: vec![DocProject {
                    id: "ia".into(),
                    name: "IA".into(),
                    repo_root: repo.to_string_lossy().into_owned(),
                    kind: crate::config::ProjectKind::Docs,
                    conventions: String::new(),
                    documents: vec![DocTarget {
                        path: "docs/estado.md".into(),
                        role: DocRole::Journal,
                        answers: "diario".into(),
                        evidence_labels: true,
                    }],
                }],
                ..InboxConfig::default()
            })
            .unwrap();
        Setup {
            service: DocsService::new(inbox, Backends::Fixed(backends)),
            repo,
            calls,
        }
    }

    fn finding(title: &str) -> NewFinding {
        NewFinding {
            kind: FindingKind::Measurement,
            title: title.into(),
            body: "Q entera paso de 1.652 s a 474 s.".into(),
            evidence: vec![Evidence {
                label: EvidenceLabel::M,
                text: "474 s".into(),
                source: Some("odm_tandaq.log".into()),
            }],
            supersedes: None,
            date: None,
            target_hint: None,
        }
    }

    fn good_answer(now: Timestamp) -> String {
        let today = SpanishDate::from_timestamp(now);
        serde_json::json!({
            "summary": "seccion nueva con la medida",
            "operations": [
                {
                    "op": "insert_section_top",
                    "file": "docs/estado.md",
                    "heading": format!("## {}: la deteccion es 3,5 veces mas rapida", today.short()),
                    "body": "Q entera paso de 1.652 s a 474 s [M]."
                },
                { "op": "set_last_updated", "file": "docs/estado.md", "date": today.long() }
            ]
        })
        .to_string()
    }

    fn later(now: Timestamp, seconds: i64) -> Timestamp {
        Timestamp::from_second(now.as_second() + seconds).unwrap()
    }

    fn journal(setup: &Setup) -> String {
        std::fs::read_to_string(setup.repo.join("docs/estado.md")).unwrap()
    }

    #[tokio::test]
    async fn waits_for_calm_then_proposes_and_approval_writes_the_journal() {
        let now = Timestamp::now();
        let (backend, calls) = scripted("remoto", false, vec![Ok(good_answer(later(now, 100)))]);
        let s = setup("happy", vec![backend], calls);
        let out = s.service.submit("ia", Some("NexoDeck en main".into()), vec![finding("uno")], now).unwrap();

        assert!(!s.service.tick(later(now, 10)).await.unwrap(), "sin calma no se procesa");
        assert!(s.service.tick(later(now, 100)).await.unwrap());

        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();
        assert_eq!(proposal.status, ProposalStatus::Ready);
        assert!(!proposal.local_model);
        assert_eq!(
            s.service.inbox().finding(&out.ids[0]).unwrap().status,
            FindingStatus::Proposed { proposal_id: proposal.id.clone() }
        );
        assert_eq!(journal(&s), JOURNAL, "proponer no escribe nada");

        let outcome = s.service.approve(&proposal.id, proposal.revision, later(now, 200)).await.unwrap();
        assert!(matches!(outcome, ApproveOutcome::Applied(_)));
        let text = journal(&s);
        assert!(text.contains("la deteccion es 3,5 veces mas rapida"));
        assert!(text.find("3,5 veces").unwrap() < text.find("## 14-sep").unwrap());
        assert!(matches!(
            s.service.inbox().finding(&out.ids[0]).unwrap().status,
            FindingStatus::Applied { .. }
        ));
        assert_eq!(*s.calls.lock().unwrap(), 1);
    }

    #[tokio::test]
    async fn an_invalid_answer_is_sent_back_and_repaired() {
        let now = Timestamp::now();
        let (backend, calls) = scripted(
            "remoto",
            false,
            vec![Ok("no es json".into()), Ok(good_answer(later(now, 100)))],
        );
        let s = setup("repair", vec![backend], calls);
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();

        assert_eq!(*s.calls.lock().unwrap(), 2);
        assert_eq!(s.service.inbox().proposals().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn a_network_failure_without_fallback_waits_and_retries_later() {
        let now = Timestamp::now();
        let (backend, calls) = scripted(
            "remoto",
            false,
            vec![Err(ModelError::new(ModelErrorKind::Network, "sin red"))],
        );
        let s = setup("retry", vec![backend], calls);
        let out = s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();

        let status = s.service.inbox().finding(&out.ids[0]).unwrap().status;
        assert!(matches!(status, FindingStatus::WaitingModel { attempts: 1, .. }), "{status:?}");
        assert!(!s.service.tick(later(now, 200)).await.unwrap(), "no reintenta antes de tiempo");
    }

    #[tokio::test]
    async fn the_local_model_takes_over_when_the_remote_is_down_and_is_labelled() {
        let now = Timestamp::now();
        let (remote, _) = scripted(
            "remoto",
            false,
            vec![Err(ModelError::new(ModelErrorKind::Server, "503"))],
        );
        let (local, calls) = scripted("qwen local", true, vec![Ok(good_answer(later(now, 100)))]);
        let s = setup("fallback", vec![remote, local], calls);
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();

        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();
        assert!(proposal.local_model);
        assert_eq!(proposal.model_label, "qwen local");
    }

    #[tokio::test]
    async fn a_bad_key_fails_without_retrying() {
        let now = Timestamp::now();
        let (backend, calls) = scripted(
            "remoto",
            false,
            vec![Err(ModelError::new(ModelErrorKind::Auth, "401"))],
        );
        let s = setup("auth", vec![backend], calls);
        let out = s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();
        let status = s.service.inbox().finding(&out.ids[0]).unwrap().status;
        assert!(matches!(status, FindingStatus::Failed { ref reason } if reason.contains("clave")), "{status:?}");
    }

    #[tokio::test]
    async fn an_edit_elsewhere_needs_review_and_the_old_revision_cannot_be_approved() {
        let now = Timestamp::now();
        let (backend, calls) = scripted("remoto", false, vec![Ok(good_answer(later(now, 100)))]);
        let s = setup("review", vec![backend], calls);
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();
        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();

        std::fs::write(s.repo.join("docs/estado.md"), JOURNAL.replace("texto viejo", "texto editado a mano")).unwrap();

        let outcome = s.service.approve(&proposal.id, proposal.revision, later(now, 150)).await.unwrap();
        let ApproveOutcome::NeedsReview(reviewed) = outcome else { panic!("{outcome:?}") };
        assert_eq!(reviewed.revision, proposal.revision + 1);
        assert!(journal(&s).contains("texto editado a mano") && !journal(&s).contains("3,5 veces"));

        assert!(s.service.approve(&proposal.id, proposal.revision, later(now, 160)).await.is_err());
        let applied = s.service.approve(&proposal.id, reviewed.revision, later(now, 170)).await.unwrap();
        assert!(matches!(applied, ApproveOutcome::Applied(_)));
        let text = journal(&s);
        assert!(text.contains("3,5 veces") && text.contains("texto editado a mano"));
    }

    #[tokio::test]
    async fn an_edit_that_removes_the_anchor_makes_it_stale() {
        let now = Timestamp::now();
        let (backend, calls) = scripted("remoto", false, vec![Ok(good_answer(later(now, 100)))]);
        let s = setup("stale", vec![backend], calls);
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();
        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();

        // Sin la linea de actualizacion, set_last_updated ya no tiene donde ir.
        std::fs::write(s.repo.join("docs/estado.md"), "# Estado\n\n## 14-sep: algo\n").unwrap();
        let checked = s.service.check(&proposal.id, later(now, 150)).await.unwrap();
        assert!(matches!(checked.status, ProposalStatus::Stale { .. }), "{:?}", checked.status);
    }

    #[tokio::test]
    async fn a_pending_proposal_holds_back_new_findings_of_the_same_project() {
        let now = Timestamp::now();
        let (backend, calls) = scripted(
            "remoto",
            false,
            vec![Ok(good_answer(later(now, 100))), Ok(good_answer(later(now, 400)))],
        );
        let s = setup("pending", vec![backend], calls);
        s.service.submit("ia", Some("a".into()), vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();

        s.service.submit("ia", Some("b".into()), vec![finding("dos")], later(now, 150)).unwrap();
        assert!(!s.service.tick(later(now, 400)).await.unwrap(), "espera a que se decida la primera");

        let first = s.service.inbox().proposals().unwrap().pop().unwrap();
        s.service.reject(&first.id, Some("no".into()), later(now, 410)).await.unwrap();
        assert!(s.service.tick(later(now, 400)).await.unwrap());
    }

    #[tokio::test]
    async fn undo_restores_the_journal() {
        let now = Timestamp::now();
        let (backend, calls) = scripted("remoto", false, vec![Ok(good_answer(later(now, 100)))]);
        let s = setup("undo", vec![backend], calls);
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        s.service.tick(later(now, 100)).await.unwrap();
        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();
        s.service.approve(&proposal.id, proposal.revision, later(now, 200)).await.unwrap();

        s.service.undo(&proposal.id, later(now, 300)).await.unwrap();
        assert_eq!(journal(&s), JOURNAL);
        assert_eq!(
            s.service.inbox().proposal(&proposal.id).unwrap().status,
            ProposalStatus::Undone
        );
    }

    #[tokio::test]
    async fn a_disabled_worker_does_nothing() {
        let now = Timestamp::now();
        let (backend, calls) = scripted("remoto", false, vec![Ok(good_answer(now))]);
        let s = setup("disabled", vec![backend], calls);
        let mut config = s.service.inbox().config().unwrap();
        config.worker_enabled = false;
        s.service.inbox().save_config(&config).unwrap();
        s.service.submit("ia", None, vec![finding("uno")], now).unwrap();
        assert!(!s.service.tick(later(now, 1_000)).await.unwrap());
        assert_eq!(*s.calls.lock().unwrap(), 0);
    }
}
