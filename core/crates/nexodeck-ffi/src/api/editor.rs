//! La ventana de notas, vista desde Dart.
//!
//! Solo Windows: la ventana es WebView2. Las funciones existen en los tres
//! targets, como en `api/docs.rs`, y fuera de Windows contestan que no esta
//! disponible, para que Dart no tenga que preguntar la plataforma.
//!
//! La ventana es la app de notas entera (lista, tareas, asistente y editor).
//! Abrir una nota es sincrono solo hasta leerla: si no hay boveda o la ruta no
//! vale, el error vuelve a quien pulso el boton. La ventana se abre despues en el
//! hilo del editor, y lo que pase en ella llega por `watch_editor_events`.
//!
//! Editar no pasa por el buzon ni por la IA, pero si por su servicio: guardar
//! avisa por `watch_docs_inbox_events` igual que aprobar una propuesta. Ese mismo
//! aviso refresca la ventana (`watch_docs`).

use crate::frb_generated::StreamSink;

#[cfg(not(windows))]
const WINDOWS_ONLY: &str = "el editor de notas solo existe en Windows";

#[derive(Debug, Clone)]
pub struct EditorAvailability {
    pub available: bool,
    /// La version de WebView2 Runtime.
    pub version: Option<String>,
    pub reason: Option<String>,
}

/// Los colores del `ColorScheme` de la app, en `#RRGGBB`.
#[derive(Debug, Clone)]
pub struct EditorThemeDto {
    pub dark: bool,
    pub surface: String,
    pub surface_container: String,
    pub surface_container_high: String,
    pub on_surface: String,
    pub on_surface_variant: String,
    pub primary: String,
    pub on_primary: String,
    pub primary_container: String,
    pub outline_variant: String,
    pub error: String,
    pub tertiary: String,
}

#[derive(Debug, Clone)]
pub struct EditorEventItem {
    /// Nunca se repite: dos eventos iguales seguidos no pueden fundirse en uno.
    pub seq: u32,
    /// `opened`, `saved`, `conflict`, `closed`, `error` o `show_inbox`.
    pub kind: String,
    pub path: Option<String>,
    pub detail: Option<String>,
}

pub fn editor_availability() -> EditorAvailability {
    #[cfg(windows)]
    {
        let availability = nexodeck_editor::availability();
        EditorAvailability {
            available: availability.available,
            version: availability.version,
            reason: availability.reason,
        }
    }
    #[cfg(not(windows))]
    {
        EditorAvailability {
            available: false,
            version: None,
            reason: Some(WINDOWS_ONLY.to_string()),
        }
    }
}

/// Abre la ventana de notas (o la trae al frente) sin abrir ninguna nota.
pub fn open_notes_window(theme: EditorThemeDto) -> Result<(), String> {
    #[cfg(windows)]
    {
        imp::show(theme)
    }
    #[cfg(not(windows))]
    {
        let _ = theme;
        Err(WINDOWS_ONLY.to_string())
    }
}

/// Abre una nota de la boveda (tambien de `privado/`). Devuelve su ruta.
pub fn open_note_editor(path: String, theme: EditorThemeDto) -> Result<String, String> {
    #[cfg(windows)]
    {
        use nexodeck_editor::EditorBackend;
        imp::open(|backend| backend.open(&path), theme)
    }
    #[cfg(not(windows))]
    {
        let _ = (path, theme);
        Err(WINDOWS_ONLY.to_string())
    }
}

/// La nota de hoy (`diario/AAAA-MM-DD.md`), creada si falta.
pub fn open_daily_note_editor(theme: EditorThemeDto) -> Result<String, String> {
    #[cfg(windows)]
    {
        use nexodeck_editor::EditorBackend;
        imp::open(|backend| backend.daily(), theme)
    }
    #[cfg(not(windows))]
    {
        let _ = theme;
        Err(WINDOWS_ONLY.to_string())
    }
}

/// Crea una nota (o abre la que ya hay en esa ruta: crear nunca pisa).
pub fn create_note_editor(path: String, title: String, theme: EditorThemeDto) -> Result<String, String> {
    #[cfg(windows)]
    {
        use nexodeck_editor::EditorBackend;
        imp::open(|backend| backend.create(&path, &title), theme)
    }
    #[cfg(not(windows))]
    {
        let _ = (path, title, theme);
        Err(WINDOWS_ONLY.to_string())
    }
}

/// Lo que pasa en la ventana de notas. Se consume con **suscripcion directa al
/// `Stream`**, nunca con `ref.listen`. No arranca el editor: sin ventana abierta
/// simplemente no llega nada.
pub fn watch_editor_events(sink: StreamSink<EditorEventItem>) {
    #[cfg(windows)]
    {
        imp::subscribe(sink);
    }
    #[cfg(not(windows))]
    {
        let _ = sink;
    }
}

#[cfg(windows)]
mod imp {
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::{Arc, Mutex, MutexGuard};

    use nexodeck_docs::{
        Candidate, Digest, DigestStatus, DigestTrigger, EditableNote, NoteSummary, NoteTask, SaveOutcome,
    };
    use nexodeck_editor::{
        AgentStepDto, CandidateDto, DetailsDto, DigestDto, Editor, EditorBackend, EditorEvent, HitDto,
        FolderDto, GroupDto, NoteDto, NoteSummaryDto, OverviewDto, SaveResult, TaskDto, ThemeDto,
    };
    use tokio::sync::broadcast::error::RecvError;

    use super::{EditorEventItem, EditorThemeDto};
    use crate::frb_generated::StreamSink;

    static EDITOR: Mutex<Option<Arc<Editor>>> = Mutex::new(None);
    static SINKS: Mutex<Vec<StreamSink<EditorEventItem>>> = Mutex::new(Vec::new());
    static SEQ: AtomicU32 = AtomicU32::new(0);

    /// Cuantos resultados trae la busqueda de la barra lateral.
    const SEARCH_LIMIT: usize = 30;

    pub(super) fn show(theme: EditorThemeDto) -> Result<(), String> {
        editor()?.show(Some(theme_dto(theme)))
    }

    pub(super) fn open(
        read: impl FnOnce(&DocsBackend) -> Result<NoteDto, String>,
        theme: EditorThemeDto,
    ) -> Result<String, String> {
        let note = read(&DocsBackend)?;
        let path = note.path.clone();
        editor()?.open(note, Some(theme_dto(theme)))?;
        Ok(path)
    }

    pub(super) fn subscribe(sink: StreamSink<EditorEventItem>) {
        lock(&SINKS).push(sink);
    }

    /// El editor se arranca la primera vez que se abre la ventana, y vive el
    /// resto de la sesion: tao no deja crear un segundo event loop.
    fn editor() -> Result<Arc<Editor>, String> {
        let mut slot = lock(&EDITOR);
        if let Some(editor) = slot.as_ref() {
            return Ok(Arc::clone(editor));
        }
        let editor = Arc::new(Editor::start(Arc::new(DocsBackend), Arc::new(emit))?);
        watch_docs(&editor);
        *slot = Some(Arc::clone(&editor));
        Ok(editor)
    }

    /// Cada cambio del buzon (una nota guardada, un digest que avanza, una
    /// propuesta aprobada) refresca la ventana. En un hilo propio con
    /// `blocking_recv`: el editor no vive dentro de tokio.
    fn watch_docs(editor: &Arc<Editor>) {
        // Sin buzon no hay nada que vigilar; la ventana relee al recibir el foco.
        let Ok(service) = service() else { return };
        let mut events = service.subscribe();
        let editor = Arc::downgrade(editor);
        let _ = std::thread::Builder::new()
            .name("nexodeck-editor-docs".into())
            .spawn(move || {
                // Atrasarse no pierde nada: un aviso vale por todos. Se corta
                // con `Closed`, o cuando la ventana ya no esta.
                while let Ok(_) | Err(RecvError::Lagged(_)) = events.blocking_recv() {
                    match editor.upgrade() {
                        Some(editor) if editor.changed().is_ok() => {}
                        _ => break,
                    }
                }
            });
    }

    fn emit(event: EditorEvent) {
        let (kind, path, detail) = match event {
            EditorEvent::Opened { path } => ("opened", Some(path), None),
            EditorEvent::Saved { path, .. } => ("saved", Some(path), None),
            EditorEvent::Conflict { path } => ("conflict", Some(path), None),
            EditorEvent::Closed { path } => ("closed", path, None),
            EditorEvent::Error { detail } => ("error", None, Some(detail)),
            EditorEvent::ShowInbox => ("show_inbox", None, None),
        };
        let item = EditorEventItem {
            seq: SEQ.fetch_add(1, Ordering::Relaxed).wrapping_add(1),
            kind: kind.to_string(),
            path,
            detail,
        };
        // Un stream que Dart ya cerro se descarta al primer envio fallido.
        lock(&SINKS).retain(|sink| sink.add(item.clone()).is_ok());
    }

    fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
        mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn service() -> Result<Arc<nexodeck_docs::DocsService>, String> {
        crate::api::docs::service()
    }

    /// El resumen que imprime el conversor de OneNote, en una linea legible.
    fn summarize_import(stdout: &str, folder: &str) -> String {
        let count = |prefix: &str| {
            stdout
                .lines()
                .find_map(|line| line.strip_prefix(prefix))
                .and_then(|n| n.trim().parse::<u32>().ok())
                .unwrap_or(0)
        };
        let pages = count("Paginas a convertir: ");
        let images = count("Imagenes extraidas: ");
        format!("Importadas {pages} notas y {images} imágenes desde OneNote en {folder}.")
    }

    fn note(note: EditableNote) -> NoteDto {
        NoteDto {
            path: note.path,
            title: note.title,
            text: note.text,
            hash: Some(note.hash),
            private: note.private,
        }
    }

    fn theme_dto(theme: EditorThemeDto) -> ThemeDto {
        ThemeDto {
            dark: theme.dark,
            surface: theme.surface,
            surface_container: theme.surface_container,
            surface_container_high: theme.surface_container_high,
            on_surface: theme.on_surface,
            on_surface_variant: theme.on_surface_variant,
            primary: theme.primary,
            on_primary: theme.on_primary,
            primary_container: theme.primary_container,
            outline_variant: theme.outline_variant,
            error: theme.error,
            tertiary: theme.tertiary,
        }
    }

    fn count(value: usize) -> u32 {
        u32::try_from(value).unwrap_or(u32::MAX)
    }

    fn summary(s: NoteSummary) -> NoteSummaryDto {
        NoteSummaryDto {
            folder: nexodeck_docs::split_virtual(&s.path).0.map(str::to_string),
            path: s.path,
            group: s.group,
            title: s.title,
            role: s.role.as_str().to_string(),
            date: s.date,
            tags: s.tags,
            open_tasks: count(s.open_tasks),
            ai_excluded: s.ai_excluded,
            modified: s.modified,
        }
    }

    fn task(path: String, t: NoteTask) -> TaskDto {
        TaskDto {
            path,
            line: count(t.line),
            text: t.text,
            done: t.done,
            due: t.due,
        }
    }

    fn hit(c: Candidate) -> HitDto {
        HitDto {
            id: c.id,
            kind: c.kind.as_str().to_string(),
            title: c.title,
            snippet: c.snippet,
            date: c.date,
            path: c.path,
        }
    }

    fn digest(d: Digest) -> DigestDto {
        let (state, state_detail, proposal_id) = match d.status {
            DigestStatus::Queued => ("queued", None, None),
            DigestStatus::Running => ("running", None, None),
            DigestStatus::Proposed { proposal_id } => ("proposed", None, Some(proposal_id)),
            DigestStatus::Skipped { reason } => ("skipped", Some(reason), None),
            DigestStatus::Failed { reason } => ("failed", Some(reason), None),
            DigestStatus::WaitingModel { reason, .. } => ("waiting_model", Some(reason), None),
        };
        let trace = d.trace;
        DigestDto {
            id: d.id,
            note: d.note,
            trigger: d.trigger.as_str().to_string(),
            state: state.to_string(),
            state_detail,
            proposal_id,
            created_at: d.created_at,
            model_label: trace.model_label,
            hub: trace.hub,
            requeried: trace.requeried,
            discarded_ids: trace.discarded_ids,
            redactions: count(trace.redactions),
            candidates: trace
                .candidates
                .into_iter()
                .map(|c| CandidateDto {
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
                .map(|s| AgentStepDto {
                    agent: s.agent,
                    ok: s.ok,
                    millis: u32::try_from(s.millis).unwrap_or(u32::MAX),
                    output: s
                        .output
                        .map(|v| serde_json::to_string_pretty(&v).unwrap_or_default()),
                    detail: s.detail,
                })
                .collect(),
        }
    }

    /// La boveda del buzon.
    pub(super) struct DocsBackend;

    impl EditorBackend for DocsBackend {
        fn open(&self, path: &str) -> Result<NoteDto, String> {
            service()?
                .open_note_for_edit(path)
                .map(note)
                .map_err(|e| e.to_string())
        }

        fn save(&self, path: &str, text: &str, base_hash: Option<&str>) -> Result<SaveResult, String> {
            let outcome = service()?
                .save_note(path, text, base_hash)
                .map_err(|e| e.to_string())?;
            Ok(match outcome {
                SaveOutcome::Saved { hash } => SaveResult::Saved { hash },
                SaveOutcome::Conflict {
                    disk_text,
                    disk_hash,
                } => SaveResult::Conflict {
                    disk_text,
                    disk_hash,
                },
            })
        }

        fn create(&self, path: &str, title: &str) -> Result<NoteDto, String> {
            service()?
                .create_note(path, title, jiff::Timestamp::now())
                .map(note)
                .map_err(|e| e.to_string())
        }

        fn daily(&self) -> Result<NoteDto, String> {
            service()?
                .open_daily_note(jiff::Timestamp::now())
                .map(note)
                .map_err(|e| e.to_string())
        }

        fn overview(&self) -> Result<OverviewDto, String> {
            let service = service()?;
            let overview = service.notes_overview().map_err(|e| e.to_string())?;
            let configured = overview.vault_project.is_some();
            let digests = if configured {
                service.inbox().digests().map_err(|e| e.to_string())?
            } else {
                Vec::new()
            };
            Ok(OverviewDto {
                configured,
                root: overview.root,
                folders: overview
                    .folders
                    .into_iter()
                    .map(|f| FolderDto {
                        id: f.id,
                        name: f.name,
                        path: f.path,
                        local: f.local,
                        available: f.available,
                    })
                    .collect(),
                groups: overview
                    .groups
                    .into_iter()
                    .map(|g| GroupDto {
                        id: g.id,
                        name: g.name,
                        color_hex: g.color_hex,
                        notes: count(g.notes),
                    })
                    .collect(),
                notes: overview.notes.into_iter().map(summary).collect(),
                tasks: overview
                    .open_tasks
                    .into_iter()
                    .map(|t| task(t.path, t.task))
                    .collect(),
                digests: digests.into_iter().rev().map(digest).collect(),
                error: overview.error,
            })
        }

        fn search(&self, query: &str) -> Result<Vec<HitDto>, String> {
            let hits = service()?
                .search_notes(query, SEARCH_LIMIT)
                .map_err(|e| e.to_string())?;
            Ok(hits.into_iter().map(hit).collect())
        }

        fn details(&self, path: &str) -> Result<DetailsDto, String> {
            let details = service()?.note_details(path).map_err(|e| e.to_string())?;
            Ok(DetailsDto {
                path: details.summary.path,
                backlinks: details.backlinks,
                related: details.related.into_iter().map(hit).collect(),
                digests: details.digests.into_iter().rev().map(digest).collect(),
            })
        }

        fn digest(&self, path: &str) -> Result<DigestDto, String> {
            service()?
                .digest_note(path, DigestTrigger::Manual, jiff::Timestamp::now())
                .map(digest)
                .map_err(|e| e.to_string())
        }

        fn move_note(&self, path: &str, group: Option<&str>) -> Result<String, String> {
            let outcome = service()?
                .move_note(path, group, None)
                .map_err(|e| e.to_string())?;
            Ok(outcome.to)
        }

        fn set_vault_folder(&self, folder: &str) -> Result<String, String> {
            let view = service()?.set_vault_folder(folder).map_err(|e| e.to_string())?;
            Ok(format!("Espacio de NexoDeck: {}. No se copió nada.", view.path))
        }

        fn add_local_folder(&self, folder: &str) -> Result<String, String> {
            let view = service()?.add_local_folder(folder).map_err(|e| e.to_string())?;
            Ok(format!("«{}» añadida como notas locales. Se leen en su sitio, sin copiarse.", view.name))
        }

        fn remove_local_folder(&self, id: &str) -> Result<String, String> {
            let name = service()?.remove_local_folder(id).map_err(|e| e.to_string())?;
            Ok(format!("«{name}» ya no sale en NexoDeck. Sus ficheros siguen en el disco."))
        }

        fn export_vault(&self, destination: &str) -> Result<String, String> {
            let outcome = service()?
                .export_vault_zip(std::path::Path::new(destination))
                .map_err(|e| e.to_string())?;
            Ok(format!(
                "Exportadas {} notas en {} carpetas a {}.",
                outcome.notes, outcome.folders, outcome.path
            ))
        }

        fn import_onenote(&self, file: &str, folder: &str) -> Result<String, String> {
            // El conversor vive en `scripts/` (se puede correr a mano) y va
            // embebido: el binario no depende del repo.
            const SCRIPT: &str = include_str!("../../../../../scripts/onenote-import.ps1");
            let script = std::env::temp_dir().join("nexodeck-onenote-import.ps1");
            std::fs::write(&script, SCRIPT)
                .map_err(|e| format!("no se pudo preparar el conversor de OneNote: {e}"))?;
            let output = std::process::Command::new("powershell")
                .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
                .arg(&script)
                .arg("-InputOne")
                .arg(file)
                .arg("-OutputDir")
                .arg(folder)
                .output()
                .map_err(|e| format!("no se pudo ejecutar PowerShell: {e}"))?;
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(format!(
                    "La importación desde OneNote falló: {}",
                    stderr.trim()
                ));
            }
            let stdout = String::from_utf8_lossy(&output.stdout);
            Ok(summarize_import(&stdout, folder))
        }

        fn read_attachment(&self, note: &str, src: &str) -> Result<Option<(String, Vec<u8>)>, String> {
            service()?
                .read_attachment(note, src)
                .map_err(|e| e.to_string())
        }

        fn resolve_link(&self, target: &str, source: Option<&str>) -> Result<Option<String>, String> {
            service()?
                .resolve_note_link(target, source)
                .map_err(|e| e.to_string())
        }
    }
}
