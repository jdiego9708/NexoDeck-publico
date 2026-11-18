//! Lo minimo de Markdown que hace falta: leer un documento sin estropearlo y
//! encontrar sus encabezados.

/// Un documento leido de disco, listo para operar sobre su texto.
///
/// El texto se trabaja **siempre con `\n`**, que es lo que ve el modelo, y se
/// vuelve a escribir con los finales de linea y el BOM que traia. Convertir un
/// fichero CRLF a LF entero por añadir una seccion convertiria un cambio de diez
/// lineas en un diff de ocho mil.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Document {
    pub bom: bool,
    pub crlf: bool,
    pub body: String,
}

const BOM: [u8; 3] = [0xEF, 0xBB, 0xBF];

impl Document {
    /// Falla si no es UTF-8 valido, y es a proposito: un documento con bytes
    /// raros **no se toca**. Leerlo con perdida y reescribirlo lo corromperia.
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        let (bom, rest) = match bytes.strip_prefix(&BOM) {
            Some(rest) => (true, rest),
            None => (false, bytes),
        };
        let text = std::str::from_utf8(rest).map_err(|e| {
            format!(
                "no es UTF-8 valido (byte {}), asi que no se toca",
                e.valid_up_to()
            )
        })?;

        // Solo se trata como CRLF si TODAS las lineas lo son. Con finales
        // mezclados, normalizar y volver a escribir cambiaria lineas que nadie
        // pidio tocar; se deja el texto tal cual.
        let newlines = text.matches('\n').count();
        let crlf = newlines > 0 && text.matches("\r\n").count() == newlines;
        let body = if crlf {
            text.replace("\r\n", "\n")
        } else {
            text.to_string()
        };
        Ok(Document { bom, crlf, body })
    }

    /// Los bytes a escribir para un texto nuevo, con el formato original.
    pub fn render(&self, body: &str) -> Vec<u8> {
        let text = if self.crlf {
            body.replace('\n', "\r\n")
        } else {
            body.to_string()
        };
        let mut out = Vec::with_capacity(text.len() + BOM.len());
        if self.bom {
            out.extend_from_slice(&BOM);
        }
        out.extend_from_slice(text.as_bytes());
        out
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Heading {
    pub level: usize,
    /// Indice de linea, empezando en 0.
    pub line: usize,
    /// La linea entera, sin espacios al final: `## 14-sep: algo`.
    pub text: String,
}

/// Encabezados ATX (`#` a `######`), saltando los bloques de codigo: un
/// `## ` dentro de un ``` no es un encabezado, y los diarios traen muchos
/// fragmentos de logs y de scripts.
pub fn headings(lines: &[&str]) -> Vec<Heading> {
    let mut out = Vec::new();
    let mut fence: Option<&'static str> = None;

    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim_start();
        if let Some(marker) = fence {
            if trimmed.starts_with(marker) {
                fence = None;
            }
            continue;
        }
        if trimmed.starts_with("```") {
            fence = Some("```");
            continue;
        }
        if trimmed.starts_with("~~~") {
            fence = Some("~~~");
            continue;
        }
        // Cuatro espacios de sangria es un bloque de codigo, no un encabezado.
        if line.len() - trimmed.len() >= 4 {
            continue;
        }
        let level = trimmed.bytes().take_while(|b| *b == b'#').count();
        if (1..=6).contains(&level) && trimmed[level..].starts_with(' ') {
            out.push(Heading {
                level,
                line: index,
                text: trimmed.trim_end().to_string(),
            });
        }
    }
    out
}

/// Donde termina la seccion del encabezado `index`: en el siguiente de nivel
/// igual o superior, o al final del documento.
pub(crate) fn section_end(headings: &[Heading], index: usize, total_lines: usize) -> usize {
    let level = headings[index].level;
    headings[index + 1..]
        .iter()
        .find(|h| h.level <= level)
        .map(|h| h.line)
        .unwrap_or(total_lines)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_crlf_and_bom_on_the_way_back() {
        let raw = b"\xEF\xBB\xBF# T\r\n\r\nuno\r\n";
        let doc = Document::parse(raw).unwrap();
        assert!(doc.bom && doc.crlf);
        assert_eq!(doc.body, "# T\n\nuno\n");
        assert_eq!(doc.render(&doc.body), raw.to_vec());
    }

    #[test]
    fn mixed_line_endings_are_left_alone() {
        let raw = b"a\r\nb\nc\r\n";
        let doc = Document::parse(raw).unwrap();
        assert!(!doc.crlf);
        assert_eq!(doc.render(&doc.body), raw.to_vec());
    }

    #[test]
    fn invalid_utf8_is_refused() {
        assert!(Document::parse(b"hola \xFF mundo").is_err());
    }

    #[test]
    fn headings_inside_code_fences_do_not_count() {
        let text = "# T\n## uno\n```\n## no\n```\n    ## tampoco\n### dos\n##sin espacio";
        let lines: Vec<&str> = text.split('\n').collect();
        let found: Vec<String> = headings(&lines).into_iter().map(|h| h.text).collect();
        assert_eq!(found, vec!["# T", "## uno", "### dos"]);
    }
}
