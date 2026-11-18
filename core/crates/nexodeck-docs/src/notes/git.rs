//! Los commits de los repositorios que se cruzan con las notas.
//!
//! Por la linea de ordenes de `git` y no con `git2`: `git2` mete libgit2 (C) en
//! el workspace para leer un log, y `git` ya esta en cualquier maquina donde
//! haya repositorios que cruzar. NexoDeck **solo lee**: nada de aca escribe en un
//! repositorio.

use std::path::Path;
use std::process::Command;

/// Separadores que no aparecen en un mensaje de commit: unidad (campo) y
/// registro (commit).
const FIELD: char = '\u{1f}';
const RECORD: char = '\u{1e}';

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommitInfo {
    /// El nombre de la carpeta del repositorio: `NexoDeck`, `ExampleApi`.
    pub repo: String,
    pub sha: String,
    /// `AAAA-MM-DD`.
    pub date: String,
    pub author: String,
    pub subject: String,
    pub body: String,
}

impl CommitInfo {
    /// `c:NexoDeck@17004c2`.
    pub fn id(&self) -> String {
        format!("c:{}@{}", self.repo, &self.sha[..self.sha.len().min(7)])
    }
}

/// Los commits de los ultimos `days` dias, hasta `limit`, del mas nuevo al mas
/// viejo. Un repositorio que no existe o no es git devuelve el error como texto:
/// quien llama decide si es grave (para un digest no lo es).
pub fn recent_commits(repo: &Path, days: u32, limit: usize) -> Result<Vec<CommitInfo>, String> {
    let name = repo
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| repo.display().to_string());

    let mut command = Command::new("git");
    command
        .arg("-C")
        .arg(repo)
        .args([
            "log",
            "--no-color",
            &format!("--since={days}.days"),
            &format!("-n{limit}"),
            "--date=short",
            &format!("--format=%H{FIELD}%ad{FIELD}%an{FIELD}%s{FIELD}%b{RECORD}"),
        ]);
    hide_console(&mut command);

    let output = command
        .output()
        .map_err(|e| format!("no se pudo ejecutar git en {}: {e}", repo.display()))?;
    if !output.status.success() {
        return Err(format!(
            "git log fallo en {}: {}",
            repo.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(parse_log(&name, &String::from_utf8_lossy(&output.stdout)))
}

fn parse_log(repo: &str, text: &str) -> Vec<CommitInfo> {
    text.split(RECORD)
        .filter_map(|record| {
            let record = record.trim_start_matches(['\n', '\r']);
            let mut fields = record.splitn(5, FIELD);
            let sha = fields.next()?.trim();
            if sha.len() < 7 {
                return None;
            }
            Some(CommitInfo {
                repo: repo.to_string(),
                sha: sha.to_string(),
                date: fields.next()?.trim().to_string(),
                author: fields.next()?.trim().to_string(),
                subject: fields.next()?.trim().to_string(),
                body: fields.next().unwrap_or("").trim().to_string(),
            })
        })
        .collect()
}

/// Desde la app de escritorio (subsistema GUI), lanzar `git.exe` sin esto abre y
/// cierra una consola en cada consulta.
#[cfg(windows)]
fn hide_console(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(windows))]
fn hide_console(_command: &mut Command) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_records_with_multiline_bodies() {
        let text = format!(
            "abc1234def{FIELD}2026-09-15{FIELD}Juan{FIELD}Buzon: origen{FIELD}Cuerpo\ncon dos lineas\n{RECORD}\n0123456789{FIELD}2026-09-14{FIELD}Juan{FIELD}Sin cuerpo{FIELD}{RECORD}\n"
        );
        let commits = parse_log("NexoDeck", &text);
        assert_eq!(commits.len(), 2);
        assert_eq!(commits[0].id(), "c:NexoDeck@abc1234");
        assert_eq!(commits[0].body, "Cuerpo\ncon dos lineas");
        assert_eq!(commits[1].subject, "Sin cuerpo");
        assert_eq!(commits[1].body, "");
    }

    #[test]
    fn reads_a_real_repository() {
        let dir = crate::test_support::temp_dir("git-log");
        let git = |args: &[&str]| {
            let status = Command::new("git").arg("-C").arg(&dir).args(args).output();
            status.map(|o| o.status.success()).unwrap_or(false)
        };
        if !git(&["init", "-q"]) {
            // Sin git en la maquina no hay nada que probar.
            return;
        }
        std::fs::write(dir.join("a.txt"), "uno").unwrap();
        assert!(git(&["add", "a.txt"]));
        assert!(git(&[
            "-c",
            "user.name=Prueba",
            "-c",
            "user.email=prueba@example.invalid",
            "commit",
            "-q",
            "-m",
            "Primer commit\n\nPorque hacia falta.",
        ]));

        let commits = recent_commits(&dir, 30, 10).unwrap();
        assert_eq!(commits.len(), 1);
        assert_eq!(commits[0].subject, "Primer commit");
        assert_eq!(commits[0].body, "Porque hacia falta.");
        assert_eq!(commits[0].author, "Prueba");

        assert!(recent_commits(&dir.join("no-existe"), 30, 10).is_err());
    }
}
