//! El asistente de notas dentro del trabajador del buzon.
//!
//! Comparte todo lo que ya tenia el buzon: la cola (un trabajo de modelo a la
//! vez), los candidatos de modelo (remoto primero, local solo si ya esta
//! levantado), la escalera de reintentos y la aprobacion con revision. Lo unico
//! propio es de donde sale el trabajo: una nota que el usuario manda procesar, o
//! que lleva un rato sin cambios si `digest_on_idle` esta encendido.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};

use jiff::Timestamp;

use crate::backend::ModelErrorKind;
use crate::config::{normalize_rel, DocProject, DocRole, InboxConfig};
use crate::dates::SpanishDate;
use crate::error::{DocsError, DocsResult};
use crate::generate::GenerateError;
use crate::markdown::Document;
use crate::model::{Proposal, ProposalOrigin};
use crate::notes::digest::{Blackboard, Digest, DigestStatus, DigestTrigger};
use crate::notes::git::{recent_commits, CommitInfo};
use crate::notes::index::{Candidate, IndexedNote, NotesIndex};
use crate::notes::orchestrator::{run_note_digest, DigestOutcome, DigestRequest, MIN_NOTE_CHARS};
use crate::notes::parse::NoteTask;
use crate::notes::roots::{locate, NoteRoot};
use crate::service::{new_proposal_id, DocsService, RETRY_STEPS_SECS};
use crate::store::sha256_hex;

/// Cada cuanto se vuelven a leer los commits. `git log` en varios repositorios
/// no es gratis, y un commit de hace diez minutos no cambia ningun digest.
const COMMITS_EVERY: Duration = Duration::from_secs(600);
const COMMIT_DAYS: u32 = 120;
const COMMITS_PER_REPO: usize = 300;
/// Una nota se procesa sola cuando lleva esto sin cambios...
const IDLE_AFTER: Duration = Duration::from_secs(300);
/// ...y solo si se toco hace menos de esto. Sin este tope, encender el modo
/// automatico procesaria la boveda entera de golpe.
const IDLE_WINDOW: Duration = Duration::from_secs(24 * 3600);
/// Como mucho estas notas se encolan solas por vuelta.
const IDLE_PER_TICK: usize = 3;
const SEARCH_LIMIT_MAX: usize = 50;

#[derive(Default)]
pub struct NotesState {
    index: Option<Arc<NotesIndex>>,
    /// Las carpetas con las que se construyo el indice. Si cambian (se añade o
    /// se quita una carpeta local), el indice se tira y se rehace.
    roots: Vec<(String, PathBuf)>,
    commits_at: Option<Instant>,
    /// Un repositorio que no se pudo leer. No impide nada, pero se enseña.
    commits_error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteSummary {
    pub path: String,
    /// La agrupacion a la que pertenece: **su carpeta**. `None` si esta suelta
    /// o en `inbox/`. Se deriva de `path`, no se guarda aparte.
    pub group: Option<String>,
    pub title: String,
    pub role: DocRole,
    pub date: Option<String>,
    pub tags: Vec<String>,
    pub open_tasks: usize,
    pub ai_excluded: bool,
    /// RFC 3339.
    pub modified: Option<String>,
}

#[derive(Debug, Clone)]
pub struct OpenTask {
    pub path: String,
    pub task: NoteTask,
}

#[derive(Debug, Clone, Default)]
pub struct NotesOverview {
    /// `None` si no hay boveda configurada.
    pub vault_project: Option<String>,
    pub root: Option<String>,
    pub digest_on_idle: bool,
    /// De la tocada mas recientemente a la mas vieja.
    pub notes: Vec<NoteSummary>,
    /// Las carpetas de notas: la principal primero y despues las locales.
    pub folders: Vec<super::roots::NoteFolderView>,
    /// Las agrupaciones: las carpetas de la boveda con lo que diga el catalogo.
    /// Van en la misma foto que las notas, sacadas del mismo indice, para que
    /// la lista de grupos y la de notas no puedan discrepar.
    pub groups: Vec<super::groups::NoteGroupView>,
    pub open_tasks: Vec<OpenTask>,
    pub commits: usize,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteDetails {
    pub summary: NoteSummary,
    /// La ruta real del fichero en disco. Para abrirla por fuera (Obsidian, el
    /// explorador): con una ruta virtual `@id/...` no se puede componer.
    pub real_path: String,
    pub text: String,
    pub backlinks: Vec<String>,
    /// Vacio en una nota con `ai: false`: relacionarla ya es leerla.
    pub related: Vec<Candidate>,
    pub tasks: Vec<NoteTask>,
    pub digests: Vec<Digest>,
}

enum RunFailure {
    Retry(String),
    Fatal(String),
}

impl RunFailure {
    fn reason(&self) -> &str {
        match self {
            RunFailure::Retry(reason) | RunFailure::Fatal(reason) => reason,
        }
    }
}

impl DocsService {
    /// Manda procesar una nota. Si ya hay un digest en marcha para esa nota,
    /// devuelve ese: pulsar dos veces no gasta el doble.
    pub fn digest_note(&self, note: &str, trigger: DigestTrigger, now: Timestamp) -> DocsResult<Digest> {
        let config = self.inbox.config()?;
        let roots = config.note_roots();
        if roots.is_empty() {
            return Err(no_vault());
        }
        // `note` es la ruta virtual (la que ve el usuario y guarda el digest);
        // `inner`, la de dentro de su carpeta, que es la que entiende su proyecto.
        let note = normalize_rel(note);
        let (root, inner) = locate(&roots, &note).ok_or_else(|| unknown_folder(&note))?;
        let project = &root.project;
        if project.document(&inner).is_none() {
            return Err(DocsError::Invalid(format!(
                "'{note}' no es una nota que se pueda procesar: es privada, esta en una carpeta oculta, no es un .md o se sale de la boveda"
            )));
        }
        project.resolve(&inner)?;
        if let Some(active) = self
            .inbox
            .digests()?
            .into_iter()
            .rev()
            .find(|d| d.note == note && d.is_active())
        {
            return Ok(active);
        }
        let digest = self.save_new_digest(project, &note, trigger, now)?;
        self.changed();
        self.wake.notify_one();
        Ok(digest)
    }

    /// Una vuelta del trabajador para las notas: pone el indice al dia, encola
    /// lo que toque en modo automatico y procesa como mucho un digest. Se llama
    /// con el cerrojo de trabajo ya tomado.
    pub(crate) async fn tick_notes(&self, config: &InboxConfig, now: Timestamp) -> DocsResult<bool> {
        let Some((notes, _)) = config.vault() else {
            return Ok(false);
        };
        let roots = config.note_roots();
        let Some(index) = self.notes_index(config)? else {
            return Ok(false);
        };
        let mut digests = self.inbox.digests()?;
        if notes.digest_on_idle && self.enqueue_idle(&roots, &index, &digests, now)? > 0 {
            digests = self.inbox.digests()?;
            self.changed();
        }

        let proposals = self.inbox.proposals()?;
        let Some(mut digest) = next_digest(digests, &proposals, &roots, now) else {
            return Ok(false);
        };
        // El digest se procesa con el proyecto de **su** carpeta: la propuesta que
        // salga se valida y se aprueba contra esa raiz, no contra la principal.
        let Some((root, inner)) = locate(&roots, &digest.note) else {
            return Ok(false);
        };
        let project = root.project.clone();
        let attempts = match digest.status {
            DigestStatus::WaitingModel { attempts, .. } => attempts,
            _ => 0,
        };
        digest.status = DigestStatus::Running;
        digest.updated_at = now.to_string();
        self.inbox.save_digest(&digest)?;
        self.set_working(true);

        let proposal_id = new_proposal_id(&project.id, now);
        let result = self
            .run_digest(config, &project, &index, &digest, None, None, proposal_id, 1, now)
            .await;
        self.set_working(false);

        match result {
            Ok((outcome, trace)) => {
                digest.trace = trace;
                match outcome {
                    DigestOutcome::Proposal(proposal) => {
                        self.inbox.save_proposal(&proposal)?;
                        // La propuesta guarda los hashes con la ruta de dentro de
                        // su carpeta, no con la virtual.
                        digest.note_hash = proposal.base_hashes.get(&inner).cloned();
                        digest.status = DigestStatus::Proposed {
                            proposal_id: proposal.id.clone(),
                        };
                    }
                    DigestOutcome::Skipped(reason) => {
                        digest.status = DigestStatus::Skipped { reason };
                    }
                }
            }
            Err((failure, trace)) => {
                if let Some(trace) = trace {
                    digest.trace = *trace;
                }
                digest.status = match failure {
                    RunFailure::Retry(reason) => DigestStatus::WaitingModel {
                        reason,
                        retry_at: retry_at(now, attempts),
                        attempts: attempts + 1,
                    },
                    RunFailure::Fatal(reason) => DigestStatus::Failed { reason },
                };
            }
        }
        digest.updated_at = now.to_string();
        self.inbox.save_digest(&digest)?;
        self.changed();
        Ok(true)
    }

    /// Rehace la propuesta de un digest con la nota del usuario. Se llama desde
    /// `regenerate`, con el cerrojo de trabajo ya tomado. Si falla, la propuesta
    /// anterior queda como estaba.
    pub(crate) async fn regenerate_digest(
        &self,
        old: &Proposal,
        digest_id: &str,
        user_note: Option<String>,
        now: Timestamp,
    ) -> DocsResult<Proposal> {
        let config = self.inbox.config()?;
        let project = config.project(&old.project).cloned().ok_or_else(|| {
            DocsError::Invalid(format!("el proyecto '{}' ya no esta configurado", old.project))
        })?;
        let index = self.notes_index(&config)?.ok_or_else(no_vault)?;
        let mut digest = self.inbox.digest(digest_id)?;

        self.set_working(true);
        let result = self
            .run_digest(
                &config,
                &project,
                &index,
                &digest,
                Some(old),
                user_note.as_deref(),
                old.id.clone(),
                old.revision + 1,
                now,
            )
            .await;
        self.set_working(false);

        match result {
            Ok((DigestOutcome::Proposal(proposal), trace)) => {
                let mut proposal = *proposal;
                proposal.created_at = old.created_at.clone();
                self.inbox.save_proposal(&proposal)?;
                digest.trace = trace;
                digest.note_hash = proposal
                    .base_hashes
                    .get(&note_rel(&config, &digest.note))
                    .cloned();
                digest.status = DigestStatus::Proposed {
                    proposal_id: proposal.id.clone(),
                };
                digest.updated_at = now.to_string();
                self.inbox.save_digest(&digest)?;
                self.changed();
                Ok(proposal)
            }
            Ok((DigestOutcome::Skipped(reason), _)) => Err(DocsError::Invalid(reason)),
            Err((failure, _)) => Err(DocsError::Invalid(failure.reason().to_string())),
        }
    }

    /// Tras aplicar la propuesta de un digest: se apunta como queda la nota, para
    /// que el modo automatico no la vuelva a procesar por el cambio que acaba de
    /// aprobar el propio usuario.
    pub(crate) fn settle_digest(&self, proposal: &Proposal) -> DocsResult<()> {
        let ProposalOrigin::NoteDigest { note, digest_id } = &proposal.origin else {
            return Ok(());
        };
        let Ok(mut digest) = self.inbox.digest(digest_id) else {
            return Ok(());
        };
        let config = self.inbox.config()?;
        digest.settled_hash = proposal.applied_hashes.get(&note_rel(&config, note)).cloned();
        self.inbox.save_digest(&digest)
    }

    /// Lo que la app enseña de la boveda: notas, tareas abiertas y si hay algo
    /// roto. Nunca falla por la boveda: el error va dentro.
    pub fn notes_overview(&self) -> DocsResult<NotesOverview> {
        let config = self.inbox.config()?;
        let mut overview = NotesOverview::default();
        let Some((notes, project)) = config.vault() else {
            return Ok(overview);
        };
        overview.vault_project = Some(notes.vault_project.clone());
        overview.root = Some(project.repo_root.clone());
        overview.digest_on_idle = notes.digest_on_idle;
        // Van aunque falle el indice: la interfaz tiene que poder enseñar que
        // carpetas hay configuradas y cual no esta disponible.
        overview.folders = config.note_roots().iter().map(NoteRoot::view).collect();
        // Sin indice todavia (o si falla) las agrupaciones del catalogo se ven
        // igual: una recien creada esta vacia y aun asi tiene que aparecer.
        overview.groups = super::groups::list_groups(std::iter::empty(), &notes.groups);

        match self.notes_index(&config) {
            Ok(Some(index)) => {
                // Las de todas las carpetas: las de una carpeta local llevan su
                // prefijo (`groups::virtual_group_of`), asi que no se mezclan.
                overview.groups = super::groups::list_groups(
                    index.notes().map(|note| note.path.as_str()),
                    &notes.groups,
                );
                let mut list: Vec<NoteSummary> = index.notes().map(summary).collect();
                list.sort_by(|a, b| b.modified.cmp(&a.modified).then(a.path.cmp(&b.path)));
                overview.notes = list;
                overview.open_tasks = index
                    .open_tasks()
                    .into_iter()
                    .map(|(path, task)| OpenTask { path, task })
                    .collect();
                overview.commits = index.commits().len();
                overview.error = self.lock_notes().commits_error.clone();
            }
            Ok(None) => {}
            Err(error) => overview.error = Some(error.to_string()),
        }
        Ok(overview)
    }

    /// Busqueda en notas, hallazgos y commits. Nunca devuelve una nota con
    /// `ai: false`.
    pub fn search_notes(&self, query: &str, limit: usize) -> DocsResult<Vec<Candidate>> {
        let config = self.inbox.config()?;
        let index = self.notes_index(&config)?.ok_or_else(no_vault)?;
        Ok(index.search(query, &[], limit.clamp(1, SEARCH_LIMIT_MAX), None))
    }

    /// Una nota con su texto, lo que enlaza a ella, lo que se le parece y sus
    /// digests.
    pub fn note_details(&self, path: &str) -> DocsResult<NoteDetails> {
        let config = self.inbox.config()?;
        let roots = config.note_roots();
        let index = self.notes_index(&config)?.ok_or_else(no_vault)?;
        let rel = normalize_rel(path);
        let entry = index
            .note(&rel)
            .ok_or_else(|| DocsError::NotFound(format!("la nota '{rel}' en la boveda")))?;
        let (root, inner) = locate(&roots, &rel).ok_or_else(|| unknown_folder(&rel))?;
        let full = root.project.resolve(&inner)?;
        let raw = std::fs::read(&full).map_err(|e| DocsError::io(&full, e))?;
        let text = Document::parse(&raw)
            .map_err(|e| DocsError::Invalid(format!("{rel}: {e}")))?
            .body;
        Ok(NoteDetails {
            real_path: full.to_string_lossy().into_owned(),
            summary: summary(entry),
            text,
            backlinks: index.backlinks(&rel),
            related: if entry.note.ai_excluded {
                Vec::new()
            } else {
                index.related(&rel, 8)
            },
            tasks: entry.note.tasks.clone(),
            digests: self
                .inbox
                .digests()?
                .into_iter()
                .filter(|d| d.note == rel)
                .collect(),
        })
    }

    /// El indice de la boveda, al dia. `None` si no hay boveda configurada.
    ///
    /// Se devuelve un `Arc` con una foto: quien lo usa durante un digest no
    /// bloquea a quien refresca, porque refrescar sobre una foto compartida la
    /// copia (`Arc::make_mut`).
    pub(crate) fn notes_index(&self, config: &InboxConfig) -> DocsResult<Option<Arc<NotesIndex>>> {
        let Some((notes, _)) = config.vault() else {
            return Ok(None);
        };
        let findings = self.inbox.findings()?;
        let roots: Vec<(String, PathBuf)> = config
            .note_roots()
            .into_iter()
            .map(|root| (root.prefix, PathBuf::from(root.project.repo_root)))
            .collect();

        let mut guard = self.lock_notes();
        let state = &mut *guard;
        if state.roots != roots {
            *state = NotesState {
                roots: roots.clone(),
                ..NotesState::default()
            };
        }
        let due = state
            .commits_at
            .is_none_or(|at| at.elapsed() >= COMMITS_EVERY);
        let index = Arc::make_mut(
            state
                .index
                .get_or_insert_with(|| Arc::new(NotesIndex::with_roots(roots))),
        );
        index.refresh()?;
        index.set_findings(findings);
        if due {
            let (commits, errors) = collect_commits(&notes.repos);
            index.set_commits(commits);
            state.commits_error = errors.into_iter().next();
            state.commits_at = Some(Instant::now());
        }
        Ok(state.index.clone())
    }

    fn lock_notes(&self) -> std::sync::MutexGuard<'_, NotesState> {
        self.notes.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn save_new_digest(
        &self,
        project: &DocProject,
        rel: &str,
        trigger: DigestTrigger,
        now: Timestamp,
    ) -> DocsResult<Digest> {
        let hash = sha256_hex(format!("{rel}{}", now.as_nanosecond()).as_bytes());
        let digest = Digest {
            id: format!("d-{}-{}", now.strftime("%Y%m%d-%H%M%S"), &hash[..4]),
            project: project.id.clone(),
            note: rel.to_string(),
            trigger,
            created_at: now.to_string(),
            updated_at: now.to_string(),
            status: DigestStatus::Queued,
            note_hash: None,
            settled_hash: None,
            trace: Blackboard::default(),
        };
        self.inbox.save_digest(&digest)?;
        Ok(digest)
    }

    /// Notas tocadas hoy que llevan un rato quietas y cambiaron desde su ultimo
    /// digest. Devuelve cuantas encolo.
    fn enqueue_idle(
        &self,
        roots: &[NoteRoot],
        index: &NotesIndex,
        digests: &[Digest],
        now: Timestamp,
    ) -> DocsResult<usize> {
        let wall = SystemTime::now();
        let mut queued = 0;
        for note in index.notes() {
            if queued >= IDLE_PER_TICK {
                break;
            }
            // La nota de proyecto la actualizan los digests: procesarla sola
            // seria un digest sobre lo que escribio otro digest.
            if note.note.ai_excluded || note.role == DocRole::Hub {
                continue;
            }
            let Some(modified) = note.modified() else { continue };
            let Ok(age) = wall.duration_since(modified) else { continue };
            if age < IDLE_AFTER || age > IDLE_WINDOW {
                continue;
            }
            let content: usize = note
                .note
                .sections
                .iter()
                .map(|s| s.text.trim().chars().count())
                .sum();
            if content < MIN_NOTE_CHARS {
                continue;
            }
            let last = digests.iter().rev().find(|d| d.note == note.path);
            if last.is_some_and(Digest::is_active) {
                continue;
            }
            if let (Some(last), Ok(modified)) = (last, Timestamp::try_from(modified)) {
                if last
                    .created_at
                    .parse::<Timestamp>()
                    .is_ok_and(|created| modified <= created)
                {
                    continue;
                }
            }
            let Some((root, inner)) = locate(roots, &note.path) else { continue };
            let Ok(full) = root.project.resolve(&inner) else { continue };
            let Ok(raw) = std::fs::read(&full) else { continue };
            let hash = sha256_hex(&raw);
            // Sin cambios desde el digest, o desde que se aplico su propuesta.
            if last.is_some_and(|d| {
                d.note_hash.as_deref() == Some(hash.as_str())
                    || d.settled_hash.as_deref() == Some(hash.as_str())
            }) {
                continue;
            }
            self.save_new_digest(&root.project, &note.path, DigestTrigger::Idle, now)?;
            queued += 1;
        }
        Ok(queued)
    }

    /// El digest con cada modelo candidato, en orden, igual que el buzon con los
    /// hallazgos: lo que el siguiente candidato puede arreglar (red, limite,
    /// clave, saldo) pasa al siguiente; lo demas falla en el acto.
    #[allow(clippy::too_many_arguments)]
    async fn run_digest(
        &self,
        config: &InboxConfig,
        project: &DocProject,
        index: &NotesIndex,
        digest: &Digest,
        previous: Option<&Proposal>,
        user_note: Option<&str>,
        proposal_id: String,
        revision: u32,
        now: Timestamp,
    ) -> Result<(DigestOutcome, Blackboard), (RunFailure, Option<Box<Blackboard>>)> {
        let (candidates, missing) = self.model_candidates(config).await;
        if candidates.is_empty() {
            return Err((
                RunFailure::Retry(format!("sin modelo disponible: {}", missing.join("; "))),
                None,
            ));
        }

        let mut last: Option<(RunFailure, Blackboard)> = None;
        for backend in &candidates {
            let label = backend.label().to_string();
            let run = run_note_digest(
                &DigestRequest {
                    project,
                    note: &digest.note,
                    index,
                    today: SpanishDate::from_timestamp(now),
                    now,
                    digest_id: &digest.id,
                    proposal_id: proposal_id.clone(),
                    revision,
                    previous,
                    user_note,
                },
                backend,
                Arc::clone(&self.cancel),
            )
            .await;
            match run.outcome {
                Ok(outcome) => return Ok((outcome, run.trace)),
                Err(GenerateError::Model(error)) => {
                    let failure = match error.kind {
                        kind if kind.is_transient() => {
                            RunFailure::Retry(format!("{label}: {}", error.detail))
                        }
                        ModelErrorKind::Auth => RunFailure::Fatal(format!(
                            "{label}: la clave no es valida o no tiene permiso ({})",
                            error.detail
                        )),
                        ModelErrorKind::NoCredit => {
                            RunFailure::Fatal(format!("{label}: la cuenta no tiene saldo"))
                        }
                        _ => {
                            return Err((
                                RunFailure::Fatal(format!("{label}: {}", error.detail)),
                                Some(Box::new(run.trace)),
                            ))
                        }
                    };
                    last = Some((failure, run.trace));
                }
                Err(other) => {
                    return Err((
                        RunFailure::Fatal(format!("{label}: {other}")),
                        Some(Box::new(run.trace)),
                    ))
                }
            }
        }
        match last {
            Some((failure, trace)) => Err((failure, Some(Box::new(trace)))),
            None => Err((RunFailure::Retry("sin modelo disponible".to_string()), None)),
        }
    }
}

/// El digest listo mas antiguo. Una nota con una propuesta pendiente espera: con
/// dos propuestas sobre la misma nota, aprobar la primera dejaria la segunda
/// sin poder aplicarse.
///
/// Con varias carpetas, "la misma nota" es **(proyecto, ruta dentro)**: las
/// propuestas guardan los hashes con la ruta de dentro de su carpeta, y dos
/// carpetas pueden tener una `temas/x.md` cada una. Un digest cuya carpeta ya no
/// esta configurada no se elige: fallaria al leer la nota.
fn next_digest(
    digests: Vec<Digest>,
    proposals: &[Proposal],
    roots: &[NoteRoot],
    now: Timestamp,
) -> Option<Digest> {
    let busy: HashSet<(&str, &str)> = proposals
        .iter()
        .filter(|p| p.is_pending())
        .flat_map(|p| p.base_hashes.keys().map(move |file| (p.project.as_str(), file.as_str())))
        .collect();
    digests.into_iter().find(|d| {
        let ready = match &d.status {
            DigestStatus::Queued => true,
            DigestStatus::WaitingModel { retry_at, .. } => retry_at
                .as_deref()
                .and_then(|r| r.parse::<Timestamp>().ok())
                .is_none_or(|at| at <= now),
            _ => false,
        };
        ready
            && locate(roots, &d.note)
                .is_some_and(|(root, inner)| !busy.contains(&(root.id(), inner.as_str())))
    })
}

/// La ruta de una nota dentro de su carpeta, que es como la guardan las
/// propuestas (`base_hashes`, `applied_hashes`). Si su carpeta ya no esta
/// configurada, la ruta tal cual.
fn note_rel(config: &InboxConfig, note: &str) -> String {
    locate(&config.note_roots(), note)
        .map(|(_, inner)| inner)
        .unwrap_or_else(|| note.to_string())
}

fn retry_at(now: Timestamp, attempts: u32) -> Option<String> {
    let delay = RETRY_STEPS_SECS
        .get(attempts as usize)
        .copied()
        .unwrap_or(RETRY_STEPS_SECS[RETRY_STEPS_SECS.len() - 1]);
    Timestamp::from_second(now.as_second() + delay)
        .ok()
        .map(|t| t.to_string())
}

fn collect_commits(repos: &[String]) -> (Vec<CommitInfo>, Vec<String>) {
    let mut commits = Vec::new();
    let mut errors = Vec::new();
    for repo in repos {
        match recent_commits(std::path::Path::new(repo), COMMIT_DAYS, COMMITS_PER_REPO) {
            Ok(found) => commits.extend(found),
            Err(error) => errors.push(error),
        }
    }
    (commits, errors)
}

fn summary(entry: &IndexedNote) -> NoteSummary {
    NoteSummary {
        // La agrupacion no se guarda en ningun sitio: **es** la carpeta, asi
        // que se deriva de la ruta y nunca puede discrepar de lo que hay en
        // disco (ver `notes/groups.rs`).
        // Con su prefijo si es de una carpeta local: su `clientes/` y el de la
        // principal son agrupaciones distintas.
        group: super::groups::virtual_group_of(&entry.path),
        path: entry.path.clone(),
        title: entry.note.title.clone(),
        role: entry.role,
        date: entry.note.date.clone(),
        tags: entry.note.tags.clone(),
        open_tasks: entry.note.tasks.iter().filter(|t| !t.done).count(),
        ai_excluded: entry.note.ai_excluded,
        modified: entry
            .modified()
            .and_then(|m| Timestamp::try_from(m).ok())
            .map(|t| t.to_string()),
    }
}

fn unknown_folder(path: &str) -> DocsError {
    DocsError::Invalid(format!(
        "'{path}' nombra una carpeta de notas que no esta configurada"
    ))
}

fn no_vault() -> DocsError {
    DocsError::Invalid(
        "no hay ninguna boveda configurada para el asistente de notas (\"notes\" en la configuracion del buzon)"
            .to_string(),
    )
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::sync::Mutex;

    use nexodeck_ai::openai::types::ChatMessage;
    use serde_json::json;

    use super::*;
    use crate::backend::ModelBackend;
    use crate::config::{NotesConfig, ProjectKind};
    use crate::service::{ApproveOutcome, Backends};
    use crate::store::Inbox;

    const NOTE: &str = "# Reunion\n\nLa ortofoto de la tanda R sale deformada con la malla 2.5D y hay que decidir que hacer.\n";

    struct Setup {
        service: Arc<DocsService>,
        root: PathBuf,
        prompts: Arc<Mutex<Vec<String>>>,
    }

    fn write(root: &Path, rel: &str, text: &str) {
        let path = root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    /// Contesta por agente. El redactor propone un resumen sobre el primer
    /// fichero que se le enseña, que es la nota.
    fn backend(prompts: Arc<Mutex<Vec<String>>>) -> ModelBackend {
        ModelBackend::Fake {
            label: "falso".into(),
            local: false,
            respond: Arc::new(move |messages: &[ChatMessage]| {
                let system = match &messages[0] {
                    ChatMessage::System { content } => content.clone(),
                    _ => String::new(),
                };
                let user = messages
                    .iter()
                    .filter_map(|m| match m {
                        ChatMessage::User { content } => Some(content.clone()),
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .join("\n");
                prompts.lock().unwrap().push(user.clone());
                let answer = if system.contains("LECTOR") {
                    json!({"summary": "la malla 2.5D deforma la tanda R", "entities": {"projects": []},
                           "queries": {"notes": ["malla"], "findings": [], "commits": []}})
                } else if system.contains("CRÍTICO") {
                    json!({"extra_questions": [], "contradictions": [], "gaps": [],
                           "requery": {"notes": [], "findings": [], "commits": []}})
                } else if system.contains("REDACTOR") {
                    let file = user
                        .split("===== INICIO ")
                        .nth(1)
                        .and_then(|rest| rest.split(' ').next())
                        .unwrap_or_default()
                        .to_string();
                    json!({"summary": "resumen", "operations": [
                        {"op": "add_section", "file": file, "heading": "## Resumen",
                         "body": "La malla 2.5D deforma la tanda R."}
                    ]})
                } else {
                    json!({"related": [], "already_discussed": [], "pending": [],
                           "related_commits": [], "implemented": [], "not_implemented": []})
                };
                Ok(answer.to_string())
            }),
        }
    }

    fn setup(name: &str, idle: bool) -> Setup {
        let root = crate::test_support::temp_dir(&format!("{name}-vault"));
        write(&root, "reuniones/r.md", NOTE);
        write(&root, "temas/malla.md", "# Malla\n\nLa malla 2.5D deforma las ortofotos con relieve fuerte.\n");
        write(&root, "privado/p.md", "# P\n\nlo que no tiene que salir de aqui nunca jamas\n");

        let inbox = Inbox::open(crate::test_support::temp_dir(&format!("{name}-inbox"))).unwrap();
        inbox
            .save_config(&InboxConfig {
                worker_enabled: true,
                projects: vec![DocProject {
                    id: "notas".into(),
                    name: "Notas".into(),
                    repo_root: root.to_string_lossy().into_owned(),
                    kind: ProjectKind::Vault,
                    conventions: String::new(),
                    documents: vec![],
                }],
                notes: Some(NotesConfig {
                    vault_project: "notas".into(),
                    repos: vec![],
                    digest_on_idle: idle,
                    groups: vec![],
                    local_folders: vec![],
                }),
                ..InboxConfig::default()
            })
            .unwrap();
        let prompts = Arc::new(Mutex::new(Vec::new()));
        let service = DocsService::new(inbox, Backends::Fixed(vec![backend(Arc::clone(&prompts))]));
        Setup {
            service,
            root,
            prompts,
        }
    }

    #[tokio::test]
    async fn a_manual_digest_ends_in_a_proposal_that_can_be_approved() {
        let s = setup("runner-manual", false);
        let now = Timestamp::now();
        let digest = s.service.digest_note("reuniones/r.md", DigestTrigger::Manual, now).unwrap();
        let again = s.service.digest_note("reuniones\\r.md", DigestTrigger::Manual, now).unwrap();
        assert_eq!(again.id, digest.id, "pulsar dos veces no encola dos");

        assert!(s.service.tick(now).await.unwrap());
        let digest = s.service.inbox().digest(&digest.id).unwrap();
        let DigestStatus::Proposed { proposal_id } = &digest.status else {
            panic!("{:?}", digest.status)
        };
        let proposal = s.service.inbox().proposal(proposal_id).unwrap();
        assert!(matches!(proposal.origin, ProposalOrigin::NoteDigest { .. }));
        assert!(digest.trace.steps.iter().any(|step| step.agent == "synthesizer" && step.ok));
        assert_eq!(s.service.snapshot().unwrap().digests.len(), 1);

        let outcome = s.service.approve(&proposal.id, proposal.revision, now).await.unwrap();
        assert!(matches!(outcome, ApproveOutcome::Applied(_)), "{outcome:?}");
        let text = std::fs::read_to_string(s.root.join("reuniones/r.md")).unwrap();
        assert!(text.contains("## Resumen\n\nLa malla 2.5D deforma la tanda R."), "{text}");
        assert!(s.service.inbox().digest(&digest.id).unwrap().settled_hash.is_some());
        assert!(!s.service.tick(now).await.unwrap(), "no queda nada que procesar");
    }

    #[tokio::test]
    async fn private_notes_cannot_be_digested_and_the_overview_lists_the_rest() {
        let s = setup("runner-private", false);
        assert!(s
            .service
            .digest_note("privado/p.md", DigestTrigger::Manual, Timestamp::now())
            .is_err());

        let overview = s.service.notes_overview().unwrap();
        let paths: Vec<&str> = overview.notes.iter().map(|n| n.path.as_str()).collect();
        assert!(paths.contains(&"reuniones/r.md"), "{paths:?}");
        assert!(!paths.iter().any(|p| p.starts_with("privado")), "{paths:?}");
        assert!(!s.service.search_notes("malla", 5).unwrap().is_empty());
        assert!(s.service.note_details("temas/malla.md").unwrap().text.contains("relieve"));
    }

    #[tokio::test]
    async fn a_pending_proposal_holds_back_the_same_note_but_not_the_others() {
        let s = setup("runner-pending", false);
        let now = Timestamp::now();
        s.service.digest_note("reuniones/r.md", DigestTrigger::Manual, now).unwrap();
        assert!(s.service.tick(now).await.unwrap());

        let same = s.service.digest_note("reuniones/r.md", DigestTrigger::Manual, now).unwrap();
        let other = s.service.digest_note("temas/malla.md", DigestTrigger::Manual, now).unwrap();
        assert!(s.service.tick(now).await.unwrap());

        assert!(matches!(
            s.service.inbox().digest(&other.id).unwrap().status,
            DigestStatus::Proposed { .. }
        ));
        assert_eq!(s.service.inbox().digest(&same.id).unwrap().status, DigestStatus::Queued);
    }

    #[tokio::test]
    async fn idle_mode_processes_a_quiet_note_only_once() {
        let s = setup("runner-idle", true);
        let ten_minutes_ago = SystemTime::now() - Duration::from_secs(600);
        for rel in ["reuniones/r.md", "temas/malla.md"] {
            let file = std::fs::File::options()
                .write(true)
                .open(s.root.join(rel))
                .unwrap();
            file.set_modified(ten_minutes_ago).unwrap();
        }

        let now = Timestamp::now();
        assert!(s.service.tick(now).await.unwrap());
        assert!(s.service.tick(now).await.unwrap());
        let digests = s.service.inbox().digests().unwrap();
        assert_eq!(digests.len(), 2, "{digests:?}");
        assert!(digests.iter().all(|d| d.trigger == DigestTrigger::Idle));

        // Rechazar no la vuelve a encolar: la nota no cambio.
        for proposal in s.service.inbox().proposals().unwrap() {
            s.service.reject(&proposal.id, None, now).await.unwrap();
        }
        assert!(!s.service.tick(now).await.unwrap());
        assert_eq!(s.service.inbox().digests().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn regenerating_a_digest_proposal_reruns_the_agents_with_the_user_note() {
        let s = setup("runner-regenerate", false);
        let now = Timestamp::now();
        s.service.digest_note("reuniones/r.md", DigestTrigger::Manual, now).unwrap();
        s.service.tick(now).await.unwrap();
        let proposal = s.service.inbox().proposals().unwrap().pop().unwrap();

        let again = s
            .service
            .regenerate(&proposal.id, Some("mas corto, por favor".into()), now)
            .await
            .unwrap();
        assert_eq!(again.revision, proposal.revision + 1);
        assert!(matches!(again.origin, ProposalOrigin::NoteDigest { .. }));
        assert!(s
            .prompts
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.contains("mas corto, por favor")));
    }
}
