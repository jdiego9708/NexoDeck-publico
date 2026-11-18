//! Exportar la boveda principal a un zip.
//!
//! Decision del usuario: **solo la boveda principal**. Las carpetas locales ya
//! viven en su propia ruta y el usuario las tiene a mano.
//!
//! - **Por carpetas y en el orden del arbol**: dentro del zip, una carpeta raiz
//!   con el nombre de la boveda y debajo sus agrupaciones y subcarpetas, carpetas
//!   primero y en orden natural, igual que las ve en la ventana. Un zip no tiene
//!   orden de presentacion obligado, pero los visores respetan el de las
//!   entradas.
//! - **Solo `.md`**, y fuera lo mismo que el indice deja fuera: carpetas ocultas
//!   (`.obsidian`, `.git`, la papelera) y las de primer nivel con `@`, que
//!   chocarian con el prefijo de las carpetas locales. `privado/` **si** entra:
//!   es una copia de la boveda del usuario, hecha por el.
//! - **Las carpetas vacias tambien entran**: una agrupacion recien creada es una
//!   carpeta sin notas, y perderla al restaurar perderia la agrupacion.
//! - **Se escribe a un temporal y se renombra al final**: un zip a medias con el
//!   nombre bueno parece una copia valida y no lo es.

use std::cmp::Ordering;
use std::fs::File;
use std::io::{BufWriter, Seek, Write};
use std::path::{Path, PathBuf};

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

use crate::error::{DocsError, DocsResult};
use crate::notes::roots::is_local_marker;
use crate::service::DocsService;

/// Lo que se exporto.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExportOutcome {
    pub path: String,
    pub notes: usize,
    pub folders: usize,
}

impl DocsService {
    pub fn export_vault_zip(&self, destination: &Path) -> DocsResult<ExportOutcome> {
        let config = self.inbox.config()?;
        let (_, project) = config
            .vault()
            .ok_or_else(|| DocsError::Invalid("no hay ninguna boveda configurada".into()))?;
        let root = PathBuf::from(&project.repo_root);
        if !root.is_dir() {
            return Err(DocsError::Invalid(format!("la boveda {} no esta disponible", root.display())));
        }
        if !destination.extension().is_some_and(|e| e.eq_ignore_ascii_case("zip")) {
            return Err(DocsError::Invalid("elige un fichero .zip de destino".into()));
        }

        let temporary = destination.with_extension("zip.partial");
        let file = File::create(&temporary).map_err(|e| DocsError::io(&temporary, e))?;
        let written = write_vault_zip(&root, &zip_folder_name(&project.name), BufWriter::new(file));
        let (notes, folders) = match written {
            Ok(counts) => counts,
            Err(error) => {
                let _ = std::fs::remove_file(&temporary);
                return Err(error);
            }
        };
        std::fs::rename(&temporary, destination).map_err(|e| {
            let _ = std::fs::remove_file(&temporary);
            DocsError::io(destination, e)
        })?;
        Ok(ExportOutcome {
            path: destination.display().to_string(),
            notes,
            folders,
        })
    }
}

/// Escribe la boveda en [out]. Devuelve cuantas notas y carpetas entraron.
pub(crate) fn write_vault_zip<W: Write + Seek>(root: &Path, top: &str, out: W) -> DocsResult<(usize, usize)> {
    let mut zip = ZipWriter::new(out);
    let options = SimpleFileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .unix_permissions(0o644);
    let zip_err = |e: zip::result::ZipError| DocsError::Invalid(format!("no se pudo escribir el zip: {e}"));

    zip.add_directory(format!("{top}/"), options).map_err(zip_err)?;
    let mut counts = (0, 0);
    add_dir(&mut zip, root, root, top, options, &mut counts)?;
    zip.finish().map_err(zip_err)?.flush().map_err(|e| DocsError::io(root, e))?;
    Ok(counts)
}

fn add_dir<W: Write + Seek>(
    zip: &mut ZipWriter<W>,
    root: &Path,
    dir: &Path,
    top: &str,
    options: SimpleFileOptions,
    counts: &mut (usize, usize),
) -> DocsResult<()> {
    let zip_err = |e: zip::result::ZipError| DocsError::Invalid(format!("no se pudo escribir el zip: {e}"));
    let mut folders = Vec::new();
    let mut notes = Vec::new();
    for entry in std::fs::read_dir(dir).map_err(|e| DocsError::io(dir, e))? {
        let entry = entry.map_err(|e| DocsError::io(dir, e))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        // Un enlace simbolico podria sacar el recorrido de la boveda.
        let Ok(kind) = entry.file_type() else { continue };
        if name.starts_with('.') || kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            if dir == root && is_local_marker(&name) {
                continue;
            }
            folders.push(name);
        } else if kind.is_file() && name.to_lowercase().ends_with(".md") {
            notes.push(name);
        }
    }
    folders.sort_by(|a, b| compare_natural(a, b));
    notes.sort_by(|a, b| compare_natural(a, b));

    let rel = |name: &str| -> String {
        let inner = dir.strip_prefix(root).unwrap_or(dir);
        let mut path = top.to_string();
        for part in inner.components() {
            path.push('/');
            path.push_str(&part.as_os_str().to_string_lossy());
        }
        format!("{path}/{name}")
    };

    for folder in &folders {
        zip.add_directory(format!("{}/", rel(folder)), options).map_err(zip_err)?;
        counts.1 += 1;
        add_dir(zip, root, &dir.join(folder), top, options, counts)?;
    }
    for note in &notes {
        let full = dir.join(note);
        let bytes = std::fs::read(&full).map_err(|e| DocsError::io(&full, e))?;
        zip.start_file(rel(note), options).map_err(zip_err)?;
        zip.write_all(&bytes).map_err(|e| DocsError::io(&full, e))?;
        counts.0 += 1;
    }
    Ok(())
}

/// El nombre de la carpeta raiz del zip: el de la boveda, sin lo que no vale en
/// un nombre de fichero de Windows.
fn zip_folder_name(name: &str) -> String {
    let clean: String = name
        .chars()
        .map(|c| if r#"<>:"/\|?*"#.contains(c) || c.is_control() { '-' } else { c })
        .collect();
    let clean = clean.trim().trim_end_matches('.').to_string();
    if clean.is_empty() {
        "Notas".to_string()
    } else {
        clean
    }
}

/// Orden natural sin distinguir mayusculas, como el Explorador y como el arbol
/// de la app (`compareNatural`): `nota 2` antes que `nota 10`.
pub(crate) fn compare_natural(a: &str, b: &str) -> Ordering {
    let (a, b) = (a.to_lowercase(), b.to_lowercase());
    let (left, right) = (chunks(&a), chunks(&b));
    for (x, y) in left.iter().zip(&right) {
        let digits = |s: &str| s.bytes().all(|c| c.is_ascii_digit());
        let order = if digits(x) && digits(y) {
            let (x, y) = (x.trim_start_matches('0'), y.trim_start_matches('0'));
            x.len().cmp(&y.len()).then_with(|| x.cmp(y))
        } else {
            x.cmp(y)
        };
        if order != Ordering::Equal {
            return order;
        }
    }
    left.len().cmp(&right.len())
}

fn chunks(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut previous: Option<bool> = None;
    for (i, c) in s.char_indices() {
        let digit = c.is_ascii_digit();
        if previous.is_some_and(|p| p != digit) {
            out.push(&s[start..i]);
            start = i;
        }
        previous = Some(digit);
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Read};

    use super::*;

    #[test]
    fn the_zip_follows_the_tree_order_and_skips_what_the_index_skips() {
        let root = crate::test_support::temp_dir("export-order");
        for dir in ["b-grupo", "A-grupo/sub", "vacia", "privado", ".obsidian", "@apuntes", ".trash"] {
            std::fs::create_dir_all(root.join(dir)).unwrap();
        }
        for (path, text) in [
            ("nota 10.md", "diez"),
            ("Nota 2.md", "dos"),
            ("b-grupo/x.md", "x"),
            ("A-grupo/sub/y.md", "y"),
            ("A-grupo/z.md", "z"),
            ("privado/claves.md", "privado"),
            (".obsidian/app.md", "no"),
            ("@apuntes/fuera.md", "no"),
            ("imagen.png", "no"),
        ] {
            std::fs::write(root.join(path), text).unwrap();
        }

        let mut buffer = Cursor::new(Vec::new());
        let (notes, folders) = write_vault_zip(&root, "Notas", &mut buffer).unwrap();
        assert_eq!(notes, 6);
        assert_eq!(folders, 5, "A-grupo, sub, b-grupo, privado y la vacia");

        let mut archive = zip::ZipArchive::new(Cursor::new(buffer.into_inner())).unwrap();
        let names: Vec<String> = (0..archive.len())
            .map(|i| archive.by_index(i).unwrap().name().to_string())
            .collect();
        assert_eq!(
            names,
            [
                "Notas/",
                "Notas/A-grupo/",
                "Notas/A-grupo/sub/",
                "Notas/A-grupo/sub/y.md",
                "Notas/A-grupo/z.md",
                "Notas/b-grupo/",
                "Notas/b-grupo/x.md",
                "Notas/privado/",
                "Notas/privado/claves.md",
                "Notas/vacia/",
                "Notas/Nota 2.md",
                "Notas/nota 10.md",
            ]
        );
        let mut text = String::new();
        archive.by_name("Notas/Nota 2.md").unwrap().read_to_string(&mut text).unwrap();
        assert_eq!(text, "dos");
    }

    #[test]
    fn natural_order_ignores_case_and_compares_numbers_by_value() {
        assert_eq!(compare_natural("v2", "v10"), Ordering::Less);
        assert_eq!(compare_natural("Acme", "acme"), Ordering::Equal);
        assert_eq!(compare_natural("b", "A"), Ordering::Greater);
        assert_eq!(compare_natural("007", "7"), Ordering::Equal);
    }

    #[test]
    fn the_top_folder_name_is_safe_for_windows() {
        assert_eq!(zip_folder_name("Notas: trabajo?"), "Notas- trabajo-");
        assert_eq!(zip_folder_name("  "), "Notas");
    }
}
