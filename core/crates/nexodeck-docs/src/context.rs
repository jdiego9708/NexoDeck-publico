//! Que parte de cada documento ve el modelo.
//!
//! El diario de IA pesa 483 KB: no entra en ningun contexto razonable, y aunque
//! entrara, pagar eso en cada propuesta no tiene sentido. Del diario se enseña lo
//! que hace falta para escribir la seccion nueva y para corregir lo reciente:
//! la cabecera con su resumen, el indice de encabezados, las dos secciones mas
//! recientes enteras y, si hay sitio, las antiguas que mas se parecen a los
//! hallazgos. Los planes e indices son cortos y van enteros.
//!
//! Lo que se enseña queda guardado, porque la validacion exige que todo texto
//! que una operacion quiera tocar **estuviera ahi**: un modelo no puede editar
//! algo que no vio.

use std::collections::{BTreeMap, HashSet};

use crate::config::{normalize_rel, DocProject, DocRole};
use crate::markdown::{headings, section_end};
use crate::model::Finding;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentContext {
    pub path: String,
    pub role: DocRole,
    pub answers: String,
    pub shown: String,
    pub truncated: bool,
}

const RECENT_SECTIONS: usize = 2;
const RELATED_SECTIONS: usize = 2;
const OUTLINE_MAX_CHARS: usize = 8_000;
/// Palabras de menos letras no dicen de que trata una seccion ("para", "sobre").
const MIN_WORD_CHARS: usize = 5;

/// `bodies` va indexado por la ruta normalizada del documento.
pub fn build_context(
    project: &DocProject,
    bodies: &BTreeMap<String, String>,
    findings: &[Finding],
    budget_chars: usize,
) -> Vec<DocumentContext> {
    let mut out = Vec::new();
    let mut used = 0;

    // Primero lo que va entero, para saber cuanto queda para los diarios.
    let others: Vec<_> = project
        .documents
        .iter()
        .filter(|d| d.role != DocRole::Journal)
        .collect();
    let other_cap = budget_chars / 3;
    for doc in others {
        let path = normalize_rel(&doc.path);
        let Some(body) = bodies.get(&path) else { continue };
        let (shown, truncated) = take_lines(body, other_cap);
        used += shown.len();
        out.push(DocumentContext {
            path,
            role: doc.role,
            answers: doc.answers.clone(),
            shown,
            truncated,
        });
    }

    let journals: Vec<_> = project
        .documents
        .iter()
        .filter(|d| d.role == DocRole::Journal)
        .collect();
    let per_journal = budget_chars
        .saturating_sub(used)
        .max(budget_chars / 4)
        / journals.len().max(1);
    let words = finding_words(findings);

    for doc in journals {
        let path = normalize_rel(&doc.path);
        let Some(body) = bodies.get(&path) else { continue };
        let (shown, truncated) = journal_view(body, &words, per_journal);
        out.push(DocumentContext {
            path,
            role: doc.role,
            answers: doc.answers.clone(),
            shown,
            truncated,
        });
    }
    out
}

fn journal_view(body: &str, words: &HashSet<String>, budget: usize) -> (String, bool) {
    let lines: Vec<&str> = body.split('\n').collect();
    let found = headings(&lines);
    let sections: Vec<(usize, usize)> = found
        .iter()
        .enumerate()
        .filter(|(_, h)| h.level == 2)
        .map(|(i, h)| (h.line, section_end(&found, i, lines.len())))
        .collect();

    let header_end = sections.first().map(|s| s.0).unwrap_or(lines.len());
    let header = lines[..header_end].join("\n");
    let outline = found
        .iter()
        .filter(|h| h.level <= 3)
        .map(|h| h.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    let (outline, outline_cut) = take_lines(&outline, OUTLINE_MAX_CHARS);

    let recent: Vec<String> = sections
        .iter()
        .take(RECENT_SECTIONS)
        .map(|(start, end)| lines[*start..*end].join("\n"))
        .collect();

    let mut scored: Vec<(usize, String)> = sections
        .iter()
        .skip(RECENT_SECTIONS)
        .map(|(start, end)| {
            let text = lines[*start..*end].join("\n");
            let lower = text.to_lowercase();
            let score = words.iter().filter(|w| lower.contains(w.as_str())).count();
            (score, text)
        })
        .filter(|(score, _)| *score > 0)
        .collect();
    scored.sort_by_key(|(score, _)| std::cmp::Reverse(*score));

    // Por prioridad: lo reciente y el indice antes que la cabecera, porque la
    // cabecera es lo unico que se puede truncar sin romper una seccion.
    let mut remaining = budget;
    let mut truncated = outline_cut;
    let mut recent_kept = Vec::new();
    for section in &recent {
        if section.len() <= remaining {
            remaining -= section.len();
            recent_kept.push(section.as_str());
        } else {
            truncated = true;
        }
    }
    let outline = if outline.len() <= remaining {
        remaining -= outline.len();
        outline
    } else {
        truncated = true;
        String::new()
    };
    let (header, header_cut) = take_lines(&header, remaining);
    remaining -= header.len();
    truncated |= header_cut;

    let mut related_kept = Vec::new();
    for (_, section) in scored.iter().take(RELATED_SECTIONS) {
        if section.len() <= remaining {
            remaining -= section.len();
            related_kept.push(section.as_str());
        }
    }

    let mut shown = String::new();
    shown.push_str("[CABECERA");
    shown.push_str(if header_cut { ", TRUNCADA]\n" } else { "]\n" });
    shown.push_str(&header);
    shown.push_str("\n\n[INDICE DE ENCABEZADOS]\n");
    shown.push_str(&outline);
    shown.push_str("\n\n[SECCIONES MAS RECIENTES, COMPLETAS]\n");
    shown.push_str(&recent_kept.join("\n"));
    if !related_kept.is_empty() {
        shown.push_str("\n\n[SECCIONES ANTIGUAS RELACIONADAS CON LOS HALLAZGOS]\n");
        shown.push_str(&related_kept.join("\n"));
    }
    (shown, truncated)
}

/// Que ve el modelo de una nota de boveda y de su nota de proyecto.
///
/// Una nota normal cabe entera casi siempre, y entonces va entera. Si no cabe,
/// se hace como con los diarios pero **sin suponer orden cronologico**:
/// cabecera, indice de encabezados y las secciones que mas se parecen a `focus`.
/// En la nota de proyecto (`hub`) pesan ademas las dos ultimas secciones, que es
/// donde se va acumulando lo nuevo.
///
/// Lo privado no entra aunque venga en `bodies`: quien llama no tendria que
/// pasarlo, pero esta es la ultima puerta antes del modelo.
pub fn build_note_context(
    project: &DocProject,
    bodies: &BTreeMap<String, String>,
    focus: &str,
    budget_chars: usize,
) -> Vec<DocumentContext> {
    let words = words_of(focus);
    let mut docs: Vec<(String, DocRole, String, &String)> = bodies
        .iter()
        .filter_map(|(path, body)| {
            let doc = project.document(path)?;
            Some((normalize_rel(path), doc.role, doc.answers, body))
        })
        .collect();
    // La nota que se procesa primero; la de proyecto, al final y con menos sitio.
    docs.sort_by_key(|(_, role, _, _)| *role == DocRole::Hub);

    let hubs = docs.iter().filter(|(_, role, _, _)| *role == DocRole::Hub).count();
    let hub_cap = (budget_chars / 3).checked_div(hubs).unwrap_or(0);
    let mut remaining = budget_chars;
    let mut out = Vec::new();

    for (path, role, answers, body) in docs {
        let cap = if role == DocRole::Hub {
            hub_cap.min(remaining)
        } else {
            remaining.saturating_sub(hub_cap * hubs)
        };
        let (shown, truncated) = note_view(body, &words, cap, role == DocRole::Hub);
        remaining = remaining.saturating_sub(shown.len());
        out.push(DocumentContext {
            path,
            role,
            answers,
            shown,
            truncated,
        });
    }
    out
}

fn note_view(body: &str, words: &HashSet<String>, budget: usize, hub: bool) -> (String, bool) {
    const WHOLE: &str = "[NOTA COMPLETA]\n";
    if body.len() + WHOLE.len() <= budget {
        return (format!("{WHOLE}{body}"), false);
    }

    let lines: Vec<&str> = body.split('\n').collect();
    let found = headings(&lines);
    let sections: Vec<(usize, usize)> = found
        .iter()
        .enumerate()
        .filter(|(_, h)| h.level == 2)
        .map(|(i, h)| (h.line, section_end(&found, i, lines.len())))
        .collect();

    let header_end = sections.first().map(|s| s.0).unwrap_or(lines.len());
    let outline = found
        .iter()
        .filter(|h| h.level <= 3)
        .map(|h| h.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");

    let mut remaining = budget;
    let (outline, outline_cut) = take_lines(&outline, OUTLINE_MAX_CHARS.min(remaining / 4));
    remaining = remaining.saturating_sub(outline.len());
    let (header, header_cut) = take_lines(&lines[..header_end].join("\n"), remaining / 3);
    remaining = remaining.saturating_sub(header.len());

    let count = sections.len();
    let mut ranked: Vec<(usize, usize)> = sections
        .iter()
        .enumerate()
        .map(|(index, (start, end))| {
            let lower = lines[*start..*end].join("\n").to_lowercase();
            let mut score = words.iter().filter(|w| lower.contains(w.as_str())).count();
            if hub && index + 2 >= count {
                score += 1_000;
            }
            (score, index)
        })
        .collect();
    ranked.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));

    let mut kept: Vec<usize> = Vec::new();
    for (_, index) in ranked {
        let (start, end) = sections[index];
        let len = lines[start..end].join("\n").len() + 1;
        if len <= remaining {
            remaining -= len;
            kept.push(index);
        }
    }
    // Se enseñan en el orden del documento: saltar de una seccion a otra
    // anterior confunde mas que ayuda.
    kept.sort_unstable();

    let mut shown = String::new();
    shown.push_str(if header_cut { "[CABECERA, TRUNCADA]\n" } else { "[CABECERA]\n" });
    shown.push_str(&header);
    shown.push_str("\n\n[INDICE DE ENCABEZADOS]\n");
    shown.push_str(&outline);
    shown.push_str("\n\n[SECCIONES ELEGIDAS, COMPLETAS]\n");
    for index in &kept {
        let (start, end) = sections[*index];
        shown.push_str(&lines[start..end].join("\n"));
        shown.push('\n');
    }
    let truncated = header_cut || outline_cut || kept.len() < count;
    (shown, truncated)
}

/// Palabras que dicen de que va un texto, en minusculas.
pub(crate) fn words_of(text: &str) -> HashSet<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.chars().count() >= MIN_WORD_CHARS)
        .map(str::to_string)
        .collect()
}

/// Lineas enteras hasta llenar `max` caracteres. Nunca corta una linea a la
/// mitad: un ancla partida no se podria encontrar despues.
fn take_lines(text: &str, max: usize) -> (String, bool) {
    if text.len() <= max {
        return (text.to_string(), false);
    }
    let mut out = String::new();
    for line in text.split('\n') {
        if out.len() + line.len() + 1 > max {
            break;
        }
        out.push_str(line);
        out.push('\n');
    }
    (out, true)
}

fn finding_words(findings: &[Finding]) -> HashSet<String> {
    findings
        .iter()
        .flat_map(|f| {
            let text = format!(
                "{} {} {}",
                f.content.title,
                f.content.body,
                f.content.supersedes.as_deref().unwrap_or("")
            );
            text.to_lowercase()
                .split(|c: char| !c.is_alphanumeric())
                .filter(|w| w.chars().count() >= MIN_WORD_CHARS)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{DocTarget, ProjectKind};
    use crate::model::{FindingKind, FindingStatus, NewFinding};

    fn project() -> DocProject {
        DocProject {
            id: "ia".into(),
            name: "IA".into(),
            repo_root: "D:/x".into(),
            kind: ProjectKind::Docs,
            conventions: String::new(),
            documents: vec![
                DocTarget {
                    path: "docs/estado.md".into(),
                    role: DocRole::Journal,
                    answers: "diario".into(),
                    evidence_labels: true,
                },
                DocTarget {
                    path: "docs/plan.md".into(),
                    role: DocRole::Plan,
                    answers: "plan".into(),
                    evidence_labels: true,
                },
            ],
        }
    }

    fn finding(body: &str) -> Finding {
        Finding {
            id: "f-1".into(),
            batch_id: "b-1".into(),
            project: "ia".into(),
            from: None,
            created_at: "2026-09-15T00:00:00Z".into(),
            content_hash: String::new(),
            content: NewFinding {
                kind: FindingKind::Measurement,
                title: "titulo".into(),
                body: body.into(),
                evidence: vec![],
                supersedes: None,
                date: None,
                target_hint: None,
            },
            status: FindingStatus::Queued,
        }
    }

    /// Un diario sintetico del tamaño del de IA: 8.000 lineas.
    fn big_journal() -> String {
        let mut text = String::from("# Estado\n\n> Última actualización: **14 de septiembre de 2026**.\n> - resumen\n\n");
        for i in 0..400 {
            text.push_str(&format!("## {}-ago: seccion {i}\n\n", (i % 28) + 1));
            for j in 0..18 {
                let topic = if i == 250 { "helechos arboles" } else { "relleno" };
                text.push_str(&format!("linea {j} de la seccion {i} sobre {topic}\n"));
            }
        }
        text
    }

    #[test]
    fn a_huge_journal_fits_the_budget_and_keeps_what_matters() {
        let mut bodies = BTreeMap::new();
        bodies.insert("docs/estado.md".to_string(), big_journal());
        bodies.insert("docs/plan.md".to_string(), "# Plan\n\n## 1. Hallazgos\n".to_string());

        let budget = 60_000;
        let context = build_context(&project(), &bodies, &[finding("los helechos eran arboles")], budget);
        let journal = context.iter().find(|c| c.role == DocRole::Journal).unwrap();
        let plan = context.iter().find(|c| c.role == DocRole::Plan).unwrap();

        assert!(journal.shown.len() <= budget + 500, "{}", journal.shown.len());
        assert!(journal.shown.contains("> Última actualización: **14 de septiembre de 2026**"));
        assert!(journal.shown.contains("## 1-ago: seccion 0\n"));
        assert!(journal.shown.contains("linea 17 de la seccion 1 sobre"));
        // La seccion 10 no es reciente ni relacionada: solo puede venir del indice.
        assert!(journal.shown.contains("## 11-ago: seccion 10\n"), "el indice lista las antiguas");
        assert!(journal.shown.contains("linea 3 de la seccion 250 sobre helechos"));
        assert!(!journal.shown.contains("linea 3 de la seccion 100 sobre"));
        assert!(journal.truncated);
        assert_eq!(plan.shown, "# Plan\n\n## 1. Hallazgos\n");
    }

    fn vault() -> DocProject {
        DocProject {
            id: "notas".into(),
            name: "Notas".into(),
            repo_root: "D:/v".into(),
            kind: ProjectKind::Vault,
            conventions: String::new(),
            documents: vec![],
        }
    }

    #[test]
    fn a_short_note_goes_whole_and_a_private_note_never_goes() {
        let mut bodies = BTreeMap::new();
        bodies.insert("temas/drift.md".to_string(), "# Drift\n\ncorto\n".to_string());
        bodies.insert("privado/claves.md".to_string(), "# Claves\n\nalgo\n".to_string());

        let context = build_note_context(&vault(), &bodies, "drift", 10_000);
        assert_eq!(context.len(), 1);
        assert_eq!(context[0].shown, "[NOTA COMPLETA]\n# Drift\n\ncorto\n");
        assert!(!context[0].truncated);
    }

    #[test]
    fn a_long_note_keeps_what_matters_and_the_hub_keeps_its_latest_entries() {
        let mut note = String::from("# Reunion larga\n\nintro\n\n");
        for i in 0..40 {
            let topic = if i == 30 { "ortofoto deformada" } else { "relleno" };
            note.push_str(&format!("## Punto {i}\n\n"));
            for j in 0..15 {
                note.push_str(&format!("linea {j} del punto {i} sobre {topic}\n"));
            }
            note.push('\n');
        }
        let mut hub = String::from("# NexoDeck\n\n");
        for i in 0..30 {
            hub.push_str(&format!("## Entrada {i}\n\n"));
            for j in 0..15 {
                hub.push_str(&format!("linea {j} de la entrada {i}\n"));
            }
            hub.push('\n');
        }
        let mut bodies = BTreeMap::new();
        bodies.insert("reuniones/larga.md".to_string(), note);
        bodies.insert("proyectos/NexoDeck.md".to_string(), hub);

        let budget = 12_000;
        let context = build_note_context(&vault(), &bodies, "la ortofoto sale deformada", budget);
        assert_eq!(context[0].path, "reuniones/larga.md");
        assert_eq!(context[1].role, DocRole::Hub);
        let total: usize = context.iter().map(|c| c.shown.len()).sum();
        assert!(total <= budget + 500, "{total}");

        assert!(context[0].truncated);
        assert!(context[0].shown.contains("linea 14 del punto 30 sobre ortofoto"));
        assert!(context[0].shown.contains("## Punto 5\n"), "el indice lista todas");
        assert!(
            context[1].shown.contains("linea 14 de la entrada 29"),
            "{}",
            context[1].shown
        );
    }

    #[test]
    fn take_lines_never_cuts_a_line() {
        let (out, cut) = take_lines("uno\ndos\ntres", 9);
        assert_eq!(out, "uno\ndos\n");
        assert!(cut);
    }
}
