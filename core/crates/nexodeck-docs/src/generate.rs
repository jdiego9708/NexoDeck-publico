//! Una propuesta de punta a punta: leer los documentos, preguntar al modelo,
//! validar y, si no pasa, devolverle los errores.

use std::collections::BTreeMap;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use nexodeck_ai::openai::types::ChatMessage;

use crate::apply::read_documents;
use crate::backend::{CompletionOptions, ModelBackend, ModelError};
use crate::config::{normalize_rel, DocProject};
use crate::context::build_context;
use crate::dates::SpanishDate;
use crate::error::DocsError;
use crate::model::{Finding, Proposal, ProposalOrigin, ProposalStatus, Unresolved};
use crate::parse::parse_output;
use crate::prompt::{repair_prompt, system_prompt, user_prompt};
use crate::validate::{validate_operations, Validated, ValidationInput};

/// Rondas extra en las que se le devuelven los errores al modelo. Dos alcanzan
/// para un ancla mal copiada; si a la tercera sigue sin salir, insistir solo
/// gasta tokens.
pub const REPAIR_ROUNDS: usize = 2;

pub struct GenerateRequest<'a> {
    pub project: &'a DocProject,
    pub findings: &'a [Finding],
    pub previous: Option<&'a Proposal>,
    pub note: Option<&'a str>,
    pub today: SpanishDate,
    pub now: jiff::Timestamp,
    pub proposal_id: String,
    pub revision: u32,
}

#[derive(Debug, thiserror::Error)]
pub enum GenerateError {
    #[error(transparent)]
    Model(#[from] ModelError),
    #[error("tras {} intentos la propuesta sigue sin pasar la validacion: {}", REPAIR_ROUNDS + 1, .0.join("; "))]
    Invalid(Vec<String>),
    /// El modelo no propuso nada y explico por que. No es un fallo del modelo:
    /// es informacion que le falta al hallazgo.
    #[error("ningun hallazgo encaja en los documentos: {}", .0.join("; "))]
    NothingToPropose(Vec<String>),
    #[error(transparent)]
    Docs(#[from] DocsError),
}

/// Lo que sale de una peticion de operaciones que ya paso la validacion.
pub(crate) struct Drafted {
    pub summary: String,
    pub validated: Validated,
    pub unresolved: Vec<Unresolved>,
}

pub async fn generate_proposal(
    request: &GenerateRequest<'_>,
    backend: &ModelBackend,
    cancel: Arc<AtomicBool>,
) -> Result<Proposal, GenerateError> {
    let project = request.project;
    let paths: Vec<String> = project
        .documents
        .iter()
        .map(|d| normalize_rel(&d.path))
        .collect();
    let snapshots = read_documents(project, paths.iter().map(String::as_str))?;
    let bodies: BTreeMap<String, String> = snapshots
        .iter()
        .map(|(path, snap)| (path.clone(), snap.document.body.clone()))
        .collect();
    let base_hashes: BTreeMap<String, String> = snapshots
        .iter()
        .map(|(path, snap)| (path.clone(), snap.hash.clone()))
        .collect();

    let context = build_context(project, &bodies, request.findings, backend.context_budget());
    let visible: BTreeMap<String, String> = context
        .iter()
        .map(|doc| (doc.path.clone(), doc.shown.clone()))
        .collect();

    let messages = vec![
        ChatMessage::system(system_prompt()),
        ChatMessage::user(user_prompt(
            project,
            request.today,
            request.findings,
            &context,
            request.previous,
            request.note,
        )),
    ];

    let known_ids: Vec<&str> = request.findings.iter().map(|f| f.id.as_str()).collect();
    let drafted = propose_with_repair(
        backend,
        CompletionOptions::default(),
        messages,
        &ValidationInput {
            project,
            bodies: &bodies,
            visible: Some(&visible),
            findings: request.findings,
            today: request.today,
        },
        &known_ids,
        cancel,
    )
    .await?;

    let now = request.now.to_string();
    Ok(Proposal {
        id: request.proposal_id.clone(),
        project: project.id.clone(),
        revision: request.revision,
        created_at: now.clone(),
        updated_at: now,
        finding_ids: known_ids.iter().map(|id| id.to_string()).collect(),
        origin: ProposalOrigin::Findings,
        from: request.findings.iter().find_map(|f| f.from.clone()),
        summary: drafted.summary,
        operations: drafted.validated.operations,
        unresolved: drafted.unresolved,
        warnings: drafted.validated.warnings,
        base_hashes,
        applied_hashes: BTreeMap::new(),
        model_label: backend.label().to_string(),
        local_model: backend.is_local(),
        status: ProposalStatus::Ready,
    })
}

/// Pide operaciones al modelo y, si no pasan la validacion, le devuelve los
/// errores hasta [`REPAIR_ROUNDS`] veces.
///
/// Lo comparten el buzon y el agente que redacta el digest de una nota: la regla
/// de "solo puedes tocar lo que viste" y la reparacion tienen que ser las mismas
/// para los dos, o una de las dos vias acabaria aceptando lo que la otra
/// rechaza.
pub(crate) async fn propose_with_repair(
    backend: &ModelBackend,
    options: CompletionOptions,
    mut messages: Vec<ChatMessage>,
    input: &ValidationInput<'_>,
    known_finding_ids: &[&str],
    cancel: Arc<AtomicBool>,
) -> Result<Drafted, GenerateError> {
    let mut last_errors = Vec::new();

    for round in 0..=REPAIR_ROUNDS {
        let text = backend
            .complete_with(messages.clone(), options, cancel.clone())
            .await?;

        let output = match parse_output(&text) {
            Ok(output) => output,
            Err(error) => {
                last_errors = vec![error];
                push_repair(&mut messages, text, &last_errors, round);
                continue;
            }
        };

        let unresolved: Vec<_> = output
            .unresolved
            .into_iter()
            .filter(|u| known_finding_ids.contains(&u.finding_id.as_str()))
            .collect();
        if output.operations.is_empty() && !unresolved.is_empty() {
            return Err(GenerateError::NothingToPropose(
                unresolved
                    .iter()
                    .map(|u| format!("{}: {}", u.finding_id, u.why))
                    .collect(),
            ));
        }

        match validate_operations(&output.operations, input) {
            Ok(validated) => {
                return Ok(Drafted {
                    summary: output.summary.trim().to_string(),
                    validated,
                    unresolved,
                })
            }
            Err(errors) => {
                last_errors = errors;
                push_repair(&mut messages, text, &last_errors, round);
            }
        }
    }

    Err(GenerateError::Invalid(last_errors))
}

fn push_repair(messages: &mut Vec<ChatMessage>, answer: String, errors: &[String], round: usize) {
    if round < REPAIR_ROUNDS {
        messages.push(ChatMessage::assistant_text(answer));
        messages.push(ChatMessage::user(repair_prompt(errors)));
    }
}
