//! El digest de una nota de punta a punta: cinco agentes en cadena, con Rust
//! buscando entre medias, y una propuesta del buzon al final.
//!
//! ```text
//! nota ─► Lector ─► (Rust busca) ─┬─► Memoria ─┐
//!                                  └─► Codigo  ─┴─► Critico ─(¿busca mas? una vez)─► Redactor ─► Proposal
//! ```
//!
//! No es un chat libre entre agentes: es una cadena determinista con un
//! documento compartido (el [`Blackboard`]). Un chat libre seria caro, dificil de
//! reproducir e imposible de auditar; esto se puede probar entero con un modelo
//! de mentira y cada paso queda en la traza.
//!
//! Tres garantias que no dependen de que el modelo obedezca:
//!
//! - **Lo citado existe.** Cada agente solo recibe candidatos con id, y lo que
//!   cite fuera de su lista se quita ([`agents::keep_known_ids`]).
//! - **Nada privado ni secreto sale.** Una nota con `ai: false` no llega a
//!   ningun agente, y todo el texto pasa por [`redact`] antes de cada peticion.
//! - **La propuesta es una propuesta del buzon**: las mismas operaciones, la
//!   misma validacion de "solo lo que viste" y la misma aprobacion con revision.

use std::collections::{BTreeMap, HashSet};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Instant;

use nexodeck_ai::openai::types::ChatMessage;
use serde_json::{json, Value};

use crate::apply::{read_documents, FileSnapshot};
use crate::backend::ModelBackend;
use crate::config::{normalize_rel, DocProject, HUB_DIR};
use crate::context::build_note_context;
use crate::dates::SpanishDate;
use crate::error::DocsError;
use crate::generate::{propose_with_repair, GenerateError};
use crate::model::{Proposal, ProposalOrigin, ProposalStatus};
use crate::notes::agents::{self, Agent, Queries};
use crate::notes::digest::{AgentStep, Blackboard, CandidateRef};
use crate::notes::index::{Candidate, CandidateKind, NotesIndex};
use crate::notes::roots::{link_form, split_virtual};
use crate::redact::redact;
use crate::validate::ValidationInput;

/// Menos texto que esto no da para relacionar nada y solo gastaria llamadas.
pub(crate) const MIN_NOTE_CHARS: usize = 40;
const MAX_QUERIES: usize = 4;
/// El critico puede pedir como mucho estas busquedas, en total.
const MAX_REQUERIES: usize = 3;
const NOTE_HITS: usize = 5;
const NOTE_CAP: usize = 12;
const FINDING_HITS: usize = 4;
const FINDING_CAP: usize = 8;
const COMMIT_HITS: usize = 5;
const COMMIT_CAP: usize = 10;

pub(crate) struct DigestRequest<'a> {
    pub project: &'a DocProject,
    pub note: &'a str,
    pub index: &'a NotesIndex,
    pub today: SpanishDate,
    pub now: jiff::Timestamp,
    pub digest_id: &'a str,
    pub proposal_id: String,
    pub revision: u32,
    /// Al regenerar: la propuesta anterior y lo que pidio el usuario.
    pub previous: Option<&'a Proposal>,
    pub user_note: Option<&'a str>,
}

#[derive(Debug)]
pub(crate) enum DigestOutcome {
    Proposal(Box<Proposal>),
    /// No habia nada que hacer, y por que.
    Skipped(String),
}

pub(crate) struct DigestRun {
    pub outcome: Result<DigestOutcome, GenerateError>,
    /// Lo que se llego a hacer, tambien cuando falla.
    pub trace: Blackboard,
}

pub(crate) async fn run_note_digest(
    request: &DigestRequest<'_>,
    backend: &ModelBackend,
    cancel: Arc<AtomicBool>,
) -> DigestRun {
    let mut trace = Blackboard {
        model_label: backend.label().to_string(),
        ..Blackboard::default()
    };
    let outcome = digest(request, backend, cancel, &mut trace).await;
    DigestRun { outcome, trace }
}

async fn digest(
    req: &DigestRequest<'_>,
    backend: &ModelBackend,
    cancel: Arc<AtomicBool>,
    trace: &mut Blackboard,
) -> Result<DigestOutcome, GenerateError> {
    let project = req.project;
    // Dos rutas para la misma nota, que en la boveda principal coinciden y en una
    // carpeta local no:
    // - `note_path`, la virtual (`@apuntes/x.md`): la clave del indice;
    // - `note_file`, la de dentro de su carpeta (`x.md`): la que entiende
    //   `project` para leer, validar y guardar los hashes de la propuesta.
    // Mezclarlas hace que un digest de una nota local lea un fichero que no existe.
    let note_path = normalize_rel(req.note);
    let note_file = inner(&note_path);
    let entry = req.index.note(&note_path).ok_or_else(|| {
        DocsError::NotFound(format!("la nota '{note_path}' en la boveda"))
    })?;
    if entry.note.ai_excluded {
        return Ok(DigestOutcome::Skipped(
            "la nota tiene `ai: false`: ningun agente la lee".to_string(),
        ));
    }
    if project.document(&note_file).is_none() {
        return Err(DocsError::Invalid(format!(
            "'{note_path}' no es una nota que se pueda procesar"
        ))
        .into());
    }
    let content: usize = entry
        .note
        .sections
        .iter()
        .map(|s| s.text.trim().chars().count())
        .sum();
    if content < MIN_NOTE_CHARS {
        return Ok(DigestOutcome::Skipped(
            "la nota es demasiado corta para relacionarla con nada".to_string(),
        ));
    }

    let mut hub = hub_for(req.index, &entry.note.frontmatter, &note_path, &[]);
    let mut paths = vec![note_file.clone()];
    paths.extend(hub.as_deref().map(inner));
    let mut snapshots = read_documents(project, paths.iter().map(String::as_str))?;
    let mut redacted = BTreeMap::new();
    redact_into(&snapshots, &mut redacted, trace);

    let budget = backend.context_budget();
    let focus = format!("{} {}", entry.note.title, entry.note.tags.join(" "));

    // 1. Lector.
    let reader_context = build_note_context(project, &only(&redacted, &[&note_file]), &focus, budget / 2);
    let (reader, step) = agents::ask(
        Agent::Reader,
        Agent::Reader.name(),
        backend,
        agents::reader_prompt(&project.name, req.today, &reader_context),
        cancel.clone(),
    )
    .await;
    trace.steps.push(step);
    let reader = reader?;

    // La nota de proyecto: la del frontmatter o, si no hay, la de un proyecto
    // que nombre el lector.
    if hub.is_none() {
        let named = strings(&reader["entities"]["projects"]);
        hub = hub_for(req.index, &entry.note.frontmatter, &note_path, &named);
        if let Some(path) = &hub {
            let hub_file = inner(path);
            snapshots.extend(read_documents(project, [hub_file.as_str()])?);
            redact_into(&snapshots, &mut redacted, trace);
        }
    }
    trace.hub = hub.clone();

    // 2. Rust busca.
    let summary = reader["summary"].as_str().unwrap_or_default().to_string();
    let mut queries = Queries::from_value(&reader, "queries", MAX_QUERIES);
    queries.notes.insert(0, format!("{} {summary}", entry.note.title));
    queries.findings.insert(0, summary.clone());
    queries.commits.insert(0, summary.clone());
    let mut candidates: Vec<Candidate> = Vec::new();
    retrieve(req.index, &queries, &note_path, &mut candidates);
    append_refs(&candidates, trace);

    // 3. Memoria y codigo, en paralelo.
    let (memory, code) = memory_and_code(backend, &reader, trace, true, true, "", cancel.clone()).await;
    let mut memory = memory?.unwrap_or_else(empty_memory);
    let mut code = code?.unwrap_or_else(empty_code);

    // 4. Critico, con una sola ronda extra de busqueda si la pide.
    let critic_context = build_note_context(project, &only(&redacted, &[&note_file]), &summary, budget / 3);
    let (critic, step) = agents::ask(
        Agent::Critic,
        Agent::Critic.name(),
        backend,
        agents::critic_prompt(&critic_context, &reader, &memory, &code, &trace.candidates),
        cancel.clone(),
    )
    .await;
    let allowed: HashSet<String> = trace.candidates.iter().map(|c| c.id.clone()).collect();
    let critic = settle(critic, step, &allowed, trace)?.unwrap_or_else(empty_critic);

    let requery = cap_total(Queries::from_value(&critic, "requery", MAX_REQUERIES), MAX_REQUERIES);
    if !requery.is_empty() {
        trace.requeried = true;
        let before = candidates.len();
        let (new_memory, new_code) = retrieve(req.index, &requery, &note_path, &mut candidates);
        if candidates.len() > before {
            append_refs(&candidates[before..], trace);
            let (again_memory, again_code) =
                memory_and_code(backend, &reader, trace, new_memory, new_code, "#2", cancel.clone()).await;
            if let Some(value) = again_memory? {
                memory = value;
            }
            if let Some(value) = again_code? {
                code = value;
            }
        }
    }

    // 5. Redactor.
    let hub_file = hub.as_deref().map(inner);
    let mut targets: Vec<&str> = vec![&note_file];
    if let Some(path) = &hub_file {
        targets.push(path);
    }
    let synth_context = build_note_context(project, &only(&redacted, &targets), &summary, budget * 2 / 3);
    let visible: BTreeMap<String, String> = synth_context
        .iter()
        .map(|c| (c.path.clone(), c.shown.clone()))
        .collect();
    let links = allowed_links(req.index, &memory, &note_path, hub.as_deref());
    let commits = allowed_commits(&code);
    let messages = vec![
        ChatMessage::system(Agent::Synthesizer.system_prompt()),
        ChatMessage::user(agents::synthesizer_prompt(
            req.today,
            &synth_context,
            &reader,
            &memory,
            &code,
            &critic,
            &links,
            &commits,
            req.previous,
            req.user_note,
        )),
    ];
    let real_bodies: BTreeMap<String, String> = snapshots
        .iter()
        .map(|(path, snap)| (path.clone(), snap.document.body.clone()))
        .collect();

    let started = Instant::now();
    let drafted = propose_with_repair(
        backend,
        Agent::Synthesizer.options(),
        messages,
        &ValidationInput {
            project,
            bodies: &real_bodies,
            visible: Some(&visible),
            findings: &[],
            today: req.today,
        },
        &[],
        cancel,
    )
    .await;
    trace.steps.push(AgentStep {
        agent: Agent::Synthesizer.name().to_string(),
        ok: drafted.is_ok(),
        millis: started.elapsed().as_millis() as u64,
        output: drafted.as_ref().ok().map(|d| {
            let operations: Vec<_> = d.validated.operations.iter().map(|o| &o.operation).collect();
            json!({ "summary": d.summary, "operations": operations })
        }),
        detail: drafted.as_ref().err().map(|e| e.to_string()),
    });
    let drafted = drafted?;

    let mut warnings = drafted.validated.warnings.clone();
    for op in &drafted.validated.operations {
        for target in wikilink_targets(&op.operation.added_text()) {
            // Se resuelve como lo leera quien abra la nota: desde ella, que en una
            // carpeta local significa relativo a esa carpeta.
            if req.index.resolve_link_from(&target, &note_path).is_none() {
                warnings.push(format!(
                    "{} enlaza a [[{target}]], que no es ninguna nota de la boveda",
                    op.operation.file()
                ));
            }
        }
    }

    let now = req.now.to_string();
    Ok(DigestOutcome::Proposal(Box::new(Proposal {
        id: req.proposal_id.clone(),
        project: project.id.clone(),
        revision: req.revision,
        created_at: now.clone(),
        updated_at: now,
        finding_ids: Vec::new(),
        origin: ProposalOrigin::NoteDigest {
            note: note_path,
            digest_id: req.digest_id.to_string(),
        },
        from: Some("asistente de notas".to_string()),
        summary: drafted.summary,
        operations: drafted.validated.operations,
        unresolved: Vec::new(),
        warnings,
        base_hashes: snapshots
            .iter()
            .map(|(path, snap)| (path.clone(), snap.hash.clone()))
            .collect(),
        applied_hashes: BTreeMap::new(),
        model_label: backend.label().to_string(),
        local_model: backend.is_local(),
        status: ProposalStatus::Ready,
    })))
}

type AgentResult = Result<Option<Value>, GenerateError>;

/// Memoria (notas y hallazgos) y codigo (commits) a la vez. Un agente sin
/// candidatos de su tipo no se llama: `Ok(None)`.
async fn memory_and_code(
    backend: &ModelBackend,
    reader: &Value,
    trace: &mut Blackboard,
    run_memory: bool,
    run_code: bool,
    suffix: &str,
    cancel: Arc<AtomicBool>,
) -> (AgentResult, AgentResult) {
    let memory_candidates: Vec<CandidateRef> = trace
        .candidates
        .iter()
        .filter(|c| c.kind != CandidateKind::Commit.as_str())
        .cloned()
        .collect();
    let code_candidates: Vec<CandidateRef> = trace
        .candidates
        .iter()
        .filter(|c| c.kind == CandidateKind::Commit.as_str())
        .cloned()
        .collect();
    let memory_label = format!("{}{suffix}", Agent::Memory.name());
    let code_label = format!("{}{suffix}", Agent::Code.name());

    let memory_call = async {
        if run_memory && !memory_candidates.is_empty() {
            Some(
                agents::ask(
                    Agent::Memory,
                    &memory_label,
                    backend,
                    agents::memory_prompt(reader, &memory_candidates),
                    cancel.clone(),
                )
                .await,
            )
        } else {
            None
        }
    };
    let code_call = async {
        if run_code && !code_candidates.is_empty() {
            Some(
                agents::ask(
                    Agent::Code,
                    &code_label,
                    backend,
                    agents::code_prompt(reader, &code_candidates),
                    cancel.clone(),
                )
                .await,
            )
        } else {
            None
        }
    };
    let (memory, code) = tokio::join!(memory_call, code_call);

    let memory_allowed: HashSet<String> = memory_candidates.iter().map(|c| c.id.clone()).collect();
    let code_allowed: HashSet<String> = code_candidates.iter().map(|c| c.id.clone()).collect();
    let memory = match memory {
        Some((result, step)) => settle(result, step, &memory_allowed, trace),
        None => {
            if run_memory {
                trace.steps.push(skipped_step(&memory_label));
            }
            Ok(None)
        }
    };
    let code = match code {
        Some((result, step)) => settle(result, step, &code_allowed, trace),
        None => {
            if run_code {
                trace.steps.push(skipped_step(&code_label));
            }
            Ok(None)
        }
    };
    (memory, code)
}

/// Deja en la traza lo que hizo un agente y decide si su fallo para la cadena.
///
/// Un error del **modelo** si la para: si la red cayo para este agente, caera
/// para el siguiente, y el trabajador sabe reintentar. Una respuesta ilegible
/// despues de pedirla dos veces no la para: sin la memoria o sin el critico, el
/// redactor todavia puede proponer algo util.
fn settle(
    result: Result<Value, GenerateError>,
    mut step: AgentStep,
    allowed: &HashSet<String>,
    trace: &mut Blackboard,
) -> AgentResult {
    match result {
        Ok(mut value) => {
            agents::keep_known_ids(&mut value, allowed, &mut trace.discarded_ids);
            step.output = Some(value.clone());
            trace.steps.push(step);
            Ok(Some(value))
        }
        Err(GenerateError::Model(error)) => {
            trace.steps.push(step);
            Err(GenerateError::Model(error))
        }
        Err(_) => {
            trace.steps.push(step);
            Ok(None)
        }
    }
}

fn skipped_step(label: &str) -> AgentStep {
    AgentStep {
        agent: label.to_string(),
        ok: true,
        millis: 0,
        output: None,
        detail: Some("no se llamo: no habia candidatos de su tipo".to_string()),
    }
}

fn empty_memory() -> Value {
    json!({ "related": [], "already_discussed": [], "pending": [] })
}

fn empty_code() -> Value {
    json!({ "related_commits": [], "implemented": [], "not_implemented": [] })
}

fn empty_critic() -> Value {
    json!({ "extra_questions": [], "contradictions": [], "gaps": [] })
}

/// Ejecuta las busquedas y añade lo nuevo. Devuelve si entro algo para la
/// memoria y algo para el agente de codigo.
fn retrieve(
    index: &NotesIndex,
    queries: &Queries,
    note_path: &str,
    into: &mut Vec<Candidate>,
) -> (bool, bool) {
    let mut new_memory = false;
    let mut new_code = false;
    let plan = [
        (CandidateKind::Note, &queries.notes, NOTE_HITS, NOTE_CAP),
        (CandidateKind::Finding, &queries.findings, FINDING_HITS, FINDING_CAP),
        (CandidateKind::Commit, &queries.commits, COMMIT_HITS, COMMIT_CAP),
    ];
    for (kind, list, hits, cap) in plan {
        let mut count = into.iter().filter(|c| c.kind == kind).count();
        for query in list {
            for hit in index.search(query, &[kind], hits, Some(note_path)) {
                if count >= cap {
                    break;
                }
                if into.iter().any(|c| c.id == hit.id) {
                    continue;
                }
                into.push(hit);
                count += 1;
                if kind == CandidateKind::Commit {
                    new_code = true;
                } else {
                    new_memory = true;
                }
            }
        }
    }
    (new_memory, new_code)
}

fn append_refs(candidates: &[Candidate], trace: &mut Blackboard) {
    for c in candidates {
        let (title, a) = redact(&c.title);
        let (snippet, b) = redact(&c.snippet);
        trace.redactions += a + b;
        trace.candidates.push(CandidateRef {
            id: c.id.clone(),
            kind: c.kind.as_str().to_string(),
            title,
            snippet,
            date: c.date.clone(),
        });
    }
}

fn redact_into(
    snapshots: &BTreeMap<String, FileSnapshot>,
    redacted: &mut BTreeMap<String, String>,
    trace: &mut Blackboard,
) {
    for (path, snap) in snapshots {
        if !redacted.contains_key(path) {
            let (text, count) = redact(&snap.document.body);
            trace.redactions += count;
            redacted.insert(path.clone(), text);
        }
    }
}

fn only(bodies: &BTreeMap<String, String>, paths: &[&str]) -> BTreeMap<String, String> {
    bodies
        .iter()
        .filter(|(path, _)| paths.contains(&path.as_str()))
        .map(|(path, body)| (path.clone(), body.clone()))
        .collect()
}

/// La ruta de una nota dentro de su carpeta (`@apuntes/x.md` -> `x.md`).
fn inner(path: &str) -> String {
    split_virtual(path).1.to_string()
}

/// `proyectos/<X>.md` para el primer nombre que tenga nota de proyecto.
///
/// **En la misma carpeta que la nota.** La propuesta se valida y se aplica contra
/// una sola raiz, asi que una nota de proyecto de otra carpeta no se podria ni
/// leer. Y por nombre unico, `proyectos/X` podria encontrarse en otra carpeta si
/// en la de la nota no existe: por eso se comprueba la carpeta del resultado.
fn hub_for(
    index: &NotesIndex,
    frontmatter: &BTreeMap<String, String>,
    note_path: &str,
    named: &[String],
) -> Option<String> {
    let from_front = ["project", "proyecto"]
        .iter()
        .filter_map(|key| frontmatter.get(*key))
        .map(|value| {
            value
                .trim()
                .trim_matches(['"', '\''])
                .trim_start_matches("[[")
                .trim_end_matches("]]")
                .to_string()
        });
    from_front
        .chain(named.iter().cloned())
        .filter(|name| !name.trim().is_empty())
        .find_map(|name| {
            let path = index.resolve_link_from(&format!("{HUB_DIR}{}", name.trim()), note_path)?;
            let same_folder = split_virtual(&path).0 == split_virtual(note_path).0;
            (same_folder && inner(&path).to_lowercase().starts_with(HUB_DIR) && path != note_path)
                .then_some(path)
        })
}

/// Enlaces a notas que la memoria relaciono, mas la propia nota y su nota de
/// proyecto (la entrada del proyecto tiene que poder enlazar a la nota).
fn allowed_links(index: &NotesIndex, memory: &Value, note_path: &str, hub: Option<&str>) -> Vec<String> {
    let mut paths: Vec<String> = vec![note_path.to_string()];
    paths.extend(hub.map(str::to_string));
    for id in agents::cited_ids(memory) {
        if let Some(rest) = id.strip_prefix("n:") {
            let path = rest.rsplit_once('#').map(|(p, _)| p).unwrap_or(rest);
            if index.note(path).is_some() && !paths.iter().any(|p| p == path) {
                paths.push(path.to_string());
            }
        }
    }
    // Cada enlace en la forma en que funciona **desde esta nota**: relativo dentro
    // de su carpeta local (como lo escribe Obsidian al abrirla), con la ruta
    // virtual hacia fuera.
    paths
        .into_iter()
        .map(|p| {
            let link = link_form(&p, note_path);
            format!("[[{}]]", link.strip_suffix(".md").unwrap_or(&link))
        })
        .collect()
}

/// `Repo@sha` de los commits que cito el agente de codigo.
fn allowed_commits(code: &Value) -> Vec<String> {
    agents::cited_ids(code)
        .into_iter()
        .filter_map(|id| id.strip_prefix("c:").map(str::to_string))
        .collect()
}

fn wikilink_targets(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("[[") {
        let after = &rest[start + 2..];
        let Some(end) = after.find("]]") else { break };
        let inner = &after[..end];
        let target = inner.split(['|', '#']).next().unwrap_or("").trim();
        if !target.is_empty() && !out.iter().any(|t| t == target) {
            out.push(target.to_string());
        }
        rest = &after[end + 2..];
    }
    out
}

fn strings(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn cap_total(mut queries: Queries, max: usize) -> Queries {
    let mut left = max;
    for list in [&mut queries.notes, &mut queries.findings, &mut queries.commits] {
        list.truncate(left);
        left -= list.len();
    }
    queries
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::sync::Mutex;

    use super::*;
    use crate::backend::{ModelError, ModelErrorKind};
    use crate::config::ProjectKind;
    use crate::notes::git::CommitInfo;

    /// En una carpeta local, la nota de proyecto se busca en esa carpeta y **no
    /// cruza a otra** en ningun sentido; y los enlaces que puede escribir la
    /// propuesta van relativos a la carpeta, como en Obsidian.
    #[test]
    fn a_local_note_finds_its_hub_and_links_inside_its_own_folder() {
        let main = crate::test_support::temp_dir("orch-roots-main");
        let local = crate::test_support::temp_dir("orch-roots-local");
        for (root, rel, text) in [
            (&main, "proyectos/ODM.md", "# ODM principal\n"),
            (&main, "proyectos/Solo.md", "# Solo en la principal\n"),
            (&local, "proyectos/ODM.md", "# ODM local\n"),
            (&local, "proyectos/Remota.md", "# Solo en la local\n"),
            (&local, "diario/hoy.md", "# Hoy\n"),
        ] {
            let path = root.join(rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        }
        let mut index = NotesIndex::with_roots(vec![
            (String::new(), main.clone()),
            ("@apuntes/".into(), local.clone()),
        ]);
        index.refresh().unwrap();
        let front = |project: &str| BTreeMap::from([("project".to_string(), project.to_string())]);

        assert_eq!(
            hub_for(&index, &front("ODM"), "@apuntes/diario/hoy.md", &[]).as_deref(),
            Some("@apuntes/proyectos/ODM.md"),
            "la de su propia carpeta, no la de la principal"
        );
        assert_eq!(
            hub_for(&index, &front("ODM"), "temas/x.md", &[]).as_deref(),
            Some("proyectos/ODM.md")
        );
        assert_eq!(hub_for(&index, &front("Solo"), "@apuntes/diario/hoy.md", &[]), None);
        // Por nombre unico se encontraria en la local, pero no se podria leer con
        // el proyecto de la principal.
        assert_eq!(hub_for(&index, &front("Remota"), "temas/x.md", &[]), None);

        let links = allowed_links(
            &index,
            &json!({}),
            "@apuntes/diario/hoy.md",
            Some("@apuntes/proyectos/ODM.md"),
        );
        assert_eq!(links, vec!["[[diario/hoy]]", "[[proyectos/ODM]]"]);
    }

    const NOTE: &str = "---\nproject: ODM\n---\n# Reunion del 15\n\nLa ortofoto de la tanda R sale deformada con la malla 2.5D.\nConexion de prueba: Password=Secreta123;\n\n## Tareas\n\n- [ ] reprocesar la tanda R\n";

    struct Vault {
        project: DocProject,
        index: NotesIndex,
    }

    fn write(root: &Path, rel: &str, text: &str) {
        let path = root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn vault(name: &str) -> Vault {
        let root = crate::test_support::temp_dir(name);
        write(&root, "reuniones/2026-09-15.md", NOTE);
        write(&root, "proyectos/ODM.md", "# ODM\n\n## 10-sep: arranque\n\nSe procesan tandas con ODM.\n");
        write(&root, "temas/malla.md", "# Malla\n\nLa malla 2.5D deforma las ortofotos con relieve fuerte; la 3D no.\n");
        write(&root, "temas/drift.md", "# Drift\n\nMigraciones idempotentes con _addColumnIfMissing.\n");
        write(&root, "temas/secreta.md", "---\nai: false\n---\n# Nomina\n\nortofoto tanda malla sueldo sueldo sueldo sueldo sueldo\n");

        let mut index = NotesIndex::new(&root);
        index.refresh().unwrap();
        index.set_commits(vec![CommitInfo {
            repo: "ExampleApi".into(),
            sha: "abcdef1234567".into(),
            date: "2026-09-14".into(),
            author: "Juan".into(),
            subject: "Tanda R: reprocesar con malla 3D".into(),
            body: "La malla 2.5D deformaba la ortofoto.".into(),
        }]);
        Vault {
            project: DocProject {
                id: "notas".into(),
                name: "Notas".into(),
                repo_root: root.to_string_lossy().into_owned(),
                kind: ProjectKind::Vault,
                conventions: String::new(),
                documents: vec![],
            },
            index,
        }
    }

    type Calls = Arc<Mutex<Vec<(String, String)>>>;

    /// Contesta segun el agente, que se reconoce por su prompt de sistema, y
    /// guarda todo lo que se le mando.
    fn fake(answers: impl Fn(&str, usize) -> Result<String, ModelError> + Send + Sync + 'static) -> (ModelBackend, Calls) {
        let calls: Calls = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&calls);
        let backend = ModelBackend::Fake {
            label: "falso".into(),
            local: false,
            respond: Arc::new(move |messages: &[ChatMessage]| {
                let system = match &messages[0] {
                    ChatMessage::System { content } => content.clone(),
                    _ => String::new(),
                };
                let agent = ["LECTOR", "MEMORIA", "CÓDIGO", "CRÍTICO", "REDACTOR"]
                    .into_iter()
                    .find(|name| system.contains(name))
                    .unwrap_or("?")
                    .to_string();
                let user: String = messages
                    .iter()
                    .filter_map(|m| match m {
                        ChatMessage::User { content } => Some(content.clone()),
                        _ => None,
                    })
                    .collect::<Vec<_>>()
                    .join("\n");
                let mut log = log.lock().unwrap();
                let nth = log.iter().filter(|(a, _)| *a == agent).count();
                log.push((agent.clone(), user));
                drop(log);
                answers(&agent, nth)
            }),
        };
        (backend, calls)
    }

    fn happy(agent: &str, _nth: usize) -> Result<String, ModelError> {
        Ok(match agent {
            "LECTOR" => json!({
                "summary": "La ortofoto de la tanda R sale deformada por la malla 2.5D.",
                "entities": {"projects": ["ODM"], "repos": [], "people": [], "topics": ["malla"]},
                "decisions": [],
                "task_candidates": ["reprocesar con malla 3D"],
                "open_questions": ["¿vale la malla 3D para todas las tandas?"],
                "queries": {"notes": ["malla ortofoto deformada"], "findings": [], "commits": ["malla 3D tanda"]}
            }),
            "MEMORIA" => json!({
                "related": [
                    {"id": "n:temas/malla.md#0", "why": "explica la deformacion"},
                    {"id": "n:inventada.md#0", "why": "no existe"}
                ],
                "already_discussed": [],
                "pending": []
            }),
            "CÓDIGO" => json!({
                "related_commits": [{"id": "c:ExampleApi@abcdef1", "why": "reprocesa con malla 3D"}],
                "implemented": [],
                "not_implemented": [{"what": "automatizar la eleccion de malla"}]
            }),
            "CRÍTICO" => json!({
                "extra_questions": ["¿cuanto tarda la malla 3D en una tanda completa?"],
                "contradictions": [],
                "gaps": [],
                "requery": {"notes": ["drift migraciones"], "findings": [], "commits": []}
            }),
            "REDACTOR" => json!({
                "summary": "Resumen, relaciones y preguntas",
                "operations": [
                    {"op": "add_section", "file": "reuniones/2026-09-15.md", "heading": "## Resumen",
                     "body": "La ortofoto sale deformada por la malla 2.5D. Ver [[temas/malla]] y `ExampleApi@abcdef1`. Tambien [[no-existe]]."},
                    {"op": "set_frontmatter_key", "file": "reuniones/2026-09-15.md", "key": "status", "value": "procesada"},
                    {"op": "add_section", "file": "proyectos/ODM.md", "heading": "## 15-sep: la malla 2.5D deforma la tanda R",
                     "body": "Ver [[reuniones/2026-09-15]]."}
                ]
            }),
            other => panic!("agente inesperado {other}"),
        }
        .to_string())
    }

    fn request<'a>(v: &'a Vault, note: &'a str) -> DigestRequest<'a> {
        DigestRequest {
            project: &v.project,
            note,
            index: &v.index,
            today: SpanishDate::parse_iso("2026-09-15").unwrap(),
            now: jiff::Timestamp::from_second(1_789_000_000).unwrap(),
            digest_id: "d-1",
            proposal_id: "p-1".into(),
            revision: 1,
            previous: None,
            user_note: None,
        }
    }

    #[tokio::test]
    async fn the_whole_chain_ends_in_a_valid_note_proposal() {
        let v = vault("orchestrator-happy");
        let (backend, calls) = fake(happy);
        let run = run_note_digest(&request(&v, "reuniones/2026-09-15.md"), &backend, Arc::new(AtomicBool::new(false))).await;

        let DigestOutcome::Proposal(proposal) = run.outcome.unwrap() else { panic!("sin propuesta") };
        assert_eq!(
            proposal.origin,
            ProposalOrigin::NoteDigest { note: "reuniones/2026-09-15.md".into(), digest_id: "d-1".into() }
        );
        assert_eq!(proposal.operations.len(), 3);
        assert!(proposal.warnings.iter().any(|w| w.contains("[[no-existe]]")), "{:?}", proposal.warnings);
        assert!(!proposal.warnings.iter().any(|w| w.contains("[[temas/malla]]")));
        assert!(proposal.base_hashes.contains_key("proyectos/ODM.md"));

        let trace = run.trace;
        assert_eq!(trace.hub.as_deref(), Some("proyectos/ODM.md"));
        assert_eq!(trace.discarded_ids, vec!["n:inventada.md#0"]);
        assert!(trace.requeried);
        let agents: Vec<&str> = trace.steps.iter().map(|s| s.agent.as_str()).collect();
        assert_eq!(agents, vec!["reader", "memory", "code", "critic", "memory#2", "synthesizer"]);
        assert!(trace.candidates.iter().any(|c| c.id == "c:ExampleApi@abcdef1"));
        assert!(trace.redactions >= 1);

        let calls = calls.lock().unwrap();
        assert_eq!(calls.iter().filter(|(a, _)| a == "CRÍTICO").count(), 1, "el critico no repite");
        assert!(calls.iter().all(|(_, text)| !text.contains("Secreta123")), "un secreto salio hacia el modelo");
        assert!(calls.iter().all(|(_, text)| !text.contains("sueldo")), "una nota con ai: false llego a un agente");
        let synth = &calls.iter().find(|(a, _)| a == "REDACTOR").unwrap().1;
        assert!(synth.contains("[[temas/malla]]") && synth.contains("ExampleApi@abcdef1"), "{synth}");
    }

    #[tokio::test]
    async fn a_note_with_ai_false_never_reaches_a_model() {
        let v = vault("orchestrator-excluded");
        let (backend, calls) = fake(happy);
        let run = run_note_digest(&request(&v, "temas/secreta.md"), &backend, Arc::new(AtomicBool::new(false))).await;
        assert!(matches!(run.outcome, Ok(DigestOutcome::Skipped(_))));
        assert!(calls.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_network_failure_in_the_middle_stops_the_chain_with_a_model_error() {
        let v = vault("orchestrator-network");
        let (backend, calls) = fake(|agent, nth| {
            if agent == "CÓDIGO" {
                Err(ModelError::new(ModelErrorKind::Network, "sin red"))
            } else {
                happy(agent, nth)
            }
        });
        let run = run_note_digest(&request(&v, "reuniones/2026-09-15.md"), &backend, Arc::new(AtomicBool::new(false))).await;
        assert!(matches!(run.outcome, Err(GenerateError::Model(ref e)) if e.kind == ModelErrorKind::Network));
        assert!(!calls.lock().unwrap().iter().any(|(a, _)| a == "REDACTOR"));
        assert!(run.trace.steps.iter().any(|s| s.agent == "code" && !s.ok));
    }

    #[tokio::test]
    async fn an_unreadable_critic_does_not_stop_the_synthesizer() {
        let v = vault("orchestrator-critic");
        let (backend, _) = fake(|agent, nth| {
            if agent == "CRÍTICO" {
                Ok("no se".to_string())
            } else {
                happy(agent, nth)
            }
        });
        let run = run_note_digest(&request(&v, "reuniones/2026-09-15.md"), &backend, Arc::new(AtomicBool::new(false))).await;
        assert!(matches!(run.outcome, Ok(DigestOutcome::Proposal(_))));
        assert!(!run.trace.requeried);
        assert!(run.trace.steps.iter().any(|s| s.agent == "critic" && !s.ok));
    }

    #[test]
    fn wikilink_targets_ignore_aliases_and_headings() {
        assert_eq!(
            wikilink_targets("ver [[temas/malla|la malla]] y [[ODM#decisiones]] y [[temas/malla]]"),
            vec!["temas/malla", "ODM"]
        );
    }
}
