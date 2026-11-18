//! Buzon de hallazgos de documentacion.
//!
//! Claude Code manda hallazgos por MCP ("manda los hallazgos a NexoDeck"), un
//! modelo los convierte en una **propuesta** de cambios a los documentos de un
//! proyecto, y el usuario la aprueba antes de que se escriba nada. Este crate es
//! el almacen, la configuracion de proyectos y todo lo que decide si una
//! propuesta se puede aplicar; el trabajador que llama al modelo va aparte.
//!
//! ## Rust es el dueño, no Drift
//!
//! Quien produce (el servidor MCP) y quien procesa (el trabajador) viven en Rust.
//! Guardarlo en Drift obligaria a empujar cada hallazgo a Dart y de vuelta, con
//! dos copias, y con la ventana en modo solo telefono Dart puede no estar
//! escuchando. Aca hay una sola fuente de verdad: ficheros JSON en el directorio
//! de datos, escritos de forma atomica. La UI pide una foto y la refresca.
//!
//! ## El modelo nunca escribe un fichero entero
//!
//! Una propuesta son operaciones pequeñas y verificables ([`Operation`]): insertar
//! una seccion arriba del diario, cambiar la fecha de actualizacion, reemplazar un
//! texto que aparece exactamente una vez, o añadir al final de una seccion. Las
//! posiciones las calcula Rust. Un documento de 8.000 lineas no cabe en el
//! contexto de un modelo, y reescribirlo entero es la forma segura de perder algo
//! que el modelo nunca vio.

mod apply;
mod backend;
mod config;
mod context;
mod dates;
mod error;
mod generate;
mod markdown;
mod model;
mod notes;
mod ops;
mod parse;
mod prompt;
mod redact;
mod service;
mod store;
mod validate;

pub use apply::{apply_to_disk, read_documents, undo_on_disk, ApplyError, FileSnapshot};
pub use backend::{
    live_candidates, CompletionOptions, FakeModel, ModelBackend, ModelError, ModelErrorKind,
};
pub use generate::{generate_proposal, GenerateError, GenerateRequest};
pub use service::{ApproveOutcome, Backends, DocsService, InboxSnapshot};
pub use config::{
    normalize_rel, vault_role, DocProject, DocRole, DocTarget, InboxConfig, NoteGroup, NotesConfig,
    ProjectKind, RemoteModel, DAILY_DIR, HUB_DIR, PRIVATE_SEGMENT,
};
pub use context::{build_context, build_note_context, DocumentContext};
pub use notes::{
    group_of, list_groups, parse_note, path_in_group, prepare_capture, recent_commits,
    sanitize_markdown, validate_color, validate_group_name, AgentStep, Blackboard,
    Candidate, CandidateKind, CandidateRef, CapturedNote, CommitInfo, DeleteOutcome, Digest,
    DigestStatus, DigestTrigger, EditableNote, IndexedNote,
    LinkTarget, MoveOutcome, NoteDetails, NoteGroupView, NoteSection, NoteStamp, RelinkedNote,
    SaveOutcome,
    NoteSummary, NoteTask, NotesIndex, NotesOverview, OpenTask, ParsedNote, RefreshStats,
    VaultManifest, CAPTURE_DIR, DEFAULT_GROUP_COLOR, TRASH_DIR,
};
pub use notes::{
    folder_problems, is_local_marker, link_form, local_prefix, locate, split_virtual,
    virtual_group_of, ExportOutcome, NoteFolderView, NoteRoot, LOCAL_PREFIX,
};
pub use redact::{redact, REDACTED};
pub use dates::SpanishDate;
pub use error::{DocsError, DocsResult};
pub use markdown::{headings, Document, Heading};
pub use model::{
    Evidence, EvidenceLabel, Finding, FindingKind, FindingStatus, NewFinding, Proposal,
    ProposalOrigin, ProposalStatus, ProposedOperation, Unresolved, MAX_FINDINGS_PER_CALL,
};
pub use ops::{apply_operation, preview, Operation, Preview, LAST_UPDATED_MARK};
pub use store::{sha256_hex, write_atomic, Inbox, SubmitOutcome};
pub use validate::{validate_operations, Validated, ValidationInput, DESTRUCTIVE_LINES};

#[cfg(test)]
pub(crate) mod test_support {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU32, Ordering};

    static COUNTER: AtomicU32 = AtomicU32::new(0);

    /// Directorio temporal propio de cada test. El pid y un contador evitan que
    /// dos tests del mismo binario, que corren en paralelo, se pisen.
    pub fn temp_dir(name: &str) -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "nexodeck-docs-{name}-{}-{n}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }
}
