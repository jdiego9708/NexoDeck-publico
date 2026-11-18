//! La ventana de notas sin Flutter, sobre una carpeta de notas cualquiera.
//!
//! `cargo run -p nexodeck-editor --example open_note -- <carpeta> [nota]`
//!
//! Abre la ventana (con la nota, si se da) e imprime lo que pasa. Por stdin:
//! `open <nota>` abre otra, `show` trae la ventana, `changed` simula un cambio en
//! el buzon, `close` cierra la ventana (guardando antes) y `quit` sale. El
//! backend es de juguete: no conserva CRLF ni BOM, el hash no es sha256, la
//! busqueda es por texto literal y no hay asistente. Todo eso lo hace
//! `nexodeck-docs` en la app.

#[cfg(windows)]
mod folder {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::path::{Path, PathBuf};

    use nexodeck_editor::{
        DetailsDto, DigestDto, EditorBackend, HitDto, NoteDto, NoteSummaryDto, OverviewDto, SaveResult,
        TaskDto,
    };

    pub struct FolderBackend {
        pub root: PathBuf,
    }

    fn hash(bytes: &[u8]) -> String {
        let mut hasher = DefaultHasher::new();
        bytes.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    }

    fn title_of(text: &str, rel: &str) -> String {
        text.lines()
            .find_map(|line| line.strip_prefix("# "))
            .unwrap_or(rel)
            .trim()
            .to_string()
    }

    impl FolderBackend {
        fn resolve(&self, path: &str) -> Result<(String, PathBuf), String> {
            let rel = path.replace('\\', "/");
            let rel = if rel.ends_with(".md") { rel } else { format!("{rel}.md") };
            if rel.split('/').any(|s| s.is_empty() || s == ".." || s.starts_with('.')) {
                return Err(format!("ruta no valida: {path}"));
            }
            let full = self.root.join(&rel);
            Ok((rel, full))
        }

        fn read(&self, rel: String, full: &Path) -> Result<NoteDto, String> {
            let raw = std::fs::read(full).map_err(|e| format!("{rel}: {e}"))?;
            let text = String::from_utf8_lossy(&raw).replace("\r\n", "\n");
            Ok(NoteDto {
                private: rel.starts_with("privado/"),
                hash: Some(hash(&raw)),
                title: title_of(&text, &rel),
                text,
                path: rel,
            })
        }

        /// Las notas visibles (sin `privado/` ni carpetas ocultas), con su texto.
        fn notes(&self) -> Vec<(String, String)> {
            let mut out = Vec::new();
            self.walk(&self.root, &mut out);
            out
        }

        fn walk(&self, dir: &Path, out: &mut Vec<(String, String)>) {
            let Ok(entries) = std::fs::read_dir(dir) else { return };
            for entry in entries.flatten() {
                let path = entry.path();
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') || name == "privado" {
                    continue;
                }
                if path.is_dir() {
                    self.walk(&path, out);
                } else if name.ends_with(".md") {
                    let rel = path
                        .strip_prefix(&self.root)
                        .unwrap_or(&path)
                        .to_string_lossy()
                        .replace('\\', "/");
                    let text = std::fs::read_to_string(&path).unwrap_or_default();
                    out.push((rel, text));
                }
            }
        }
    }

    impl EditorBackend for FolderBackend {
        fn open(&self, path: &str) -> Result<NoteDto, String> {
            let (rel, full) = self.resolve(path)?;
            self.read(rel, &full)
        }

        fn save(&self, path: &str, text: &str, base_hash: Option<&str>) -> Result<SaveResult, String> {
            let (_, full) = self.resolve(path)?;
            let disk = std::fs::read(&full).ok();
            let disk_hash = disk.as_deref().map(hash);
            if disk_hash.as_deref() != base_hash {
                return Ok(SaveResult::Conflict {
                    disk_text: disk
                        .map(|d| String::from_utf8_lossy(&d).into_owned())
                        .unwrap_or_default(),
                    disk_hash: disk_hash.unwrap_or_default(),
                });
            }
            std::fs::write(&full, text).map_err(|e| e.to_string())?;
            Ok(SaveResult::Saved {
                hash: hash(text.as_bytes()),
            })
        }

        fn create(&self, path: &str, title: &str) -> Result<NoteDto, String> {
            let (rel, full) = self.resolve(path)?;
            if !full.exists() {
                if let Some(dir) = full.parent() {
                    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
                }
                let heading = if title.trim().is_empty() {
                    rel.trim_end_matches(".md")
                } else {
                    title.trim()
                };
                std::fs::write(&full, format!("# {heading}\n\n")).map_err(|e| e.to_string())?;
            }
            self.read(rel, &full)
        }

        fn daily(&self) -> Result<NoteDto, String> {
            self.create("diario/hoy", "Hoy")
        }

        fn overview(&self) -> Result<OverviewDto, String> {
            let mut notes = Vec::new();
            let mut tasks = Vec::new();
            for (rel, text) in self.notes() {
                let mut open_tasks = 0;
                for (index, line) in text.lines().enumerate() {
                    if let Some(task) = line.trim_start().strip_prefix("- [ ] ") {
                        open_tasks += 1;
                        tasks.push(TaskDto {
                            path: rel.clone(),
                            line: u32::try_from(index + 1).unwrap_or(u32::MAX),
                            text: task.to_string(),
                            done: false,
                            due: None,
                        });
                    }
                }
                let role = if rel.starts_with("diario/") {
                    "daily"
                } else if rel.starts_with("proyectos/") {
                    "hub"
                } else {
                    "note"
                };
                notes.push(NoteSummaryDto {
                    // El backend de juguete no sabe de agrupaciones: eso vive
                    // en `nexodeck-docs`, del que este crate no depende.
                    group: None,
                    folder: None,
                    title: title_of(&text, &rel),
                    path: rel,
                    role: role.to_string(),
                    date: None,
                    tags: Vec::new(),
                    open_tasks,
                    ai_excluded: false,
                    modified: None,
                });
            }
            Ok(OverviewDto {
                configured: true,
                root: Some(self.root.display().to_string()),
                folders: vec![],
                groups: vec![],
                notes,
                tasks,
                digests: Vec::new(),
                error: None,
            })
        }

        fn search(&self, query: &str) -> Result<Vec<HitDto>, String> {
            let needle = query.to_lowercase();
            Ok(self
                .notes()
                .into_iter()
                .filter_map(|(rel, text)| {
                    let line = text.lines().find(|l| l.to_lowercase().contains(&needle))?;
                    Some(HitDto {
                        id: format!("n:{rel}"),
                        kind: "note".to_string(),
                        title: title_of(&text, &rel),
                        snippet: line.trim().to_string(),
                        date: None,
                        path: Some(rel),
                    })
                })
                .collect())
        }

        fn details(&self, path: &str) -> Result<DetailsDto, String> {
            let target = format!("[[{}", path.trim_end_matches(".md"));
            let backlinks = self
                .notes()
                .into_iter()
                .filter(|(rel, text)| rel != path && text.contains(&target))
                .map(|(rel, _)| rel)
                .collect();
            Ok(DetailsDto {
                path: path.to_string(),
                backlinks,
                related: Vec::new(),
                digests: Vec::new(),
            })
        }

        fn digest(&self, _path: &str) -> Result<DigestDto, String> {
            Err("este ejemplo no tiene asistente".to_string())
        }

        fn resolve_link(&self, target: &str, _source: Option<&str>) -> Result<Option<String>, String> {
            let (rel, full) = self.resolve(target)?;
            Ok(full.exists().then_some(rel))
        }
    }
}

#[cfg(windows)]
fn main() {
    use std::io::BufRead;
    use std::sync::Arc;

    use nexodeck_editor::{Editor, EditorBackend};

    let mut args = std::env::args().skip(1);
    let Some(root) = args.next() else {
        eprintln!("uso: open_note <carpeta> [nota]");
        std::process::exit(2);
    };
    println!("{:?}", nexodeck_editor::availability());

    let backend = Arc::new(folder::FolderBackend { root: root.into() });
    let editor = Editor::start(backend.clone(), Arc::new(|event| println!("[editor] {event:?}")))
        .expect("arrancar el editor");
    let open = |path: &str| match backend.open(path) {
        Ok(note) => editor.open(note, None).expect("el hilo del editor"),
        Err(error) => println!("[error] {error}"),
    };
    match args.next() {
        Some(first) => open(&first),
        None => editor.show(None).expect("el hilo del editor"),
    }

    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        // .NET antepone un BOM a lo primero que escribe en el stdin de un proceso.
        let line = line.trim().trim_start_matches('\u{feff}');
        match line.split_once(' ') {
            Some(("open", path)) => open(path.trim()),
            _ if line == "show" => editor.show(None).expect("el hilo del editor"),
            _ if line == "changed" => editor.changed().expect("el hilo del editor"),
            _ if line == "close" => editor.close().expect("el hilo del editor"),
            _ if line == "quit" => break,
            _ => println!("comandos: open <nota>, show, changed, close, quit"),
        }
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("el editor solo existe en Windows");
}
