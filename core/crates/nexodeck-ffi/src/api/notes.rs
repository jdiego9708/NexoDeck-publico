//! El asistente de notas, visto desde Dart.
//!
//! Vive en el mismo servicio que el buzon de documentacion (`api/docs.rs`): las
//! notas se procesan en su trabajador y sus propuestas se aprueban en su
//! bandeja. Por eso no hay un `init` ni un stream propios: lo que tiene que
//! estar inicializado es el buzon, y los avisos de `watch_docs_inbox_events`
//! valen tambien para las notas.
//!
//! Mismo criterio que `api/docs.rs`: solo escritorio con las firmas en los tres
//! targets, estados como texto, e ids, fechas y contadores como `String`/`u32`.

#[cfg(target_os = "android")]
const DESKTOP_ONLY: &str = "el asistente de notas es solo de escritorio";

#[derive(Debug, Clone)]
pub struct NotesOverviewItem {
    /// `false` si no hay boveda configurada en el buzon.
    pub configured: bool,
    pub vault_project: Option<String>,
    pub root: Option<String>,
    pub digest_on_idle: bool,
    /// De la tocada mas recientemente a la mas vieja.
    pub notes: Vec<NoteSummaryItem>,
    /// Las carpetas de notas: la boveda principal primero y despues las locales.
    pub folders: Vec<NoteFolderItem>,
    /// Las agrupaciones, ya ordenadas. Cada una es una carpeta de la boveda.
    pub groups: Vec<NoteGroupItem>,
    pub open_tasks: Vec<NoteTaskItem>,
    pub commits: u32,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteSummaryItem {
    pub path: String,
    /// El id de la carpeta local donde vive, o `None` si es de la boveda
    /// principal. Sale de la ruta en Rust para no parsear el `@` en tres
    /// lenguajes.
    pub folder: Option<String>,
    /// El id de su agrupacion (la carpeta), o `None` si esta en `inbox/`.
    pub group: Option<String>,
    pub title: String,
    /// `note`, `daily` o `hub`.
    pub role: String,
    pub date: Option<String>,
    pub tags: Vec<String>,
    pub open_tasks: u32,
    pub ai_excluded: bool,
    pub modified: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteTaskItem {
    pub path: String,
    /// Linea del fichero, desde 1.
    pub line: u32,
    pub text: String,
    pub done: bool,
    pub due: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct NoteSearchHit {
    /// `n:<ruta>#<seccion>`, `f:<hallazgo>` o `c:<repo>@<sha>`.
    pub id: String,
    /// `note`, `finding` o `commit`.
    pub kind: String,
    pub title: String,
    pub snippet: String,
    pub date: Option<String>,
    pub path: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteDetailsItem {
    pub summary: NoteSummaryItem,
    /// La ruta real del fichero, para abrirlo por fuera. Con una ruta virtual
    /// `@id/...` no se puede componer desde Dart.
    pub real_path: String,
    pub text: String,
    pub backlinks: Vec<String>,
    pub related: Vec<NoteSearchHit>,
    pub tasks: Vec<NoteTaskItem>,
    pub digests: Vec<NoteDigestItem>,
}

#[derive(Debug, Clone)]
pub struct NoteCandidateItem {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub snippet: String,
    pub date: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteAgentStepItem {
    /// `reader`, `memory`, `code`, `critic`, `synthesizer`, con `#2` si repitio.
    pub agent: String,
    pub ok: bool,
    pub millis: u32,
    /// Su salida ya verificada, en JSON legible.
    pub output_json: Option<String>,
    pub detail: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NoteDigestItem {
    pub id: String,
    pub project: String,
    pub note: String,
    /// `manual`, `idle` o `mcp`.
    pub trigger: String,
    pub created_at: String,
    pub updated_at: String,
    /// `queued`, `running`, `proposed`, `skipped`, `failed` o `waiting_model`.
    pub state: String,
    pub state_detail: Option<String>,
    pub proposal_id: Option<String>,
    pub retry_at: Option<String>,
    pub model_label: String,
    pub hub: Option<String>,
    pub requeried: bool,
    pub discarded_ids: Vec<String>,
    pub redactions: u32,
    pub candidates: Vec<NoteCandidateItem>,
    pub steps: Vec<NoteAgentStepItem>,
}

/// Notas, tareas abiertas y estado de la boveda. Sin boveda configurada no
/// falla: `configured` va en `false`.
pub fn notes_overview() -> Result<NotesOverviewItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let overview = super::docs::service()?
            .notes_overview()
            .map_err(|e| e.to_string())?;
        Ok(convert::overview(overview))
    }
    #[cfg(target_os = "android")]
    {
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Busca en notas, hallazgos y commits. Nunca devuelve una nota con `ai: false`.
pub fn search_notes(query: String, limit: u32) -> Result<Vec<NoteSearchHit>, String> {
    #[cfg(not(target_os = "android"))]
    {
        let hits = super::docs::service()?
            .search_notes(&query, limit as usize)
            .map_err(|e| e.to_string())?;
        Ok(hits.into_iter().map(convert::hit).collect())
    }
    #[cfg(target_os = "android")]
    {
        let _ = (query, limit);
        Err(DESKTOP_ONLY.to_string())
    }
}

pub fn note_details(path: String) -> Result<NoteDetailsItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let details = super::docs::service()?
            .note_details(&path)
            .map_err(|e| e.to_string())?;
        Ok(convert::details(details))
    }
    #[cfg(target_os = "android")]
    {
        let _ = path;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Manda procesar una nota. Solo encola: el resultado llega como propuesta en
/// el buzon, y los avisos de `watch_docs_inbox_events` dicen cuando.
pub fn digest_note(path: String) -> Result<NoteDigestItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let digest = super::docs::service()?
            .digest_note(
                &path,
                nexodeck_docs::DigestTrigger::Manual,
                jiff::Timestamp::now(),
            )
            .map_err(|e| e.to_string())?;
        Ok(convert::digest(digest))
    }
    #[cfg(target_os = "android")]
    {
        let _ = path;
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Todos los digests, del mas nuevo al mas viejo, con su traza.
pub fn note_digests() -> Result<Vec<NoteDigestItem>, String> {
    #[cfg(not(target_os = "android"))]
    {
        let digests = super::docs::service()?
            .inbox()
            .digests()
            .map_err(|e| e.to_string())?;
        Ok(digests.into_iter().rev().map(convert::digest).collect())
    }
    #[cfg(target_os = "android")]
    {
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Enciende o apaga el procesado automatico de notas quietas.
pub fn set_notes_digest_on_idle(enabled: bool) -> Result<(), String> {
    #[cfg(not(target_os = "android"))]
    {
        let service = super::docs::service()?;
        let mut config = service.inbox().config().map_err(|e| e.to_string())?;
        let Some(notes) = config.notes.as_mut() else {
            return Err(
                "no hay ninguna boveda configurada: añade \"notes\" en la configuracion del buzon"
                    .to_string(),
            );
        };
        notes.digest_on_idle = enabled;
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

/// Una carpeta de notas: la boveda principal o una carpeta local leida en su
/// sitio.
#[derive(Debug, Clone)]
pub struct NoteFolderItem {
    /// El id de su proyecto: lo que se pasa para mover o crear una agrupacion ahi.
    pub id: String,
    pub name: String,
    /// La ruta real en disco.
    pub path: String,
    pub local: bool,
    /// Existe ahora mismo. Una carpeta en un disco desconectado no enseña notas,
    /// y la interfaz tiene que poder decir por que.
    pub available: bool,
}

/// Una agrupacion de notas: una carpeta de la boveda con su nombre y su color.
#[derive(Debug, Clone)]
pub struct NoteGroupItem {
    /// El nombre de la carpeta. Es la identidad.
    pub id: String,
    pub name: String,
    /// `#RRGGBB`.
    pub color_hex: String,
    pub order: u32,
    pub notes: u32,
}

#[derive(Debug, Clone)]
pub struct NoteRelinkItem {
    pub path: String,
    pub links: u32,
}

/// Lo que paso al mover una nota: a donde fue y que otras notas se reescribieron
/// para que sus enlaces la siguieran.
#[derive(Debug, Clone)]
pub struct NoteMoveItem {
    pub from: String,
    /// Puede no ser la pedida: si ya habia una nota con ese nombre, se aparto.
    pub to: String,
    pub relinked: Vec<NoteRelinkItem>,
    pub digests: u32,
}

/// Crea una agrupacion, o le cambia el nombre y el color si ya existe.
///
/// Con `id` edita una que ya existe: `name` pasa a ser solo el nombre visible y
/// **la carpeta no se mueve**. Sin `id`, la carpeta se deriva del nombre.
///
/// `folder` es la carpeta de notas donde crearla (id de su proyecto); `None`, la
/// principal. Con `id` manda la carpeta que ya dice el `id`.
pub fn upsert_note_group(
    name: String,
    color_hex: Option<String>,
    id: Option<String>,
    folder: Option<String>,
) -> Result<NoteGroupItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let group = super::docs::service()?
            .upsert_note_group(&name, color_hex.as_deref(), id.as_deref(), folder.as_deref())
            .map_err(|e| e.to_string())?;
        Ok(convert::group(group))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (name, color_hex, id, folder);
        Err(DESKTOP_ONLY.to_string())
    }
}

/// Mueve una nota a otra agrupacion, o la devuelve a `inbox/` con `group` vacio.
///
/// **Mueve el fichero**: cada agrupacion es una carpeta. Lo que hace que eso no
/// rompa nada lo resuelve `DocsService::move_note` —enlaces por ruta, digests,
/// propuestas pendientes—, y lo que toco se devuelve para poder decirlo.
///
/// Con `folder` (id de la carpeta de destino) la mueve a otra carpeta de notas,
/// que puede estar en otro disco: se copia, se verifica y solo entonces se borra
/// el original.
pub fn move_note_to_group(
    path: String,
    group: Option<String>,
    folder: Option<String>,
) -> Result<NoteMoveItem, String> {
    #[cfg(not(target_os = "android"))]
    {
        let outcome = super::docs::service()?
            .move_note(&path, group.as_deref(), folder.as_deref())
            .map_err(|e| e.to_string())?;
        Ok(convert::moved(outcome))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (path, group, folder);
        Err(DESKTOP_ONLY.to_string())
    }
}

#[cfg(not(target_os = "android"))]
mod convert {
    use super::*;
    use nexodeck_docs::{
        Candidate, Digest, DigestStatus, MoveOutcome, NoteDetails, NoteFolderView, NoteGroupView,
        NoteSummary, NoteTask, NotesOverview,
    };

    pub(super) fn overview(o: NotesOverview) -> NotesOverviewItem {
        NotesOverviewItem {
            configured: o.vault_project.is_some(),
            vault_project: o.vault_project,
            root: o.root,
            digest_on_idle: o.digest_on_idle,
            notes: o.notes.into_iter().map(summary).collect(),
            folders: o.folders.into_iter().map(folder).collect(),
            groups: o.groups.into_iter().map(group).collect(),
            open_tasks: o
                .open_tasks
                .into_iter()
                .map(|t| task(t.path, t.task))
                .collect(),
            commits: u32::try_from(o.commits).unwrap_or(u32::MAX),
            error: o.error,
        }
    }

    fn summary(s: NoteSummary) -> NoteSummaryItem {
        NoteSummaryItem {
            folder: nexodeck_docs::split_virtual(&s.path).0.map(str::to_string),
            path: s.path,
            group: s.group,
            title: s.title,
            role: s.role.as_str().to_string(),
            date: s.date,
            tags: s.tags,
            open_tasks: u32::try_from(s.open_tasks).unwrap_or(u32::MAX),
            ai_excluded: s.ai_excluded,
            modified: s.modified,
        }
    }

    fn folder(f: NoteFolderView) -> NoteFolderItem {
        NoteFolderItem {
            id: f.id,
            name: f.name,
            path: f.path,
            local: f.local,
            available: f.available,
        }
    }

    pub(super) fn group(g: NoteGroupView) -> NoteGroupItem {
        NoteGroupItem {
            id: g.id,
            name: g.name,
            color_hex: g.color_hex,
            order: g.order,
            notes: u32::try_from(g.notes).unwrap_or(u32::MAX),
        }
    }

    pub(super) fn moved(m: MoveOutcome) -> NoteMoveItem {
        NoteMoveItem {
            from: m.from,
            to: m.to,
            relinked: m
                .relinked
                .into_iter()
                .map(|r| NoteRelinkItem {
                    path: r.path,
                    links: u32::try_from(r.links).unwrap_or(u32::MAX),
                })
                .collect(),
            digests: u32::try_from(m.digests).unwrap_or(u32::MAX),
        }
    }

    fn task(path: String, t: NoteTask) -> NoteTaskItem {
        NoteTaskItem {
            path,
            line: u32::try_from(t.line).unwrap_or(u32::MAX),
            text: t.text,
            done: t.done,
            due: t.due,
            tags: t.tags,
        }
    }

    pub(super) fn hit(c: Candidate) -> NoteSearchHit {
        NoteSearchHit {
            id: c.id,
            kind: c.kind.as_str().to_string(),
            title: c.title,
            snippet: c.snippet,
            date: c.date,
            path: c.path,
        }
    }

    pub(super) fn details(d: NoteDetails) -> NoteDetailsItem {
        let path = d.summary.path.clone();
        NoteDetailsItem {
            real_path: d.real_path,
            summary: summary(d.summary),
            text: d.text,
            backlinks: d.backlinks,
            related: d.related.into_iter().map(hit).collect(),
            tasks: d.tasks.into_iter().map(|t| task(path.clone(), t)).collect(),
            digests: d.digests.into_iter().rev().map(digest).collect(),
        }
    }

    pub(super) fn digest(d: Digest) -> NoteDigestItem {
        let (state, detail, proposal_id, retry_at) = match d.status {
            DigestStatus::Queued => ("queued", None, None, None),
            DigestStatus::Running => ("running", None, None, None),
            DigestStatus::Proposed { proposal_id } => ("proposed", None, Some(proposal_id), None),
            DigestStatus::Skipped { reason } => ("skipped", Some(reason), None, None),
            DigestStatus::Failed { reason } => ("failed", Some(reason), None, None),
            DigestStatus::WaitingModel {
                reason, retry_at, ..
            } => ("waiting_model", Some(reason), None, retry_at),
        };
        let trace = d.trace;
        NoteDigestItem {
            id: d.id,
            project: d.project,
            note: d.note,
            trigger: d.trigger.as_str().to_string(),
            created_at: d.created_at,
            updated_at: d.updated_at,
            state: state.to_string(),
            state_detail: detail,
            proposal_id,
            retry_at,
            model_label: trace.model_label,
            hub: trace.hub,
            requeried: trace.requeried,
            discarded_ids: trace.discarded_ids,
            redactions: u32::try_from(trace.redactions).unwrap_or(u32::MAX),
            candidates: trace
                .candidates
                .into_iter()
                .map(|c| NoteCandidateItem {
                    id: c.id,
                    kind: c.kind,
                    title: c.title,
                    snippet: c.snippet,
                    date: c.date,
                })
                .collect(),
            steps: trace
                .steps
                .into_iter()
                .map(|s| NoteAgentStepItem {
                    agent: s.agent,
                    ok: s.ok,
                    millis: u32::try_from(s.millis).unwrap_or(u32::MAX),
                    output_json: s
                        .output
                        .map(|v| serde_json::to_string_pretty(&v).unwrap_or_default()),
                    detail: s.detail,
                })
                .collect(),
        }
    }
}
