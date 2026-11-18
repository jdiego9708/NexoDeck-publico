//! Editar notas a mano, desde el editor de NexoDeck.
//!
//! Aca no hay IA ni propuestas: es el usuario escribiendo en su boveda. Por eso
//! vale `privado/`, que ningun agente lee. Lo que si se mantiene es lo que evita
//! perder trabajo:
//!
//! - **Nunca se pisa lo que cambio por fuera.** Cada guardado lleva el hash del
//!   fichero tal como lo abrio el editor; si en disco hay otra cosa (una edicion
//!   en Obsidian, una propuesta aprobada), no se escribe y se devuelve lo que hay
//!   para que el usuario elija.
//! - **El formato del fichero se conserva**: CRLF y BOM, igual que al aplicar una
//!   propuesta. El editor trabaja con `\n`.
//! - Escritura atomica, como el resto del buzon.
//!
//! Guardar cambia el hash de la nota, asi que una propuesta pendiente sobre ella
//! queda para revisar otra vez al aprobarla: eso ya lo hace `revalidate`.

use std::path::{Path, PathBuf};

use jiff::Timestamp;
use serde::{Deserialize, Serialize};

use crate::config::{DocProject, NoteGroup, DAILY_DIR, PRIVATE_SEGMENT};
use crate::dates::SpanishDate;
use crate::error::{DocsError, DocsResult};
use crate::markdown::Document;
use crate::notes::capture;
use crate::notes::groups;
use crate::notes::roots::{link_form, locate, split_virtual, NoteRoot};
use crate::notes::parse::parse_note;
use crate::service::DocsService;
use crate::store::{sha256_hex, write_atomic};

/// Una nota lista para editar.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EditableNote {
    /// Relativa a la boveda, con `/` y `.md`.
    pub path: String,
    pub title: String,
    /// Con `\n`, sin BOM.
    pub text: String,
    /// sha256 del fichero tal como esta en disco. Es lo que se devuelve al
    /// guardar para saber si alguien lo toco mientras tanto.
    pub hash: String,
    /// Esta en `privado/`: ningun agente la lee.
    pub private: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum SaveOutcome {
    Saved {
        hash: String,
    },
    /// En disco hay otra cosa que lo que abrio el editor. No se escribio nada.
    /// `disk_hash` vacio significa que la nota ya no existe.
    Conflict {
        disk_text: String,
        disk_hash: String,
    },
}

/// Lo que paso al mover una nota a otra agrupacion.
///
/// Mover no es solo cambiar el fichero de sitio: la ruta es la identidad de una
/// nota en medio sistema, y esto cuenta todo lo que hubo que tocar para que nada
/// se quedara apuntando a la ruta vieja. Quien llama tiene que poder decirle al
/// usuario que notas suyas se reescribieron.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MoveOutcome {
    pub from: String,
    /// Puede no ser la ruta pedida: si en el grupo ya habia una nota con ese
    /// nombre, se aparta a uno libre en vez de pisarla.
    pub to: String,
    /// Las notas en las que se reescribio algun `[[enlace]]`, con cuantos.
    pub relinked: Vec<RelinkedNote>,
    /// Cuantos digests de esta nota se reapuntaron a la ruta nueva.
    pub digests: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RelinkedNote {
    pub path: String,
    pub links: usize,
}

/// Un destino para autocompletar `[[`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkTarget {
    /// Lo que va dentro de los corchetes: la ruta sin `.md`.
    pub target: String,
    pub title: String,
}

impl DocsService {
    pub fn open_note_for_edit(&self, path: &str) -> DocsResult<EditableNote> {
        let (root, inner) = self.locate_note(path)?;
        let (rel, full) = root.project.resolve_user_note(&inner, true)?;
        let raw = std::fs::read(&full).map_err(|e| DocsError::io(&full, e))?;
        let document =
            Document::parse(&raw).map_err(|e| DocsError::Invalid(format!("{rel}: {e}")))?;
        Ok(EditableNote {
            title: parse_note(&rel, &document.body).title,
            private: is_private(&rel),
            hash: sha256_hex(&raw),
            text: document.body,
            // Quien la abrio tiene que poder volver a guardarla por la misma
            // ruta: la virtual, no la de dentro de su carpeta.
            path: root.virtual_path(&rel),
        })
    }

    /// Guarda el texto del editor si el fichero sigue siendo el que se abrio.
    ///
    /// `base_hash` es el hash con el que se abrio (o el del ultimo guardado).
    /// `None` es una nota nueva: solo se crea si no existe, nunca pisa una que ya
    /// esta.
    pub fn save_note(
        &self,
        path: &str,
        text: &str,
        base_hash: Option<&str>,
    ) -> DocsResult<SaveOutcome> {
        let (root, inner) = self.locate_note(path)?;
        let (rel, full) = root.project.resolve_user_note(&inner, false)?;
        let text = text.replace("\r\n", "\n");

        let raw = match std::fs::read(&full) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                if base_hash.is_some() {
                    // Se abrio y alguien la borro por fuera: guardar a ciegas la
                    // resucitaria sin avisar.
                    return Ok(SaveOutcome::Conflict {
                        disk_text: String::new(),
                        disk_hash: String::new(),
                    });
                }
                return self.write_new(&full, text.as_bytes());
            }
            Err(e) => return Err(DocsError::io(&full, e)),
        };

        let disk_hash = sha256_hex(&raw);
        if base_hash != Some(disk_hash.as_str()) {
            let disk_text = Document::parse(&raw)
                .map(|d| d.body)
                .unwrap_or_else(|_| String::from_utf8_lossy(&raw).into_owned());
            return Ok(SaveOutcome::Conflict {
                disk_text,
                disk_hash,
            });
        }

        let document =
            Document::parse(&raw).map_err(|e| DocsError::Invalid(format!("{rel}: {e}")))?;
        let bytes = document.render(&text);
        if bytes == raw {
            return Ok(SaveOutcome::Saved { hash: disk_hash });
        }
        write_atomic(&full, &bytes)?;
        self.changed();
        Ok(SaveOutcome::Saved {
            hash: sha256_hex(&bytes),
        })
    }

    /// Una nota nueva con un titulo. Si ya existe, se abre la que hay: crear no
    /// pisa nunca.
    pub fn create_note(&self, path: &str, title: &str, now: Timestamp) -> DocsResult<EditableNote> {
        let (root, inner) = self.locate_note(path)?;
        let (rel, full) = root.project.resolve_user_note(&inner, false)?;
        if !full.exists() {
            let stem = rel
                .rsplit('/')
                .next()
                .and_then(|name| name.strip_suffix(".md"))
                .unwrap_or(&rel);
            let heading = if title.trim().is_empty() { stem } else { title.trim() };
            let date = SpanishDate::from_timestamp(now).iso();
            let text = format!("---\ndate: {date}\n---\n# {heading}\n\n");
            if let SaveOutcome::Conflict { .. } = self.write_new(&full, text.as_bytes())? {
                return Err(DocsError::Invalid(format!("'{rel}' aparecio mientras se creaba")));
            }
        }
        self.open_note_for_edit(&root.virtual_path(&rel))
    }

    /// La nota del dia (`diario/AAAA-MM-DD.md`), creada si todavia no existe.
    /// Siempre en la boveda principal: el diario es uno.
    pub fn open_daily_note(&self, now: Timestamp) -> DocsResult<EditableNote> {
        let root = self.main_root()?;
        let today = SpanishDate::from_timestamp(now);
        let (rel, full) = root
            .project
            .resolve_user_note(&format!("{DAILY_DIR}{}.md", today.iso()), false)?;
        if !full.exists() {
            let text = format!("# {}\n\n", today.long());
            self.write_new(&full, text.as_bytes())?;
        }
        self.open_note_for_edit(&root.virtual_path(&rel))
    }

    /// Las notas de la boveda para autocompletar `[[`. Las privadas no estan: no
    /// entran en el indice.
    pub fn link_targets(&self) -> DocsResult<Vec<LinkTarget>> {
        let config = self.inbox.config()?;
        let Some(index) = self.notes_index(&config)? else {
            return Ok(Vec::new());
        };
        Ok(index
            .notes()
            .map(|note| LinkTarget {
                target: note
                    .path
                    .strip_suffix(".md")
                    .unwrap_or(&note.path)
                    .to_string(),
                title: note.note.title.clone(),
            })
            .collect())
    }

    /// A que nota lleva un `[[enlace]]` pulsado en el editor. Como en Obsidian:
    /// la ruta exacta o el nombre de fichero si es unico; y ademas una nota
    /// privada por su ruta, que el indice no conoce.
    ///
    /// Con `source` (la nota donde esta escrito el enlace), un enlace dentro de
    /// una carpeta local se resuelve en esa carpeta (`NotesIndex::resolve_link_from`).
    pub fn resolve_note_link(&self, target: &str, source: Option<&str>) -> DocsResult<Option<String>> {
        let config = self.inbox.config()?;
        if let Some(index) = self.notes_index(&config)? {
            let found = match source {
                Some(source) => index.resolve_link_from(target, source),
                None => index.resolve_link(target),
            };
            if let Some(path) = found {
                return Ok(Some(path));
            }
        }
        // Una privada no esta en el indice: por su ruta, en su carpeta.
        let (root, inner) = self.locate_note(target)?;
        Ok(root
            .project
            .resolve_user_note(&inner, true)
            .ok()
            .map(|(rel, _)| root.virtual_path(&rel)))
    }

    /// La carpeta de una nota y su ruta dentro de ella.
    ///
    /// Sustituye a la vieja `edit_vault`, que solo conocia una boveda. Todo lo que
    /// escribe o lee una nota por su ruta pasa por aqui (`notes/roots.rs`).
    pub(crate) fn locate_note(&self, path: &str) -> DocsResult<(NoteRoot, String)> {
        let config = self.inbox.config()?;
        let roots = config.note_roots();
        if roots.is_empty() {
            return Err(DocsError::Invalid(
                "no hay ninguna boveda configurada para el asistente de notas".to_string(),
            ));
        }
        locate(&roots, path)
            .map(|(root, inner)| (root.clone(), inner))
            .ok_or_else(|| {
                DocsError::Invalid(format!(
                    "'{path}' nombra una carpeta de notas que no esta configurada"
                ))
            })
    }

    /// Lee un adjunto (una imagen) de la boveda: `src` es la ruta tal como se
    /// escribio en la nota, relativa a su carpeta. Devuelve el mime y los bytes,
    /// o `None` si no existe o se sale de la carpeta de notas.
    pub fn read_attachment(&self, note: &str, src: &str) -> DocsResult<Option<(String, Vec<u8>)>> {
        let (root, inner) = self.locate_note(note)?;
        let dir = inner.rsplit_once('/').map(|(dir, _)| dir).unwrap_or("");
        let Some(rel) = resolve_relative(dir, src) else {
            return Ok(None);
        };
        let full = PathBuf::from(&root.project.repo_root).join(&rel);
        let Ok(bytes) = std::fs::read(&full) else {
            return Ok(None);
        };
        Ok(Some((attachment_mime(&rel, &bytes), bytes)))
    }

    /// La boveda principal.
    fn main_root(&self) -> DocsResult<NoteRoot> {
        self.locate_note("").map(|(root, _)| root)
    }

    /// Una carpeta de notas por el id de su proyecto. `None`, o el id de la
    /// principal, es la principal.
    fn folder_root(&self, folder: Option<&str>) -> DocsResult<NoteRoot> {
        let main = self.main_root()?;
        match folder.map(str::trim).filter(|f| !f.is_empty()) {
            None => Ok(main),
            Some(id) if id == main.id() => Ok(main),
            Some(id) => {
                let config = self.inbox.config()?;
                config
                    .note_roots()
                    .into_iter()
                    .find(|root| root.is_local() && root.id() == id)
                    .ok_or_else(|| {
                        DocsError::Invalid(format!("no hay ninguna carpeta de notas '{id}'"))
                    })
            }
        }
    }

    /// Guarda en la boveda algo que llega de una sesion de Claude Code.
    ///
    /// Es la excepcion acotada a "las notas no se editan desde una sesion": no
    /// hay ningun modelo reinterpretando nada, es el usuario diciendo "esto
    /// guardalo". Ver `notes/capture.rs`.
    ///
    /// **Nunca pisa una nota.** Con ruta explicita que ya existe, se anexa al
    /// final como una seccion con su hora; sin ruta, si el nombre del dia ya
    /// esta ocupado se busca el siguiente libre (`... (2).md`), igual que hace
    /// la papelera en `sync.rs`.
    pub fn capture_note(
        &self,
        text: &str,
        title: Option<&str>,
        path: Option<&str>,
        group: Option<&str>,
        source: Option<&str>,
        now: Timestamp,
    ) -> DocsResult<EditableNote> {
        let explicit_path = path.is_some();
        let mut captured = capture::prepare_capture(text, title, path, now)
            .map_err(|e| DocsError::Invalid(e.to_string()))?;

        // Con agrupacion y sin ruta, la nota nace dentro de la carpeta del grupo,
        // con el mismo nombre derivado que tendria en `inbox/`. Una ruta
        // explicita manda sobre el grupo: quien la pasa ya dijo donde.
        if !explicit_path {
            if let Some(name) = group.map(str::trim).filter(|g| !g.is_empty()) {
                let id = self.ensure_note_group(name)?;
                captured.path = groups::path_in_group(&captured.path, Some(&id));
            }
        }

        // Una ruta `@id/...` guarda en esa carpeta local; sin prefijo, en la
        // principal.
        let (root, inner) = self.locate_note(&captured.path)?;
        let project = &root.project;
        let (rel, full) = project.resolve_user_note(&inner, false)?;
        if full.exists() {
            // Una ruta que el usuario pidio a proposito se respeta y se anexa;
            // una derivada del titulo no puede robarle el sitio a otra nota del
            // mismo dia, asi que se aparta a un nombre libre.
            if explicit_path {
                let raw = std::fs::read(&full).map_err(|e| DocsError::io(&full, e))?;
                let document =
                    Document::parse(&raw).map_err(|e| DocsError::Invalid(format!("{rel}: {e}")))?;
                let body = capture::capture_section(&captured, now, &document.body);
                write_atomic(&full, &document.render(&body))?;
                self.changed();
                return self.open_note_for_edit(&root.virtual_path(&rel));
            }
            let free = free_capture_path(project, &rel)?;
            let (rel, full) = project.resolve_user_note(&free, false)?;
            self.write_captured(&full, &captured, source, now)?;
            return self.open_note_for_edit(&root.virtual_path(&rel));
        }

        self.write_captured(&full, &captured, source, now)?;
        self.open_note_for_edit(&root.virtual_path(&rel))
    }

    /// Las carpetas de notas: la boveda principal primero y despues las locales.
    pub fn note_folders(&self) -> DocsResult<Vec<crate::notes::roots::NoteFolderView>> {
        Ok(self.inbox.config()?.note_roots().iter().map(NoteRoot::view).collect())
    }

    /// Las agrupaciones de la boveda: sus carpetas, vestidas con el catalogo.
    pub fn note_groups(&self) -> DocsResult<Vec<groups::NoteGroupView>> {
        let config = self.inbox.config()?;
        let Some((notes, _)) = config.vault() else {
            return Ok(Vec::new());
        };
        let catalog = notes.groups.clone();
        let paths: Vec<String> = match self.notes_index(&config)? {
            Some(index) => index.notes().map(|note| note.path.clone()).collect(),
            None => Vec::new(),
        };
        Ok(groups::list_groups(paths.iter().map(String::as_str), &catalog))
    }

    /// Crea una agrupacion, o actualiza su nombre y color si ya existia.
    ///
    /// **Idempotente**: pedir dos veces la misma no crea dos. Crea la carpeta en
    /// el acto aunque este vacia, para que la agrupacion exista en el disco y no
    /// solo en la configuracion.
    ///
    /// `folder` es la carpeta de notas donde vive (id de su proyecto; `None`, la
    /// principal). Una agrupacion de una carpeta local lleva su prefijo:
    /// `@apuntes/clientes`.
    pub fn upsert_note_group(
        &self,
        name: &str,
        color: Option<&str>,
        id: Option<&str>,
        folder: Option<&str>,
    ) -> DocsResult<groups::NoteGroupView> {
        // Con `id` se edita una agrupacion que ya existe y `name` es solo lo que
        // se enseña: **renombrarla no mueve la carpeta**. Sin esta distincion,
        // cambiar el nombre visible de "Tandas de ODM" a "Vuelos" crearia una
        // carpeta `vuelos` nueva y dejaria las notas en la vieja. Y el `id` ya dice
        // en que carpeta de notas esta, asi que manda sobre `folder`.
        let (root, source) = match id.map(str::trim).filter(|i| !i.is_empty()) {
            Some(existing) => {
                let (local, group) = split_virtual(existing);
                (self.folder_root(local)?, group.to_string())
            }
            None => (self.folder_root(folder)?, name.to_string()),
        };
        let slug = groups::validate_group_name(&source).map_err(DocsError::Invalid)?;
        let id = format!("{}{slug}", root.prefix);
        let color = match color.map(str::trim).filter(|c| !c.is_empty()) {
            Some(color) => Some(groups::validate_color(color).map_err(DocsError::Invalid)?),
            None => None,
        };

        let dir = PathBuf::from(&root.project.repo_root).join(&slug);
        std::fs::create_dir_all(&dir).map_err(|e| DocsError::io(&dir, e))?;

        let mut config = self.inbox.config()?;
        let notes = config.notes.as_mut().ok_or_else(|| {
            DocsError::Invalid("no hay ninguna boveda configurada para el asistente de notas".into())
        })?;
        let display = name.trim().to_string();
        match notes.groups.iter_mut().find(|g| g.id == id) {
            Some(existing) => {
                // Pasar el nombre de la carpeta tal cual ("odm") no es pedir un
                // nombre nuevo: no puede pisar el bonito ("Tandas de ODM").
                if !display.is_empty() && display != slug && display != id {
                    existing.name = display;
                }
                if let Some(color) = color {
                    existing.color_hex = color;
                }
            }
            None => {
                let order = notes.groups.iter().map(|g| g.order).max().map_or(0, |o| o + 1);
                notes.groups.push(NoteGroup {
                    id: id.clone(),
                    name: if display.is_empty() { slug.clone() } else { display },
                    color_hex: color.unwrap_or_else(|| groups::DEFAULT_GROUP_COLOR.to_string()),
                    order,
                });
            }
        }
        self.inbox.save_config(&config)?;
        self.changed();

        self.note_groups()?
            .into_iter()
            .find(|g| g.id == id)
            .ok_or_else(|| DocsError::Invalid(format!("la agrupacion '{id}' no aparecio tras crearla")))
    }

    /// El id de la agrupacion, dandola de alta en el catalogo si todavia no
    /// estaba. **No toca una que ya existia**: guardar una nota en un grupo no
    /// puede cambiarle el nombre ni el color que eligio el usuario.
    fn ensure_note_group(&self, name: &str) -> DocsResult<String> {
        let id = groups::validate_group_name(name).map_err(DocsError::Invalid)?;
        let config = self.inbox.config()?;
        let known = config
            .notes
            .as_ref()
            .is_some_and(|notes| notes.groups.iter().any(|g| g.id == id));
        if !known {
            self.upsert_note_group(name, None, None, None)?;
        }
        Ok(id)
    }

    /// Mueve una nota a otra agrupacion, o la saca a `inbox/` con `group` vacio; y
    /// con `folder` (id del proyecto de destino), a otra carpeta de notas.
    ///
    /// **Una agrupacion es una carpeta** (ver `notes/groups.rs`), asi que esto
    /// mueve el fichero. Y la ruta es la identidad de la nota en medio sistema,
    /// por eso no es un `rename` suelto. En orden:
    ///
    /// 1. **Se niega si hay una propuesta esperando sobre esa nota.** La propuesta
    ///    guarda el hash de cada fichero por ruta: movida la nota, ya no podria
    ///    aplicarse. Reescribir propuestas por dentro seria mas fragil que pedir
    ///    que se decida antes.
    /// 2. **Nunca pisa**: si en el grupo ya hay una nota con ese nombre, se aparta
    ///    a uno libre.
    /// 3. **Reapunta los digests.** Solo el campo `note`: mover no cambia el
    ///    contenido, asi que `note_hash` y `settled_hash` siguen valiendo. Sin esto
    ///    el modo automatico reprocesaria la nota como si fuera nueva.
    /// 4. **Reescribe los `[[enlaces]]` que la citaban por ruta** en toda la
    ///    boveda, `privado/` incluido. Los que la citan por nombre suelto siguen
    ///    funcionando solos; los que llevan ruta son los que hoy se rompen en
    ///    silencio, y el autocompletado del editor propone justo ese estilo.
    pub fn move_note(
        &self,
        path: &str,
        group: Option<&str>,
        folder: Option<&str>,
    ) -> DocsResult<MoveOutcome> {
        let (source, inner) = self.locate_note(path)?;
        let (from_rel, from_full) = source.project.resolve_user_note(&inner, true)?;
        let from = source.virtual_path(&from_rel);
        // Sin carpeta de destino, la de la nota.
        let target = match folder.map(str::trim).filter(|f| !f.is_empty()) {
            Some(_) => self.folder_root(folder)?,
            None => source.clone(),
        };
        let across = target.id() != source.id();

        let group = match group.map(str::trim).filter(|g| !g.is_empty()) {
            // `privado` no es una agrupacion (es una carpeta reservada), pero
            // mover una nota ahi si que es valido: es como se la esconde de los
            // agentes. Se acepta tal cual, sin la validacion de agrupacion.
            Some(name) if name.eq_ignore_ascii_case(PRIVATE_SEGMENT) => Some(PRIVATE_SEGMENT.to_string()),
            Some(name) => Some(groups::validate_group_name(name).map_err(DocsError::Invalid)?),
            None => None,
        };
        // Dentro de la misma carpeta, sin agrupacion es volver a la bandeja. Entre
        // carpetas, sin agrupacion **conserva su ruta**: quien mueve una nota a
        // otra carpeta de notas quiere llevarsela tal cual, no que caiga en un
        // `inbox/` que quiza esa carpeta ni tenia.
        let wanted = if across && group.is_none() {
            from_rel.clone()
        } else {
            groups::path_in_group(&from_rel, group.as_deref())
        };
        if !across && wanted.eq_ignore_ascii_case(&from_rel) {
            // Ya esta ahi: no hay nada que mover ni que reescribir.
            return Ok(MoveOutcome {
                to: from.clone(),
                from,
                relinked: Vec::new(),
                digests: 0,
            });
        }

        if let Some(proposal) = self.pending_proposal_for(&source.project.id, &from_rel)? {
            return Err(DocsError::Invalid(format!(
                "'{from}' tiene una propuesta esperando en el buzon ({proposal}). Apruebala o \
                descartala antes de moverla: movida, esa propuesta ya no podria aplicarse. No se \
                ha movido nada."
            )));
        }

        let (mut to_rel, mut to_full) = target.project.resolve_user_note(&wanted, false)?;
        if to_full.exists() {
            let free = free_capture_path(&target.project, &to_rel)?;
            (to_rel, to_full) = target.project.resolve_user_note(&free, false)?;
        }

        if let Some(dir) = to_full.parent() {
            std::fs::create_dir_all(dir).map_err(|e| DocsError::io(dir, e))?;
        }
        if across {
            move_across(&from_full, &to_full)?;
        } else {
            // Dentro de una misma carpeta, `rename`: atomico, y nunca cruza discos.
            std::fs::rename(&from_full, &to_full).map_err(|e| DocsError::io(&from_full, e))?;
        }
        let to = target.virtual_path(&to_rel);

        // Lo que sigue ya no puede deshacer el movimiento, asi que un fallo aqui se
        // devuelve con el fichero ya movido: es preferible a dejar la nota en su
        // sitio viejo con los digests a medio reapuntar.
        let digests = self.repoint_digests(&from, &to, &target.project.id)?;
        let relinked = self.relink_vault(&from, &to)?;

        self.changed();
        Ok(MoveOutcome {
            from,
            to,
            relinked,
            digests,
        })
    }

    /// El id de una propuesta pendiente que toca esa nota, si la hay.
    ///
    /// Por **proyecto y ruta dentro de su carpeta**: es como guardan las
    /// propuestas sus hashes, y dos carpetas pueden tener una `temas/x.md` cada
    /// una. Comparar solo la ruta bloquearia la nota de otra carpeta.
    fn pending_proposal_for(&self, project: &str, rel: &str) -> DocsResult<Option<String>> {
        // Un buzon que nunca genero propuestas no tiene la carpeta, y leerla falla:
        // eso es "ninguna", no un error.
        if !self.inbox.root().join("proposals").exists() {
            return Ok(None);
        }
        Ok(self
            .inbox
            .proposals()?
            .into_iter()
            .find(|p| {
                p.is_pending()
                    && p.project == project
                    && p.base_hashes.keys().any(|file| file.eq_ignore_ascii_case(rel))
            })
            .map(|p| p.id))
    }

    /// Los digests siguen a la nota, tambien a otra carpeta: su `project` pasa a
    /// ser el de destino, que es contra el que se procesara la proxima vez.
    fn repoint_digests(&self, from: &str, to: &str, project: &str) -> DocsResult<usize> {
        let mut count = 0;
        for mut digest in self.inbox.digests()? {
            if digest.note == from {
                digest.note = to.to_string();
                digest.project = project.to_string();
                self.inbox.save_digest(&digest)?;
                count += 1;
            }
        }
        Ok(count)
    }

    /// Reescribe, en **todas** las carpetas, los enlaces que citaban `from` por
    /// ruta para que citen `to` (las dos, rutas virtuales).
    ///
    /// Cada nota que enlaza lo hace en su forma (`link_form`): dentro de una
    /// misma carpeta local, relativo a ella; si no, con la ruta virtual. Por eso
    /// el texto a buscar y el de reemplazo se calculan por nota.
    fn relink_vault(&self, from: &str, to: &str) -> DocsResult<Vec<RelinkedNote>> {
        let config = self.inbox.config()?;
        let roots = config.note_roots();
        let mut relinked = Vec::new();
        for stamp in self.vault_manifest()?.notes {
            let Some((root, inner)) = locate(&roots, &stamp.path) else {
                continue;
            };
            let full = PathBuf::from(&root.project.repo_root).join(&inner);
            let Ok(raw) = std::fs::read(&full) else {
                continue;
            };
            // Un fichero que no es UTF-8 valido no se toca, igual que en el resto
            // del buzon: reescribirlo con perdida lo corromperia.
            let Ok(document) = Document::parse(&raw) else {
                continue;
            };
            let (body, links) = crate::notes::parse::rewrite_wikilinks(
                &document.body,
                &link_form(from, &stamp.path),
                &link_form(to, &stamp.path),
            );
            // Un enlace que ya estaba en su forma buena cuenta como encontrado pero
            // no cambia nada (una nota de la carpeta de destino que la citaba
            // relativa): no se reescribe ni se anuncia como tocada.
            if links == 0 || body == document.body {
                continue;
            }
            // `render` conserva el CRLF y el BOM que traia el fichero.
            write_atomic(&full, &document.render(&body))?;
            relinked.push(RelinkedNote {
                path: stamp.path,
                links,
            });
        }
        Ok(relinked)
    }

    fn write_captured(
        &self,
        full: &Path,
        captured: &capture::CapturedNote,
        source: Option<&str>,
        now: Timestamp,
    ) -> DocsResult<()> {
        let document = capture::capture_document(captured, source, now);
        if let SaveOutcome::Conflict { .. } = self.write_new(full, document.as_bytes())? {
            return Err(DocsError::Invalid(format!(
                "'{}' aparecio mientras se guardaba",
                captured.path
            )));
        }
        Ok(())
    }

    /// Escribe una nota que no existia. Si aparecio entretanto, no la pisa.
    fn write_new(&self, full: &Path, bytes: &[u8]) -> DocsResult<SaveOutcome> {
        if let Ok(raw) = std::fs::read(full) {
            return Ok(SaveOutcome::Conflict {
                disk_text: String::from_utf8_lossy(&raw).into_owned(),
                disk_hash: sha256_hex(&raw),
            });
        }
        if let Some(dir) = full.parent() {
            std::fs::create_dir_all(dir).map_err(|e| DocsError::io(dir, e))?;
        }
        write_atomic(full, bytes)?;
        self.changed();
        Ok(SaveOutcome::Saved {
            hash: sha256_hex(bytes),
        })
    }
}

fn is_private(rel: &str) -> bool {
    rel.to_lowercase()
        .split('/')
        .any(|segment| segment == PRIVATE_SEGMENT)
}

/// `dir/src` normalizada, o `None` si `src` es absoluta o se sale de la raiz.
/// Un `..` que vacie la pila se rechaza: el adjunto nunca sale de la boveda.
fn resolve_relative(dir: &str, src: &str) -> Option<String> {
    let src = src.trim().replace('\\', "/");
    if src.is_empty() || src.starts_with('/') || src.contains(':') {
        return None;
    }
    let mut parts: Vec<&str> = dir.split('/').filter(|segment| !segment.is_empty()).collect();
    for segment in src.split('/') {
        match segment {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            other => parts.push(other),
        }
    }
    Some(parts.join("/"))
}

/// El tipo de una imagen por su extension; si no, por su firma.
fn attachment_mime(rel: &str, bytes: &[u8]) -> String {
    let ext = rel.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_default();
    let mime = match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        "svg" => "image/svg+xml",
        _ => match bytes {
            [0x89, 0x50, ..] => "image/png",
            [0xFF, 0xD8, ..] => "image/jpeg",
            [0x47, 0x49, 0x46, ..] => "image/gif",
            _ => "application/octet-stream",
        },
    };
    mime.to_string()
}

/// Mueve un fichero a otra carpeta de notas, que puede estar en otro disco.
///
/// Primero `rename`, que en el mismo volumen es atomico. Si falla (volumenes
/// distintos), `copy_verified`.
fn move_across(from: &Path, to: &Path) -> DocsResult<()> {
    if std::fs::rename(from, to).is_ok() {
        return Ok(());
    }
    copy_verified(from, to)
}

/// Copia, relee la copia y compara, y **solo entonces** borra el original.
///
/// Es la unica forma de mover entre discos, y lo que se mueve es una nota del
/// usuario: si la copia no sale identica, se borra la copia y el original queda
/// donde estaba, en vez de arriesgarse a quedarse con una nota a medias.
fn copy_verified(from: &Path, to: &Path) -> DocsResult<()> {
    let bytes = std::fs::read(from).map_err(|e| DocsError::io(from, e))?;
    write_atomic(to, &bytes)?;
    let copied = std::fs::read(to).map_err(|e| DocsError::io(to, e))?;
    if sha256_hex(&copied) != sha256_hex(&bytes) {
        let _ = std::fs::remove_file(to);
        return Err(DocsError::Invalid(format!(
            "la copia de '{}' no salio identica: no se ha movido nada",
            from.display()
        )));
    }
    std::fs::remove_file(from).map_err(|e| DocsError::io(from, e))
}

/// `inbox/2026-09-16-resumen.md`, o `... (2).md` si ese nombre ya esta ocupado.
///
/// Dos envios con el mismo titulo el mismo dia caen en la misma ruta derivada, y
/// el segundo no puede llevarse por delante al primero. Mismo criterio que
/// `free_trash_path` en `sync.rs`.
fn free_capture_path(project: &DocProject, rel: &str) -> DocsResult<String> {
    let stem = rel.strip_suffix(".md").unwrap_or(rel);
    for copy in 2..1000 {
        let candidate = format!("{stem} ({copy}).md");
        let (_, full) = project.resolve_user_note(&candidate, false)?;
        if !full.exists() {
            return Ok(candidate);
        }
    }
    // Mil notas iguales el mismo dia no va a pasar; si pasara, el reloj da un
    // nombre libre en vez de fallar.
    Ok(format!("{stem} ({}).md", Timestamp::now().as_nanosecond()))
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Arc;

    use super::*;
    use crate::config::{InboxConfig, NotesConfig, ProjectKind};
    use crate::service::Backends;
    use crate::store::Inbox;

    struct Setup {
        service: Arc<DocsService>,
        root: PathBuf,
    }

    fn setup(name: &str) -> Setup {
        let root = crate::test_support::temp_dir(&format!("{name}-vault"));
        std::fs::create_dir_all(root.join("temas")).unwrap();
        std::fs::write(root.join("temas/crlf.md"), b"\xEF\xBB\xBF# Crlf\r\n\r\nlinea\r\n").unwrap();
        let inbox = Inbox::open(crate::test_support::temp_dir(&format!("{name}-inbox"))).unwrap();
        inbox
            .save_config(&InboxConfig {
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
                    digest_on_idle: false,
                    groups: vec![],
                    local_folders: vec![],
                }),
                ..InboxConfig::default()
            })
            .unwrap();
        Setup {
            service: DocsService::new(inbox, Backends::Fixed(vec![])),
            root,
        }
    }

    fn at_sept_15() -> Timestamp {
        "2026-09-15T15:00:00Z".parse().unwrap()
    }

    fn write(root: &Path, rel: &str, text: &str) {
        let full = root.join(rel);
        std::fs::create_dir_all(full.parent().unwrap()).unwrap();
        std::fs::write(full, text).unwrap();
    }

    /// Lo que hace que "una agrupacion es una carpeta" no rompa nada: el enlace
    /// que la citaba por ruta sigue apuntando bien y los digests la siguen.
    #[test]
    fn moving_a_note_relinks_the_vault_and_repoints_its_digests() {
        let s = setup("move-relink");
        write(&s.root, "inbox/malla.md", "# Malla\n");
        // Uno por ruta (se reescribe) y uno por nombre (resuelve solo, no se toca).
        write(&s.root, "temas/indice.md", "ver [[inbox/malla]] y [[malla]]\n");
        let digest: crate::notes::Digest = serde_json::from_str(
            r#"{"id":"d-1","project":"notas","note":"inbox/malla.md","trigger":"manual",
                "created_at":"x","updated_at":"x","status":{"state":"queued"}}"#,
        )
        .unwrap();
        s.service.inbox().save_digest(&digest).unwrap();

        let outcome = s.service.move_note("inbox/malla.md", Some("ODM"), None).unwrap();

        assert_eq!(outcome.to, "odm/malla.md");
        assert!(s.root.join("odm/malla.md").exists());
        assert!(!s.root.join("inbox/malla.md").exists());
        assert_eq!(
            std::fs::read_to_string(s.root.join("temas/indice.md")).unwrap(),
            "ver [[odm/malla]] y [[malla]]\n"
        );
        assert_eq!(
            outcome.relinked,
            vec![RelinkedNote {
                path: "temas/indice.md".into(),
                links: 1
            }]
        );
        assert_eq!(outcome.digests, 1);
        assert_eq!(s.service.inbox().digest("d-1").unwrap().note, "odm/malla.md");
    }

    /// Una nota del mismo nombre en el grupo de destino no se pisa nunca.
    #[test]
    fn moving_never_overwrites_and_can_go_back_to_the_inbox() {
        let s = setup("move-free");
        write(&s.root, "odm/nota.md", "# La que ya estaba\n");
        write(&s.root, "inbox/nota.md", "# La que llega\n");

        let moved = s.service.move_note("inbox/nota.md", Some("odm"), None).unwrap();
        assert_eq!(moved.to, "odm/nota (2).md");
        assert_eq!(
            std::fs::read_to_string(s.root.join("odm/nota.md")).unwrap(),
            "# La que ya estaba\n"
        );

        let back = s.service.move_note(&moved.to, None, None).unwrap();
        assert_eq!(back.to, "inbox/nota (2).md");
        assert!(s.root.join("inbox/nota (2).md").exists());
    }

    /// `privado` no es una agrupacion (es una carpeta reservada), pero mover una
    /// nota ahi si que es valido: es como se la esconde de los agentes.
    #[test]
    fn a_note_can_be_moved_to_privado_and_back_to_the_inbox() {
        let s = setup("move-private");
        write(&s.root, "inbox/claves.md", "# Claves\n");

        let moved = s.service.move_note("inbox/claves.md", Some("privado"), None).unwrap();
        assert_eq!(moved.to, "privado/claves.md");
        assert!(s.root.join("privado/claves.md").exists());
        assert!(!s.root.join("inbox/claves.md").exists());

        let back = s.service.move_note(&moved.to, None, None).unwrap();
        assert_eq!(back.to, "inbox/claves.md");
        assert!(s.root.join("inbox/claves.md").exists());
    }

    #[test]
    fn an_attachment_is_read_relative_to_its_note_and_never_escapes() {
        let s = setup("attachment");
        write(&s.root, "diario/2025-01-07.md", "# Notas\n");
        write(&s.root, "diario/imagenes/foo.png", "PNG");
        write(&s.root, "otra.png", "X");

        let found = s.service.read_attachment("diario/2025-01-07.md", "imagenes/foo.png").unwrap();
        assert_eq!(
            found.map(|(mime, bytes)| (mime, bytes.len())),
            Some(("image/png".to_string(), 3))
        );

        // `..` sale de la carpeta de la nota, pero sigue dentro de la boveda.
        let up = s.service.read_attachment("diario/2025-01-07.md", "../otra.png").unwrap();
        assert_eq!(up.map(|(_, bytes)| bytes.len()), Some(1));

        // Salirse de la boveda, o una ruta absoluta, no se sirve.
        assert!(s.service.read_attachment("diario/2025-01-07.md", "../../fuera.png").unwrap().is_none());
        assert!(s.service.read_attachment("diario/2025-01-07.md", "C:/Windows/x.png").unwrap().is_none());
        assert!(s.service.read_attachment("diario/2025-01-07.md", "imagenes/no.png").unwrap().is_none());
    }

    /// Movida, una propuesta pendiente ya no podria aplicarse: se decide antes.
    #[test]
    fn a_note_with_a_pending_proposal_is_not_moved() {
        let s = setup("move-pending");
        write(&s.root, "temas/pendiente.md", "# Pendiente\n");
        let proposal: crate::model::Proposal = serde_json::from_str(
            r#"{"id":"p-1","project":"notas","revision":1,"created_at":"x","updated_at":"x",
                "finding_ids":[],"summary":"s","operations":[],
                "base_hashes":{"temas/pendiente.md":"abc"},"model_label":"m",
                "status":{"state":"ready"}}"#,
        )
        .unwrap();
        s.service.inbox().save_proposal(&proposal).unwrap();

        let error = s.service.move_note("temas/pendiente.md", Some("odm"), None).unwrap_err();

        assert!(error.to_string().contains("propuesta"), "{error}");
        assert!(s.root.join("temas/pendiente.md").exists(), "no se tenia que mover");
        assert!(!s.root.join("odm").exists());
    }

    struct LocalSetup {
        service: Arc<DocsService>,
        main: PathBuf,
        local: PathBuf,
    }

    /// La boveda principal y una carpeta local `apuntes`, en dos directorios
    /// distintos: es el caso real, una carpeta que ya existia en otro sitio.
    fn setup_with_local(name: &str) -> LocalSetup {
        let main = crate::test_support::temp_dir(&format!("{name}-main"));
        let local = crate::test_support::temp_dir(&format!("{name}-local"));
        std::fs::create_dir_all(&main).unwrap();
        std::fs::create_dir_all(&local).unwrap();
        let vault = |id: &str, root: &Path| DocProject {
            id: id.into(),
            name: id.into(),
            repo_root: root.to_string_lossy().into_owned(),
            kind: ProjectKind::Vault,
            conventions: String::new(),
            documents: vec![],
        };
        let inbox = Inbox::open(crate::test_support::temp_dir(&format!("{name}-inbox"))).unwrap();
        inbox
            .save_config(&InboxConfig {
                projects: vec![vault("notas", &main), vault("apuntes", &local)],
                notes: Some(NotesConfig {
                    vault_project: "notas".into(),
                    repos: vec![],
                    digest_on_idle: false,
                    groups: vec![],
                    local_folders: vec!["apuntes".into()],
                }),
                ..InboxConfig::default()
            })
            .unwrap();
        LocalSetup {
            service: DocsService::new(inbox, Backends::Fixed(vec![])),
            main,
            local,
        }
    }

    /// Lo que pidio el usuario: la nota se edita **en su sitio**, y nada se copia
    /// a la boveda principal.
    #[test]
    fn a_local_note_is_edited_in_place() {
        let s = setup_with_local("local-edit");
        write(&s.local, "clientes/acme.md", "# Acme\n\nantes\n");

        let note = s.service.open_note_for_edit("@apuntes/clientes/acme.md").unwrap();
        assert_eq!(note.path, "@apuntes/clientes/acme.md");
        let outcome = s
            .service
            .save_note(&note.path, "# Acme\n\ndespues\n", Some(&note.hash))
            .unwrap();
        assert!(matches!(outcome, SaveOutcome::Saved { .. }), "{outcome:?}");
        assert_eq!(
            std::fs::read_to_string(s.local.join("clientes/acme.md")).unwrap(),
            "# Acme\n\ndespues\n"
        );
        assert!(!s.main.join("@apuntes").exists(), "nada se copia a la principal");
    }

    #[test]
    fn capturing_to_a_local_path_writes_in_that_folder() {
        let s = setup_with_local("local-capture");
        let note = s
            .service
            .capture_note("texto", Some("Idea"), Some("@apuntes/ideas/idea"), None, None, at_sept_15())
            .unwrap();
        assert_eq!(note.path, "@apuntes/ideas/idea.md");
        assert!(s.local.join("ideas/idea.md").exists());
    }

    /// Cada nota que enlaza se reescribe **en su propia forma**: dentro de la
    /// carpeta local, relativo a ella (como en Obsidian); desde la principal, con
    /// el prefijo.
    #[test]
    fn moving_inside_a_local_folder_relinks_in_each_notes_form() {
        let s = setup_with_local("local-move");
        write(&s.local, "inbox/acme.md", "# Acme\n");
        write(&s.local, "diario/hoy.md", "ver [[inbox/acme]]\n");
        write(&s.main, "temas/cliente.md", "ver [[@apuntes/inbox/acme]]\n");

        let moved = s.service.move_note("@apuntes/inbox/acme.md", Some("clientes"), None).unwrap();

        assert_eq!(moved.to, "@apuntes/clientes/acme.md");
        assert!(s.local.join("clientes/acme.md").exists());
        assert_eq!(
            std::fs::read_to_string(s.local.join("diario/hoy.md")).unwrap(),
            "ver [[clientes/acme]]\n"
        );
        assert_eq!(
            std::fs::read_to_string(s.main.join("temas/cliente.md")).unwrap(),
            "ver [[@apuntes/clientes/acme]]\n"
        );
        assert_eq!(moved.relinked.len(), 2);
    }

    /// El movil ve las dos carpetas sin saber que son dos, y lo que borra de una
    /// carpeta local va a la papelera **de esa carpeta**: puede estar en otro disco.
    #[test]
    fn the_manifest_covers_every_folder_and_the_trash_stays_in_each_one() {
        let s = setup_with_local("local-sync");
        write(&s.main, "temas/a.md", "# A\n");
        write(&s.local, "b.md", "# B\n");

        let paths: Vec<String> = s
            .service
            .vault_manifest()
            .unwrap()
            .notes
            .into_iter()
            .map(|note| note.path)
            .collect();
        assert!(paths.contains(&"temas/a.md".to_string()), "{paths:?}");
        assert!(paths.contains(&"@apuntes/b.md".to_string()), "{paths:?}");

        let outcome = s.service.delete_note("@apuntes/b.md", None).unwrap();
        assert!(
            matches!(outcome, crate::notes::DeleteOutcome::Trashed { .. }),
            "{outcome:?}"
        );
        assert!(s.local.join(".trash/b.md").exists());
        assert!(!s.main.join(".trash").exists());
    }

    /// Entre carpetas la nota **conserva su ruta**, se va del origen, se lleva sus
    /// digests, y cada enlace se reescribe en la forma de la nota que lo escribe.
    #[test]
    fn moving_across_folders_moves_the_file_and_relinks_both_sides() {
        let s = setup_with_local("local-across");
        write(&s.main, "temas/malla.md", "# Malla\n\nLa malla 3D de la tanda R, con texto suficiente.\n");
        write(&s.main, "diario/hoy.md", "ver [[temas/malla]]\n");
        write(&s.local, "otra/indice.md", "ver [[@apuntes/temas/malla]]\n");
        let digest = s
            .service
            .digest_note("temas/malla.md", crate::notes::DigestTrigger::Manual, at_sept_15())
            .unwrap();

        let moved = s.service.move_note("temas/malla.md", None, Some("apuntes")).unwrap();

        assert_eq!(moved.to, "@apuntes/temas/malla.md");
        assert!(s.local.join("temas/malla.md").exists());
        assert!(!s.main.join("temas/malla.md").exists(), "se va del origen");
        // Desde la principal hace falta el prefijo...
        assert_eq!(
            std::fs::read_to_string(s.main.join("diario/hoy.md")).unwrap(),
            "ver [[@apuntes/temas/malla]]\n"
        );
        // ...y la digest la sigue, con el proyecto de destino.
        let digest = s.service.inbox().digest(&digest.id).unwrap();
        assert_eq!(digest.note, "@apuntes/temas/malla.md");
        assert_eq!(digest.project, "apuntes");
    }

    /// Lo que usa mover entre discos: la copia sale byte a byte (BOM y CRLF
    /// incluidos) y el original desaparece.
    #[test]
    fn a_verified_copy_keeps_every_byte_and_removes_the_original() {
        let dir = crate::test_support::temp_dir("copy-verified");
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        let from = dir.join("a.md");
        let to = dir.join("sub/b.md");
        std::fs::write(&from, "\u{FEFF}# A\r\nñandú\r\n").unwrap();

        copy_verified(&from, &to).unwrap();

        assert!(!from.exists());
        assert_eq!(std::fs::read(&to).unwrap(), "\u{FEFF}# A\r\nñandú\r\n".as_bytes());
    }

    /// Cada carpeta tiene sus agrupaciones, y editar una por su id no crea otra.
    #[test]
    fn a_local_folder_has_its_own_groups() {
        let s = setup_with_local("local-groups");
        write(&s.local, "clientes/acme.md", "# Acme\n");
        write(&s.main, "clientes/otro.md", "# Otro\n");

        let group = s
            .service
            .upsert_note_group("Clientes", Some("#10B981"), None, Some("apuntes"))
            .unwrap();
        assert_eq!(group.id, "@apuntes/clientes");
        assert_eq!(group.notes, 1);

        let ids: Vec<String> = s.service.note_groups().unwrap().into_iter().map(|g| g.id).collect();
        assert!(ids.contains(&"clientes".to_string()), "{ids:?}");
        assert!(ids.contains(&"@apuntes/clientes".to_string()), "{ids:?}");

        let edited = s
            .service
            .upsert_note_group("Clientes activos", None, Some("@apuntes/clientes"), None)
            .unwrap();
        assert_eq!(edited.id, "@apuntes/clientes");
        assert_eq!(edited.name, "Clientes activos");
        assert!(!s.local.join("clientes-activos").exists(), "renombrar no crea carpeta");
    }

    /// El digest se asocia al proyecto de su carpeta: es contra esa raiz como se
    /// valida y se aprueba luego la propuesta.
    #[test]
    fn a_local_note_is_digested_with_its_own_project() {
        let s = setup_with_local("local-digest");
        write(
            &s.local,
            "clientes/acme.md",
            "# Acme\n\nEl cliente de la malla 3D, con bastante texto para que merezca la pena procesarlo.\n",
        );
        let digest = s
            .service
            .digest_note("@apuntes/clientes/acme.md", crate::notes::DigestTrigger::Manual, at_sept_15())
            .unwrap();
        assert_eq!(digest.note, "@apuntes/clientes/acme.md");
        assert_eq!(digest.project, "apuntes");
    }

    #[test]
    fn saving_keeps_crlf_and_bom_and_returns_the_new_hash() {
        let s = setup("edit-crlf");
        let note = s.service.open_note_for_edit("temas/crlf").unwrap();
        assert_eq!(note.path, "temas/crlf.md");
        assert_eq!(note.text, "# Crlf\n\nlinea\n");
        assert!(!note.private);

        let outcome = s
            .service
            .save_note(&note.path, "# Crlf\n\nlinea\notra ñandú\n", Some(&note.hash))
            .unwrap();
        let SaveOutcome::Saved { hash } = outcome else { panic!("{outcome:?}") };
        let raw = std::fs::read(s.root.join("temas/crlf.md")).unwrap();
        assert_eq!(raw, "\u{FEFF}# Crlf\r\n\r\nlinea\r\notra ñandú\r\n".as_bytes());
        assert_eq!(hash, sha256_hex(&raw));

        // Guardar lo mismo otra vez no reescribe nada.
        let again = s
            .service
            .save_note(&note.path, "# Crlf\n\nlinea\notra ñandú\n", Some(&hash))
            .unwrap();
        assert_eq!(again, SaveOutcome::Saved { hash });
    }

    #[test]
    fn a_change_made_elsewhere_is_never_overwritten() {
        let s = setup("edit-conflict");
        let note = s.service.open_note_for_edit("temas/crlf.md").unwrap();
        std::fs::write(s.root.join("temas/crlf.md"), "# Editada en Obsidian\n").unwrap();

        let outcome = s
            .service
            .save_note(&note.path, "lo del editor", Some(&note.hash))
            .unwrap();
        let SaveOutcome::Conflict { disk_text, .. } = outcome else { panic!("{outcome:?}") };
        assert_eq!(disk_text, "# Editada en Obsidian\n");
        assert_eq!(
            std::fs::read_to_string(s.root.join("temas/crlf.md")).unwrap(),
            "# Editada en Obsidian\n"
        );

        std::fs::remove_file(s.root.join("temas/crlf.md")).unwrap();
        let gone = s.service.save_note(&note.path, "x", Some(&note.hash)).unwrap();
        assert_eq!(
            gone,
            SaveOutcome::Conflict {
                disk_text: String::new(),
                disk_hash: String::new()
            }
        );
    }

    #[test]
    fn a_new_note_never_replaces_an_existing_one() {
        let s = setup("edit-new");
        let created = s.service.save_note("temas/nueva", "# Nueva\n", None).unwrap();
        assert!(matches!(created, SaveOutcome::Saved { .. }));
        assert_eq!(std::fs::read_to_string(s.root.join("temas/nueva.md")).unwrap(), "# Nueva\n");

        let clash = s.service.save_note("temas/nueva.md", "otra cosa", None).unwrap();
        assert!(matches!(clash, SaveOutcome::Conflict { .. }));
        assert_eq!(std::fs::read_to_string(s.root.join("temas/nueva.md")).unwrap(), "# Nueva\n");
    }

    #[tokio::test]
    async fn a_private_note_is_editable_but_never_reaches_the_index() {
        let s = setup("edit-private");
        let note = s
            .service
            .create_note("privado/claves", "Claves", at_sept_15())
            .unwrap();
        assert!(note.private);
        assert_eq!(note.text, "---\ndate: 2026-09-15\n---\n# Claves\n\n");

        let saved = s
            .service
            .save_note(&note.path, "# Claves\n\nmalla secreta\n", Some(&note.hash))
            .unwrap();
        assert!(matches!(saved, SaveOutcome::Saved { .. }));
        assert!(s.service.open_note_for_edit("privado/claves.md").unwrap().private);

        let overview = s.service.notes_overview().unwrap();
        assert!(!overview.notes.iter().any(|n| n.path.starts_with("privado")));
        assert!(s.service.search_notes("malla secreta", 10).unwrap().is_empty());
        assert!(!s
            .service
            .link_targets()
            .unwrap()
            .iter()
            .any(|t| t.target.starts_with("privado")));
        // Pero un enlace escrito a mano a la privada si se sigue desde el editor.
        assert_eq!(
            s.service.resolve_note_link("privado/claves", None).unwrap().as_deref(),
            Some("privado/claves.md")
        );
    }

    #[test]
    fn paths_that_escape_or_hide_are_refused() {
        let s = setup("edit-escape");
        for bad in ["../fuera", "temas/../../fuera.md", ".obsidian/workspace", "temas/.oculta/x"] {
            assert!(
                matches!(s.service.save_note(bad, "x", None), Err(DocsError::Invalid(_))),
                "{bad} tendria que rechazarse"
            );
        }
        assert!(matches!(
            s.service.open_note_for_edit("temas/no-existe"),
            Err(DocsError::NotFound(_))
        ));
    }

    #[test]
    fn a_junction_cannot_take_a_new_note_out_of_the_vault() {
        let s = setup("edit-junction");
        let outside = crate::test_support::temp_dir("edit-junction-outside");
        let link = s.root.join("temas").join("salida");
        let made = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&outside)
            .output()
            .is_ok_and(|o| o.status.success());
        if !made {
            // Sin junctions en esta maquina no hay nada que probar.
            return;
        }
        let result = s.service.save_note("temas/salida/robada", "x", None);
        assert!(matches!(result, Err(DocsError::Invalid(_))), "{result:?}");
        assert!(!outside.join("robada.md").exists());
    }

    #[tokio::test]
    async fn the_daily_note_is_created_once_with_its_spanish_heading() {
        let s = setup("edit-daily");
        let first = s.service.open_daily_note(at_sept_15()).unwrap();
        assert_eq!(first.path, "diario/2026-09-15.md");
        assert_eq!(first.text, "# 15 de septiembre de 2026\n\n");

        let edited = s
            .service
            .save_note(&first.path, "# 15 de septiembre de 2026\n\nalgo\n", Some(&first.hash))
            .unwrap();
        assert!(matches!(edited, SaveOutcome::Saved { .. }));
        let second = s.service.open_daily_note(at_sept_15()).unwrap();
        assert_eq!(second.text, "# 15 de septiembre de 2026\n\nalgo\n", "abrirla otra vez no la pisa");

        let targets = s.service.link_targets().unwrap();
        assert!(targets.iter().any(|t| t.target == "diario/2026-09-15"), "{targets:?}");
    }

    #[test]
    fn creating_a_note_that_exists_opens_it_instead() {
        let s = setup("edit-create-existing");
        let note = s.service.create_note("temas/crlf", "Otro titulo", at_sept_15()).unwrap();
        assert_eq!(note.text, "# Crlf\n\nlinea\n");
    }
}
