//! Lo que hace la ventana de notas con cada cosa que pasa, sin ventana de por medio.
//!
//! La ventana y el WebView solo existen en Windows y no se pueden probar sin
//! escritorio; la logica si. `Session` recibe lo que pasa (un mensaje de la
//! pagina, abrir otra nota, la X de la ventana, un cambio en el buzon) y
//! devuelve los efectos que `host.rs` aplica. Asi el guardado, el conflicto, el
//! cierre y las lecturas de la boveda se prueban con un backend falso.
//!
//! Reglas que no son obvias:
//!
//! - **Nada se pierde al cerrar ni al cambiar de nota.** Si la pagina tiene
//!   cambios, se le pide que guarde (`requestClose`) y solo cuando contesta
//!   `closeReady` se cierra o se carga la otra nota.
//! - **Una pagina colgada no deja la ventana abierta para siempre**: una segunda
//!   X pasados unos segundos cierra sin esperar respuesta.
//! - **Lo lento va en otro hilo** (`Effect::Fetch`): la foto de la boveda, la
//!   busqueda, el detalle y el digest recorren el indice y a veces corren
//!   `git log`. En el hilo de la ventana la congelarian.
//! - **Las lecturas de la boveda no se amontonan.** Cada guardado avisa de un
//!   cambio; con una lectura en marcha se apunta que hace falta otra y se hace
//!   una sola al terminar.

use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::assets::is_external_url;
use crate::backend::{EditorBackend, EditorEvent, SaveResult};
use crate::protocol::{
    DetailsDto, DigestDto, HitDto, HostMessage, LinkTargetDto, NoteDto, OverviewDto, PageMessage,
    SaveReason, ThemeDto,
};

/// Una X pasado este tiempo desde la primera cierra aunque la pagina no conteste.
pub(crate) const FORCE_CLOSE_AFTER: Duration = Duration::from_secs(5);

/// Cada cuanto, como mucho, se vuelve a leer la boveda al volver a la ventana:
/// una nota creada en Obsidian tiene que aparecer sin cerrar nada.
pub(crate) const OVERVIEW_EVERY: Duration = Duration::from_secs(20);

/// Un trabajo lento, para otro hilo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Job {
    Overview,
    Search(String),
    Details(String),
    Digest(String),
    SetVault(String),
    AddLocalFolder(String),
    RemoveLocalFolder(String),
    Export(String),
    /// Importar un cuaderno de OneNote (`.one`) a markdown en [folder].
    ImportOneNote { file: String, folder: String },
}

/// Un dialogo nativo que tiene que abrir la ventana: elegir carpeta o donde
/// guardar. Lo abre `host.rs`, que tiene la ventana para hacerlo modal, y lo
/// elegido vuelve con [`Session::picked`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Pick {
    Vault,
    LocalFolder,
    ExportZip { file_name: String },
    /// El `.one` a importar; despues se pide la carpeta de destino.
    OneNoteFile,
    /// La carpeta de destino, con el `.one` ya elegido.
    OneNoteFolder { file: String },
}

/// El resultado de un [`Job`], con lo que se pidio.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Fetched {
    Overview(Result<OverviewDto, String>),
    Search(String, Result<Vec<HitDto>, String>),
    Details(String, Result<DetailsDto, String>),
    Digest(String, Result<DigestDto, String>),
    /// Cambiar carpetas o exportar: el aviso para el usuario, o el motivo.
    Folders(Result<String, String>),
}

pub(crate) fn run_job(backend: &dyn EditorBackend, job: Job) -> Fetched {
    match job {
        Job::SetVault(folder) => Fetched::Folders(backend.set_vault_folder(&folder)),
        Job::AddLocalFolder(folder) => Fetched::Folders(backend.add_local_folder(&folder)),
        Job::RemoveLocalFolder(id) => Fetched::Folders(backend.remove_local_folder(&id)),
        Job::Export(destination) => Fetched::Folders(backend.export_vault(&destination)),
        Job::ImportOneNote { file, folder } => Fetched::Folders(backend.import_onenote(&file, &folder)),
        Job::Overview => Fetched::Overview(backend.overview()),
        Job::Search(query) => {
            let hits = backend.search(&query);
            Fetched::Search(query, hits)
        }
        Job::Details(path) => {
            let details = backend.details(&path);
            Fetched::Details(path, details)
        }
        Job::Digest(path) => {
            let digest = backend.digest(&path);
            Fetched::Digest(path, digest)
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Effect {
    /// Entregar un mensaje a la pagina.
    Send(HostMessage),
    Title(String),
    /// Traer la ventana al frente.
    Focus,
    /// El tema de la barra de titulo.
    Theme(ThemeDto),
    Fetch(Job),
    Pick(Pick),
    OpenExternal(String),
    Destroy,
    Emit(EditorEvent),
}

struct Current {
    path: String,
    title: String,
}

pub(crate) struct Session {
    backend: Arc<dyn EditorBackend>,
    /// La pagina ya cargo y escucha. Antes, los mensajes esperan en `queue`.
    ready: bool,
    queue: Vec<HostMessage>,
    current: Option<Current>,
    dirty: bool,
    theme: Option<ThemeDto>,
    targets: Vec<LinkTargetDto>,
    overview_at: Option<Instant>,
    overview_busy: bool,
    overview_again: bool,
    /// Una nota que se abrira cuando la pagina termine de guardar la actual.
    pending_open: Option<NoteDto>,
    /// Cuando se pidio cerrar por primera vez sin respuesta.
    close_asked: Option<Instant>,
}

impl Session {
    pub(crate) fn new(backend: Arc<dyn EditorBackend>) -> Self {
        Session {
            backend,
            ready: false,
            queue: Vec::new(),
            current: None,
            dirty: false,
            theme: None,
            targets: Vec::new(),
            overview_at: None,
            overview_busy: false,
            overview_again: false,
            pending_open: None,
            close_asked: None,
        }
    }

    /// Traer la ventana sin abrir ninguna nota: el boton "Notas" de la app.
    pub(crate) fn show(&mut self, theme: Option<ThemeDto>, now: Instant) -> Vec<Effect> {
        let mut effects = vec![Effect::Focus];
        if let Some(theme) = theme {
            effects.extend(self.set_theme(theme));
        }
        effects.push(self.title());
        effects.extend(self.refresh_if_stale(now));
        effects
    }

    /// Abrir una nota desde la app.
    pub(crate) fn open(&mut self, note: NoteDto, theme: Option<ThemeDto>, now: Instant) -> Vec<Effect> {
        let mut effects = vec![Effect::Focus];
        if let Some(theme) = theme {
            effects.extend(self.set_theme(theme));
        }
        effects.extend(self.navigate(note, now));
        effects
    }

    pub(crate) fn set_theme(&mut self, theme: ThemeDto) -> Vec<Effect> {
        if self.theme.as_ref() == Some(&theme) {
            return Vec::new();
        }
        self.theme = Some(theme.clone());
        let mut effects = vec![Effect::Theme(theme.clone())];
        effects.extend(self.send(HostMessage::Theme { theme }));
        effects
    }

    /// Algo cambio en el buzon: una nota guardada, un digest que avanza, una
    /// propuesta aprobada.
    pub(crate) fn changed(&mut self, now: Instant) -> Vec<Effect> {
        let mut effects = self.fetch_overview(now);
        if let Some(path) = self.current_path() {
            effects.push(Effect::Fetch(Job::Details(path)));
        }
        effects
    }

    /// Mueve una nota y refresca la barra lateral. Si era la nota abierta, se
    /// reabre en su nueva ruta (guardando antes si estaba sin guardar, igual que
    /// al cambiar de nota).
    fn move_note(&mut self, path: String, group: Option<String>, now: Instant) -> Vec<Effect> {
        match self.backend.move_note(&path, group.as_deref()) {
            Ok(to) => {
                let mut effects = self.fetch_overview(now);
                if self.current_path().as_deref() == Some(path.as_str()) {
                    effects.extend(self.navigate_or_fail(self.backend.open(&to), now));
                }
                effects
            }
            Err(message) => self.send(HostMessage::Error { message }),
        }
    }

    pub(crate) fn focused(&mut self, now: Instant) -> Vec<Effect> {
        self.refresh_if_stale(now)
    }

    pub(crate) fn page(&mut self, message: PageMessage, now: Instant) -> Vec<Effect> {
        match message {
            PageMessage::Ready => self.ready(now),
            PageMessage::Save {
                path,
                text,
                base_hash,
                reason,
            } => self.save(path, &text, base_hash.as_deref(), reason),
            PageMessage::Dirty { dirty } => {
                self.dirty = dirty;
                vec![self.title()]
            }
            PageMessage::OpenLink { target } => self.open_link(&target, now),
            PageMessage::OpenExternal { url } => {
                if is_external_url(&url) {
                    vec![Effect::OpenExternal(url)]
                } else {
                    log::warn!("la pagina pidio abrir un enlace que no es web");
                    Vec::new()
                }
            }
            PageMessage::CloseReady => match self.pending_open.take() {
                Some(note) => self.load(note, now),
                None => self.destroy(),
            },
            PageMessage::OpenNote { path } => {
                if self.current_path().as_deref() == Some(path.as_str()) {
                    return Vec::new();
                }
                let opened = self.backend.open(&path);
                self.navigate_or_fail(opened, now)
            }
            PageMessage::CreateNote { path, title } => {
                let created = self.backend.create(&path, &title);
                self.navigate_or_fail(created, now)
            }
            PageMessage::OpenDaily => {
                let daily = self.backend.daily();
                self.navigate_or_fail(daily, now)
            }
            PageMessage::Search { query } => {
                if query.trim().is_empty() {
                    self.send(HostMessage::SearchResults {
                        query,
                        hits: Vec::new(),
                    })
                } else {
                    vec![Effect::Fetch(Job::Search(query))]
                }
            }
            PageMessage::RequestDetails { path } => vec![Effect::Fetch(Job::Details(path))],
            PageMessage::Digest { path } => vec![Effect::Fetch(Job::Digest(path))],
            PageMessage::MoveNote { path, group } => self.move_note(path, group, now),
            PageMessage::ShowInbox => vec![Effect::Emit(EditorEvent::ShowInbox)],
            PageMessage::Refresh => self.changed(now),
            PageMessage::ChooseVault => vec![Effect::Pick(Pick::Vault)],
            PageMessage::ImportLocalFolder => vec![Effect::Pick(Pick::LocalFolder)],
            PageMessage::ImportOneNote => vec![Effect::Pick(Pick::OneNoteFile)],
            PageMessage::ExportVault { file_name } => vec![Effect::Pick(Pick::ExportZip { file_name })],
            PageMessage::RemoveLocalFolder { id } => vec![Effect::Fetch(Job::RemoveLocalFolder(id))],
            // Solo lo necesita el movil (ver `PageMessage::ConflictResolved`).
            PageMessage::ConflictResolved { .. } => Vec::new(),
        }
    }

    /// Lo que el usuario eligio en un dialogo nativo. `None` si lo cancelo, y
    /// cancelar no avisa de nada.
    pub(crate) fn picked(&mut self, pick: Pick, path: Option<String>) -> Vec<Effect> {
        let Some(path) = path else {
            return Vec::new();
        };
        match pick {
            Pick::Vault => vec![Effect::Fetch(Job::SetVault(path))],
            Pick::LocalFolder => vec![Effect::Fetch(Job::AddLocalFolder(path))],
            // Importar de OneNote son dos pasos: el `.one` y luego la carpeta.
            Pick::OneNoteFile => vec![Effect::Pick(Pick::OneNoteFolder { file: path })],
            Pick::OneNoteFolder { file } => vec![Effect::Fetch(Job::ImportOneNote { file, folder: path })],
            Pick::ExportZip { .. } => {
                // Comprimir una boveda grande tarda: sin este aviso, el clic
                // parece no haber hecho nada.
                let mut effects = self.send(HostMessage::Notice {
                    message: "Exportando las notas…".into(),
                });
                effects.push(Effect::Fetch(Job::Export(path)));
                effects
            }
        }
    }

    pub(crate) fn fetched(&mut self, result: Fetched, now: Instant) -> Vec<Effect> {
        match result {
            Fetched::Overview(result) => {
                self.overview_busy = false;
                let mut effects = match result {
                    Ok(overview) => self.overview_loaded(overview),
                    Err(detail) => {
                        log::warn!("no se pudo leer la boveda: {detail}");
                        Vec::new()
                    }
                };
                if std::mem::take(&mut self.overview_again) {
                    effects.extend(self.fetch_overview(now));
                }
                effects
            }
            Fetched::Search(query, result) => {
                let hits = result.unwrap_or_else(|detail| {
                    log::warn!("la busqueda fallo: {detail}");
                    Vec::new()
                });
                self.send(HostMessage::SearchResults { query, hits })
            }
            Fetched::Details(path, result) => {
                if self.current_path().as_deref() != Some(path.as_str()) {
                    // Llego tarde: la nota ya no es la abierta.
                    return Vec::new();
                }
                // Una nota privada no esta en el indice y su detalle falla: el
                // panel se vacia en vez de seguir enseñando el de la anterior.
                let details = result.unwrap_or_else(|_| DetailsDto::empty(&path));
                self.send(HostMessage::Details { details })
            }
            Fetched::Digest(path, result) => match result {
                Ok(digest) => {
                    let mut effects = self.send(HostMessage::Notice {
                        message: digest_notice(&digest),
                    });
                    effects.extend(self.fetch_overview(now));
                    if self.current_path().as_deref() == Some(path.as_str()) {
                        effects.push(Effect::Fetch(Job::Details(path)));
                    }
                    effects
                }
                Err(detail) => self.fail(detail),
            },
            Fetched::Folders(result) => match result {
                Ok(message) => {
                    let mut effects = self.send(HostMessage::Notice { message });
                    // Otra carpeta, otras notas: la barra lateral se relee ya.
                    effects.extend(self.fetch_overview(now));
                    effects
                }
                // Un rechazo (documentacion del buzon, carpeta anidada) es algo
                // que el usuario tiene que leer, no un fallo de la app: va a la
                // pagina y no se avisa a Dart.
                Err(message) => self.send(HostMessage::Error { message }),
            },
        }
    }

    /// La X de la ventana (o cerrar desde la app).
    pub(crate) fn close_requested(&mut self, now: Instant) -> Vec<Effect> {
        if !self.ready || !self.dirty {
            return self.destroy();
        }
        let first = *self.close_asked.get_or_insert(now);
        if now.duration_since(first) >= FORCE_CLOSE_AFTER {
            log::warn!("la pagina del editor no contesto al cerrar: se cierra igual");
            return self.destroy();
        }
        // Cerrar gana a cambiar de nota: la otra ya no se abre.
        self.pending_open = None;
        self.send(HostMessage::RequestClose)
    }

    fn navigate(&mut self, note: NoteDto, now: Instant) -> Vec<Effect> {
        if self.current_path().as_deref() == Some(note.path.as_str()) {
            // Ya esta abierta: recargarla perderia lo que no se guardo.
            return Vec::new();
        }
        if self.dirty && self.ready {
            self.pending_open = Some(note);
            return self.send(HostMessage::RequestClose);
        }
        self.load(note, now)
    }

    fn navigate_or_fail(&mut self, note: Result<NoteDto, String>, now: Instant) -> Vec<Effect> {
        match note {
            Ok(note) => self.navigate(note, now),
            Err(detail) => self.fail(detail),
        }
    }

    fn overview_loaded(&mut self, overview: OverviewDto) -> Vec<Effect> {
        let targets: Vec<LinkTargetDto> = overview
            .notes
            .iter()
            .map(|note| LinkTargetDto {
                target: note.path.strip_suffix(".md").unwrap_or(&note.path).to_string(),
                title: note.title.clone(),
            })
            .collect();
        let mut effects = Vec::new();
        if targets != self.targets {
            self.targets = targets.clone();
            effects.extend(self.send(HostMessage::Targets { targets }));
        }
        effects.extend(self.send(HostMessage::Overview { overview }));
        effects
    }

    fn refresh_if_stale(&mut self, now: Instant) -> Vec<Effect> {
        let fresh = self
            .overview_at
            .is_some_and(|at| now.duration_since(at) < OVERVIEW_EVERY);
        if fresh {
            Vec::new()
        } else {
            self.fetch_overview(now)
        }
    }

    fn fetch_overview(&mut self, now: Instant) -> Vec<Effect> {
        self.overview_at = Some(now);
        if self.overview_busy {
            self.overview_again = true;
            return Vec::new();
        }
        self.overview_busy = true;
        vec![Effect::Fetch(Job::Overview)]
    }

    fn ready(&mut self, now: Instant) -> Vec<Effect> {
        self.ready = true;
        if !self.queue.is_empty() {
            return self.queue.drain(..).map(Effect::Send).collect();
        }
        // Una pagina que avisa otra vez que esta lista se recargo (o WebView2 la
        // levanto tras caerse): se le manda todo de nuevo, la nota leida del disco.
        let mut effects = Vec::new();
        match self.current_path() {
            Some(path) => match self.backend.open(&path) {
                Ok(note) => effects.extend(self.load(note, now)),
                Err(detail) => effects.extend(self.fail(detail)),
            },
            None => {
                if let Some(theme) = self.theme.clone() {
                    effects.extend(self.send(HostMessage::Theme { theme }));
                }
            }
        }
        effects.extend(self.fetch_overview(now));
        effects
    }

    fn save(&mut self, path: String, text: &str, base_hash: Option<&str>, reason: SaveReason) -> Vec<Effect> {
        log::debug!("guardando {path} ({reason:?})");
        match self.backend.save(&path, text, base_hash) {
            Ok(SaveResult::Saved { hash }) => vec![
                Effect::Send(HostMessage::Saved {
                    path: path.clone(),
                    hash: hash.clone(),
                }),
                Effect::Emit(EditorEvent::Saved { path, hash }),
            ],
            Ok(SaveResult::Conflict { disk_text, disk_hash }) => vec![
                Effect::Send(HostMessage::Conflict {
                    path: path.clone(),
                    disk_text,
                    disk_hash,
                }),
                Effect::Emit(EditorEvent::Conflict { path }),
            ],
            Err(detail) => vec![
                Effect::Send(HostMessage::Error {
                    message: format!("No se pudo guardar: {detail}"),
                }),
                Effect::Emit(EditorEvent::Error { detail }),
            ],
        }
    }

    fn open_link(&mut self, target: &str, now: Instant) -> Vec<Effect> {
        let source = self.current.as_ref().map(|c| c.path.clone());
        let opened = match self.backend.resolve_link(target, source.as_deref()) {
            Ok(Some(path)) => self.backend.open(&path),
            // Como en Obsidian: seguir un enlace a una nota que no existe la crea,
            // y en la carpeta de la nota que enlaza.
            Ok(None) => self.backend.create(&in_folder_of(target, source.as_deref()), ""),
            Err(detail) => Err(detail),
        };
        self.navigate_or_fail(opened, now)
    }

    fn load(&mut self, note: NoteDto, now: Instant) -> Vec<Effect> {
        self.pending_open = None;
        self.close_asked = None;
        self.dirty = false;
        let path = note.path.clone();
        self.current = Some(Current {
            path: path.clone(),
            title: note.title.clone(),
        });

        let message = HostMessage::Load {
            note,
            targets: self.targets.clone(),
            theme: self.theme.clone(),
        };
        let mut effects = vec![self.title()];
        effects.extend(self.send(message));
        effects.push(Effect::Fetch(Job::Details(path.clone())));
        if self.overview_at.is_none() {
            effects.extend(self.fetch_overview(now));
        }
        effects.push(Effect::Emit(EditorEvent::Opened { path }));
        effects
    }

    fn fail(&mut self, detail: String) -> Vec<Effect> {
        let mut effects = self.send(HostMessage::Error {
            message: detail.clone(),
        });
        effects.push(Effect::Emit(EditorEvent::Error { detail }));
        effects
    }

    fn destroy(&mut self) -> Vec<Effect> {
        let path = self.current.take().map(|c| c.path);
        self.ready = false;
        self.queue.clear();
        self.dirty = false;
        self.pending_open = None;
        self.close_asked = None;
        vec![Effect::Destroy, Effect::Emit(EditorEvent::Closed { path })]
    }

    fn current_path(&self) -> Option<String> {
        self.current.as_ref().map(|c| c.path.clone())
    }

    fn title(&self) -> Effect {
        Effect::Title(match &self.current {
            Some(current) => {
                let mark = if self.dirty { "● " } else { "" };
                format!("{mark}{} — Notas de NexoDeck", current.title)
            }
            None => "Notas de NexoDeck".to_string(),
        })
    }

    fn send(&mut self, message: HostMessage) -> Vec<Effect> {
        if self.ready {
            return vec![Effect::Send(message)];
        }
        // Mientras carga la pagina solo vale lo ultimo de cada cosa: dos notas
        // abiertas seguidas, o dos fotos de la boveda.
        let replaces = |queued: &HostMessage| {
            matches!(
                (&message, queued),
                (HostMessage::Load { .. }, HostMessage::Load { .. })
                    | (HostMessage::Overview { .. }, HostMessage::Overview { .. })
                    | (HostMessage::Targets { .. }, HostMessage::Targets { .. })
                    | (HostMessage::Details { .. }, HostMessage::Details { .. })
            )
        };
        self.queue.retain(|queued| !replaces(queued));
        self.queue.push(message);
        Vec::new()
    }
}

/// Donde se crea la nota de un enlace que no lleva a ninguna: en la carpeta
/// local de la nota que enlaza (`@apuntes/…`), salvo que el enlace ya nombre
/// una carpeta. Sin esto, `[[nueva]]` escrito en una carpeta local crearia la
/// nota en la boveda principal, lejos de donde el usuario la escribio.
///
/// El prefijo se reconoce igual que en `nexodeck-docs` (`@<id>/`); este crate
/// no depende de aquel, asi que la regla se repite aqui, acotada a esto.
fn in_folder_of(target: &str, source: Option<&str>) -> String {
    if target.starts_with('@') {
        return target.to_string();
    }
    match source.and_then(|s| s.strip_prefix('@')).and_then(|s| s.split_once('/')) {
        Some((id, _)) => format!("@{id}/{target}"),
        None => target.to_string(),
    }
}

fn digest_notice(digest: &DigestDto) -> String {
    match digest.state.as_str() {
        "running" => "El asistente ya está con esa nota.".to_string(),
        "proposed" => "Esa nota ya tiene una propuesta esperando en el buzón.".to_string(),
        _ => "En cola. Cuando esté lista, la propuesta aparece en el buzón.".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    use super::*;
    use crate::protocol::NoteSummaryDto;

    #[derive(Default)]
    struct Fake {
        notes: Mutex<BTreeMap<String, String>>,
        fail_saves: bool,
    }

    fn hash(text: &str) -> String {
        format!("h:{text}")
    }

    fn with_md(path: &str) -> String {
        if path.ends_with(".md") {
            path.to_string()
        } else {
            format!("{path}.md")
        }
    }

    impl Fake {
        fn with(notes: &[(&str, &str)]) -> Arc<Fake> {
            Arc::new(Fake {
                notes: Mutex::new(notes.iter().map(|(p, t)| (p.to_string(), t.to_string())).collect()),
                fail_saves: false,
            })
        }

        fn write(&self, path: &str, text: &str) {
            self.notes.lock().unwrap().insert(path.into(), text.into());
        }
    }

    impl EditorBackend for Fake {
        fn open(&self, path: &str) -> Result<NoteDto, String> {
            let path = with_md(path);
            let notes = self.notes.lock().unwrap();
            let text = notes.get(&path).ok_or_else(|| format!("{path} no existe"))?;
            Ok(NoteDto {
                title: path.trim_end_matches(".md").to_string(),
                text: text.clone(),
                hash: Some(hash(text)),
                private: path.starts_with("privado/"),
                path,
            })
        }

        fn save(&self, path: &str, text: &str, base_hash: Option<&str>) -> Result<SaveResult, String> {
            let mut notes = self.notes.lock().unwrap();
            if let Some(disk) = notes.get(path) {
                if base_hash != Some(hash(disk).as_str()) {
                    return Ok(SaveResult::Conflict {
                        disk_text: disk.clone(),
                        disk_hash: hash(disk),
                    });
                }
            }
            if self.fail_saves {
                return Err("disco lleno".into());
            }
            notes.insert(path.into(), text.into());
            Ok(SaveResult::Saved { hash: hash(text) })
        }

        fn create(&self, path: &str, title: &str) -> Result<NoteDto, String> {
            let path = with_md(path);
            self.notes
                .lock()
                .unwrap()
                .entry(path.clone())
                .or_insert_with(|| format!("# {title}\n"));
            self.open(&path)
        }

        fn daily(&self) -> Result<NoteDto, String> {
            self.create("diario/hoy", "Hoy")
        }

        fn move_note(&self, path: &str, group: Option<&str>) -> Result<String, String> {
            let mut notes = self.notes.lock().unwrap();
            let key = path.to_string();
            let text = notes.remove(&key).ok_or_else(|| format!("{path} no existe"))?;
            let file = key.rsplit('/').next().unwrap_or(&key).to_string();
            let target = match group.map(str::trim).filter(|g| !g.is_empty()) {
                Some(group) => format!("{group}/{file}"),
                None => format!("inbox/{file}"),
            };
            notes.insert(target.clone(), text);
            Ok(target)
        }

        fn overview(&self) -> Result<OverviewDto, String> {
            let notes = self
                .notes
                .lock()
                .unwrap()
                .keys()
                .filter(|p| !p.starts_with("privado/"))
                .map(|p| NoteSummaryDto {
                    path: p.clone(),
                    folder: None,
                    group: None,
                    title: p.trim_end_matches(".md").to_string(),
                    role: "note".into(),
                    date: None,
                    tags: vec![],
                    open_tasks: 0,
                    ai_excluded: false,
                    modified: None,
                })
                .collect();
            Ok(OverviewDto {
                configured: true,
                root: Some("boveda".into()),
                folders: vec![],
                groups: vec![],
                notes,
                tasks: vec![],
                digests: vec![],
                error: None,
            })
        }

        fn search(&self, query: &str) -> Result<Vec<HitDto>, String> {
            Ok(self
                .notes
                .lock()
                .unwrap()
                .iter()
                .filter(|(_, text)| text.contains(query))
                .map(|(path, text)| HitDto {
                    id: format!("n:{path}"),
                    kind: "note".into(),
                    title: path.clone(),
                    snippet: text.clone(),
                    date: None,
                    path: Some(path.clone()),
                })
                .collect())
        }

        fn details(&self, path: &str) -> Result<DetailsDto, String> {
            if path.starts_with("privado/") {
                return Err("no esta en el indice".into());
            }
            Ok(DetailsDto {
                path: path.into(),
                backlinks: vec!["temas/odm.md".into()],
                related: vec![],
                digests: vec![],
            })
        }

        fn digest(&self, path: &str) -> Result<DigestDto, String> {
            Ok(DigestDto {
                id: "d-1".into(),
                note: path.into(),
                trigger: "manual".into(),
                state: "queued".into(),
                state_detail: None,
                proposal_id: None,
                created_at: "2026-09-15T14:05:00Z".into(),
                model_label: String::new(),
                hub: None,
                requeried: false,
                discarded_ids: vec![],
                redactions: 0,
                candidates: vec![],
                steps: vec![],
            })
        }

        fn resolve_link(&self, target: &str, _source: Option<&str>) -> Result<Option<String>, String> {
            let path = with_md(target);
            Ok(self.notes.lock().unwrap().contains_key(&path).then_some(path))
        }
    }

    fn sent(effects: &[Effect]) -> Vec<&HostMessage> {
        effects
            .iter()
            .filter_map(|e| match e {
                Effect::Send(m) => Some(m),
                _ => None,
            })
            .collect()
    }

    fn emitted(effects: &[Effect]) -> Vec<&EditorEvent> {
        effects
            .iter()
            .filter_map(|e| match e {
                Effect::Emit(ev) => Some(ev),
                _ => None,
            })
            .collect()
    }

    fn fetches(effects: &[Effect]) -> Vec<&Job> {
        effects
            .iter()
            .filter_map(|e| match e {
                Effect::Fetch(job) => Some(job),
                _ => None,
            })
            .collect()
    }

    fn loaded_path(effects: &[Effect]) -> Option<String> {
        sent(effects).into_iter().find_map(|m| match m {
            HostMessage::Load { note, .. } => Some(note.path.clone()),
            _ => None,
        })
    }

    /// Una sesion con `temas/malla.md` abierta, la pagina lista y la primera
    /// foto de la boveda ya recibida.
    fn opened(backend: &Arc<Fake>, now: Instant) -> Session {
        let mut session = Session::new(backend.clone());
        session.open(backend.open("temas/malla.md").unwrap(), None, now);
        session.page(PageMessage::Ready, now);
        session.fetched(Fetched::Overview(backend.overview()), now);
        session
    }

    fn save(path: &str, text: &str, base: &str) -> PageMessage {
        PageMessage::Save {
            path: path.into(),
            text: text.into(),
            base_hash: Some(base.into()),
            reason: SaveReason::Auto,
        }
    }

    #[test]
    fn the_note_waits_for_the_page_and_the_vault_is_read_aside() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = Session::new(backend.clone());

        let effects = session.open(backend.open("temas/malla").unwrap(), None, now);
        assert!(sent(&effects).is_empty(), "la pagina todavia no escucha");
        assert_eq!(
            fetches(&effects),
            [&Job::Details("temas/malla.md".into()), &Job::Overview]
        );
        assert_eq!(
            emitted(&effects),
            [&EditorEvent::Opened { path: "temas/malla.md".into() }]
        );

        let effects = session.page(PageMessage::Ready, now);
        assert_eq!(loaded_path(&effects).as_deref(), Some("temas/malla.md"));
    }

    #[test]
    fn the_window_can_open_without_a_note_and_closes_at_once() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = Session::new(backend.clone());

        let effects = session.show(None, now);
        assert!(effects.contains(&Effect::Focus));
        assert!(effects.contains(&Effect::Title("Notas de NexoDeck".into())));
        assert_eq!(fetches(&effects), [&Job::Overview]);

        session.page(PageMessage::Ready, now);
        let effects = session.fetched(Fetched::Overview(backend.overview()), now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Targets { .. }, HostMessage::Overview { .. }]
        ));

        assert_eq!(
            session.close_requested(now),
            [Effect::Destroy, Effect::Emit(EditorEvent::Closed { path: None })]
        );
    }

    #[test]
    fn saving_answers_the_page_and_tells_the_app() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let effects = session.page(save("temas/malla.md", "# Malla\nñandú\n", "h:# Malla\n"), now);
        assert_eq!(
            sent(&effects),
            [&HostMessage::Saved {
                path: "temas/malla.md".into(),
                hash: "h:# Malla\nñandú\n".into()
            }]
        );
        assert!(matches!(emitted(&effects)[..], [EditorEvent::Saved { .. }]));

        backend.write("temas/malla.md", "de obsidian");
        let effects = session.page(save("temas/malla.md", "mio", "h:# Malla\nñandú\n"), now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Conflict { disk_text, .. }] if disk_text == "de obsidian"
        ));
        assert_eq!(backend.open("temas/malla").unwrap().text, "de obsidian", "no se piso");
    }

    #[test]
    fn a_failed_save_is_shown_in_the_page() {
        let backend = Arc::new(Fake {
            notes: Mutex::new(BTreeMap::from([("a.md".to_string(), "x".to_string())])),
            fail_saves: true,
        });
        let now = Instant::now();
        let mut session = Session::new(backend.clone());
        session.open(backend.open("a.md").unwrap(), None, now);
        session.page(PageMessage::Ready, now);

        let effects = session.page(save("a.md", "y", "h:x"), now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Error { message }] if message.contains("disco lleno")
        ));
    }

    #[test]
    fn a_clean_window_closes_at_once_and_a_dirty_one_saves_first() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();

        let mut clean = opened(&backend, now);
        assert_eq!(
            clean.close_requested(now),
            [
                Effect::Destroy,
                Effect::Emit(EditorEvent::Closed {
                    path: Some("temas/malla.md".into())
                })
            ]
        );

        let mut dirty = opened(&backend, now);
        let effects = dirty.page(PageMessage::Dirty { dirty: true }, now);
        assert!(matches!(&effects[..], [Effect::Title(t)] if t.starts_with("● temas/malla")));

        assert_eq!(dirty.close_requested(now), [Effect::Send(HostMessage::RequestClose)]);
        let effects = dirty.page(PageMessage::CloseReady, now);
        assert_eq!(effects[0], Effect::Destroy);
    }

    #[test]
    fn a_page_that_does_not_answer_is_closed_on_a_later_try() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let start = Instant::now();
        let mut session = opened(&backend, start);
        session.page(PageMessage::Dirty { dirty: true }, start);

        assert_eq!(session.close_requested(start), [Effect::Send(HostMessage::RequestClose)]);
        assert_eq!(
            session.close_requested(start + Duration::from_secs(1)),
            [Effect::Send(HostMessage::RequestClose)],
            "una segunda X enseguida se la pasa a la pagina, que decide"
        );
        let effects = session.close_requested(start + FORCE_CLOSE_AFTER + Duration::from_secs(1));
        assert_eq!(effects[0], Effect::Destroy);
    }

    #[test]
    fn opening_another_note_with_unsaved_changes_waits_for_the_save() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n"), ("temas/odm.md", "# ODM\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);
        session.page(PageMessage::Dirty { dirty: true }, now);

        let same = session.page(PageMessage::OpenNote { path: "temas/malla.md".into() }, now);
        assert!(same.is_empty(), "la misma nota no se recarga");

        let effects = session.page(PageMessage::OpenNote { path: "temas/odm.md".into() }, now);
        assert_eq!(sent(&effects), [&HostMessage::RequestClose]);
        assert_eq!(loaded_path(&effects), None);

        let effects = session.page(PageMessage::CloseReady, now);
        assert_eq!(loaded_path(&effects).as_deref(), Some("temas/odm.md"));
        assert!(!effects.contains(&Effect::Destroy));
    }

    #[test]
    fn a_link_to_a_missing_note_creates_it() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let effects = session.page(
            PageMessage::OpenLink {
                target: "temas/nueva".into(),
            },
            now,
        );
        assert_eq!(loaded_path(&effects).as_deref(), Some("temas/nueva.md"));
        assert!(backend.resolve_link("temas/nueva", None).unwrap().is_some());
    }

    #[test]
    fn the_folder_menu_opens_a_native_dialog_and_cancelling_does_nothing() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        assert_eq!(session.page(PageMessage::ChooseVault, now), vec![Effect::Pick(Pick::Vault)]);
        assert_eq!(
            session.page(PageMessage::ImportLocalFolder, now),
            vec![Effect::Pick(Pick::LocalFolder)]
        );
        let export = session.page(
            PageMessage::ExportVault {
                file_name: "notas-2026-09-16.zip".into(),
            },
            now,
        );
        assert_eq!(
            export,
            vec![Effect::Pick(Pick::ExportZip {
                file_name: "notas-2026-09-16.zip".into()
            })]
        );
        assert!(session.picked(Pick::Vault, None).is_empty(), "cancelar no avisa de nada");
    }

    #[test]
    fn a_chosen_folder_is_applied_elsewhere_and_the_sidebar_reloads() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let effects = session.picked(Pick::LocalFolder, Some(r"D:\Apuntes".into()));
        assert_eq!(effects, vec![Effect::Fetch(Job::AddLocalFolder(r"D:\Apuntes".into()))]);

        let effects = session.picked(
            Pick::ExportZip {
                file_name: "notas.zip".into(),
            },
            Some(r"D:\notas.zip".into()),
        );
        assert!(matches!(sent(&effects)[..], [HostMessage::Notice { .. }]));
        assert!(effects.contains(&Effect::Fetch(Job::Export(r"D:\notas.zip".into()))));

        let effects = session.fetched(Fetched::Folders(Ok("Carpeta añadida".into())), now);
        assert!(matches!(sent(&effects)[..], [HostMessage::Notice { message }] if message == "Carpeta añadida"));
        assert!(effects.contains(&Effect::Fetch(Job::Overview)));

        // Un rechazo se lee en la pagina, sin tratarlo como un fallo de la app.
        let effects = session.fetched(Fetched::Folders(Err("es documentacion del buzon".into())), now);
        assert!(matches!(sent(&effects)[..], [HostMessage::Error { .. }]));
        assert!(emitted(&effects).is_empty());
    }

    #[test]
    fn importing_from_onenote_asks_for_the_file_then_the_folder() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let effects = session.page(PageMessage::ImportOneNote, now);
        assert_eq!(effects, vec![Effect::Pick(Pick::OneNoteFile)]);

        // Elegido el `.one`, se pide la carpeta. Cancelar no hace nada.
        let effects = session.picked(Pick::OneNoteFile, Some(r"D:\notas.one".into()));
        assert_eq!(
            effects,
            vec![Effect::Pick(Pick::OneNoteFolder {
                file: r"D:\notas.one".into()
            })]
        );
        assert!(session.picked(Pick::OneNoteFile, None).is_empty());

        // Elegida la carpeta, se lanza la importacion.
        let effects = session.picked(
            Pick::OneNoteFolder {
                file: r"D:\notas.one".into(),
            },
            Some(r"D:\Notas\onenote".into()),
        );
        assert_eq!(
            effects,
            vec![Effect::Fetch(Job::ImportOneNote {
                file: r"D:\notas.one".into(),
                folder: r"D:\Notas\onenote".into(),
            })]
        );
    }

    #[test]
    fn removing_a_local_folder_needs_no_dialog() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);
        let effects = session.page(PageMessage::RemoveLocalFolder { id: "apuntes".into() }, now);
        assert_eq!(effects, vec![Effect::Fetch(Job::RemoveLocalFolder("apuntes".into()))]);
        assert_eq!(
            run_job(backend.as_ref(), Job::RemoveLocalFolder("apuntes".into())),
            Fetched::Folders(Err(crate::backend::tests_unsupported()))
        );
    }

    #[test]
    fn moving_a_note_refreshes_the_sidebar_and_fails_without_hiding() {
        let backend = Fake::with(&[("inbox/suelta.md", "# Suelta\n")]);
        let now = Instant::now();
        let mut session = Session::new(backend.clone());
        session.page(PageMessage::Ready, now);
        session.fetched(Fetched::Overview(backend.overview()), now);

        let effects = session.page(
            PageMessage::MoveNote {
                path: "inbox/suelta.md".into(),
                group: Some("privado".into()),
            },
            now,
        );
        assert_eq!(effects, vec![Effect::Fetch(Job::Overview)]);
        {
            let notes = backend.notes.lock().unwrap();
            assert!(notes.contains_key("privado/suelta.md"));
            assert!(!notes.contains_key("inbox/suelta.md"));
        }

        // Un movimiento que no sale (nota inexistente) se lee en la pagina.
        let effects = session.page(
            PageMessage::MoveNote {
                path: "no/existe.md".into(),
                group: None,
            },
            now,
        );
        assert!(matches!(sent(&effects)[..], [HostMessage::Error { .. }]));
    }

    #[test]
    fn a_missing_link_is_created_in_the_folder_of_the_note_that_links() {
        assert_eq!(in_folder_of("nueva", Some("@apuntes/clientes/acme.md")), "@apuntes/nueva");
        assert_eq!(in_folder_of("@otra/x", Some("@apuntes/a.md")), "@otra/x");
        assert_eq!(in_folder_of("temas/nueva", Some("temas/malla.md")), "temas/nueva");
        assert_eq!(in_folder_of("nueva", None), "nueva");
    }

    #[test]
    fn a_reloaded_page_gets_everything_again_from_disk() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);
        backend.write("temas/malla.md", "# Malla editada\n");

        let effects = session.page(PageMessage::Ready, now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Load { note, .. }] if note.text == "# Malla editada\n"
        ));
        assert!(fetches(&effects).contains(&&Job::Overview));
    }

    #[test]
    fn only_web_links_leave_the_editor() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);
        let open = |session: &mut Session, url: &str| {
            session.page(PageMessage::OpenExternal { url: url.into() }, now)
        };

        assert_eq!(
            open(&mut session, "https://docs.rs/wry"),
            [Effect::OpenExternal("https://docs.rs/wry".into())]
        );
        assert!(open(&mut session, "file:///C:/Windows/System32/calc.exe").is_empty());
        assert!(open(&mut session, "javascript:alert(1)").is_empty());
    }

    #[test]
    fn vault_reads_do_not_pile_up_while_saving() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let first = session.changed(now);
        assert_eq!(
            fetches(&first),
            [&Job::Overview, &Job::Details("temas/malla.md".into())]
        );
        let second = session.changed(now);
        assert_eq!(
            fetches(&second),
            [&Job::Details("temas/malla.md".into())],
            "con una lectura en marcha no se lanza otra"
        );

        let effects = session.fetched(Fetched::Overview(backend.overview()), now);
        assert!(matches!(sent(&effects)[..], [HostMessage::Overview { .. }]));
        assert_eq!(fetches(&effects), [&Job::Overview], "una sola lectura mas, al terminar");

        let effects = session.fetched(Fetched::Overview(backend.overview()), now);
        assert!(fetches(&effects).is_empty());
    }

    #[test]
    fn new_notes_in_the_vault_become_link_targets() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        backend.write("temas/odm.md", "# ODM\n");
        session.changed(now);
        let effects = session.fetched(Fetched::Overview(backend.overview()), now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Targets { targets }, HostMessage::Overview { .. }]
                if targets.iter().any(|t| t.target == "temas/odm")
        ));
    }

    #[test]
    fn details_that_arrive_late_or_fail_do_not_show_the_wrong_note() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n"), ("privado/claves.md", "x")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let late = session.fetched(
            Fetched::Details("temas/odm.md".into(), backend.details("temas/odm.md")),
            now,
        );
        assert!(late.is_empty());

        session.page(PageMessage::OpenNote { path: "privado/claves.md".into() }, now);
        let effects = session.fetched(
            Fetched::Details("privado/claves.md".into(), backend.details("privado/claves.md")),
            now,
        );
        assert_eq!(
            sent(&effects),
            [&HostMessage::Details {
                details: DetailsDto::empty("privado/claves.md")
            }]
        );
    }

    #[test]
    fn asking_for_a_digest_tells_the_page_and_refreshes_what_it_shows() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let effects = session.page(PageMessage::Digest { path: "temas/malla.md".into() }, now);
        assert_eq!(fetches(&effects), [&Job::Digest("temas/malla.md".into())]);

        let result = run_job(backend.as_ref(), Job::Digest("temas/malla.md".into()));
        let effects = session.fetched(result, now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::Notice { message }] if message.contains("En cola")
        ));
        assert_eq!(
            fetches(&effects),
            [&Job::Overview, &Job::Details("temas/malla.md".into())]
        );
    }

    #[test]
    fn searching_nothing_does_not_reach_the_backend() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla ortofoto\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        let empty = session.page(PageMessage::Search { query: "  ".into() }, now);
        assert!(matches!(
            sent(&empty)[..],
            [HostMessage::SearchResults { hits, .. }] if hits.is_empty()
        ));
        assert!(fetches(&empty).is_empty());

        let effects = session.page(PageMessage::Search { query: "ortofoto".into() }, now);
        let [Effect::Fetch(job)] = &effects[..] else { panic!("{effects:?}") };
        let effects = session.fetched(run_job(backend.as_ref(), job.clone()), now);
        assert!(matches!(
            sent(&effects)[..],
            [HostMessage::SearchResults { query, hits }] if query == "ortofoto" && hits.len() == 1
        ));
    }

    #[test]
    fn the_vault_is_read_again_only_after_a_while() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);

        assert!(session.focused(now + Duration::from_secs(5)).is_empty());
        assert_eq!(
            session.focused(now + OVERVIEW_EVERY + Duration::from_secs(1)),
            [Effect::Fetch(Job::Overview)]
        );
    }

    #[test]
    fn the_inbox_is_opened_by_the_app() {
        let backend = Fake::with(&[("temas/malla.md", "# Malla\n")]);
        let now = Instant::now();
        let mut session = opened(&backend, now);
        assert_eq!(
            session.page(PageMessage::ShowInbox, now),
            [Effect::Emit(EditorEvent::ShowInbox)]
        );
    }
}
