//! Leer una nota de la boveda: frontmatter, enlaces, etiquetas, tareas y
//! secciones.
//!
//! Se lee el formato que ya usa Obsidian para que la boveda siga abriendose
//! alli sin conversion: `[[enlaces]]`, `#etiquetas`, frontmatter YAML y tareas
//! `- [ ] texto 📅 2026-09-20`. No es un parser de YAML ni de Markdown completo:
//! es lo justo para relacionar notas, y todo lo que este dentro de un bloque de
//! codigo se ignora (un `[[x]]` en un log no es un enlace).

use std::collections::BTreeMap;
use std::sync::LazyLock;

use regex::Regex;

use crate::markdown::headings;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteTask {
    /// Linea del fichero, empezando en 1 y contando el frontmatter.
    pub line: usize,
    pub text: String,
    pub done: bool,
    /// `AAAA-MM-DD`, del `📅` de Obsidian Tasks.
    pub due: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteSection {
    /// La linea del encabezado (`## Tareas`), o vacio para lo que va antes del
    /// primero.
    pub heading: String,
    /// Linea del fichero donde empieza, desde 1.
    pub line: usize,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ParsedNote {
    pub title: String,
    pub frontmatter: BTreeMap<String, String>,
    pub tags: Vec<String>,
    /// Destinos de los `[[enlaces]]`, sin alias ni `#seccion`, sin repetir.
    pub links: Vec<String>,
    pub tasks: Vec<NoteTask>,
    pub sections: Vec<NoteSection>,
    /// `ai: false` en el frontmatter: ningun agente la lee.
    pub ai_excluded: bool,
    /// `AAAA-MM-DD`: la del frontmatter, o la del nombre de una nota diaria.
    pub date: Option<String>,
}

static WIKILINK: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[\[([^\]\|#\n]+)(?:#[^\]\|\n]*)?(?:\|[^\]\n]*)?\]\]").expect("regex valida")
});
static TAG: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?:^|[\s(])#([\p{L}\p{N}_][\p{L}\p{N}_/\-]*)").expect("regex valida")
});
static TASK: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*[-*+] \[([ xX])\] (.*)$").expect("regex valida"));
static DUE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"📅\s*(\d{4}-\d{2}-\d{2})").expect("regex valida"));
static ISO_DATE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\d{4}-\d{2}-\d{2})").expect("regex valida"));

pub fn parse_note(rel_path: &str, body: &str) -> ParsedNote {
    let lines: Vec<&str> = body.split('\n').collect();
    let (frontmatter, body_start) = frontmatter(&lines);
    let in_code = code_mask(&lines);

    let mut tags: Vec<String> = frontmatter
        .get("tags")
        .map(|raw| list_items(raw))
        .unwrap_or_default()
        .into_iter()
        .map(|t| t.trim_start_matches('#').to_string())
        .filter(|t| !t.is_empty())
        .collect();
    let mut links = Vec::new();
    let mut tasks = Vec::new();

    for (index, line) in lines.iter().enumerate().skip(body_start) {
        if in_code[index] {
            continue;
        }
        for cap in WIKILINK.captures_iter(line) {
            push_unique(&mut links, cap[1].trim().to_string());
        }
        // Un encabezado empieza por `#` seguido de espacio, que la regex de
        // etiquetas ya no acepta.
        for cap in TAG.captures_iter(line) {
            push_unique(&mut tags, cap[1].to_string());
        }
        if let Some(cap) = TASK.captures(line) {
            let text = cap[2].trim().to_string();
            tasks.push(NoteTask {
                line: index + 1,
                done: &cap[1] != " ",
                due: DUE.captures(&text).map(|d| d[1].to_string()),
                tags: TAG.captures_iter(&text).map(|t| t[1].to_string()).collect(),
                text,
            });
        }
    }

    let sections = sections(&lines, body_start);
    let title = frontmatter
        .get("title")
        .map(|t| unquote(t).to_string())
        .filter(|t| !t.is_empty())
        .or_else(|| {
            headings(&lines[body_start..])
                .into_iter()
                .find(|h| h.level == 1)
                .map(|h| h.text.trim_start_matches('#').trim().to_string())
        })
        .unwrap_or_else(|| file_stem(rel_path));

    let date = frontmatter
        .get("date")
        .and_then(|d| ISO_DATE.captures(unquote(d)).map(|c| c[1].to_string()))
        .or_else(|| {
            let stem = file_stem(rel_path);
            ISO_DATE
                .captures(&stem)
                .filter(|_| stem.len() == 10)
                .map(|c| c[1].to_string())
        });

    let ai_excluded = frontmatter
        .get("ai")
        .is_some_and(|v| matches!(unquote(v).to_lowercase().as_str(), "false" | "no" | "0" | "off"));

    ParsedNote {
        title,
        frontmatter,
        tags,
        links,
        tasks,
        sections,
        ai_excluded,
        date,
    }
}

/// El bloque YAML inicial como `clave -> valor crudo`, y la linea donde empieza
/// el cuerpo. Una lista en bloque se junta como `[a, b]`.
fn frontmatter(lines: &[&str]) -> (BTreeMap<String, String>, usize) {
    let mut map = BTreeMap::new();
    if lines.first().map(|l| l.trim_end()) != Some("---") {
        return (map, 0);
    }
    let Some(close) = lines
        .iter()
        .skip(1)
        .position(|l| l.trim_end() == "---")
        .map(|i| i + 1)
    else {
        // Un bloque que no cierra no es frontmatter: es texto.
        return (map, 0);
    };

    let mut current: Option<(String, Vec<String>)> = None;
    for line in &lines[1..close] {
        let trimmed = line.trim();
        if let Some(item) = trimmed.strip_prefix("- ") {
            if let Some((_, items)) = current.as_mut() {
                items.push(unquote(item.trim()).to_string());
            }
            continue;
        }
        if let Some((key, items)) = current.take() {
            map.insert(key, format!("[{}]", items.join(", ")));
        }
        let Some((key, value)) = line.split_once(':') else { continue };
        if line.starts_with([' ', '\t']) {
            continue;
        }
        let key = key.trim().to_string();
        let value = value.trim();
        if value.is_empty() {
            current = Some((key, Vec::new()));
        } else {
            map.insert(key, value.to_string());
        }
    }
    if let Some((key, items)) = current {
        map.insert(key, format!("[{}]", items.join(", ")));
    }
    (map, close + 1)
}

/// `true` en las lineas que estan dentro de un bloque de codigo, vallas incluidas.
fn code_mask(lines: &[&str]) -> Vec<bool> {
    let mut mask = vec![false; lines.len()];
    let mut fence: Option<&str> = None;
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim_start();
        match fence {
            Some(marker) => {
                mask[index] = true;
                if trimmed.starts_with(marker) {
                    fence = None;
                }
            }
            None if trimmed.starts_with("```") || trimmed.starts_with("~~~") => {
                mask[index] = true;
                fence = Some(if trimmed.starts_with("```") { "```" } else { "~~~" });
            }
            None => {}
        }
    }
    mask
}

/// Reescribe los `[[enlaces]]` que apuntan **por ruta** a `from` para que
/// apunten a `to`. Devuelve el texto y cuantos cambio.
///
/// Vive aqui, al lado de `WIKILINK` y `code_mask`, a proposito: al mover una nota
/// hay que reescribir exactamente lo que el indice cuenta como enlace. Con dos
/// criterios, el movimiento dejaria enlaces que el indice da por rotos, o
/// tocaria cosas que para el no son enlaces.
///
/// - **Solo los que llevan ruta.** `[[nota]]` por nombre suelto resuelve por
///   nombre unico (`NotesIndex::resolve_link`) y sigue funcionando sin tocarlo.
/// - **Conserva** la `#seccion`, el `|alias` y si llevaba `.md` o no.
/// - **No toca lo que este dentro de un bloque de codigo**: un `[[x]]` en un log
///   no es un enlace.
/// - Sin distinguir mayusculas, igual que `resolve_link`.
pub(crate) fn rewrite_wikilinks(body: &str, from: &str, to: &str) -> (String, usize) {
    let key = |rel: &str| {
        let rel = rel.trim().replace('\\', "/");
        rel.strip_suffix(".md")
            .or_else(|| rel.strip_suffix(".MD"))
            .unwrap_or(&rel)
            .to_lowercase()
    };
    let from_key = key(from);
    let to_stem = to.trim().replace('\\', "/");
    let to_stem = to_stem.strip_suffix(".md").unwrap_or(&to_stem).to_string();

    let lines: Vec<&str> = body.split('\n').collect();
    let in_code = code_mask(&lines);
    let mut changed = 0;
    let mut out = Vec::with_capacity(lines.len());

    for (index, line) in lines.iter().enumerate() {
        if in_code[index] || !line.contains("[[") {
            out.push((*line).to_string());
            continue;
        }
        let mut rebuilt = String::with_capacity(line.len());
        let mut last = 0;
        for caps in WIKILINK.captures_iter(line) {
            let Some(target) = caps.get(1) else {
                continue;
            };
            let raw = target.as_str();
            // Por nombre suelto: resuelve solo, no hay nada que arreglar.
            if !raw.contains('/') && !raw.contains('\\') {
                continue;
            }
            if key(raw) != from_key {
                continue;
            }
            let replacement = if raw.trim().to_lowercase().ends_with(".md") {
                format!("{to_stem}.md")
            } else {
                to_stem.clone()
            };
            // Solo se sustituye el destino: lo que haya antes (`[[`) y despues
            // (`#seccion|alias]]`) se copia tal cual.
            rebuilt.push_str(&line[last..target.start()]);
            rebuilt.push_str(&replacement);
            last = target.end();
            changed += 1;
        }
        rebuilt.push_str(&line[last..]);
        out.push(rebuilt);
    }
    (out.join("\n"), changed)
}

#[cfg(test)]
mod rewrite_tests {
    use super::rewrite_wikilinks;

    #[test]
    fn rewrites_links_that_cite_the_note_by_path() {
        let (out, changed) = rewrite_wikilinks(
            "ver [[inbox/nota]] y [[inbox/nota.md]]",
            "inbox/nota.md",
            "odm/nota.md",
        );
        assert_eq!(out, "ver [[odm/nota]] y [[odm/nota.md]]");
        assert_eq!(changed, 2);
    }

    #[test]
    fn keeps_the_section_and_the_alias() {
        let (out, _) = rewrite_wikilinks(
            "[[inbox/nota#Resumen|el resumen]]",
            "inbox/nota.md",
            "odm/nota.md",
        );
        assert_eq!(out, "[[odm/nota#Resumen|el resumen]]");
    }

    /// Por nombre suelto el enlace resuelve solo: tocarlo seria reescribir la
    /// nota de otro sin ninguna necesidad.
    #[test]
    fn leaves_links_by_bare_name_alone() {
        let (out, changed) = rewrite_wikilinks("[[nota]]", "inbox/nota.md", "odm/nota.md");
        assert_eq!(out, "[[nota]]");
        assert_eq!(changed, 0);
    }

    #[test]
    fn ignores_other_notes_and_code_blocks_but_not_case() {
        let body = "[[inbox/otra]]\n```\n[[inbox/nota]]\n```\n[[Inbox/Nota]]";
        let (out, changed) = rewrite_wikilinks(body, "inbox/nota.md", "odm/nota.md");
        assert_eq!(
            out,
            "[[inbox/otra]]\n```\n[[inbox/nota]]\n```\n[[odm/nota]]"
        );
        assert_eq!(changed, 1);
    }
}

/// Partes de la nota por encabezados de nivel 1 y 2. Lo de antes del primero
/// va con encabezado vacio. Los de nivel 3 quedan dentro de su seccion: una
/// nota partida en trozos demasiado chicos relaciona peor.
fn sections(lines: &[&str], body_start: usize) -> Vec<NoteSection> {
    let body = &lines[body_start..];
    let cuts: Vec<(usize, String)> = headings(body)
        .into_iter()
        .filter(|h| h.level <= 2)
        .map(|h| (h.line, h.text))
        .collect();

    let mut out = Vec::new();
    let first = cuts.first().map(|c| c.0).unwrap_or(body.len());
    let preamble = body[..first].join("\n");
    if !preamble.trim().is_empty() {
        out.push(NoteSection {
            heading: String::new(),
            line: body_start + 1,
            text: preamble,
        });
    }
    for (i, (start, heading)) in cuts.iter().enumerate() {
        let end = cuts.get(i + 1).map(|c| c.0).unwrap_or(body.len());
        out.push(NoteSection {
            heading: heading.clone(),
            line: body_start + start + 1,
            text: body[*start..end].join("\n"),
        });
    }
    out
}

/// `[a, b]`, `a, b` o `a` como lista.
fn list_items(raw: &str) -> Vec<String> {
    let raw = raw.trim();
    let inner = raw
        .strip_prefix('[')
        .and_then(|r| r.strip_suffix(']'))
        .unwrap_or(raw);
    inner
        .split(',')
        .map(|item| unquote(item.trim()).to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

fn unquote(value: &str) -> &str {
    let value = value.trim();
    value
        .strip_prefix('"')
        .and_then(|v| v.strip_suffix('"'))
        .or_else(|| value.strip_prefix('\'').and_then(|v| v.strip_suffix('\'')))
        .unwrap_or(value)
}

fn file_stem(rel_path: &str) -> String {
    let name = rel_path.rsplit(['/', '\\']).next().unwrap_or(rel_path);
    name.strip_suffix(".md")
        .or_else(|| name.strip_suffix(".MD"))
        .unwrap_or(name)
        .to_string()
}

fn push_unique(list: &mut Vec<String>, value: String) {
    if !value.is_empty() && !list.contains(&value) {
        list.push(value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOTE: &str = "---\ntitle: \"Reunion con soporte\"\ndate: 2026-09-14\ntags:\n  - trabajo\n  - proyecto\nproject: NexoDeck\n---\n# Titulo del cuerpo\n\nHablamos de [[proyectos/NexoDeck|NexoDeck]] y de [[temas/Drift#migraciones]]. #urgente\n\n## Tareas\n\n- [ ] revisar la tanda R 📅 2026-09-20 #odm\n- [x] mandar el informe\n\n```bash\n# no es etiqueta\n- [ ] no es tarea [[ni enlace]]\n```\n\n## Notas\n\ntexto final\n";

    #[test]
    fn reads_frontmatter_links_tags_and_tasks() {
        let note = parse_note("reuniones/soporte.md", NOTE);
        assert_eq!(note.title, "Reunion con soporte");
        assert_eq!(note.date.as_deref(), Some("2026-09-14"));
        assert_eq!(note.frontmatter["project"], "NexoDeck");
        assert_eq!(note.links, vec!["proyectos/NexoDeck", "temas/Drift"]);
        assert_eq!(note.tags, vec!["trabajo", "proyecto", "urgente", "odm"]);

        assert_eq!(note.tasks.len(), 2, "{:?}", note.tasks);
        assert_eq!(note.tasks[0].text, "revisar la tanda R 📅 2026-09-20 #odm");
        assert_eq!(note.tasks[0].due.as_deref(), Some("2026-09-20"));
        assert_eq!(note.tasks[0].tags, vec!["odm"]);
        assert!(!note.tasks[0].done);
        assert!(note.tasks[1].done);
        assert_eq!(NOTE.split('\n').nth(note.tasks[0].line - 1).unwrap(), "- [ ] revisar la tanda R 📅 2026-09-20 #odm");
    }

    #[test]
    fn splits_sections_and_keeps_the_preamble() {
        let note = parse_note("reuniones/soporte.md", NOTE);
        let headings: Vec<&str> = note.sections.iter().map(|s| s.heading.as_str()).collect();
        assert_eq!(headings, vec!["# Titulo del cuerpo", "## Tareas", "## Notas"]);
        assert!(note.sections[1].text.contains("mandar el informe"));
        assert_eq!(NOTE.split('\n').nth(note.sections[1].line - 1).unwrap(), "## Tareas");
    }

    #[test]
    fn a_note_without_frontmatter_takes_its_title_and_date_from_the_file() {
        let note = parse_note("diario/2026-09-15.md", "hoy\n\n- [ ] algo\n");
        assert_eq!(note.title, "2026-09-15");
        assert_eq!(note.date.as_deref(), Some("2026-09-15"));
        assert_eq!(note.sections.len(), 1);
        assert!(note.frontmatter.is_empty());
    }

    #[test]
    fn ai_false_excludes_the_note() {
        assert!(parse_note("a.md", "---\nai: false\n---\n# A\n").ai_excluded);
        assert!(parse_note("a.md", "---\nai: \"no\"\n---\n# A\n").ai_excluded);
        assert!(!parse_note("a.md", "---\nai: true\n---\n# A\n").ai_excluded);
        assert!(!parse_note("a.md", "# A\n").ai_excluded);
    }

    #[test]
    fn an_unclosed_frontmatter_is_just_text() {
        let note = parse_note("a.md", "---\ntitle: x\n# A\n");
        assert!(note.frontmatter.is_empty());
        assert_eq!(note.title, "A");
    }
}
