//! El asistente de notas: leer la boveda y tener a mano lo que se relaciona con
//! cada nota (otras notas, hallazgos del buzon y commits).
//!
//! Aca no se llama a ningun modelo. Esto es lo que **Rust busca** para que los
//! agentes solo tengan que razonar sobre candidatos con id, y lo que permite
//! comprobar despues que todo lo que citan existe.

mod agents;
mod capture;
mod digest;
mod editing;
mod export;
mod folders;
mod groups;
mod roots;
mod git;
mod index;
mod orchestrator;
mod parse;
mod runner;
mod sync;

pub use capture::{prepare_capture, sanitize_markdown, CapturedNote, CAPTURE_DIR};
pub use groups::{
    group_of, list_groups, path_in_group, validate_color, validate_group_name, virtual_group_of,
    NoteGroupView, DEFAULT_GROUP_COLOR,
};
pub use roots::{
    folder_problems, is_local_marker, link_form, local_prefix, locate, split_virtual,
    NoteFolderView, NoteRoot, LOCAL_PREFIX,
};
pub use runner::{NoteDetails, NoteSummary, NotesOverview, NotesState, OpenTask};
pub use sync::{DeleteOutcome, NoteStamp, VaultManifest, TRASH_DIR};

pub use digest::{AgentStep, Blackboard, CandidateRef, Digest, DigestStatus, DigestTrigger};
pub use export::ExportOutcome;
pub use editing::{EditableNote, LinkTarget, MoveOutcome, RelinkedNote, SaveOutcome};
pub use git::{recent_commits, CommitInfo};
pub use index::{Candidate, CandidateKind, IndexedNote, NotesIndex, RefreshStats};
pub use parse::{parse_note, NoteSection, NoteTask, ParsedNote};
