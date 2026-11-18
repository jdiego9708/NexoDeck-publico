//! El digest de una nota tal como se guarda: en que estado esta y que hizo cada
//! agente para llegar a la propuesta.
//!
//! La traza no es decoracion. Una propuesta que dice "esto ya se hablo el 3-sep"
//! solo se puede creer si se puede ver de donde lo saco: que buscó Rust, que
//! candidatos le enseñó a cada agente y que citas se descartaron por no existir.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum DigestStatus {
    Queued,
    Running,
    Proposed {
        proposal_id: String,
    },
    /// No habia nada que procesar: la nota esta vacia o es demasiado corta. No es
    /// un fallo, y no se reintenta.
    Skipped {
        reason: String,
    },
    Failed {
        reason: String,
    },
    /// Sin modelo disponible, o un fallo pasajero. Se reintenta sola a partir de
    /// `retry_at`, con la misma escalera que los hallazgos.
    WaitingModel {
        reason: String,
        #[serde(default)]
        retry_at: Option<String>,
        #[serde(default)]
        attempts: u32,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DigestTrigger {
    /// El usuario pulso "Procesar nota".
    Manual,
    /// La nota llevaba un rato sin cambios y `digest_on_idle` esta encendido.
    Idle,
    /// Lo pidio una sesion de Claude Code por MCP.
    Mcp,
}

impl DigestTrigger {
    pub fn as_str(&self) -> &'static str {
        match self {
            DigestTrigger::Manual => "manual",
            DigestTrigger::Idle => "idle",
            DigestTrigger::Mcp => "mcp",
        }
    }
}

/// Un candidato tal como se le enseño a los agentes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CandidateRef {
    pub id: String,
    /// `note`, `finding` o `commit`.
    pub kind: String,
    pub title: String,
    pub snippet: String,
    #[serde(default)]
    pub date: Option<String>,
}

/// Lo que hizo un agente.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentStep {
    /// `reader`, `memory`, `code`, `critic` o `synthesizer`, con `#2` si repitio.
    pub agent: String,
    pub ok: bool,
    pub millis: u64,
    /// Su salida ya verificada: sin las citas a ids que no existian.
    #[serde(default)]
    pub output: Option<Value>,
    /// Por que fallo, o por que no hizo falta llamarlo.
    #[serde(default)]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Blackboard {
    #[serde(default)]
    pub model_label: String,
    /// La nota de proyecto que se cruzo con la nota, si la habia.
    #[serde(default)]
    pub hub: Option<String>,
    #[serde(default)]
    pub candidates: Vec<CandidateRef>,
    #[serde(default)]
    pub steps: Vec<AgentStep>,
    /// El Critico pidio buscar mas. Pasa como mucho una vez.
    #[serde(default)]
    pub requeried: bool,
    /// Ids que algun agente cito y que no estaban entre sus candidatos.
    #[serde(default)]
    pub discarded_ids: Vec<String>,
    /// Cuantos secretos se quitaron antes de mandar nada al modelo.
    #[serde(default)]
    pub redactions: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Digest {
    pub id: String,
    pub project: String,
    /// Ruta de la nota dentro de la boveda.
    pub note: String,
    pub trigger: DigestTrigger,
    /// RFC 3339 en UTC.
    pub created_at: String,
    pub updated_at: String,
    pub status: DigestStatus,
    /// sha256 de la nota cuando se proceso: si no cambio, no hay que volver a
    /// procesarla sola.
    #[serde(default)]
    pub note_hash: Option<String>,
    /// sha256 de la nota despues de aplicar la propuesta. Sin esto, aprobar un
    /// digest cambiaria la nota y el modo automatico la volveria a procesar, en
    /// bucle.
    #[serde(default)]
    pub settled_hash: Option<String>,
    #[serde(default)]
    pub trace: Blackboard,
}

impl Digest {
    /// Todavia puede acabar en una propuesta.
    pub fn is_active(&self) -> bool {
        matches!(
            self.status,
            DigestStatus::Queued | DigestStatus::Running | DigestStatus::WaitingModel { .. }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_digest_round_trips_and_old_files_without_trace_still_load() {
        let json = r#"{"id":"d-1","project":"notas","note":"diario/2026-09-15.md","trigger":"manual","created_at":"x","updated_at":"x","status":{"state":"queued"}}"#;
        let digest: Digest = serde_json::from_str(json).unwrap();
        assert!(digest.is_active());
        assert!(digest.trace.steps.is_empty());

        let back = serde_json::to_string(&digest).unwrap();
        assert_eq!(serde_json::from_str::<Digest>(&back).unwrap(), digest);
    }

    #[test]
    fn statuses_serialize_with_a_state_tag() {
        let json = serde_json::to_string(&DigestStatus::Proposed {
            proposal_id: "p-1".into(),
        })
        .unwrap();
        assert_eq!(json, r#"{"state":"proposed","proposal_id":"p-1"}"#);
    }
}
