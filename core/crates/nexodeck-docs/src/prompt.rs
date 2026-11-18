//! Lo que se le dice al modelo.
//!
//! El prompt esta en español porque los documentos lo estan y el modelo imita el
//! idioma de sus instrucciones.

use std::fmt::Write;

use crate::config::DocProject;
use crate::context::DocumentContext;
use crate::dates::SpanishDate;
use crate::model::{EvidenceLabel, Finding, Proposal};

pub fn system_prompt() -> String {
    // Cuatro `#`: el texto trae `"##` (los encabezados de ejemplo), que cerraria
    // un `r#"..."#` a mitad.
    r####"Eres el redactor de la documentación de un proyecto de software. Recibes hallazgos (mediciones, decisiones, errores, cambios) y los documentos del proyecto, y propones cambios a esos documentos. Una persona revisa tu propuesta antes de que se escriba nada.

Responde SOLO con un objeto JSON, sin texto alrededor, con esta forma:
{
  "summary": "una o dos frases: qué cambias y por qué",
  "operations": [ ... ],
  "unresolved": [ { "finding_id": "...", "why": "..." } ]
}

Operaciones permitidas, y ninguna más:
- {"op":"insert_section_top","file":"<ruta>","heading":"## <día>-<mes>: <conclusión>","body":"<markdown>"}
  Solo en documentos con rol journal. Crea una sección nueva encima de la más reciente. El encabezado es una conclusión, no un tema: "## 15-sep: la detección es 3,5 veces más rápida", no "## 15-sep: rendimiento". El mes va en tres letras minúsculas: ene feb mar abr may jun jul ago sep oct nov dic.
- {"op":"set_last_updated","file":"<ruta>","date":"<día> de <mes> de <año>"}
  Cambia la fecha de la línea "> Última actualización: **...**". Úsala siempre que añadas una sección a un diario que tenga esa línea.
- {"op":"replace_exact","file":"<ruta>","old":"<texto literal>","new":"<texto nuevo>","reason":"<por qué>"}
  "old" tiene que aparecer exactamente UNA vez y copiarse literal, con sus saltos de línea, del documento que se te enseña. Sirve para corregir o borrar lo que un hallazgo deja sin efecto, o para actualizar el resumen de la cabecera.
- {"op":"append_under_heading","file":"<ruta>","heading":"<línea exacta del encabezado>","text":"<markdown>"}
  Añade al final de esa sección. Útil en planes, por ejemplo una casilla "- [ ] ..." en los próximos pasos.

Reglas:
1. Solo puedes tocar texto que aparece en los documentos que se te enseñan. Las marcas entre corchetes ([CABECERA], [INDICE DE ENCABEZADOS], [SECCIONES MAS RECIENTES, COMPLETAS]...) no forman parte del documento.
2. Escribe en español, con el tono y el formato de los documentos existentes. Nombres de código, rutas y comandos entre `comillas invertidas`.
3. Cada cifra lleva [M] si es medida o [S] si es supuesta, según la evidencia del hallazgo. Nunca marques [M] algo que el hallazgo trae como [S].
4. No inventes nada que no esté en los hallazgos. Si un hallazgo no encaja en ningún documento o le falta información, déjalo en "unresolved" con el motivo.
5. Si un hallazgo trae "deja sin efecto", corrige o borra ese texto con replace_exact: lo que deja de ser cierto se borra.
6. Varios hallazgos del mismo día y tema van en una sola sección, no en una por hallazgo.
7. Explica el porqué, no solo el qué: qué se rompía, qué se midió, qué se descartó."####
        .to_string()
}

pub fn user_prompt(
    project: &DocProject,
    today: SpanishDate,
    findings: &[Finding],
    context: &[DocumentContext],
    previous: Option<&Proposal>,
    note: Option<&str>,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "Proyecto: {} ({})", project.name, project.id);
    let _ = writeln!(out, "Hoy es {} ({}).", today.long(), today.short());
    if !project.conventions.trim().is_empty() {
        let _ = writeln!(out, "Convenciones del proyecto: {}", project.conventions.trim());
    }

    out.push_str("\nDocumentos del proyecto:\n");
    for doc in &project.documents {
        let _ = writeln!(out, "- {} (rol {}): {}", doc.path, doc.role.as_str(), doc.answers);
    }

    out.push_str("\nHALLAZGOS\n");
    for finding in findings {
        let content = &finding.content;
        let kind = serde_json::to_value(content.kind)
            .ok()
            .and_then(|v| v.as_str().map(str::to_string))
            .unwrap_or_default();
        let date = content.date.as_deref().unwrap_or("hoy");
        let from = finding.from.as_deref().unwrap_or("sin firma");
        let _ = writeln!(out, "\n[{}] tipo {kind} · fecha {date} · de {from}", finding.id);
        let _ = writeln!(out, "Título: {}", content.title.trim());
        let _ = writeln!(out, "{}", content.body.trim());
        out.push_str("Evidencia:\n");
        for evidence in &content.evidence {
            let label = match evidence.label {
                EvidenceLabel::M => "[M]",
                EvidenceLabel::S => "[S]",
            };
            match evidence.source.as_deref().filter(|s| !s.trim().is_empty()) {
                Some(source) => {
                    let _ = writeln!(out, "- {label} {} (fuente: {source})", evidence.text.trim());
                }
                None => {
                    let _ = writeln!(out, "- {label} {}", evidence.text.trim());
                }
            }
        }
        if let Some(supersedes) = content.supersedes.as_deref() {
            let _ = writeln!(out, "Deja sin efecto: \"{}\"", supersedes.trim());
        }
        if let Some(hint) = content.target_hint {
            let _ = writeln!(out, "Sugiere ir en el documento con rol {}", hint.as_str());
        }
    }

    if let Some(previous) = previous {
        let operations: Vec<_> = previous.operations.iter().map(|o| &o.operation).collect();
        let _ = writeln!(
            out,
            "\nPROPUESTA ANTERIOR (revisión {}), que el usuario pidió rehacer:\n{}",
            previous.revision,
            serde_json::to_string_pretty(&operations).unwrap_or_default()
        );
    }
    if let Some(note) = note.filter(|n| !n.trim().is_empty()) {
        let _ = writeln!(out, "\nNota del usuario para esta versión: {}", note.trim());
    }

    out.push_str("\nDOCUMENTOS\n");
    for doc in context {
        let truncated = if doc.truncated { ", recortado" } else { "" };
        let _ = writeln!(
            out,
            "\n===== INICIO {} (rol {}{truncated}) =====\n{}\n===== FIN {} =====",
            doc.path,
            doc.role.as_str(),
            doc.shown,
            doc.path
        );
    }
    out
}

pub fn repair_prompt(errors: &[String]) -> String {
    let mut out = String::from(
        "Tu respuesta no se pudo usar. Corrige estos errores y devuelve el objeto JSON completo otra vez, no solo las operaciones que fallaron:\n",
    );
    for error in errors {
        let _ = writeln!(out, "- {error}");
    }
    out
}
