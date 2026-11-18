//! La boveda entera para un cliente que guarda su propia copia (el movil).
//!
//! Esto **no** es el indice. El indice es lo que ven los agentes, y por eso
//! salta `privado/` (`notes/index.rs`). Aca el destinatario es el usuario en su
//! telefono, que quiere sus notas **todas**, privadas incluidas. Lo que sigue
//! fuera son las carpetas ocultas (`.obsidian`, `.git`, `.trash`) y los enlaces
//! simbolicos, que podrian sacar la lectura de la boveda.
//!
//! El manifiesto va aparte del texto a proposito: la lista de rutas con su hash
//! es pequena y se pide seguido para saber que cambio; el texto solo se pide de
//! lo que de verdad cambio.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::config::normalize_rel;
use crate::error::{DocsError, DocsResult};
use crate::markdown::Document;
use crate::notes::roots::is_local_marker;
use crate::service::DocsService;
use crate::store::sha256_hex;

/// La carpeta donde va lo borrado. Empieza por punto, asi que queda fuera del
/// indice, de las busquedas y de este mismo manifiesto.
pub const TRASH_DIR: &str = ".trash";

/// Una nota de la boveda, sin su texto.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoteStamp {
    /// Relativa a la boveda, con `/` y `.md`.
    pub path: String,
    /// sha256 del fichero tal como esta en disco.
    pub hash: String,
    /// Cuando cambio, en segundos desde epoca. Es lo que da el sistema de
    /// ficheros (`SystemTime`), igual que en el indice, y al cliente le basta
    /// para ordenar y para decidir cual es mas nueva. `None` si no lo dice.
    pub modified_secs: Option<i64>,
    /// Esta en `privado/`: ningun agente la lee, pero el usuario si.
    pub private: bool,
}

/// Todas las notas de la boveda con su hash: con esto un cliente sabe que le
/// falta, que le sobra y que cambio, sin bajarse nada.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VaultManifest {
    pub notes: Vec<NoteStamp>,
}

/// Que paso al borrar.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum DeleteOutcome {
    /// Movida a `.trash/`, de donde se puede recuperar a mano.
    Trashed { trashed_path: String },
    /// En disco hay otra cosa que lo que tenia el cliente: no se borro nada.
    Conflict { disk_text: String, disk_hash: String },
    /// Ya no estaba. Borrar dos veces no es un error: el cliente que reintenta
    /// tras quedarse sin conexion tiene que poder terminar.
    Missing,
}

impl DocsService {
    /// La lista de notas de la boveda con su hash, privadas incluidas.
    ///
    /// **Todas las carpetas de notas**, cada nota con su ruta virtual (`@id/...`
    /// en las locales). El movil no necesita saber que son varias: su espejo usa
    /// la ruta como clave, y el protocolo no la interpreta.
    pub fn vault_manifest(&self) -> DocsResult<VaultManifest> {
        let config = self.inbox.config()?;
        let roots = config.note_roots();
        if roots.is_empty() {
            return Err(DocsError::Invalid(
                "no hay ninguna boveda configurada para el asistente de notas".to_string(),
            ));
        }
        let mut files = Vec::new();
        for note_root in &roots {
            let base = PathBuf::from(&note_root.project.repo_root);
            // Una carpeta local desconectada no vacia el manifiesto de las demas.
            if !base.is_dir() {
                continue;
            }
            let mut found = Vec::new();
            walk(&base, &base, !note_root.is_local(), &mut found);
            files.extend(
                found
                    .into_iter()
                    .map(|(rel, full)| (note_root.virtual_path(&rel), full)),
            );
        }
        files.sort_by(|a, b| a.0.cmp(&b.0));

        let mut notes = Vec::with_capacity(files.len());
        for (rel, full) in files {
            let raw = match std::fs::read(&full) {
                Ok(raw) => raw,
                // Una nota que desaparece a mitad del recorrido no rompe la foto:
                // el cliente la pedira en la vuelta siguiente.
                Err(_) => continue,
            };
            notes.push(NoteStamp {
                private: is_private(&rel),
                hash: sha256_hex(&raw),
                modified_secs: modified_at(&full),
                path: rel,
            });
        }
        Ok(VaultManifest { notes })
    }

    /// Borra una nota moviendola a `.trash/`. Solo si el cliente tenia la
    /// version que hay en disco: si alguien la edito mientras tanto, se avisa y
    /// no se borra nada.
    ///
    /// `base_hash` en `None` borra sin comprobar, que es lo que hace falta
    /// cuando el usuario borra una nota que acaba de ver.
    pub fn delete_note(&self, path: &str, base_hash: Option<&str>) -> DocsResult<DeleteOutcome> {
        let (note_root, inner) = self.locate_note(path)?;
        let project = &note_root.project;
        let (rel, full) = project.resolve_user_note(&inner, false)?;
        let raw = match std::fs::read(&full) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(DeleteOutcome::Missing),
            Err(e) => return Err(DocsError::io(&full, e)),
        };
        let disk_hash = sha256_hex(&raw);
        if let Some(base) = base_hash {
            if base != disk_hash {
                let disk_text = Document::parse(&raw)
                    .map(|d| d.body)
                    .unwrap_or_else(|_| String::from_utf8_lossy(&raw).into_owned());
                return Ok(DeleteOutcome::Conflict {
                    disk_text,
                    disk_hash,
                });
            }
        }

        let root = PathBuf::from(&project.repo_root);
        let trashed = free_trash_path(&root, &rel);
        let target = root.join(&trashed);
        if let Some(dir) = target.parent() {
            std::fs::create_dir_all(dir).map_err(|e| DocsError::io(dir, e))?;
        }
        // `rename` no vale entre volumenes distintos. Por eso la papelera va
        // **dentro de la carpeta de cada nota** (`<carpeta>/.trash`) y no en la
        // principal: una carpeta local puede estar en otro disco.
        std::fs::rename(&full, &target).map_err(|e| DocsError::io(&full, e))?;
        self.changed();
        Ok(DeleteOutcome::Trashed {
            trashed_path: note_root.virtual_path(&trashed),
        })
    }
}

/// `temas/malla.md` -> `.trash/temas/malla.md`, y si ya hay una borrada con ese
/// nombre, `malla (2).md`. Borrar dos veces la misma nota no puede perder la
/// primera.
fn free_trash_path(root: &Path, rel: &str) -> String {
    let base = format!("{TRASH_DIR}/{rel}");
    if !root.join(&base).exists() {
        return base;
    }
    let stem = rel.strip_suffix(".md").unwrap_or(rel);
    for copy in 2..1000 {
        let candidate = format!("{TRASH_DIR}/{stem} ({copy}).md");
        if !root.join(&candidate).exists() {
            return candidate;
        }
    }
    format!("{TRASH_DIR}/{stem} ({}).md", jiff::Timestamp::now().as_nanosecond())
}

fn modified_at(path: &Path) -> Option<i64> {
    let system = std::fs::metadata(path).ok()?.modified().ok()?;
    let since = system.duration_since(std::time::UNIX_EPOCH).ok()?;
    i64::try_from(since.as_secs()).ok()
}

fn is_private(rel: &str) -> bool {
    rel.to_lowercase()
        .split('/')
        .any(|segment| segment == crate::config::PRIVATE_SEGMENT)
}

/// Los `.md` de la boveda, `privado/` incluido. Quedan fuera las carpetas
/// ocultas (`.obsidian`, `.git`, `.trash`) y los enlaces simbolicos.
///
/// Con `skip_markers`, tambien las carpetas de primer nivel que empiezan por `@`:
/// en la boveda principal chocarian con el prefijo de una carpeta local.
fn walk(root: &Path, dir: &Path, skip_markers: bool, out: &mut Vec<(String, PathBuf)>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_symlink() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        if kind.is_dir() {
            if skip_markers && dir == root && is_local_marker(&name) {
                continue;
            }
            walk(root, &path, skip_markers, out);
        } else if name.to_lowercase().ends_with(".md") {
            if let Ok(rel) = path.strip_prefix(root) {
                out.push((normalize_rel(&rel.to_string_lossy()), path));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Arc;

    use super::*;
    use crate::config::{DocProject, InboxConfig, NotesConfig, ProjectKind};
    use crate::service::Backends;
    use crate::store::Inbox;

    struct Setup {
        service: Arc<DocsService>,
        root: PathBuf,
    }

    fn write(root: &Path, rel: &str, text: &str) {
        let path = root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn setup(name: &str) -> Setup {
        let root = crate::test_support::temp_dir(&format!("{name}-vault"));
        write(&root, "temas/malla.md", "# Malla\n\nla ortofoto\n");
        write(&root, "privado/claves.md", "# Claves\n\nsecreto\n");
        write(&root, "diario/2026-09-15.md", "# 15 de septiembre\n");
        write(&root, ".obsidian/workspace.md", "# no es una nota\n");
        write(&root, "temas/notas.txt", "no es markdown\n");

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

    fn paths(manifest: &VaultManifest) -> Vec<&str> {
        manifest.notes.iter().map(|n| n.path.as_str()).collect()
    }

    #[test]
    fn the_manifest_carries_the_private_notes_but_not_the_hidden_folders() {
        let s = setup("sync-manifest");
        let manifest = s.service.vault_manifest().unwrap();
        assert_eq!(
            paths(&manifest),
            ["diario/2026-09-15.md", "privado/claves.md", "temas/malla.md"],
            "ordenado, con privado/ dentro y sin .obsidian ni .txt"
        );

        let private = manifest.notes.iter().find(|n| n.path.starts_with("privado")).unwrap();
        assert!(private.private);
        assert!(!manifest.notes[2].private);

        // El hash es el del fichero, el mismo que usa guardar.
        let raw = std::fs::read(s.root.join("temas/malla.md")).unwrap();
        assert_eq!(manifest.notes[2].hash, sha256_hex(&raw));
        assert!(manifest.notes[2].modified_secs.is_some());
    }

    #[test]
    fn a_note_that_changes_changes_its_hash() {
        let s = setup("sync-hash");
        let before = s.service.vault_manifest().unwrap();
        s.service
            .save_note("temas/malla.md", "# Malla\n\notra cosa\n", Some(&before.notes[2].hash))
            .unwrap();
        let after = s.service.vault_manifest().unwrap();
        assert_ne!(before.notes[2].hash, after.notes[2].hash);
        assert_eq!(paths(&before), paths(&after));
    }

    #[test]
    fn deleting_moves_the_note_to_the_trash_and_out_of_the_manifest() {
        let s = setup("sync-delete");
        let outcome = s.service.delete_note("temas/malla", None).unwrap();
        assert_eq!(
            outcome,
            DeleteOutcome::Trashed {
                trashed_path: ".trash/temas/malla.md".into()
            }
        );
        assert!(!s.root.join("temas/malla.md").exists());
        assert_eq!(
            std::fs::read_to_string(s.root.join(".trash/temas/malla.md")).unwrap(),
            "# Malla\n\nla ortofoto\n",
            "lo borrado se puede recuperar a mano"
        );

        let manifest = s.service.vault_manifest().unwrap();
        assert_eq!(paths(&manifest), ["diario/2026-09-15.md", "privado/claves.md"]);
    }

    #[test]
    fn deleting_twice_keeps_the_first_one_and_never_fails() {
        let s = setup("sync-delete-twice");
        s.service.delete_note("temas/malla.md", None).unwrap();
        std::fs::write(s.root.join("temas/malla.md"), "# Malla otra vez\n").unwrap();

        let second = s.service.delete_note("temas/malla.md", None).unwrap();
        assert_eq!(
            second,
            DeleteOutcome::Trashed {
                trashed_path: ".trash/temas/malla (2).md".into()
            }
        );
        assert_eq!(
            std::fs::read_to_string(s.root.join(".trash/temas/malla.md")).unwrap(),
            "# Malla\n\nla ortofoto\n",
            "la primera borrada sigue ahi"
        );

        // Y borrar lo que ya no esta no es un error.
        assert_eq!(
            s.service.delete_note("temas/malla.md", None).unwrap(),
            DeleteOutcome::Missing
        );
    }

    #[test]
    fn a_note_changed_elsewhere_is_never_deleted() {
        let s = setup("sync-delete-conflict");
        let manifest = s.service.vault_manifest().unwrap();
        let stale = manifest.notes[2].hash.clone();
        std::fs::write(s.root.join("temas/malla.md"), "# Editada en Obsidian\n").unwrap();

        let outcome = s.service.delete_note("temas/malla.md", Some(&stale)).unwrap();
        assert!(matches!(
            outcome,
            DeleteOutcome::Conflict { ref disk_text, .. } if disk_text == "# Editada en Obsidian\n"
        ));
        assert!(s.root.join("temas/malla.md").exists(), "no se toco");
        assert!(!s.root.join(".trash/temas/malla.md").exists());
    }

    #[test]
    fn the_trash_is_not_a_place_to_write_notes() {
        let s = setup("sync-trash-guard");
        // `.trash` es una carpeta oculta: las rutas de usuario la rechazan, asi
        // que nadie puede editar ahi por accidente desde el editor.
        assert!(matches!(
            s.service.save_note(".trash/temas/malla.md", "x", None),
            Err(DocsError::Invalid(_))
        ));
        assert!(matches!(
            s.service.delete_note(".trash/temas/malla.md", None),
            Err(DocsError::Invalid(_))
        ));
    }
}
