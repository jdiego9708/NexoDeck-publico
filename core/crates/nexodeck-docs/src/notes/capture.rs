//! Guardar en la boveda algo que llega de una sesion de Claude Code.
//!
//! Es la excepcion **acotada** a la regla de que las notas no se editan desde
//! una sesion: aca no hay ningun modelo reinterpretando nada, es el usuario
//! diciendo "esto que me acabas de dar, guardalo". Por eso se escribe directo y
//! no pasa por el buzon. Lo que sigue valiendo es todo lo demas: procesar una
//! nota, cruzarla y proponer cambios sigue siendo cosa del buzon y de su
//! aprobacion.
//!
//! **El formato lo arregla NexoDeck, no quien llama.** Una herramienta MCP
//! recibe lo que le manden, y si el markdown dependiera de la buena voluntad del
//! que llama, antes o despues entraria texto con el frontmatter inventado, todo
//! envuelto en una cerca de codigo o con tres encabezados de nivel uno. Lo de
//! aqui es tosco a proposito: normaliza lo que se rompe en la practica y no
//! intenta ser un formateador de Markdown.
//!
//! Lo que **nunca** se toca es el interior de un bloque de codigo: ahi una linea
//! en blanco de mas o un espacio al final pueden ser parte de lo que se guarda.

use std::collections::BTreeMap;

use jiff::Timestamp;

use crate::dates::SpanishDate;

/// Donde aterriza lo que llega sin ruta. Decision del usuario: nota nueva por
/// envio, en su propia bandeja, en vez de acumularse en el diario.
pub const CAPTURE_DIR: &str = "inbox/";

/// Lo que hay que escribir, ya decidido y limpio.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapturedNote {
    /// Relativa a la boveda, con `/` y `.md`.
    pub path: String,
    pub title: String,
    /// El markdown saneado, **sin** frontmatter ni el encabezado del titulo:
    /// los pone quien escribe.
    pub body: String,
}

/// Prepara lo que manda una sesion: sanea el markdown, decide el titulo y la
/// ruta.
///
/// `path` explicito manda sobre todo lo demas; sin el, se deriva del titulo y
/// del dia. `title` explicito manda sobre el que se pueda deducir del texto.
pub fn prepare_capture(
    raw_text: &str,
    title: Option<&str>,
    path: Option<&str>,
    now: Timestamp,
) -> Result<CapturedNote, String> {
    // **El orden importa, y costo un fallo en el e2e.** Una sesion manda a
    // menudo TODO envuelto en una cerca de markdown y con su frontmatter dentro.
    // Quitando el frontmatter primero no hay nada que quitar --la primera linea
    // es la cerca-- y el `ai: false` acaba en la nota del usuario.
    let normalized = raw_text.replace("\r\n", "\n").replace('\r', "\n");
    let (front, rest) = strip_frontmatter(&unwrap_code_fence(&normalized));
    let body = sanitize_markdown(&rest);
    if body.trim().is_empty() {
        return Err("el texto esta vacio: no hay nada que guardar".to_string());
    }

    // El titulo sale, por este orden, de lo que pidio quien llama, del `# `
    // que encabece el texto, del frontmatter que traia, o de la primera linea.
    let (title, body) = match title.map(str::trim).filter(|t| !t.is_empty()) {
        Some(explicit) => (explicit.to_string(), demote_extra_h1(&body)),
        None => match take_leading_h1(&body) {
            Some((heading, rest)) => (heading, demote_extra_h1(&rest)),
            None => {
                let fallback = front
                    .get("title")
                    .map(|t| t.trim().to_string())
                    .filter(|t| !t.is_empty())
                    .or_else(|| first_sentence(&body))
                    .unwrap_or_else(|| "Nota de sesion".to_string());
                (fallback, demote_extra_h1(&body))
            }
        },
    };

    let path = match path.map(str::trim).filter(|p| !p.is_empty()) {
        Some(explicit) => normalize_note_path(explicit),
        None => format!(
            "{CAPTURE_DIR}{}-{}.md",
            SpanishDate::from_timestamp(now).iso(),
            slug(&title)
        ),
    };

    Ok(CapturedNote { path, title, body })
}

/// El cuerpo de una nota nueva, con el frontmatter que pone NexoDeck.
///
/// `source` es de donde vino (la sesion que lo mando), y se guarda porque dentro
/// de un mes la pregunta va a ser "¿esto lo escribi yo o me lo dio una sesion?".
pub fn capture_document(note: &CapturedNote, source: Option<&str>, now: Timestamp) -> String {
    let date = SpanishDate::from_timestamp(now).iso();
    let mut out = format!("---\ndate: {date}\nsource: claude-code\n");
    if let Some(source) = source.map(str::trim).filter(|s| !s.is_empty()) {
        // En una linea y sin comillas: el parser del proyecto es de clave/valor,
        // no un YAML completo (ver `notes/parse.rs`).
        out.push_str(&format!("session: {}\n", single_line(source)));
    }
    out.push_str("---\n");
    out.push_str(&format!("# {}\n\n", note.title));
    out.push_str(&note.body);
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

/// Lo que se añade al final de una nota que ya existe.
///
/// Se anexa en vez de pisar, y con la hora en el encabezado: dos envios del
/// mismo dia a la misma nota tienen que quedar distinguibles.
pub fn capture_section(note: &CapturedNote, now: Timestamp, previous: &str) -> String {
    let time = now
        .to_zoned(jiff::tz::TimeZone::system())
        .strftime("%H:%M")
        .to_string();
    let mut out = String::from(previous);
    while out.ends_with('\n') {
        out.pop();
    }
    if !out.is_empty() {
        out.push_str("\n\n");
    }
    out.push_str(&format!("## {} · {}\n\n", note.title, time));
    out.push_str(&note.body);
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

/// Normaliza el markdown que llega de fuera.
///
/// Fuera de los bloques de codigo: quita los espacios del final de linea, deja
/// como mucho una linea en blanco seguida, y separa los encabezados de lo que
/// tienen encima y debajo. Dentro de un bloque de codigo no toca nada.
pub fn sanitize_markdown(raw: &str) -> String {
    let text = unwrap_code_fence(&raw.replace("\r\n", "\n").replace('\r', "\n"));

    let mut out: Vec<String> = Vec::new();
    let mut in_code = false;
    let mut last_was_heading = false;

    for line in text.split('\n') {
        let trimmed_start = line.trim_start();
        if trimmed_start.starts_with("```") || trimmed_start.starts_with("~~~") {
            if !in_code && !out.is_empty() && !out.last().is_some_and(|l| l.is_empty()) {
                out.push(String::new());
            }
            in_code = !in_code;
            out.push(line.trim_end().to_string());
            last_was_heading = false;
            continue;
        }
        if in_code {
            out.push(line.to_string());
            continue;
        }

        let line = line.trim_end();
        if line.is_empty() {
            // Ni al principio ni dos seguidas.
            if !out.is_empty() && !out.last().is_some_and(|l| l.is_empty()) {
                out.push(String::new());
            }
            last_was_heading = false;
            continue;
        }
        if is_heading(line) {
            if !out.is_empty() && !out.last().is_some_and(|l| l.is_empty()) {
                out.push(String::new());
            }
            out.push(line.to_string());
            last_was_heading = true;
            continue;
        }
        if last_was_heading {
            out.push(String::new());
            last_was_heading = false;
        }
        out.push(line.to_string());
    }

    while out.last().is_some_and(|l| l.is_empty()) {
        out.pop();
    }
    let mut body = out.join("\n");
    if !body.is_empty() {
        body.push('\n');
    }
    body
}

/// Un texto entero envuelto en una sola cerca de codigo es markdown citado, no
/// codigo: pasa constantemente cuando una sesion "manda el resumen".
///
/// Solo se desenvuelve si la cerca abre en la primera linea y cierra en la
/// ultima, y no hay ninguna otra: con mas cercas, el contenido es codigo de
/// verdad y desenvolverlo lo romperia.
fn unwrap_code_fence(text: &str) -> String {
    let trimmed = text.trim();
    let lines: Vec<&str> = trimmed.split('\n').collect();
    if lines.len() < 2 {
        return text.to_string();
    }
    let first = lines[0].trim();
    let last = lines[lines.len() - 1].trim();
    let opens = first.starts_with("```");
    let info = first.trim_start_matches('`').trim().to_lowercase();
    let closes = last == "```";
    let fences = lines
        .iter()
        .filter(|l| l.trim_start().starts_with("```"))
        .count();
    if opens && closes && fences == 2 && (info.is_empty() || info == "markdown" || info == "md") {
        return lines[1..lines.len() - 1].join("\n");
    }
    text.to_string()
}

/// Quita el frontmatter que traiga el texto y devuelve sus claves.
///
/// **No se conserva.** El de la nota lo pone NexoDeck: si se respetara el que
/// llega, una sesion podria marcar la nota `ai: false`, ponerle etiquetas o
/// falsear su fecha sin que el usuario lo pidiera.
fn strip_frontmatter(raw: &str) -> (BTreeMap<String, String>, String) {
    let text = raw.trim_start_matches('\u{feff}');
    let normalized = text.replace("\r\n", "\n");
    let mut keys = BTreeMap::new();
    let trimmed = normalized.trim_start();
    if !trimmed.starts_with("---\n") {
        return (keys, normalized);
    }
    let rest = &trimmed[4..];
    let Some(end) = rest.find("\n---") else {
        return (keys, normalized);
    };
    for line in rest[..end].split('\n') {
        if let Some((key, value)) = line.split_once(':') {
            keys.insert(
                key.trim().to_lowercase(),
                value.trim().trim_matches('"').to_string(),
            );
        }
    }
    let after = &rest[end + 4..];
    let after = after.strip_prefix('-').unwrap_or(after);
    let after = after.strip_prefix('-').unwrap_or(after);
    (keys, after.trim_start_matches('\n').to_string())
}

/// El `# Titulo` que encabeza el texto, si lo hay, y el resto sin el.
fn take_leading_h1(body: &str) -> Option<(String, String)> {
    let mut lines = body.split('\n');
    let first = lines.next()?.trim();
    let heading = first.strip_prefix("# ")?.trim();
    if heading.is_empty() {
        return None;
    }
    let rest: String = lines.collect::<Vec<_>>().join("\n");
    Some((
        heading.to_string(),
        rest.trim_start_matches('\n').to_string(),
    ))
}

/// Una nota tiene **un** titulo. Los `#` que queden sueltos en el cuerpo bajan a
/// `##` para que el esquema de la nota no salga con varias raices.
fn demote_extra_h1(body: &str) -> String {
    let mut out = Vec::new();
    let mut in_code = false;
    for line in body.split('\n') {
        let start = line.trim_start();
        if start.starts_with("```") || start.starts_with("~~~") {
            in_code = !in_code;
            out.push(line.to_string());
            continue;
        }
        if !in_code && start.starts_with("# ") {
            out.push(format!("#{}", start));
            continue;
        }
        out.push(line.to_string());
    }
    out.join("\n")
}

/// La primera linea con texto, sin marcas, para cuando no hay titulo por ningun
/// lado. Recortada: un titulo es una linea, no un parrafo.
fn first_sentence(body: &str) -> Option<String> {
    let line = body
        .split('\n')
        .map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with("```"))?;
    let clean = line
        .trim_start_matches(['#', '-', '*', '>', ' '])
        .replace(['`', '*', '_'], "");
    let clean = clean.trim();
    if clean.is_empty() {
        return None;
    }
    Some(truncate_words(clean, 70))
}

fn truncate_words(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let cut: String = text.chars().take(max).collect();
    match cut.rsplit_once(' ') {
        Some((head, _)) if head.chars().count() > max / 2 => format!("{}…", head.trim_end()),
        _ => format!("{}…", cut.trim_end()),
    }
}

/// `Resumen del paso 4` -> `resumen-del-paso-4`.
///
/// Sin tildes ni ñ en el nombre del fichero: la boveda se sincroniza con el
/// movil y se abre en Obsidian, y un nombre con acentos viaja distinto segun el
/// sistema de ficheros.
pub fn slug(title: &str) -> String {
    let mut out = String::new();
    for ch in title.trim().to_lowercase().chars() {
        let mapped = match ch {
            'á' | 'à' | 'ä' | 'â' => 'a',
            'é' | 'è' | 'ë' | 'ê' => 'e',
            'í' | 'ì' | 'ï' | 'î' => 'i',
            'ó' | 'ò' | 'ö' | 'ô' => 'o',
            'ú' | 'ù' | 'ü' | 'û' => 'u',
            'ñ' => 'n',
            'ç' => 'c',
            c if c.is_ascii_alphanumeric() => c,
            _ => '-',
        };
        if mapped == '-' {
            if !out.ends_with('-') && !out.is_empty() {
                out.push('-');
            }
        } else {
            out.push(mapped);
        }
    }
    let trimmed = out.trim_matches('-');
    let short: String = trimmed.chars().take(60).collect();
    let short = short.trim_matches('-').to_string();
    if short.is_empty() {
        "nota".to_string()
    } else {
        short
    }
}

/// Acepta `inbox/algo`, `inbox\algo.md` o `algo` y devuelve `inbox/algo.md`.
fn normalize_note_path(path: &str) -> String {
    let path = path.trim().replace('\\', "/");
    let path = path.trim_start_matches("./").trim_start_matches('/');
    let path = if path.to_lowercase().ends_with(".md") {
        path.to_string()
    } else {
        format!("{path}.md")
    };
    if path.contains('/') {
        path
    } else {
        format!("{CAPTURE_DIR}{path}")
    }
}

fn is_heading(line: &str) -> bool {
    let hashes = line.chars().take_while(|c| *c == '#').count();
    (1..=6).contains(&hashes) && line.chars().nth(hashes) == Some(' ')
}

fn single_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now() -> Timestamp {
        "2026-09-16T12:30:00Z".parse().unwrap()
    }

    #[test]
    fn unwraps_a_whole_answer_quoted_as_a_code_fence() {
        let raw = "```markdown\n# Resumen\n\nUna cosa.\n```";
        let note = prepare_capture(raw, None, None, now()).unwrap();
        assert_eq!(note.title, "Resumen");
        assert_eq!(note.body, "Una cosa.\n");
    }

    /// Con mas de una cerca el contenido es codigo de verdad: desenvolverlo lo
    /// romperia.
    #[test]
    fn keeps_real_code_blocks_untouched() {
        let raw = "Esto hace:\n\n```rust\nfn main() {\n\n    println!(\"hola\");  \n}\n```\n";
        let note = prepare_capture(raw, Some("Ejemplo"), None, now()).unwrap();
        assert!(note.body.contains("    println!(\"hola\");  \n"), "{}", note.body);
        assert!(note.body.contains("fn main() {\n\n"), "{}", note.body);
    }

    #[test]
    fn drops_any_frontmatter_that_came_in_the_text() {
        let raw = "---\nai: false\ntags: [secreto]\n---\n# Algo\n\nCuerpo.\n";
        let note = prepare_capture(raw, None, None, now()).unwrap();
        assert!(!note.body.contains("ai: false"));
        let document = capture_document(&note, Some("NexoDeck en main"), now());
        assert!(!document.contains("ai: false"), "{document}");
        assert!(document.contains("source: claude-code"));
        assert!(document.contains("session: NexoDeck en main"));
    }

    /// El caso de verdad, y el que fallo primero: envuelto en una cerca **y**
    /// con el frontmatter dentro. Hay que desenvolver antes de mirarlo.
    #[test]
    fn drops_frontmatter_that_came_inside_a_code_fence() {
        let raw = "```markdown\n---\nai: false\n---\n# Resumen del paso 4\n\nLa cola sale al reconectar.\n```";
        let note = prepare_capture(raw, None, None, now()).unwrap();
        assert_eq!(note.title, "Resumen del paso 4");
        assert_eq!(note.body, "La cola sale al reconectar.\n");
        assert!(!capture_document(&note, None, now()).contains("ai: false"));
    }

    #[test]
    fn normalizes_spacing_and_extra_titles() {
        let raw = "# Uno\ntexto pegado\n\n\n\n# Dos\nmas texto   \n";
        let note = prepare_capture(raw, None, None, now()).unwrap();
        assert_eq!(note.title, "Uno");
        assert_eq!(note.body, "texto pegado\n\n## Dos\n\nmas texto\n");
    }

    #[test]
    fn derives_the_path_from_the_day_and_the_title() {
        let raw = "Un resumen del paso 4.";
        let note = prepare_capture(raw, Some("Resumen del paso 4 — ñandú"), None, now()).unwrap();
        assert_eq!(note.path, "inbox/2026-09-16-resumen-del-paso-4-nandu.md");
    }

    #[test]
    fn an_explicit_path_wins_and_gets_completed() {
        let raw = "texto";
        assert_eq!(
            prepare_capture(raw, Some("T"), Some("temas/malla"), now())
                .unwrap()
                .path,
            "temas/malla.md"
        );
        assert_eq!(
            prepare_capture(raw, Some("T"), Some("suelta"), now())
                .unwrap()
                .path,
            "inbox/suelta.md"
        );
    }

    #[test]
    fn without_any_title_it_uses_the_first_line() {
        let raw = "- La cadena de ODM tarda tres horas y media\n- y algo mas";
        let note = prepare_capture(raw, None, None, now()).unwrap();
        assert_eq!(note.title, "La cadena de ODM tarda tres horas y media");
    }

    #[test]
    fn empty_text_is_refused() {
        assert!(prepare_capture("   \n\n", None, None, now()).is_err());
    }

    /// Anexar nunca pisa: lo de antes se conserva entero y lo nuevo entra como
    /// seccion con su hora.
    #[test]
    fn appending_keeps_what_was_there() {
        let note = prepare_capture("lo nuevo", Some("Segundo envio"), None, now()).unwrap();
        let out = capture_section(&note, now(), "# Nota\n\nlo de antes\n");
        assert!(out.starts_with("# Nota\n\nlo de antes\n\n"));
        assert!(out.contains("## Segundo envio · "));
        assert!(out.ends_with("lo nuevo\n"));
    }
}
