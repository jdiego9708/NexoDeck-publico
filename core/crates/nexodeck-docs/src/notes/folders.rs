//! Elegir la boveda y añadir o quitar carpetas locales, desde la ventana de notas.
//!
//! Hasta ahora esto solo lo hacia la app editando el JSON del buzon
//! (`vault_config.dart`). La ventana del editor no tiene Dart detras, asi que
//! necesita hacerlo aqui, y aqui se hace **sobre la configuracion ya leida y
//! validada**: `save_config` pasa por `problems()`, que es quien sabe si una
//! carpeta pisa documentacion del buzon o esta dentro de otra. Nada se valida
//! dos veces.
//!
//! Ninguna de estas operaciones toca los ficheros de las notas: solo dicen de
//! donde leerlas.

use std::path::Path;

use crate::config::{DocProject, InboxConfig, NotesConfig, ProjectKind};
use crate::error::{DocsError, DocsResult};
use crate::notes::roots::{NoteFolderView, NoteRoot};
use crate::service::DocsService;

/// El id del proyecto de la boveda cuando no habia ninguna.
const VAULT_ID: &str = "notas";

impl DocsService {
    /// Usar [folder] como boveda principal. **No copia ni mueve nada**: la
    /// anterior se queda en el disco tal cual, solo deja de leerse.
    pub fn set_vault_folder(&self, folder: &str) -> DocsResult<NoteFolderView> {
        let path = existing_dir(folder)?;
        let mut config = self.inbox.config()?;
        match config.vault().map(|(notes, _)| notes.vault_project.clone()) {
            Some(id) => {
                let project = config
                    .projects
                    .iter_mut()
                    .find(|p| p.id == id)
                    .ok_or_else(|| DocsError::Invalid(format!("no hay ningun proyecto '{id}'")))?;
                project.repo_root = path;
            }
            None => {
                let id = unique_id(&config, VAULT_ID);
                config.projects.push(vault_project(&id, "Notas", path));
                let previous = config.notes.take();
                config.notes = Some(NotesConfig {
                    vault_project: id,
                    // Lo que el usuario ya tuviera (repositorios, modo automatico)
                    // se conserva aunque la boveda a la que apuntaba no existiera.
                    repos: previous.as_ref().map(|n| n.repos.clone()).unwrap_or_default(),
                    digest_on_idle: previous.as_ref().is_some_and(|n| n.digest_on_idle),
                    groups: previous.as_ref().map(|n| n.groups.clone()).unwrap_or_default(),
                    local_folders: previous.map(|n| n.local_folders).unwrap_or_default(),
                });
            }
        }
        self.inbox.save_config(&config)?;
        self.changed();
        main_view(&config)
    }

    /// Añadir una carpeta local. Si no se admite (documentacion del buzon,
    /// anidada, repetida), el error dice por que y la configuracion no cambia.
    pub fn add_local_folder(&self, folder: &str) -> DocsResult<NoteFolderView> {
        let path = existing_dir(folder)?;
        let mut config = self.inbox.config()?;
        if config.vault().is_none() {
            return Err(DocsError::Invalid(
                "primero elige la carpeta principal de notas (el espacio de NexoDeck)".into(),
            ));
        }
        let name = Path::new(&path)
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| path.clone());
        let id = unique_id(&config, &folder_id(&name));
        config.projects.push(vault_project(&id, &name, path));
        if let Some(notes) = config.notes.as_mut() {
            notes.local_folders.push(id.clone());
        }
        self.inbox.save_config(&config)?;
        self.changed();
        config
            .note_roots()
            .iter()
            .find(|root| root.is_local() && root.id() == id)
            .map(NoteRoot::view)
            .ok_or_else(|| DocsError::Invalid(format!("la carpeta '{name}' no se pudo leer")))
    }

    /// Quitar una carpeta local de NexoDeck. **No borra nada del disco**: sus
    /// notas siguen donde estaban, solo dejan de salir. Devuelve su nombre.
    pub fn remove_local_folder(&self, id: &str) -> DocsResult<String> {
        let mut config = self.inbox.config()?;
        let listed = config
            .notes
            .as_ref()
            .is_some_and(|notes| notes.local_folders.iter().any(|f| f == id));
        if !listed {
            return Err(DocsError::Invalid(format!("no hay ninguna carpeta local '{id}'")));
        }
        if let Some(notes) = config.notes.as_mut() {
            notes.local_folders.retain(|f| f != id);
        }
        let name = config.project(id).map(|p| p.name.clone()).unwrap_or_else(|| id.to_string());
        // El proyecto sale tambien: huerfano confundiria en el editor del buzon.
        // Solo si es de clase `vault`, que es lo unico que este codigo añade.
        config.projects.retain(|p| !(p.id == id && p.kind == ProjectKind::Vault));
        self.inbox.save_config(&config)?;
        self.changed();
        Ok(name)
    }
}

fn existing_dir(folder: &str) -> DocsResult<String> {
    let path = folder.trim();
    if path.is_empty() || !Path::new(path).is_absolute() {
        return Err(DocsError::Invalid(format!("'{path}' no es una ruta absoluta")));
    }
    if !Path::new(path).is_dir() {
        return Err(DocsError::Invalid(format!("la carpeta {path} no existe")));
    }
    Ok(path.to_string())
}

fn vault_project(id: &str, name: &str, path: String) -> DocProject {
    DocProject {
        id: id.to_string(),
        name: name.to_string(),
        repo_root: path,
        kind: ProjectKind::Vault,
        conventions: String::new(),
        documents: vec![],
    }
}

fn main_view(config: &InboxConfig) -> DocsResult<NoteFolderView> {
    config
        .note_roots()
        .first()
        .map(NoteRoot::view)
        .ok_or_else(|| DocsError::Invalid("la boveda no quedo configurada".into()))
}

/// Un id de proyecto valido (`problems()`): minusculas, cifras y guiones. Mismo
/// criterio que `folderId` en `vault_config.dart`, para que una carpeta añadida
/// desde la app o desde la ventana tenga el mismo id.
pub(crate) fn folder_id(name: &str) -> String {
    let mut id = String::new();
    for c in name.to_lowercase().chars() {
        let c = match c {
            'á' | 'à' | 'ä' | 'â' => 'a',
            'é' | 'è' | 'ë' | 'ê' => 'e',
            'í' | 'ì' | 'ï' | 'î' => 'i',
            'ó' | 'ò' | 'ö' | 'ô' => 'o',
            'ú' | 'ù' | 'ü' | 'û' => 'u',
            'ñ' => 'n',
            'ç' => 'c',
            other => other,
        };
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            id.push(c);
        } else if !id.ends_with('-') {
            id.push('-');
        }
    }
    let id = id.trim_matches('-');
    if id.is_empty() {
        "carpeta".to_string()
    } else {
        id.to_string()
    }
}

fn unique_id(config: &InboxConfig, base: &str) -> String {
    if config.project(base).is_none() {
        return base.to_string();
    }
    (2..)
        .map(|n| format!("{base}-{n}"))
        .find(|candidate| config.project(candidate).is_none())
        .expect("siempre hay un id libre")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::Backends;
    use crate::store::Inbox;

    fn service(name: &str) -> std::sync::Arc<DocsService> {
        let inbox = Inbox::open(crate::test_support::temp_dir(&format!("{name}-inbox"))).unwrap();
        DocsService::new(inbox, Backends::Fixed(vec![]))
    }

    fn dir(name: &str) -> String {
        let path = crate::test_support::temp_dir(name);
        std::fs::create_dir_all(&path).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn choosing_the_vault_creates_it_and_changing_it_keeps_the_rest() {
        let service = service("folders-vault");
        let first = dir("folders-vault-a");
        let view = service.set_vault_folder(&first).unwrap();
        assert!(!view.local);
        assert_eq!(view.path, first);

        let apuntes = dir("folders-vault-apuntes");
        service.add_local_folder(&apuntes).unwrap();

        let second = dir("folders-vault-b");
        service.set_vault_folder(&second).unwrap();
        let config = service.inbox().config().unwrap();
        let (notes, project) = config.vault().unwrap();
        assert_eq!(project.repo_root, second);
        assert_eq!(project.id, "notas");
        assert_eq!(notes.local_folders.len(), 1, "la carpeta local tenia que seguir");
        assert_eq!(config.projects.len(), 2, "cambiar la boveda no añade otro proyecto");
    }

    #[test]
    fn a_local_folder_is_added_with_a_safe_unique_id_and_removed_without_touching_disk() {
        let service = service("folders-local");
        service.set_vault_folder(&dir("folders-local-main")).unwrap();
        let apuntes = crate::test_support::temp_dir("folders-local").join("Notas Clientes");
        std::fs::create_dir_all(&apuntes).unwrap();
        std::fs::write(apuntes.join("acme.md"), "# Acme\n").unwrap();

        let view = service.add_local_folder(&apuntes.to_string_lossy()).unwrap();
        assert!(view.local && view.available);
        assert_eq!(view.id, "notas-clientes");
        assert_eq!(view.name, "Notas Clientes");

        let name = service.remove_local_folder("notas-clientes").unwrap();
        assert_eq!(name, "Notas Clientes");
        let config = service.inbox().config().unwrap();
        assert!(config.vault().unwrap().0.local_folders.is_empty());
        assert!(config.project("notas-clientes").is_none());
        assert!(apuntes.join("acme.md").exists(), "quitar no borra nada del disco");
    }

    #[test]
    fn what_cannot_be_added_says_why_and_changes_nothing() {
        let service = service("folders-refused");
        let loose = dir("folders-refused-loose");
        let err = service.add_local_folder(&loose).unwrap_err().to_string();
        assert!(err.contains("carpeta principal"), "{err}");

        let main = dir("folders-refused-main");
        service.set_vault_folder(&main).unwrap();
        let inside = Path::new(&main).join("dentro");
        std::fs::create_dir_all(&inside).unwrap();
        assert!(service.add_local_folder(&inside.to_string_lossy()).is_err());
        assert!(service.add_local_folder(r"Z:\no\existe").is_err());
        assert!(service.remove_local_folder("nada").is_err());
        let config = service.inbox().config().unwrap();
        assert!(config.vault().unwrap().0.local_folders.is_empty());
    }

    #[test]
    fn ids_match_the_app() {
        assert_eq!(folder_id("Apuntes Clientes"), "apuntes-clientes");
        assert_eq!(folder_id("Reunión  ñandú"), "reunion-nandu");
        assert_eq!(folder_id("***"), "carpeta");
    }
}
