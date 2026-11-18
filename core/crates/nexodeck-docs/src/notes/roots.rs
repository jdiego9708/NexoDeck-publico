//! Varias carpetas de notas a la vez: la boveda principal y las "notas locales".
//!
//! Una **carpeta local** es una carpeta de `.md` que el usuario ya tenia
//! organizada en otro sitio y que NexoDeck lee **donde esta**, sin copiarla.
//! Por dentro es un `DocProject` de clase `vault` mas, listado en
//! `NotesConfig.local_folders`: asi las propuestas, su validacion y su
//! aprobacion, que ya van por proyecto, funcionan sin tocarlas.
//!
//! **La identidad de una nota** es su ruta virtual:
//!
//! - en la boveda principal, **la de siempre** (`temas/malla.md`), para que no
//!   cambie nada de lo que ya existe: el espejo del movil, los digests, los
//!   enlaces y las agrupaciones;
//! - en una carpeta local, **`@<id>/<ruta dentro>`** (`@apuntes/clientes/acme.md`).
//!
//! Por que `@` y no otra marca: es la unica que pasa por todos los validadores
//! de ruta —Rust, la pagina del editor y Flutter— sin tocarlos. `:` lo rechazan
//! los dialogos y en NTFS es un flujo alternativo; una carpeta `_ext/` seria
//! indistinguible de una carpeta real. Los ids de proyecto ya solo admiten
//! minusculas, cifras y guiones, asi que el prefijo es seguro.
//!
//! Aqui no se lee ninguna nota. Esto decide **a que carpeta pertenece una ruta**
//! y **que carpetas no pueden convivir**.

use std::collections::HashSet;
use std::path::Path;

use crate::config::{normalize_rel, DocProject, InboxConfig, ProjectKind};

/// La marca de las rutas de una carpeta local.
pub const LOCAL_PREFIX: char = '@';

/// Una carpeta de notas.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteRoot {
    /// Vacio en la boveda principal; `@id/` en una carpeta local.
    pub prefix: String,
    pub project: DocProject,
}

impl NoteRoot {
    pub fn is_local(&self) -> bool {
        !self.prefix.is_empty()
    }

    pub fn id(&self) -> &str {
        &self.project.id
    }

    /// La ruta virtual de una nota de esta carpeta.
    pub fn virtual_path(&self, rel: &str) -> String {
        format!("{}{}", self.prefix, normalize_rel(rel))
    }
}

/// Una carpeta de notas tal como la enseña la interfaz.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteFolderView {
    /// El id de su proyecto. Es lo que se pasa para mover o crear una agrupacion
    /// en ella.
    pub id: String,
    pub name: String,
    /// La ruta real en disco.
    pub path: String,
    /// Es una carpeta local (no la boveda principal).
    pub local: bool,
    /// La carpeta existe ahora mismo. Una en un disco desconectado no tumba nada,
    /// pero la interfaz tiene que poder decir por que no enseña sus notas.
    pub available: bool,
}

impl NoteRoot {
    pub fn view(&self) -> NoteFolderView {
        NoteFolderView {
            id: self.project.id.clone(),
            name: self.project.name.clone(),
            path: self.project.repo_root.clone(),
            local: self.is_local(),
            available: Path::new(&self.project.repo_root).is_dir(),
        }
    }
}

/// `@id/`.
pub fn local_prefix(id: &str) -> String {
    format!("{LOCAL_PREFIX}{id}/")
}

/// Separa la carpeta de la ruta dentro de ella.
///
/// `@apuntes/clientes/acme.md` -> `(Some("apuntes"), "clientes/acme.md")`, y una
/// ruta de la principal -> `(None, ruta)`. No valida nada: eso lo hace
/// `resolve_user_note` sobre la raiz real.
pub fn split_virtual(path: &str) -> (Option<&str>, &str) {
    match path.strip_prefix(LOCAL_PREFIX) {
        Some(rest) => match rest.split_once('/') {
            Some((id, rel)) => (Some(id), rel),
            None => (Some(rest), ""),
        },
        None => (None, path),
    }
}

/// Un nombre de carpeta de primer nivel que chocaria con el prefijo. En la
/// boveda principal se salta al recorrerla, igual que las ocultas: una carpeta
/// real `@apuntes` seria indistinguible de la carpeta local `apuntes`.
pub fn is_local_marker(segment: &str) -> bool {
    segment.starts_with(LOCAL_PREFIX)
}

impl InboxConfig {
    /// Las carpetas de notas: la principal primero y despues las locales, en el
    /// orden en que se añadieron.
    ///
    /// Una entrada de `local_folders` que no apunta a un proyecto `vault` valido
    /// **se ignora aqui** y la denuncia `problems()`: una carpeta mal configurada
    /// no puede dejar sin notas a las demas.
    pub fn note_roots(&self) -> Vec<NoteRoot> {
        let Some((notes, main)) = self.vault() else {
            return Vec::new();
        };
        let mut roots = vec![NoteRoot {
            prefix: String::new(),
            project: main.clone(),
        }];
        for id in &notes.local_folders {
            if roots.iter().any(|root| root.id() == id) {
                continue;
            }
            if let Some(project) = self.project(id).filter(|p| p.kind == ProjectKind::Vault) {
                roots.push(NoteRoot {
                    prefix: local_prefix(id),
                    project: project.clone(),
                });
            }
        }
        roots
    }
}

/// La carpeta de una ruta virtual y la ruta dentro de ella.
///
/// **Es la costura central**: todo lo que antes pedia "la" boveda y resolvia una
/// ruta contra ella pasa por aqui. `None` si la ruta nombra una carpeta local que
/// no existe.
pub fn locate<'a>(roots: &'a [NoteRoot], path: &str) -> Option<(&'a NoteRoot, String)> {
    let normalized = normalize_rel(path);
    let (id, rel) = split_virtual(&normalized);
    let root = match id {
        Some(id) => roots.iter().find(|root| root.is_local() && root.id() == id)?,
        None => roots.iter().find(|root| !root.is_local())?,
    };
    Some((root, rel.to_string()))
}

/// Como se escribe dentro de la nota `source` un enlace a la nota `target`
/// (las dos, rutas virtuales).
///
/// Si las dos estan **en la misma carpeta local**, relativo a esa carpeta
/// (`[[clientes/acme]]`): es como lo escribe Obsidian cuando esa carpeta se abre
/// como boveda, y asi sigue funcionando alli. En cualquier otro caso, la ruta
/// virtual: en la principal no hay prefijo, y entre carpetas hace falta.
pub fn link_form(target: &str, source: &str) -> String {
    match (split_virtual(target), split_virtual(source)) {
        ((Some(target_id), rel), (Some(source_id), _)) if target_id == source_id => rel.to_string(),
        _ => target.to_string(),
    }
}

/// Lo que esta mal en las carpetas de notas. Lo llama `InboxConfig::problems()`,
/// asi que vale tambien para quien edite la configuracion a mano.
///
/// Dos reglas:
///
/// 1. **Una carpeta local no puede ser documentacion del buzon** (decision del
///    usuario). Esos documentos se cambian con propuestas que se aprueban, y como
///    notas se editarian a mano saltandose esa regla. Se rechaza si la carpeta es
///    la raiz de un proyecto de documentacion, si la contiene, o si contiene
///    alguno de sus documentos. Una carpeta dentro del repositorio que no pisa
///    ningun documento **si** se admite.
/// 2. **Ninguna carpeta de notas puede estar dentro de otra**, la principal
///    incluida: sus notas saldrian dos veces, con dos rutas distintas.
///
/// Las rutas se comparan **por componentes y ya resueltas**, nunca como texto: si
/// no, `ExampleApi2` pasaria por hija de `ExampleApi`.
pub fn folder_problems(config: &InboxConfig) -> Vec<String> {
    let mut problems = Vec::new();
    let Some(notes) = &config.notes else {
        return problems;
    };

    let mut seen = HashSet::new();
    for id in &notes.local_folders {
        if !seen.insert(id.as_str()) {
            problems.push(format!("notas: la carpeta local '{id}' esta repetida"));
            continue;
        }
        if id == &notes.vault_project {
            problems.push(format!(
                "notas: '{id}' ya es la boveda principal, no puede ser tambien una carpeta local"
            ));
            continue;
        }
        let folder = match config.project(id) {
            None => {
                problems.push(format!("notas: no hay ningun proyecto '{id}' para la carpeta local"));
                continue;
            }
            Some(project) if project.kind != ProjectKind::Vault => {
                problems.push(format!(
                    "notas: la carpeta local '{id}' tiene que ser de clase \"vault\""
                ));
                continue;
            }
            Some(project) => project,
        };

        let local = path_key(Path::new(&folder.repo_root));
        for docs in config
            .projects
            .iter()
            .filter(|p| p.kind == ProjectKind::Docs)
        {
            let docs_root = path_key(Path::new(&docs.repo_root));
            let clashes = local == docs_root
                || contains(&local, &docs_root)
                || docs
                    .documents
                    .iter()
                    .any(|doc| contains(&local, &join_key(&docs_root, &doc.path)));
            if clashes {
                problems.push(format!(
                    "notas: la carpeta '{}' ya es documentacion del proyecto '{}' del buzon. Sus \
                    documentos se cambian con propuestas que se aprueban, no como notas: elige una \
                    carpeta que no los contenga",
                    folder.repo_root, docs.id
                ));
            }
        }
    }

    let roots: Vec<(String, Vec<String>)> = config
        .note_roots()
        .iter()
        .map(|root| {
            (
                root.project.repo_root.clone(),
                path_key(Path::new(&root.project.repo_root)),
            )
        })
        .collect();
    for (index, (a_path, a)) in roots.iter().enumerate() {
        for (b_path, b) in roots.iter().skip(index + 1) {
            if a == b {
                problems.push(format!(
                    "notas: '{a_path}' y '{b_path}' son la misma carpeta"
                ));
            } else if contains(a, b) || contains(b, a) {
                problems.push(format!(
                    "notas: '{a_path}' y '{b_path}' estan una dentro de la otra, y sus notas \
                    saldrian dos veces"
                ));
            }
        }
    }
    problems
}

/// La ruta partida en componentes, resuelta y en minusculas.
///
/// Se canonicaliza para seguir los junctions (mismo criterio que
/// `resolve_user_note`). Lo que no existe se compara tal cual: una carpeta que
/// todavia no se ha creado no puede estar dentro de otra por un enlace.
fn path_key(path: &Path) -> Vec<String> {
    let resolved = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    components(&resolved.to_string_lossy())
}

fn components(raw: &str) -> Vec<String> {
    // `canonicalize` en Windows devuelve `\\?\D:\...`; sin quitarlo, una ruta
    // resuelta y una que no existe nunca coincidirian.
    let raw = raw.strip_prefix(r"\\?\").unwrap_or(raw);
    raw.replace('\\', "/")
        .to_lowercase()
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(str::to_string)
        .collect()
}

/// Un documento que quiza no existe, sobre la raiz ya resuelta.
fn join_key(root: &[String], rel: &str) -> Vec<String> {
    let mut key = root.to_vec();
    key.extend(components(&normalize_rel(rel)));
    key
}

/// `outer` contiene estrictamente a `inner`.
fn contains(outer: &[String], inner: &[String]) -> bool {
    inner.len() > outer.len() && inner[..outer.len()] == *outer
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::config::{DocRole, DocTarget, NotesConfig};

    fn vault(id: &str, root: &Path) -> DocProject {
        DocProject {
            id: id.into(),
            name: id.into(),
            repo_root: root.to_string_lossy().into_owned(),
            kind: ProjectKind::Vault,
            conventions: String::new(),
            documents: vec![],
        }
    }

    fn docs(id: &str, root: &Path, paths: &[&str]) -> DocProject {
        DocProject {
            id: id.into(),
            name: id.into(),
            repo_root: root.to_string_lossy().into_owned(),
            kind: ProjectKind::Docs,
            conventions: String::new(),
            documents: paths
                .iter()
                .map(|path| DocTarget {
                    path: (*path).into(),
                    role: DocRole::Journal,
                    answers: "x".into(),
                    evidence_labels: false,
                })
                .collect(),
        }
    }

    fn config(projects: Vec<DocProject>, locals: &[&str]) -> InboxConfig {
        InboxConfig {
            projects,
            notes: Some(NotesConfig {
                vault_project: "notas".into(),
                repos: vec![],
                digest_on_idle: false,
                groups: vec![],
                local_folders: locals.iter().map(|id| (*id).to_string()).collect(),
            }),
            ..InboxConfig::default()
        }
    }

    fn dir(base: &Path, rel: &str) -> PathBuf {
        let path = base.join(rel);
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    /// Dentro de una misma carpeta local, el enlace va como lo escribe Obsidian;
    /// entre carpetas, con el prefijo.
    #[test]
    fn a_link_is_written_relative_only_inside_the_same_local_folder() {
        assert_eq!(link_form("@apuntes/clientes/acme.md", "@apuntes/diario/hoy.md"), "clientes/acme.md");
        assert_eq!(link_form("@apuntes/clientes/acme.md", "temas/malla.md"), "@apuntes/clientes/acme.md");
        assert_eq!(link_form("temas/malla.md", "@apuntes/diario/hoy.md"), "temas/malla.md");
        assert_eq!(link_form("temas/malla.md", "diario/hoy.md"), "temas/malla.md");
        assert_eq!(link_form("@otra/x.md", "@apuntes/y.md"), "@otra/x.md");
    }

    #[test]
    fn splits_a_virtual_path() {
        assert_eq!(
            split_virtual("@apuntes/clientes/acme.md"),
            (Some("apuntes"), "clientes/acme.md")
        );
        assert_eq!(split_virtual("temas/malla.md"), (None, "temas/malla.md"));
    }

    /// La principal conserva sus rutas de siempre; solo las locales llevan marca.
    #[test]
    fn locates_notes_in_the_main_vault_and_in_local_folders() {
        let base = crate::test_support::temp_dir("roots-locate");
        let cfg = config(
            vec![vault("notas", &dir(&base, "notas")), vault("apuntes", &dir(&base, "apuntes"))],
            &["apuntes"],
        );
        let roots = cfg.note_roots();
        assert_eq!(roots.len(), 2);

        let (root, rel) = locate(&roots, "temas/malla.md").unwrap();
        assert!(!root.is_local());
        assert_eq!(rel, "temas/malla.md");

        let (root, rel) = locate(&roots, "@apuntes/clientes/acme.md").unwrap();
        assert_eq!(root.id(), "apuntes");
        assert_eq!(rel, "clientes/acme.md");
        assert_eq!(root.virtual_path(&rel), "@apuntes/clientes/acme.md");

        assert!(locate(&roots, "@inventada/x.md").is_none());
    }

    /// Una carpeta mal configurada se ignora aqui (la denuncia `problems`) y no
    /// deja sin notas a las demas.
    #[test]
    fn broken_local_entries_do_not_take_the_others_down() {
        let base = crate::test_support::temp_dir("roots-broken");
        let cfg = config(
            vec![
                vault("notas", &dir(&base, "notas")),
                docs("ia", &dir(&base, "repo"), &["docs/a.md"]),
            ],
            &["ia", "inventada", "notas"],
        );
        let roots = cfg.note_roots();
        assert_eq!(roots.len(), 1, "solo la principal");
        let problems = folder_problems(&cfg);
        assert!(problems.iter().any(|p| p.contains("'ia'") && p.contains("vault")), "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("'inventada'")), "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("boveda principal")), "{problems:?}");
    }

    /// El caso real: `ExampleApi\docs` es documentacion del buzon y no puede
    /// ser una carpeta de notas.
    #[test]
    fn a_folder_with_mailbox_documents_is_refused() {
        let base = crate::test_support::temp_dir("roots-mailbox");
        let repo = dir(&base, "ExampleApi");
        dir(&repo, "docs/ia-deteccion");
        std::fs::write(repo.join("docs/README.md"), "# Docs\n").unwrap();
        let notes_in_repo = dir(&repo, "scripts/notas");
        let sibling = dir(&base, "ExampleApi2");

        let refused = |folder: &Path| {
            let cfg = config(
                vec![
                    vault("notas", &dir(&base, "boveda")),
                    docs("ia", &repo, &["docs/README.md", "docs/ia-deteccion/estado.md"]),
                    vault("local", folder),
                ],
                &["local"],
            );
            folder_problems(&cfg)
                .iter()
                .any(|p| p.contains("documentacion del proyecto 'ia'"))
        };

        assert!(refused(&repo.join("docs")), "contiene sus documentos");
        assert!(refused(&repo), "es la raiz del proyecto");
        assert!(refused(&base), "contiene la raiz del proyecto");
        assert!(!refused(&notes_in_repo), "dentro del repo pero sin pisar documentos");
        assert!(!refused(&sibling), "ExampleApi2 no es hija de ExampleApi");
    }

    /// Una carpeta dentro de otra haria salir sus notas dos veces.
    #[test]
    fn nested_note_folders_are_refused() {
        let base = crate::test_support::temp_dir("roots-nested");
        let main = dir(&base, "notas");
        let inner = dir(&main, "sub");
        let cfg = config(vec![vault("notas", &main), vault("sub", &inner)], &["sub"]);
        let problems = folder_problems(&cfg);
        assert!(problems.iter().any(|p| p.contains("una dentro de la otra")), "{problems:?}");
    }

    #[test]
    fn problems_include_the_folder_rules() {
        let base = crate::test_support::temp_dir("roots-problems");
        let main = dir(&base, "notas");
        let cfg = config(vec![vault("notas", &main), vault("sub", &dir(&main, "sub"))], &["sub"]);
        assert!(cfg.problems().iter().any(|p| p.contains("una dentro de la otra")));
    }
}
