//! Que proyectos tienen documentacion que alimentar, y donde.
//!
//! Nada de esto esta fijado en el codigo: IA y MAPAS entran por configuracion,
//! igual que entraria cualquier otro repositorio.
//!
//! Hay dos clases de proyecto. Uno de **documentacion** lista uno por uno los
//! documentos que se pueden tocar. Una **boveda** de notas no puede: tiene
//! cientos o miles de ficheros que aparecen y desaparecen, asi que cualquier
//! `.md` de dentro vale, con el rol que da su carpeta, salvo lo privado.

use std::collections::HashSet;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{DocsError, DocsResult};

/// Carpetas con significado dentro de una boveda. Relativas a la raiz, en
/// minusculas y con `/`.
pub const DAILY_DIR: &str = "diario/";
pub const HUB_DIR: &str = "proyectos/";
/// Ningun agente la lee ni la toca. Vale en cualquier nivel: `trabajo/privado/`
/// tambien es privado.
pub const PRIVATE_SEGMENT: &str = "privado";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocRole {
    /// Diario con lo mas reciente arriba: `## <dia>-<mes>: <conclusion>`.
    Journal,
    /// Un plan con secciones fijas; se edita, no se le añaden fechas.
    Plan,
    /// Indice "documento | que responde".
    Index,
    /// Una nota libre de la boveda.
    Note,
    /// La nota de un dia, en `diario/AAAA-MM-DD.md`.
    Daily,
    /// La nota viva de un proyecto, en `proyectos/<X>.md`: lo que se va
    /// aprendiendo de el, nota a nota.
    Hub,
}

impl DocRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            DocRole::Journal => "journal",
            DocRole::Plan => "plan",
            DocRole::Index => "index",
            DocRole::Note => "note",
            DocRole::Daily => "daily",
            DocRole::Hub => "hub",
        }
    }

    /// Los roles de una boveda de notas.
    pub fn is_note(&self) -> bool {
        matches!(self, DocRole::Note | DocRole::Daily | DocRole::Hub)
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectKind {
    /// Documentos listados uno por uno. Es lo que tienen las configuraciones
    /// guardadas antes de que existieran las bovedas.
    #[default]
    Docs,
    /// Una boveda de notas: vale cualquier `.md` que no sea privado.
    Vault,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocTarget {
    /// Relativa a la raiz del repositorio, con `/`.
    pub path: String,
    pub role: DocRole,
    /// Que responde este documento. Es lo que lee el modelo para decidir a
    /// donde va cada hallazgo.
    #[serde(default)]
    pub answers: String,
    /// Las cifras de este documento llevan `[M]` (medido) o `[S]` (supuesto).
    #[serde(default)]
    pub evidence_labels: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocProject {
    pub id: String,
    pub name: String,
    pub repo_root: String,
    #[serde(default)]
    pub kind: ProjectKind,
    /// Convenciones de redaccion del proyecto, en texto libre para el modelo.
    #[serde(default)]
    pub conventions: String,
    /// En una boveda es opcional: sirve para darle `answers` a alguna nota.
    #[serde(default)]
    pub documents: Vec<DocTarget>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoteModel {
    /// El id con el que `nexodeck-ai` guardo la clave (`deepseek`, `openai`...).
    pub provider_id: String,
    pub base_url: String,
    pub model: String,
}

/// Una agrupacion de notas: **la carpeta manda**, esto solo la viste.
///
/// El `id` es el nombre de la carpeta dentro de la boveda, y es la identidad.
/// Una carpeta sin entrada aqui sigue siendo una agrupacion (con su nombre y un
/// color por defecto): esto no es la lista de grupos que existen, es la lista de
/// los que el usuario ha personalizado. Ver `notes/groups.rs`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoteGroup {
    /// Nombre de la carpeta, en minusculas y sin tildes.
    pub id: String,
    /// Lo que se enseña: "Tandas de ODM" para la carpeta `odm`.
    #[serde(default)]
    pub name: String,
    /// `#RRGGBB`. Mismo formato que los grupos del deck.
    #[serde(default)]
    pub color_hex: String,
    /// Para ordenarlos a mano. Los que no esten aqui van despues, alfabeticos.
    #[serde(default)]
    pub order: u32,
}

/// El asistente de notas: que boveda, con que repositorios cruzarla y como se
/// ven sus agrupaciones.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotesConfig {
    /// Id de un proyecto de clase `vault`.
    pub vault_project: String,
    /// Repositorios git cuyos commits se relacionan con las notas. Rutas
    /// absolutas.
    #[serde(default)]
    pub repos: Vec<String>,
    /// Procesar sola una nota que lleva un rato sin cambios. **Apagado por
    /// defecto**: cada digest son varias llamadas al modelo.
    #[serde(default)]
    pub digest_on_idle: bool,
    /// Nombre y color de las agrupaciones que el usuario ha personalizado.
    ///
    /// **No es la lista de agrupaciones**: esas son las carpetas de la boveda.
    /// Va con `serde(default)` porque toda configuracion anterior a esto no lo
    /// tiene y tiene que seguir leyendose.
    #[serde(default)]
    pub groups: Vec<NoteGroup>,
    /// Carpetas de notas **leidas en su sitio**, ademas de la principal: ids de
    /// proyectos `vault`. Sus notas se nombran `@<id>/<ruta>` (ver
    /// `notes/roots.rs`). `serde(default)` porque ninguna configuracion anterior
    /// lo tiene.
    #[serde(default)]
    pub local_folders: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InboxConfig {
    /// **Apagado por defecto**, igual que la IA y el servidor de control: sin
    /// esto encendido los hallazgos se guardan pero nadie los procesa.
    #[serde(default)]
    pub worker_enabled: bool,
    #[serde(default)]
    pub remote: Option<RemoteModel>,
    /// Usar el modelo local si el remoto no esta disponible, pero **solo si ya
    /// esta levantado**: arrancarlo durante una tanda de ODM le quitaria la GPU.
    #[serde(default = "default_true")]
    pub local_fallback: bool,
    #[serde(default)]
    pub projects: Vec<DocProject>,
    #[serde(default)]
    pub notes: Option<NotesConfig>,
}

fn default_true() -> bool {
    true
}

impl Default for InboxConfig {
    fn default() -> Self {
        InboxConfig {
            worker_enabled: false,
            remote: None,
            local_fallback: true,
            projects: Vec::new(),
            notes: None,
        }
    }
}

impl InboxConfig {
    pub fn project(&self, id: &str) -> Option<&DocProject> {
        self.projects.iter().find(|p| p.id == id)
    }

    pub fn project_ids(&self) -> Vec<&str> {
        self.projects.iter().map(|p| p.id.as_str()).collect()
    }

    /// La boveda configurada para el asistente de notas, si la hay y es valida.
    pub fn vault(&self) -> Option<(&NotesConfig, &DocProject)> {
        let notes = self.notes.as_ref()?;
        let project = self.project(&notes.vault_project)?;
        (project.kind == ProjectKind::Vault).then_some((notes, project))
    }

    /// Todo lo que esta mal, no solo lo primero: quien edita la configuracion
    /// a mano prefiere arreglarlo de una vez.
    pub fn problems(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let mut ids = HashSet::new();

        for project in &self.projects {
            let id = &project.id;
            if id.is_empty() || !id.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-') {
                problems.push(format!(
                    "proyecto '{id}': el id solo puede llevar minusculas, cifras y guiones"
                ));
            }
            if !ids.insert(id.as_str()) {
                problems.push(format!("proyecto '{id}': el id esta repetido"));
            }
            if project.name.trim().is_empty() {
                problems.push(format!("proyecto '{id}': falta el nombre"));
            }
            if !Path::new(&project.repo_root).is_absolute() {
                problems.push(format!(
                    "proyecto '{id}': repo_root tiene que ser una ruta absoluta"
                ));
            }
            if project.kind == ProjectKind::Docs && project.documents.is_empty() {
                problems.push(format!("proyecto '{id}': no tiene ningun documento"));
            }

            let mut paths = HashSet::new();
            for doc in &project.documents {
                let path = normalize_rel(&doc.path);
                if !is_safe_relative(&path) {
                    problems.push(format!(
                        "proyecto '{id}': '{}' tiene que ser relativa al repositorio y sin '..'",
                        doc.path
                    ));
                }
                if !path.ends_with(".md") {
                    problems.push(format!("proyecto '{id}': '{}' no es un .md", doc.path));
                }
                if !paths.insert(path) {
                    problems.push(format!("proyecto '{id}': '{}' esta repetido", doc.path));
                }
            }
        }

        if let Some(notes) = &self.notes {
            match self.project(&notes.vault_project) {
                None => problems.push(format!(
                    "notas: no hay ningun proyecto '{}'",
                    notes.vault_project
                )),
                Some(project) if project.kind != ProjectKind::Vault => problems.push(format!(
                    "notas: el proyecto '{}' tiene que ser de clase \"vault\"",
                    notes.vault_project
                )),
                Some(_) => {}
            }
            for repo in &notes.repos {
                if !Path::new(repo).is_absolute() {
                    problems.push(format!("notas: el repositorio '{repo}' tiene que ser una ruta absoluta"));
                }
            }

            // El catalogo de agrupaciones: el id es un nombre de carpeta de la
            // boveda, asi que vale lo mismo que para cualquier carpeta. Un id
            // invalido aqui no rompe nada (la carpeta manda), pero deja una
            // entrada que no viste a ninguna agrupacion real, y eso se ve como
            // "el color no se guarda".
            let mut group_ids = HashSet::new();
            for group in &notes.groups {
                let id = &group.id;
                if !group_ids.insert(id.as_str()) {
                    problems.push(format!("notas: la agrupacion '{id}' esta repetida"));
                }
                if let Err(error) = crate::notes::validate_group_name(id) {
                    problems.push(format!("notas: agrupacion '{id}': {error}"));
                }
                if !group.color_hex.trim().is_empty() {
                    if let Err(error) = crate::notes::validate_color(&group.color_hex) {
                        problems.push(format!("notas: agrupacion '{id}': {error}"));
                    }
                }
            }
        }
        // Las carpetas locales: que no sean documentacion del buzon y que ninguna
        // este dentro de otra (`notes/roots.rs`).
        problems.extend(crate::notes::folder_problems(self));
        problems
    }
}

impl DocProject {
    /// El documento de esa ruta, si el proyecto deja tocarlo.
    ///
    /// En una boveda, lo listado en `documents` manda (por sus `answers`); lo
    /// demas se deduce de la carpeta con [`vault_role`].
    pub fn document(&self, path: &str) -> Option<DocTarget> {
        let wanted = normalize_rel(path);
        if let Some(doc) = self
            .documents
            .iter()
            .find(|d| normalize_rel(&d.path) == wanted)
        {
            return Some(doc.clone());
        }
        match self.kind {
            ProjectKind::Docs => None,
            ProjectKind::Vault => vault_role(&wanted).map(|role| DocTarget {
                path: wanted,
                role,
                answers: String::new(),
                evidence_labels: false,
            }),
        }
    }

    /// Ruta real de un documento del proyecto, comprobando que **sigue dentro**
    /// del repositorio despues de resolver enlaces. La ruta la propone un
    /// modelo: un `..` o un junction no pueden sacar la escritura de ahi.
    pub fn resolve(&self, path: &str) -> DocsResult<PathBuf> {
        let rel = normalize_rel(path);
        if self.document(&rel).is_none() {
            return Err(DocsError::Invalid(format!(
                "'{rel}' no es un documento del proyecto '{}'",
                self.id
            )));
        }
        if !is_safe_relative(&rel) {
            return Err(DocsError::Invalid(format!(
                "'{rel}' tiene que ser relativa al repositorio y sin '..'"
            )));
        }

        let root = std::fs::canonicalize(&self.repo_root)
            .map_err(|e| DocsError::io(&self.repo_root, e))?;
        let full = std::fs::canonicalize(root.join(&rel))
            .map_err(|_| DocsError::NotFound(format!("{rel} en {}", self.repo_root)))?;
        if !full.starts_with(&root) {
            return Err(DocsError::Invalid(format!(
                "'{rel}' resuelve fuera del repositorio"
            )));
        }
        Ok(full)
    }

    /// La ruta real de una nota que el **usuario** quiere abrir o crear en su
    /// boveda desde el editor. Devuelve la ruta relativa normalizada (con `.md`)
    /// y la absoluta.
    ///
    /// Mas permisiva que [`resolve`](Self::resolve) justo en lo que la IA no puede
    /// hacer: vale `privado/`, porque editar es del usuario y ningun agente lee lo
    /// que se escribe aqui; y vale un fichero que todavia no existe. Igual de
    /// estricta en lo demas: solo `.md`, nada oculto, y nada fuera de la raiz
    /// aunque haya un junction en una carpeta intermedia.
    pub fn resolve_user_note(&self, path: &str, must_exist: bool) -> DocsResult<(String, PathBuf)> {
        if self.kind != ProjectKind::Vault {
            return Err(DocsError::Invalid(format!(
                "el proyecto '{}' no es una boveda: solo se editan notas de una boveda",
                self.id
            )));
        }
        let mut rel = normalize_rel(path);
        if !rel.to_lowercase().ends_with(".md") {
            rel.push_str(".md");
        }
        if !is_safe_relative(&rel) {
            return Err(DocsError::Invalid(format!(
                "'{rel}' tiene que ser relativa a la boveda y sin '..'"
            )));
        }
        if rel.split('/').any(|segment| segment.starts_with('.')) {
            return Err(DocsError::Invalid(format!(
                "'{rel}' esta en una carpeta oculta"
            )));
        }

        let root = std::fs::canonicalize(&self.repo_root)
            .map_err(|e| DocsError::io(&self.repo_root, e))?;
        let joined = root.join(&rel);
        if joined.exists() {
            let full = std::fs::canonicalize(&joined).map_err(|e| DocsError::io(&joined, e))?;
            if !full.starts_with(&root) {
                return Err(DocsError::Invalid(format!("'{rel}' resuelve fuera de la boveda")));
            }
            return Ok((rel, full));
        }
        if must_exist {
            return Err(DocsError::NotFound(format!("la nota '{rel}' en la boveda")));
        }
        // Todavia no existe: la carpeta mas cercana que si existe tiene que seguir
        // dentro. Un junction en una carpeta intermedia no puede sacar la escritura.
        let mut ancestor = joined.parent();
        while let Some(dir) = ancestor {
            if dir.exists() {
                let real = std::fs::canonicalize(dir).map_err(|e| DocsError::io(dir, e))?;
                if !real.starts_with(&root) {
                    return Err(DocsError::Invalid(format!("'{rel}' resuelve fuera de la boveda")));
                }
                break;
            }
            ancestor = dir.parent();
        }
        Ok((rel, joined))
    }

    /// La nota viva de un proyecto dentro de esta boveda: `proyectos/<nombre>.md`.
    pub fn hub_path(name: &str) -> String {
        format!("{HUB_DIR}{}.md", name.trim())
    }
}

/// El rol de una nota de boveda segun su carpeta. `None` si no se puede tocar:
/// no es un `.md`, esta en una carpeta privada, en una oculta (`.obsidian`,
/// `.git`, `.trash`) o se sale de la raiz.
pub fn vault_role(rel: &str) -> Option<DocRole> {
    let rel = normalize_rel(rel);
    if !rel.to_lowercase().ends_with(".md") || !is_safe_relative(&rel) {
        return None;
    }
    let lower = rel.to_lowercase();
    let segments: Vec<&str> = lower.split('/').collect();
    let (file, dirs) = segments.split_last()?;
    if file.starts_with('.')
        || dirs
            .iter()
            .any(|d| d.starts_with('.') || *d == PRIVATE_SEGMENT)
    {
        return None;
    }
    Some(if lower.starts_with(DAILY_DIR) {
        DocRole::Daily
    } else if lower.starts_with(HUB_DIR) {
        DocRole::Hub
    } else {
        DocRole::Note
    })
}

/// `docs\a.md`, `./docs/a.md` y `docs/a.md` son el mismo documento.
pub fn normalize_rel(path: &str) -> String {
    let path = path.trim().replace('\\', "/");
    path.trim_start_matches("./").to_string()
}

fn is_safe_relative(path: &str) -> bool {
    let path = Path::new(path);
    !path.as_os_str().is_empty()
        && path
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn project(root: &str, doc: &str) -> DocProject {
        DocProject {
            id: "ia".into(),
            name: "IA".into(),
            repo_root: root.into(),
            kind: ProjectKind::Docs,
            conventions: String::new(),
            documents: vec![DocTarget {
                path: doc.into(),
                role: DocRole::Journal,
                answers: String::new(),
                evidence_labels: false,
            }],
        }
    }

    fn vault(root: &str) -> DocProject {
        DocProject {
            id: "notas".into(),
            name: "Notas".into(),
            repo_root: root.into(),
            kind: ProjectKind::Vault,
            conventions: String::new(),
            documents: vec![],
        }
    }

    #[test]
    fn a_missing_config_field_takes_its_default() {
        let config: InboxConfig = serde_json::from_str("{}").unwrap();
        assert_eq!(config, InboxConfig::default());
        assert!(config.local_fallback);
        assert!(!config.worker_enabled);
        assert!(config.notes.is_none());
    }

    #[test]
    fn a_project_saved_before_vaults_existed_is_a_docs_project() {
        let json = r#"{"id":"ia","name":"IA","repo_root":"D:/x","documents":[{"path":"a.md","role":"journal"}]}"#;
        let project: DocProject = serde_json::from_str(json).unwrap();
        assert_eq!(project.kind, ProjectKind::Docs);
    }

    #[test]
    fn problems_lists_every_mistake() {
        let mut bad = project("relativa", "../fuera.md");
        bad.id = "IA".into();
        let config = InboxConfig {
            projects: vec![bad],
            ..InboxConfig::default()
        };
        let problems = config.problems();
        assert!(problems.iter().any(|p| p.contains("minusculas")));
        assert!(problems.iter().any(|p| p.contains("absoluta")));
        assert!(problems.iter().any(|p| p.contains("'..'")));
    }

    #[test]
    fn a_vault_needs_no_documents_but_notes_must_point_to_a_vault() {
        let root = std::env::temp_dir().to_string_lossy().into_owned();
        let config = InboxConfig {
            projects: vec![vault(&root), project(&root, "docs/a.md")],
            notes: Some(NotesConfig {
                vault_project: "ia".into(),
                repos: vec!["relativa".into()],
                digest_on_idle: false,
                groups: vec![],
                local_folders: vec![],
            }),
            ..InboxConfig::default()
        };
        let problems = config.problems();
        assert!(!problems.iter().any(|p| p.contains("ningun documento")), "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("\"vault\"")), "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("'relativa'")), "{problems:?}");
        assert!(config.vault().is_none());

        let mut fixed = config.clone();
        fixed.notes = Some(NotesConfig {
            vault_project: "notas".into(),
            repos: vec![],
            digest_on_idle: false,
            groups: vec![],
            local_folders: vec![],
        });
        assert!(fixed.problems().is_empty(), "{:?}", fixed.problems());
        assert_eq!(fixed.vault().unwrap().1.id, "notas");
    }

    #[test]
    fn vault_roles_come_from_the_folder_and_private_notes_are_out() {
        assert_eq!(vault_role("diario/2026-09-15.md"), Some(DocRole::Daily));
        assert_eq!(vault_role("proyectos/NexoDeck.md"), Some(DocRole::Hub));
        assert_eq!(vault_role("temas/drift.md"), Some(DocRole::Note));
        assert_eq!(vault_role("Temas\\Mayusculas.MD"), Some(DocRole::Note));
        assert_eq!(vault_role("privado/claves.md"), None);
        assert_eq!(vault_role("trabajo/privado/x.md"), None);
        assert_eq!(vault_role(".obsidian/workspace.md"), None);
        assert_eq!(vault_role("temas/imagen.png"), None);
        assert_eq!(vault_role("../fuera.md"), None);
    }

    #[test]
    fn a_vault_accepts_any_note_and_resolve_keeps_it_inside() {
        let root = crate::test_support::temp_dir("vault-resolve");
        std::fs::create_dir_all(root.join("temas")).unwrap();
        std::fs::create_dir_all(root.join("privado")).unwrap();
        std::fs::write(root.join("temas/a.md"), "# A\n").unwrap();
        std::fs::write(root.join("privado/b.md"), "# B\n").unwrap();
        let v = vault(root.to_str().unwrap());

        assert_eq!(v.document("temas/a.md").unwrap().role, DocRole::Note);
        assert!(v.resolve("temas/a.md").is_ok());
        assert!(matches!(v.resolve("privado/b.md"), Err(DocsError::Invalid(_))));
        assert!(matches!(v.resolve("../a.md"), Err(DocsError::Invalid(_))));
    }

    #[test]
    fn resolve_refuses_documents_outside_the_repo_or_not_configured() {
        let root = crate::test_support::temp_dir("resolve");
        std::fs::create_dir_all(root.join("docs")).unwrap();
        std::fs::write(root.join("docs/a.md"), "# A\n").unwrap();
        let p = project(root.to_str().unwrap(), "docs/a.md");

        assert!(p.resolve("docs\\a.md").is_ok());
        assert!(matches!(p.resolve("docs/b.md"), Err(DocsError::Invalid(_))));

        let mut escaping = p.clone();
        escaping.documents[0].path = "../a.md".into();
        assert!(matches!(escaping.resolve("../a.md"), Err(DocsError::Invalid(_))));
    }
}
