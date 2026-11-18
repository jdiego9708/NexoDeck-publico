//! Escribir en los documentos de verdad, y poder deshacerlo.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::config::{normalize_rel, DocProject};
use crate::error::DocsError;
use crate::markdown::Document;
use crate::store::{sha256_hex, write_atomic};

#[derive(Debug, thiserror::Error)]
pub enum ApplyError {
    /// Alguien toco el documento desde que se genero la propuesta. No se
    /// escribe nada: la propuesta se revalida y se vuelve a enseñar.
    #[error("cambiaron desde la propuesta: {}", files.join(", "))]
    BaseChanged { files: Vec<String> },
    #[error("{detail}")]
    Write { detail: String, rolled_back: bool },
    #[error(transparent)]
    Docs(#[from] DocsError),
}

/// Un documento leido de disco con su hash.
#[derive(Debug, Clone)]
pub struct FileSnapshot {
    pub full_path: PathBuf,
    pub raw: Vec<u8>,
    pub document: Document,
    pub hash: String,
}

/// Lee los documentos pedidos. Uno que no es UTF-8 valido se rechaza entero.
pub fn read_documents<'a>(
    project: &DocProject,
    paths: impl IntoIterator<Item = &'a str>,
) -> Result<BTreeMap<String, FileSnapshot>, DocsError> {
    let mut out = BTreeMap::new();
    for path in paths {
        let rel = normalize_rel(path);
        let full_path = project.resolve(&rel)?;
        let raw = std::fs::read(&full_path).map_err(|e| DocsError::io(&full_path, e))?;
        let document = Document::parse(&raw)
            .map_err(|e| DocsError::Invalid(format!("{rel}: {e}")))?;
        let hash = sha256_hex(&raw);
        out.insert(
            rel,
            FileSnapshot {
                full_path,
                raw,
                document,
                hash,
            },
        );
    }
    Ok(out)
}

/// Escribe el texto final de cada documento y devuelve el hash de lo escrito.
///
/// Orden, y por que:
/// 1. **Se relee y se compara el hash** con el de la propuesta. Si no coincide,
///    no se escribe nada.
/// 2. **Se guardan los bytes originales** en `originals_dir`, que es lo que
///    permite deshacer sin git.
/// 3. Cada fichero se escribe de forma atomica y **se relee para comprobarlo**.
/// 4. Si falla uno, se restauran los que ya se habian escrito: una propuesta
///    aplicada a medias dejaria el diario y el plan diciendo cosas distintas.
pub fn apply_to_disk(
    project: &DocProject,
    new_bodies: &BTreeMap<String, String>,
    base_hashes: &BTreeMap<String, String>,
    originals_dir: &Path,
) -> Result<BTreeMap<String, String>, ApplyError> {
    let snapshots = read_documents(project, new_bodies.keys().map(String::as_str))?;

    let changed: Vec<String> = snapshots
        .iter()
        .filter(|(path, snap)| base_hashes.get(*path) != Some(&snap.hash))
        .map(|(path, _)| path.clone())
        .collect();
    if !changed.is_empty() {
        return Err(ApplyError::BaseChanged { files: changed });
    }

    std::fs::create_dir_all(originals_dir).map_err(|e| DocsError::io(originals_dir, e))?;
    for (path, snap) in &snapshots {
        write_atomic(&originals_dir.join(original_name(path)), &snap.raw)?;
    }

    let mut written: Vec<&FileSnapshot> = Vec::new();
    let mut applied = BTreeMap::new();

    for (path, body) in new_bodies {
        let snap = &snapshots[path];
        let bytes = snap.document.render(body);

        let result = write_atomic(&snap.full_path, &bytes)
            .map_err(|e| e.to_string())
            .and_then(|()| match std::fs::read(&snap.full_path) {
                Ok(back) if back == bytes => Ok(()),
                Ok(_) => Err(format!(
                    "{path}: al releerlo no tiene lo que se escribio"
                )),
                Err(e) => Err(format!("{path}: no se pudo releer: {e}")),
            });

        if let Err(detail) = result {
            // El que fallo tambien se restaura: pudo quedar escrito y distinto.
            written.push(snap);
            let rolled_back = restore(&written);
            return Err(ApplyError::Write {
                detail,
                rolled_back,
            });
        }

        written.push(snap);
        applied.insert(path.clone(), sha256_hex(&bytes));
    }

    Ok(applied)
}

/// Vuelve a dejar los documentos como estaban antes de aplicar, **solo si nadie
/// los toco despues**. Si alguno cambio, no se toca ninguno: deshacer encima de
/// una edicion posterior la borraria.
pub fn undo_on_disk(
    project: &DocProject,
    applied_hashes: &BTreeMap<String, String>,
    originals_dir: &Path,
) -> Result<(), ApplyError> {
    let snapshots = read_documents(project, applied_hashes.keys().map(String::as_str))?;
    let changed: Vec<String> = snapshots
        .iter()
        .filter(|(path, snap)| applied_hashes.get(*path) != Some(&snap.hash))
        .map(|(path, _)| path.clone())
        .collect();
    if !changed.is_empty() {
        return Err(ApplyError::BaseChanged { files: changed });
    }

    for (path, snap) in &snapshots {
        let original_path = originals_dir.join(original_name(path));
        let original =
            std::fs::read(&original_path).map_err(|e| DocsError::io(&original_path, e))?;
        write_atomic(&snap.full_path, &original)?;
    }
    Ok(())
}

fn restore(written: &[&FileSnapshot]) -> bool {
    written
        .iter()
        .rev()
        .all(|snap| write_atomic(&snap.full_path, &snap.raw).is_ok())
}

fn original_name(path: &str) -> String {
    path.replace(['/', '\\'], "__")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{DocRole, DocTarget, ProjectKind};

    fn setup(name: &str) -> (PathBuf, DocProject) {
        let root = crate::test_support::temp_dir(name);
        std::fs::create_dir_all(root.join("docs")).unwrap();
        std::fs::write(root.join("docs/estado.md"), "# Estado\r\n\r\nviejo\r\n").unwrap();
        std::fs::write(root.join("docs/plan.md"), "# Plan\n").unwrap();
        let project = DocProject {
            id: "ia".into(),
            name: "IA".into(),
            repo_root: root.to_string_lossy().into_owned(),
            kind: ProjectKind::Docs,
            conventions: String::new(),
            documents: ["docs/estado.md", "docs/plan.md"]
                .into_iter()
                .map(|p| DocTarget {
                    path: p.into(),
                    role: DocRole::Journal,
                    answers: String::new(),
                    evidence_labels: false,
                })
                .collect(),
        };
        (root, project)
    }

    fn hashes(project: &DocProject) -> BTreeMap<String, String> {
        read_documents(project, ["docs/estado.md", "docs/plan.md"])
            .unwrap()
            .into_iter()
            .map(|(p, s)| (p, s.hash))
            .collect()
    }

    fn bodies() -> BTreeMap<String, String> {
        let mut map = BTreeMap::new();
        map.insert("docs/estado.md".to_string(), "# Estado\n\nnuevo\n".to_string());
        map.insert("docs/plan.md".to_string(), "# Plan\n\n- [ ] paso\n".to_string());
        map
    }

    #[test]
    fn applies_keeps_crlf_and_can_be_undone() {
        let (root, project) = setup("apply");
        let base = hashes(&project);
        let originals = root.join("originals");

        let applied = apply_to_disk(&project, &bodies(), &base, &originals).unwrap();
        assert_eq!(
            std::fs::read(root.join("docs/estado.md")).unwrap(),
            b"# Estado\r\n\r\nnuevo\r\n"
        );
        assert_eq!(applied, hashes(&project));

        undo_on_disk(&project, &applied, &originals).unwrap();
        assert_eq!(hashes(&project), base);
    }

    #[test]
    fn a_document_touched_since_the_proposal_is_not_written() {
        let (root, project) = setup("changed");
        let base = hashes(&project);
        std::fs::write(root.join("docs/plan.md"), "# Plan editado a mano\n").unwrap();

        let err = apply_to_disk(&project, &bodies(), &base, &root.join("o")).unwrap_err();
        assert!(matches!(err, ApplyError::BaseChanged { ref files } if files == &["docs/plan.md"]));
        assert_eq!(
            std::fs::read(root.join("docs/estado.md")).unwrap(),
            b"# Estado\r\n\r\nviejo\r\n",
            "el otro documento tampoco se toca"
        );
    }

    #[test]
    fn undo_refuses_when_someone_edited_after_applying() {
        let (root, project) = setup("undo");
        let base = hashes(&project);
        let originals = root.join("originals");
        let applied = apply_to_disk(&project, &bodies(), &base, &originals).unwrap();

        std::fs::write(root.join("docs/estado.md"), "editado despues\n").unwrap();
        assert!(matches!(
            undo_on_disk(&project, &applied, &originals),
            Err(ApplyError::BaseChanged { .. })
        ));
        assert_eq!(std::fs::read(root.join("docs/estado.md")).unwrap(), b"editado despues\n");
    }

    #[test]
    fn no_temporary_files_are_left_in_the_repo() {
        let (root, project) = setup("tmp");
        let base = hashes(&project);
        apply_to_disk(&project, &bodies(), &base, &root.join("o")).unwrap();
        let names: Vec<String> = std::fs::read_dir(root.join("docs"))
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert!(names.iter().all(|n| !n.contains("nexodeck-tmp")), "{names:?}");
    }

    #[test]
    fn a_non_utf8_document_is_refused_before_anything_is_written() {
        let (root, project) = setup("utf8");
        std::fs::write(root.join("docs/plan.md"), b"# Plan \xFF\n").unwrap();
        let err = read_documents(&project, ["docs/plan.md"]).unwrap_err();
        assert!(err.to_string().contains("UTF-8"));
    }
}
