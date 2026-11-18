//! Hallazgos y propuestas, tal como se guardan en disco.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::config::DocRole;
use crate::dates::SpanishDate;
use crate::ops::{Operation, Preview};

pub const MAX_FINDINGS_PER_CALL: usize = 20;
const MAX_TITLE_CHARS: usize = 120;
const MAX_BODY_CHARS: usize = 4_000;
const MAX_EVIDENCE_CHARS: usize = 1_000;
const MAX_SUPERSEDES_CHARS: usize = 2_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FindingKind {
    Measurement,
    Decision,
    Bug,
    Change,
    Correction,
    OpenQuestion,
}

impl FindingKind {
    pub const ALL: [&'static str; 6] = [
        "measurement",
        "decision",
        "bug",
        "change",
        "correction",
        "open_question",
    ];
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EvidenceLabel {
    /// Medido: tiene que decir de donde sale.
    M,
    /// Supuesto.
    S,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Evidence {
    pub label: EvidenceLabel,
    pub text: String,
    /// Ruta:linea, commit, comando o log. Obligatorio en las medidas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

/// Un hallazgo tal como lo manda Claude Code.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NewFinding {
    pub kind: FindingKind,
    pub title: String,
    pub body: String,
    pub evidence: Vec<Evidence>,
    /// Cita literal de lo que deja de ser cierto en el documento.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supersedes: Option<String>,
    /// `YYYY-MM-DD`. Si falta, es de hoy.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub date: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_hint: Option<DocRole>,
}

impl NewFinding {
    /// Lo que impide guardarlo. Vacio si esta bien.
    pub fn problems(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let title = self.title.trim();
        if title.is_empty() {
            problems.push("falta 'title'".to_string());
        } else if title.chars().count() > MAX_TITLE_CHARS {
            problems.push(format!("'title' pasa de {MAX_TITLE_CHARS} caracteres"));
        }
        if self.body.trim().is_empty() {
            problems.push("falta 'body'".to_string());
        } else if self.body.chars().count() > MAX_BODY_CHARS {
            problems.push(format!(
                "'body' pasa de {MAX_BODY_CHARS} caracteres: parte el hallazgo en varios"
            ));
        }
        if self.evidence.is_empty() {
            problems.push(
                "no trae evidencia: cada hallazgo necesita al menos una, [M] medida con 'source' o [S] supuesta"
                    .to_string(),
            );
        }
        for (i, evidence) in self.evidence.iter().enumerate() {
            if evidence.text.trim().is_empty() {
                problems.push(format!("evidencia {}: falta 'text'", i + 1));
            }
            if evidence.text.chars().count() > MAX_EVIDENCE_CHARS {
                problems.push(format!(
                    "evidencia {}: pasa de {MAX_EVIDENCE_CHARS} caracteres",
                    i + 1
                ));
            }
            let has_source = evidence
                .source
                .as_deref()
                .is_some_and(|s| !s.trim().is_empty());
            if evidence.label == EvidenceLabel::M && !has_source {
                problems.push(format!(
                    "evidencia {}: una medida [M] necesita 'source' (ruta:linea, commit, comando o log); si no se puede citar, es [S]",
                    i + 1
                ));
            }
        }
        if self
            .supersedes
            .as_deref()
            .is_some_and(|s| s.chars().count() > MAX_SUPERSEDES_CHARS)
        {
            problems.push(format!(
                "'supersedes' pasa de {MAX_SUPERSEDES_CHARS} caracteres"
            ));
        }
        if let Some(date) = &self.date {
            if SpanishDate::parse_iso(date).is_none() {
                problems.push(format!("'date' tiene que ser YYYY-MM-DD, llego {date:?}"));
            }
        }
        problems
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum FindingStatus {
    Queued,
    Proposing,
    Proposed { proposal_id: String },
    Applied { proposal_id: String },
    Rejected {
        proposal_id: String,
        #[serde(default)]
        note: Option<String>,
    },
    Failed { reason: String },
    /// No habia modelo disponible, o fallo por algo pasajero (red, limite de
    /// peticiones). Vuelve a intentarse sola a partir de `retry_at`.
    WaitingModel {
        reason: String,
        #[serde(default)]
        retry_at: Option<String>,
        #[serde(default)]
        attempts: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Finding {
    pub id: String,
    pub batch_id: String,
    pub project: String,
    #[serde(default)]
    pub from: Option<String>,
    /// RFC 3339 en UTC.
    pub created_at: String,
    /// Proyecto + titulo + cuerpo. Es lo que detecta un reenvio del cliente.
    pub content_hash: String,
    pub content: NewFinding,
    pub status: FindingStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProposedOperation {
    pub operation: Operation,
    pub preview: Preview,
    /// Borra muchas lineas. No se bloquea --lo que deja de ser cierto se borra--,
    /// pero la UI lo pinta en rojo.
    pub destructive: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Unresolved {
    pub finding_id: String,
    pub why: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum ProposalStatus {
    Ready,
    /// El documento cambio desde la propuesta pero las operaciones siguen
    /// aplicando. **Hay que volver a enseñarla**: nunca se aplica a ciegas.
    NeedsReview { reason: String },
    /// El documento cambio y alguna operacion ya no aplica.
    Stale { reasons: Vec<String> },
    Applied,
    Rejected {
        #[serde(default)]
        note: Option<String>,
    },
    Failed { reason: String },
    Undone,
}

/// De donde sale una propuesta.
///
/// El buzon nacio solo con hallazgos, y las propuestas que ya estan en disco no
/// traen este campo: por eso el valor por defecto es `Findings`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ProposalOrigin {
    /// Hallazgos que mando Claude Code, listados en `finding_ids`.
    #[default]
    Findings,
    /// El digest de una nota de la boveda. `digest_id` apunta a la traza de los
    /// agentes que la prepararon.
    NoteDigest { note: String, digest_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Proposal {
    pub id: String,
    pub project: String,
    pub revision: u32,
    pub created_at: String,
    pub updated_at: String,
    /// Vacio en una propuesta que no sale de hallazgos.
    pub finding_ids: Vec<String>,
    #[serde(default)]
    pub origin: ProposalOrigin,
    #[serde(default)]
    pub from: Option<String>,
    pub summary: String,
    pub operations: Vec<ProposedOperation>,
    #[serde(default)]
    pub unresolved: Vec<Unresolved>,
    #[serde(default)]
    pub warnings: Vec<String>,
    /// sha256 de cada fichero cuando se genero la propuesta.
    pub base_hashes: BTreeMap<String, String>,
    /// sha256 de cada fichero justo despues de aplicar. Sirve para deshacer
    /// solo si nadie lo toco despues.
    #[serde(default)]
    pub applied_hashes: BTreeMap<String, String>,
    pub model_label: String,
    /// Generada con el modelo local: la UI pide revisarla con mas cuidado.
    #[serde(default)]
    pub local_model: bool,
    pub status: ProposalStatus,
}

impl Proposal {
    /// Esperando decision del usuario.
    pub fn is_pending(&self) -> bool {
        matches!(
            self.status,
            ProposalStatus::Ready | ProposalStatus::NeedsReview { .. } | ProposalStatus::Stale { .. }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn finding(evidence: Vec<Evidence>) -> NewFinding {
        NewFinding {
            kind: FindingKind::Measurement,
            title: "La deteccion va 3,5 veces mas rapido".into(),
            body: "Q entera paso de 1.652 s a 474 s.".into(),
            evidence,
            supersedes: None,
            date: None,
            target_hint: None,
        }
    }

    #[test]
    fn a_finding_without_evidence_is_refused() {
        let problems = finding(vec![]).problems();
        assert!(problems.iter().any(|p| p.contains("evidencia")));
    }

    #[test]
    fn a_measurement_needs_a_source_but_an_assumption_does_not() {
        let measured = finding(vec![Evidence {
            label: EvidenceLabel::M,
            text: "474 s".into(),
            source: None,
        }]);
        assert!(measured.problems().iter().any(|p| p.contains("source")));

        let assumed = finding(vec![Evidence {
            label: EvidenceLabel::S,
            text: "deberia escalar igual".into(),
            source: None,
        }]);
        assert!(assumed.problems().is_empty());
    }

    #[test]
    fn a_bad_date_is_reported() {
        let mut f = finding(vec![Evidence {
            label: EvidenceLabel::S,
            text: "x".into(),
            source: None,
        }]);
        f.date = Some("15/09/2026".into());
        assert!(f.problems().iter().any(|p| p.contains("YYYY-MM-DD")));
    }

    #[test]
    fn a_proposal_saved_before_origin_existed_reads_as_findings() {
        let json = r#"{"id":"p-1","project":"ia","revision":1,"created_at":"x","updated_at":"x","finding_ids":["f-1"],"summary":"s","operations":[],"base_hashes":{},"model_label":"m","status":{"state":"ready"}}"#;
        let proposal: Proposal = serde_json::from_str(json).unwrap();
        assert_eq!(proposal.origin, ProposalOrigin::Findings);
    }

    #[test]
    fn a_note_digest_origin_serializes_with_a_kind_tag() {
        let json = serde_json::to_string(&ProposalOrigin::NoteDigest {
            note: "diario/2026-09-15.md".into(),
            digest_id: "d-1".into(),
        })
        .unwrap();
        assert_eq!(
            json,
            r#"{"kind":"note_digest","note":"diario/2026-09-15.md","digest_id":"d-1"}"#
        );
    }

    #[test]
    fn statuses_serialize_with_a_state_tag() {
        let json = serde_json::to_string(&FindingStatus::Proposed {
            proposal_id: "p-1".into(),
        })
        .unwrap();
        assert_eq!(json, r#"{"state":"proposed","proposal_id":"p-1"}"#);
    }
}
