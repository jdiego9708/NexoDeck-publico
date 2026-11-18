//! Las operaciones que puede proponer el modelo, y nada mas: cuatro para los
//! documentos del buzon, y dos (`add_section`, `set_frontmatter_key`) que solo
//! valen en las notas de una boveda.
//!
//! Todas son **por ancla, nunca por numero de linea**: si el usuario toca el
//! documento entre la propuesta y la aprobacion, una operacion por ancla sigue
//! aplicando donde tiene que aplicar, y una por linea escribiria en otro sitio
//! sin avisar.

use serde::{Deserialize, Serialize};

use crate::markdown::{headings, section_end};

/// Como empieza la linea de fecha de los diarios. Lleva la tilde porque es el
/// texto real de los documentos.
pub const LAST_UPDATED_MARK: &str = "> Última actualización: **";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum Operation {
    /// Una seccion nueva justo encima de la mas reciente del diario.
    InsertSectionTop {
        file: String,
        heading: String,
        body: String,
    },
    /// Cambia la fecha de la linea `> Última actualización: **...**`.
    SetLastUpdated { file: String, date: String },
    /// Reemplaza un texto que aparece **exactamente una vez**, como la
    /// herramienta Edit de Claude Code.
    ReplaceExact {
        file: String,
        old: String,
        new: String,
        #[serde(default)]
        reason: String,
    },
    /// Añade texto al final de la seccion cuyo encabezado es esa linea exacta.
    AppendUnderHeading {
        file: String,
        heading: String,
        text: String,
    },
    /// Una seccion nueva al final de una nota, **solo si ese encabezado no
    /// existe todavia** (`## Tareas`, `## Resumen`). Si ya existe, lo que toca es
    /// `AppendUnderHeading`: crearla otra vez partiria la nota en dos secciones
    /// con el mismo nombre, y ninguna ancla posterior sabria cual es cual.
    AddSection {
        file: String,
        heading: String,
        body: String,
    },
    /// Crea o cambia **una** clave del frontmatter YAML sin reescribir el resto
    /// del bloque. Si la nota no tiene frontmatter, lo crea.
    SetFrontmatterKey {
        file: String,
        key: String,
        value: String,
    },
}

impl Operation {
    pub fn file(&self) -> &str {
        match self {
            Operation::InsertSectionTop { file, .. }
            | Operation::SetLastUpdated { file, .. }
            | Operation::ReplaceExact { file, .. }
            | Operation::AppendUnderHeading { file, .. }
            | Operation::AddSection { file, .. }
            | Operation::SetFrontmatterKey { file, .. } => file,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Operation::InsertSectionTop { .. } => "insert_section_top",
            Operation::SetLastUpdated { .. } => "set_last_updated",
            Operation::ReplaceExact { .. } => "replace_exact",
            Operation::AppendUnderHeading { .. } => "append_under_heading",
            Operation::AddSection { .. } => "add_section",
            Operation::SetFrontmatterKey { .. } => "set_frontmatter_key",
        }
    }

    /// El texto del documento que el modelo tuvo que haber visto para escribir
    /// esto. `None` si la operacion no depende de ningun texto existente.
    pub fn anchor(&self) -> Option<&str> {
        match self {
            Operation::InsertSectionTop { .. } => None,
            Operation::SetLastUpdated { .. } => Some(LAST_UPDATED_MARK),
            Operation::ReplaceExact { old, .. } => Some(old),
            Operation::AppendUnderHeading { heading, .. } => Some(heading.trim()),
            // Las dos se posicionan solas (al final, dentro del frontmatter) y
            // fallan si lo que buscan no cuadra: no hay texto ajeno que copiar.
            Operation::AddSection { .. } | Operation::SetFrontmatterKey { .. } => None,
        }
    }

    /// Lo que la operacion mete en el documento.
    pub fn added_text(&self) -> String {
        match self {
            Operation::InsertSectionTop { heading, body, .. }
            | Operation::AddSection { heading, body, .. } => format!("{heading}\n{body}"),
            Operation::SetLastUpdated { date, .. } => date.clone(),
            Operation::ReplaceExact { new, .. } => new.clone(),
            Operation::AppendUnderHeading { text, .. } => text.clone(),
            Operation::SetFrontmatterKey { key, value, .. } => format!("{key}: {value}"),
        }
    }
}

/// Aplica una operacion sobre el texto (con `\n`). El error es una frase para
/// devolverle al modelo, asi que dice que corregir.
pub fn apply_operation(body: &str, op: &Operation) -> Result<String, String> {
    match op {
        Operation::InsertSectionTop { heading, body: text, .. } => {
            insert_section_top(body, heading, text)
        }
        Operation::SetLastUpdated { date, .. } => set_last_updated(body, date),
        Operation::ReplaceExact { old, new, .. } => replace_exact(body, old, new),
        Operation::AppendUnderHeading { heading, text, .. } => {
            append_under_heading(body, heading, text)
        }
        Operation::AddSection { heading, body: text, .. } => add_section(body, heading, text),
        Operation::SetFrontmatterKey { key, value, .. } => set_frontmatter_key(body, key, value),
    }
}

fn add_section(body: &str, heading: &str, text: &str) -> Result<String, String> {
    let heading = heading.trim();
    if !heading.starts_with("## ") || heading.contains('\n') || heading.len() <= 3 {
        return Err(format!(
            "el encabezado tiene que ser una sola linea que empiece por \"## \": {heading:?}"
        ));
    }
    let mut lines: Vec<&str> = body.split('\n').collect();
    if headings(&lines).iter().any(|h| h.text == heading) {
        return Err(format!(
            "ya existe el encabezado {heading:?}; para escribir debajo usa append_under_heading"
        ));
    }

    while lines.last().is_some_and(|l| l.trim().is_empty()) {
        lines.pop();
    }
    if !lines.is_empty() {
        lines.push("");
    }
    lines.push(heading);
    lines.push("");
    let text = text.trim_matches('\n').trim_end();
    if !text.is_empty() {
        lines.extend(text.split('\n'));
        lines.push("");
    }
    Ok(lines.join("\n"))
}

fn set_frontmatter_key(body: &str, key: &str, value: &str) -> Result<String, String> {
    let key = key.trim();
    if key.is_empty()
        || !key
            .chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
    {
        return Err(format!(
            "la clave {key:?} solo puede llevar letras, cifras, '_' y '-'"
        ));
    }
    let value = value.trim();
    if value.contains('\n') {
        return Err("el valor tiene que ser una sola linea; una lista va como [a, b]".into());
    }
    let entry = if value.is_empty() {
        format!("{key}:")
    } else {
        format!("{key}: {value}")
    };

    let mut lines: Vec<String> = body.split('\n').map(str::to_string).collect();
    let opens = lines.first().is_some_and(|l| l.trim_end() == "---");
    if !opens {
        lines.splice(0..0, ["---".to_string(), entry, "---".to_string()]);
        return Ok(lines.join("\n"));
    }
    let Some(close) = lines
        .iter()
        .skip(1)
        .position(|l| l.trim_end() == "---")
        .map(|i| i + 1)
    else {
        return Err("el frontmatter abre con '---' pero no cierra; no se toca".into());
    };

    let prefix = format!("{key}:");
    let hits: Vec<usize> = (1..close)
        .filter(|&i| lines[i].starts_with(&prefix))
        .collect();
    match hits.as_slice() {
        [] => lines.insert(close, entry),
        [start] => {
            // Una lista en bloque (`tags:` y debajo `  - a`) es parte de la
            // misma clave: se reemplaza entera, o quedarian elementos huerfanos.
            let start = *start;
            let mut end = start + 1;
            while end < close
                && (lines[end].starts_with(' ')
                    || lines[end].starts_with('\t')
                    || lines[end].starts_with("- "))
            {
                end += 1;
            }
            lines.splice(start..end, [entry]);
        }
        many => {
            return Err(format!(
                "la clave {key:?} aparece {} veces en el frontmatter; no se sabe cual cambiar",
                many.len()
            ))
        }
    }
    Ok(lines.join("\n"))
}

fn insert_section_top(body: &str, heading: &str, text: &str) -> Result<String, String> {
    let heading = heading.trim();
    if !heading.starts_with("## ") || heading.contains('\n') {
        return Err(format!(
            "el encabezado tiene que ser una sola linea que empiece por \"## \": {heading:?}"
        ));
    }
    let text = text.trim_matches('\n').trim_end();

    let mut block: Vec<&str> = vec![heading, ""];
    if !text.is_empty() {
        block.extend(text.split('\n'));
        block.push("");
    }

    let mut lines: Vec<&str> = body.split('\n').collect();
    let first_section = headings(&lines)
        .into_iter()
        .find(|h| h.level == 2)
        .map(|h| h.line);

    match first_section {
        Some(at) => {
            lines.splice(at..at, block);
        }
        None => {
            while lines.last().is_some_and(|l| l.trim().is_empty()) {
                lines.pop();
            }
            if !lines.is_empty() {
                lines.push("");
            }
            lines.extend(block);
            if lines.last() != Some(&"") {
                lines.push("");
            }
        }
    }
    Ok(lines.join("\n"))
}

fn set_last_updated(body: &str, date: &str) -> Result<String, String> {
    let date = date.trim();
    if date.is_empty() || date.contains('\n') || date.contains("**") {
        return Err("la fecha tiene que ser una sola linea, sin '**'".into());
    }

    let mut lines: Vec<String> = body.split('\n').map(str::to_string).collect();
    let hits: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| l.trim_start().starts_with(LAST_UPDATED_MARK))
        .map(|(i, _)| i)
        .collect();

    let index = match hits.as_slice() {
        [index] => *index,
        [] => {
            return Err(format!(
                "no hay ninguna linea que empiece por {LAST_UPDATED_MARK:?}"
            ))
        }
        many => {
            return Err(format!(
                "hay {} lineas que empiezan por {LAST_UPDATED_MARK:?}; no se sabe cual cambiar",
                many.len()
            ))
        }
    };

    let line = &lines[index];
    let start = line.find(LAST_UPDATED_MARK).unwrap_or(0) + LAST_UPDATED_MARK.len();
    let Some(len) = line[start..].find("**") else {
        return Err("la linea de actualizacion no cierra el '**' de la fecha".into());
    };
    lines[index] = format!("{}{}{}", &line[..start], date, &line[start + len..]);
    Ok(lines.join("\n"))
}

fn replace_exact(body: &str, old: &str, new: &str) -> Result<String, String> {
    if old.is_empty() {
        return Err("'old' esta vacio".into());
    }
    if old == new {
        return Err("'old' y 'new' son iguales".into());
    }
    match body.matches(old).count() {
        1 => Ok(body.replacen(old, new, 1)),
        0 => Err("el texto de 'old' no aparece en el documento; copialo literal, con sus espacios y saltos".into()),
        n => Err(format!(
            "el texto de 'old' aparece {n} veces; amplialo con lineas de alrededor hasta que sea unico"
        )),
    }
}

fn append_under_heading(body: &str, heading: &str, text: &str) -> Result<String, String> {
    let heading = heading.trim();
    let text = text.trim_matches('\n').trim_end();
    if text.is_empty() {
        return Err("'text' esta vacio".into());
    }

    let mut lines: Vec<&str> = body.split('\n').collect();
    let found = headings(&lines);
    let matches: Vec<usize> = found
        .iter()
        .enumerate()
        .filter(|(_, h)| h.text == heading)
        .map(|(i, _)| i)
        .collect();

    let index = match matches.as_slice() {
        [index] => *index,
        [] => return Err(format!("no existe el encabezado {heading:?}; copia la linea exacta")),
        many => {
            return Err(format!(
                "el encabezado {heading:?} aparece {} veces; usa replace_exact",
                many.len()
            ))
        }
    };

    let start = found[index].line;
    let end = section_end(&found, index, lines.len());

    // Se inserta despues del ultimo contenido de la seccion, no despues de las
    // lineas en blanco que la separan de la siguiente.
    let mut at = end;
    while at > start + 1 && lines[at - 1].trim().is_empty() {
        at -= 1;
    }

    let mut insert: Vec<&str> = Vec::new();
    if at == start + 1 {
        insert.push("");
    }
    insert.extend(text.split('\n'));
    if lines.get(at).is_some_and(|l| !l.trim().is_empty()) {
        insert.push("");
    }
    lines.splice(at..at, insert);
    Ok(lines.join("\n"))
}

/// Antes y despues de un cambio, con unas lineas de contexto. Se calcula en
/// Rust y la UI solo lo pinta.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Preview {
    /// Primera linea que cambia, empezando en 1.
    pub line: usize,
    pub before: String,
    pub after: String,
    pub removed_lines: usize,
    pub added_lines: usize,
}

const PREVIEW_CONTEXT: usize = 4;

pub fn preview(old: &str, new: &str) -> Preview {
    let a: Vec<&str> = old.split('\n').collect();
    let b: Vec<&str> = new.split('\n').collect();

    let prefix = a.iter().zip(&b).take_while(|(x, y)| x == y).count();
    let max_suffix = a.len().min(b.len()) - prefix;
    let suffix = a
        .iter()
        .rev()
        .zip(b.iter().rev())
        .take(max_suffix)
        .take_while(|(x, y)| x == y)
        .count();

    let from = prefix.saturating_sub(PREVIEW_CONTEXT);
    let a_to = (a.len() - suffix + PREVIEW_CONTEXT).min(a.len());
    let b_to = (b.len() - suffix + PREVIEW_CONTEXT).min(b.len());

    Preview {
        line: prefix + 1,
        before: a[from..a_to].join("\n"),
        after: b[from..b_to].join("\n"),
        removed_lines: a.len() - prefix - suffix,
        added_lines: b.len() - prefix - suffix,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const JOURNAL: &str = "# Estado\n\n> Última actualización: **14 de septiembre de 2026**. Entrada.\n> - resumen\n\n## 14-sep: algo\n\ntexto\n\n## 10-sep: otro\n\nmas\n";

    fn insert(body: &str) -> Operation {
        Operation::InsertSectionTop {
            file: "d.md".into(),
            heading: "## 15-sep: nuevo".into(),
            body: body.into(),
        }
    }

    #[test]
    fn insert_section_top_goes_above_the_newest_section() {
        let out = apply_operation(JOURNAL, &insert("hallazgo\n")).unwrap();
        let expected_head = "> - resumen\n\n## 15-sep: nuevo\n\nhallazgo\n\n## 14-sep: algo";
        assert!(out.contains(expected_head), "{out}");
        assert!(out.ends_with("mas\n"));
    }

    #[test]
    fn insert_section_top_appends_when_there_is_no_section_yet() {
        let out = apply_operation("# T\n\nintro\n\n\n", &insert("x")).unwrap();
        assert_eq!(out, "# T\n\nintro\n\n## 15-sep: nuevo\n\nx\n");
    }

    #[test]
    fn insert_section_top_needs_a_level_two_heading() {
        let op = Operation::InsertSectionTop {
            file: "d.md".into(),
            heading: "### 15-sep: nuevo".into(),
            body: "x".into(),
        };
        assert!(apply_operation(JOURNAL, &op).is_err());
    }

    #[test]
    fn set_last_updated_changes_only_the_bold_date() {
        let op = Operation::SetLastUpdated {
            file: "d.md".into(),
            date: "15 de septiembre de 2026".into(),
        };
        let out = apply_operation(JOURNAL, &op).unwrap();
        assert!(out.contains("> Última actualización: **15 de septiembre de 2026**. Entrada."));
    }

    #[test]
    fn set_last_updated_needs_exactly_one_line() {
        let op = Operation::SetLastUpdated {
            file: "d.md".into(),
            date: "hoy".into(),
        };
        assert!(apply_operation("# T\n", &op).unwrap_err().contains("ninguna"));
        let twice = format!("{JOURNAL}\n> Última actualización: **ayer**\n");
        assert!(apply_operation(&twice, &op).unwrap_err().contains("2 lineas"));
    }

    #[test]
    fn replace_exact_needs_a_single_occurrence() {
        let op = |old: &str| Operation::ReplaceExact {
            file: "d.md".into(),
            old: old.into(),
            new: "cambiado".into(),
            reason: String::new(),
        };
        assert!(apply_operation(JOURNAL, &op("texto")).unwrap().contains("cambiado"));
        assert!(apply_operation(JOURNAL, &op("no esta")).unwrap_err().contains("no aparece"));
        assert!(apply_operation(JOURNAL, &op("sep")).unwrap_err().contains("veces"));
    }

    #[test]
    fn append_under_heading_lands_at_the_end_of_its_section() {
        let op = Operation::AppendUnderHeading {
            file: "d.md".into(),
            heading: "## 14-sep: algo".into(),
            text: "- [ ] nuevo".into(),
        };
        let out = apply_operation(JOURNAL, &op).unwrap();
        assert!(out.contains("texto\n- [ ] nuevo\n\n## 10-sep: otro"), "{out}");
    }

    #[test]
    fn append_under_heading_in_an_empty_section_keeps_blank_lines() {
        let op = Operation::AppendUnderHeading {
            file: "d.md".into(),
            heading: "## A".into(),
            text: "x".into(),
        };
        let out = apply_operation("## A\n## B\n", &op).unwrap();
        assert_eq!(out, "## A\n\nx\n\n## B\n");
    }

    #[test]
    fn append_under_heading_at_the_end_of_the_document() {
        let op = Operation::AppendUnderHeading {
            file: "d.md".into(),
            heading: "## 10-sep: otro".into(),
            text: "fin".into(),
        };
        let out = apply_operation(JOURNAL, &op).unwrap();
        assert!(out.ends_with("mas\nfin\n"), "{out}");
    }

    #[test]
    fn preview_shows_the_change_with_context() {
        let out = apply_operation(JOURNAL, &insert("hallazgo")).unwrap();
        let p = preview(JOURNAL, &out);
        assert_eq!(p.removed_lines, 0);
        assert_eq!(p.added_lines, 4);
        assert!(p.after.contains("## 15-sep: nuevo"));
        assert!(p.before.contains("## 14-sep: algo"));
    }

    #[test]
    fn add_section_goes_at_the_end_only_when_the_heading_is_new() {
        let op = |heading: &str| Operation::AddSection {
            file: "n.md".into(),
            heading: heading.into(),
            body: "- [ ] llamar a soporte".into(),
        };
        let note = "# Nota\n\nidea suelta\n\n## Contexto\n\nalgo\n\n\n";
        let out = apply_operation(note, &op("## Tareas")).unwrap();
        assert_eq!(
            out,
            "# Nota\n\nidea suelta\n\n## Contexto\n\nalgo\n\n## Tareas\n\n- [ ] llamar a soporte\n"
        );
        assert!(apply_operation(note, &op("## Contexto"))
            .unwrap_err()
            .contains("append_under_heading"));
        assert!(apply_operation(note, &op("### Tareas")).is_err());
    }

    #[test]
    fn set_frontmatter_key_creates_the_block_when_there_is_none() {
        let op = Operation::SetFrontmatterKey {
            file: "n.md".into(),
            key: "status".into(),
            value: "procesada".into(),
        };
        let out = apply_operation("# Nota\n\ntexto\n", &op).unwrap();
        assert_eq!(out, "---\nstatus: procesada\n---\n# Nota\n\ntexto\n");
    }

    #[test]
    fn set_frontmatter_key_replaces_one_key_and_leaves_the_rest() {
        let note = "---\ntitle: Reunion\ntags:\n  - trabajo\n  - ia\nproject: NexoDeck\n---\n# Reunion\n";
        let tags = Operation::SetFrontmatterKey {
            file: "n.md".into(),
            key: "tags".into(),
            value: "[trabajo, ia, odm]".into(),
        };
        let out = apply_operation(note, &tags).unwrap();
        assert_eq!(
            out,
            "---\ntitle: Reunion\ntags: [trabajo, ia, odm]\nproject: NexoDeck\n---\n# Reunion\n"
        );

        let new_key = Operation::SetFrontmatterKey {
            file: "n.md".into(),
            key: "status".into(),
            value: "procesada".into(),
        };
        let out = apply_operation(note, &new_key).unwrap();
        assert!(out.contains("project: NexoDeck\nstatus: procesada\n---\n"), "{out}");
    }

    #[test]
    fn set_frontmatter_key_refuses_what_it_cannot_do_safely() {
        let op = |key: &str, value: &str| Operation::SetFrontmatterKey {
            file: "n.md".into(),
            key: key.into(),
            value: value.into(),
        };
        assert!(apply_operation("---\ntitle: x\n# sin cerrar\n", &op("status", "a"))
            .unwrap_err()
            .contains("no cierra"));
        assert!(apply_operation("# T\n", &op("mal clave", "a")).is_err());
        assert!(apply_operation("# T\n", &op("status", "dos\nlineas")).is_err());
    }

    #[test]
    fn operations_round_trip_through_json_with_an_op_tag() {
        let json = r###"{"op":"replace_exact","file":"a.md","old":"x","new":"y"}"###;
        let op: Operation = serde_json::from_str(json).unwrap();
        assert_eq!(op.name(), "replace_exact");
        assert_eq!(op.anchor(), Some("x"));
    }
}
