//! Los cinco agentes del digest de una nota: que se le dice a cada uno y como se
//! lee lo que contesta.
//!
//! Ninguno llama a herramientas. Rust hace las busquedas y cada agente recibe
//! **candidatos con id**; solo puede citar esos ids, y lo que cite fuera de la
//! lista se descarta con [`keep_known_ids`]. Asi "lo citado existe" no depende de
//! que el modelo obedezca: se comprueba.
//!
//! Los prompts van en `r####"..."####` por lo mismo que el del buzon: traen `"##`
//! (encabezados de ejemplo), que cerraria un `r#"..."#` a mitad.

use std::collections::HashSet;
use std::fmt::Write;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Instant;

use nexodeck_ai::openai::types::ChatMessage;
use serde_json::Value;

use crate::backend::{CompletionOptions, ModelBackend};
use crate::context::DocumentContext;
use crate::dates::SpanishDate;
use crate::generate::GenerateError;
use crate::model::Proposal;
use crate::notes::digest::{AgentStep, CandidateRef};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Agent {
    Reader,
    Memory,
    Code,
    Critic,
    Synthesizer,
}

impl Agent {
    pub fn name(&self) -> &'static str {
        match self {
            Agent::Reader => "reader",
            Agent::Memory => "memory",
            Agent::Code => "code",
            Agent::Critic => "critic",
            Agent::Synthesizer => "synthesizer",
        }
    }

    /// Los cuatro primeros contestan en pocas lineas y tienen que ser fieles a
    /// lo que leen; el que redacta necesita sitio y algo mas de soltura.
    pub fn options(&self) -> CompletionOptions {
        match self {
            Agent::Synthesizer => CompletionOptions {
                temperature: 0.3,
                max_tokens: 8_192,
            },
            _ => CompletionOptions {
                temperature: 0.2,
                max_tokens: 2_048,
            },
        }
    }

    pub fn system_prompt(&self) -> &'static str {
        match self {
            Agent::Reader => READER_SYSTEM,
            Agent::Memory => MEMORY_SYSTEM,
            Agent::Code => CODE_SYSTEM,
            Agent::Critic => CRITIC_SYSTEM,
            Agent::Synthesizer => SYNTHESIZER_SYSTEM,
        }
    }
}

const READER_SYSTEM: &str = r####"Eres el LECTOR de un asistente de notas de trabajo. Recibes UNA nota de la bóveda del usuario (y a veces la nota viva de su proyecto) y la desmenuzas para que otros agentes la relacionen con notas anteriores, hallazgos documentados y commits. No escribes en la nota.

Responde SOLO con un objeto JSON, sin texto alrededor, con esta forma:
{
  "summary": "dos o tres frases: de qué trata la nota y qué concluye",
  "entities": {"projects": [], "repos": [], "people": [], "topics": []},
  "decisions": ["decisiones que la nota toma o da por tomadas"],
  "task_candidates": ["cosas por hacer que la nota menciona y que todavía no son una tarea '- [ ]'"],
  "open_questions": ["dudas que la nota deja abiertas"],
  "queries": {
    "notes": ["búsquedas de 2 a 6 palabras para encontrar notas anteriores sobre lo mismo"],
    "findings": ["búsquedas para encontrar hallazgos ya documentados"],
    "commits": ["búsquedas con las palabras que saldrían en un mensaje de commit relacionado"]
  }
}

Reglas:
1. No inventes nada que no esté en la nota. Una lista sin contenido va vacía.
2. Como mucho 4 búsquedas por tipo, con las palabras concretas de la nota (módulos, tandas, clientes, errores), no generalidades.
3. Escribe en español. Nombres de código, rutas y comandos, tal cual."####;

const MEMORY_SYSTEM: &str = r####"Eres la MEMORIA de un asistente de notas de trabajo. Recibes lo que el lector sacó de una nota nueva y una lista de CANDIDATOS: fragmentos de notas anteriores y hallazgos ya documentados, cada uno con su id entre corchetes. Decides cuáles tienen que ver de verdad con la nota nueva.

Responde SOLO con un objeto JSON, sin texto alrededor:
{
  "related": [{"id": "<id de un candidato>", "why": "qué tiene que ver, en una frase"}],
  "already_discussed": [{"id": "<id>", "quote": "frase literal del candidato que ya trataba esto", "date": "AAAA-MM-DD o vacío"}],
  "pending": [{"id": "<id>", "task": "lo que quedó pendiente", "since": "AAAA-MM-DD o vacío"}]
}

Reglas:
1. Solo puedes citar ids que están en la lista de CANDIDATOS. Un id que no esté ahí se descarta.
2. Mejor pocas relaciones ciertas que muchas dudosas. Si ninguno encaja, listas vacías.
3. "already_discussed" es para temas que la nota nueva repite o retoma. "pending" es para tareas o dudas de antes que la nota nueva no cierra.
4. Escribe en español."####;

const CODE_SYSTEM: &str = r####"Eres el agente de CÓDIGO de un asistente de notas de trabajo. Recibes lo que el lector sacó de una nota y una lista de CANDIDATOS: commits de los repositorios del usuario, cada uno con su id entre corchetes. Decides qué commits tienen que ver con la nota y qué de lo que plantea la nota ya está hecho.

Responde SOLO con un objeto JSON, sin texto alrededor:
{
  "related_commits": [{"id": "<id de un commit>", "why": "qué tiene que ver"}],
  "implemented": [{"id": "<id del commit que lo hace>", "what": "lo que la nota plantea y ese commit ya hizo"}],
  "not_implemented": [{"what": "lo que la nota plantea y no aparece en ningún commit"}]
}

Reglas:
1. Solo puedes citar ids que están en la lista de CANDIDATOS.
2. Lee el asunto y el cuerpo: el cuerpo explica el porqué. No des algo por hecho solo porque comparte una palabra.
3. Si ningún commit encaja, listas vacías. Escribe en español."####;

const CRITIC_SYSTEM: &str = r####"Eres el CRÍTICO de un asistente de notas de trabajo. Recibes una nota, lo que sacó el lector, lo que la memoria relacionó con notas anteriores y lo que el agente de código relacionó con commits. Buscas lo que falta.

Responde SOLO con un objeto JSON, sin texto alrededor:
{
  "extra_questions": ["preguntas que el usuario debería contestarse y la nota no plantea"],
  "contradictions": [{"id": "<id de un candidato>", "quote": "lo que decía antes", "why": "en qué choca con la nota"}],
  "gaps": ["información que falta para que la nota sirva dentro de un mes"],
  "requery": {"notes": [], "findings": [], "commits": []}
}

Reglas:
1. Solo puedes citar ids que aparecen en lo que recibes.
2. Pide "requery" solo si algo importante de la nota no se buscó; si no, deja las tres listas vacías. Como mucho 3 búsquedas en total.
3. Preguntas concretas, no genéricas ("¿qué pasa con la tanda R si también falla la malla 3D?", no "¿hay riesgos?"). Como mucho 5.
4. Escribe en español."####;

const SYNTHESIZER_SYSTEM: &str = r####"Eres el REDACTOR de un asistente de notas de trabajo. Recibes una nota del usuario, su nota de proyecto si la hay, y el trabajo de otros agentes: resumen, relaciones con notas anteriores y con commits, y preguntas. Propones cambios que COMPLETAN la nota. Una persona revisa tu propuesta antes de que se escriba nada.

Responde SOLO con un objeto JSON, sin texto alrededor:
{
  "summary": "una o dos frases: qué añades y por qué",
  "operations": [ ... ]
}

Operaciones permitidas, y ninguna más:
- {"op":"add_section","file":"<ruta>","heading":"## <título>","body":"<markdown>"}
  Crea una sección al final. Solo si ese encabezado NO existe ya en ese fichero.
- {"op":"append_under_heading","file":"<ruta>","heading":"<línea exacta del encabezado>","text":"<markdown>"}
  Añade al final de una sección que ya existe.
- {"op":"set_frontmatter_key","file":"<ruta>","key":"<clave>","value":"<valor en una sola línea>"}
  Crea o cambia una clave del frontmatter. Una lista va como [a, b].
- {"op":"replace_exact","file":"<ruta>","old":"<texto literal>","new":"<texto nuevo>","reason":"<por qué>"}
  Solo para corregir un dato que un candidato demuestra falso. "old" aparece exactamente UNA vez y se copia literal.

Qué proponer en la nota:
1. "## Resumen" con 2 a 4 frases, si la nota no lo tiene.
2. "## Relacionado": una línea por relación, con un enlace de ENLACES PERMITIDOS o una referencia de COMMITS PERMITIDOS, y el porqué. Solo lo que otro agente ya relacionó.
3. "## Tareas": las tareas nuevas como "- [ ] ...". No repitas las que ya están en la nota.
4. "## Preguntas abiertas": las preguntas del crítico y las dudas del lector que sigan abiertas.
5. En el frontmatter, "status" con el valor "procesada".
En la nota de proyecto, si se te enseña: una sección "## <día>-<mes>: <conclusión>" con lo que esta nota aporta al proyecto y el enlace a la nota.

Reglas:
1. NUNCA reescribas ni borres lo que escribió el usuario: añade. replace_exact solo para corregir un dato que un candidato contradice, con el motivo.
2. Solo puedes tocar los ficheros que se te enseñan, y solo texto que aparece en ellos. Las marcas entre corchetes ([NOTA COMPLETA], [CABECERA]...) no son parte del fichero.
3. No inventes nada que no esté en la nota o en el trabajo de los agentes. Ningún enlace ni commit fuera de las listas permitidas.
4. Escribe en español, con el tono de la nota. Nombres de código y rutas entre `comillas invertidas`.
5. Una sección que no tendría contenido no se crea."####;

/// Llama a un agente que contesta un objeto JSON. Si lo que devuelve no se puede
/// leer, se le pide **una** vez mas; un error del modelo sube tal cual, porque
/// lo decide quien llama (reintentar mas tarde, otro modelo). Siempre devuelve
/// el paso para la traza, haya ido bien o mal.
pub(crate) async fn ask(
    agent: Agent,
    label: &str,
    backend: &ModelBackend,
    user: String,
    cancel: Arc<AtomicBool>,
) -> (Result<Value, GenerateError>, AgentStep) {
    let started = Instant::now();
    let mut messages = vec![
        ChatMessage::system(agent.system_prompt().to_string()),
        ChatMessage::user(user),
    ];
    let mut result: Result<Value, GenerateError> =
        Err(GenerateError::Invalid(vec!["el agente no contesto".into()]));

    for attempt in 0..2 {
        match backend
            .complete_with(messages.clone(), agent.options(), cancel.clone())
            .await
        {
            Err(error) => {
                result = Err(GenerateError::Model(error));
                break;
            }
            Ok(text) => match parse_object(&text) {
                Ok(value) => {
                    result = Ok(value);
                    break;
                }
                Err(error) => {
                    if attempt == 0 {
                        messages.push(ChatMessage::assistant_text(text));
                        messages.push(ChatMessage::user(format!(
                            "Tu respuesta no se pudo leer: {error}. Devuelve solo el objeto JSON pedido, completo."
                        )));
                    }
                    result = Err(GenerateError::Invalid(vec![error]));
                }
            },
        }
    }

    let step = AgentStep {
        agent: label.to_string(),
        ok: result.is_ok(),
        millis: started.elapsed().as_millis() as u64,
        output: result.as_ref().ok().cloned(),
        detail: result.as_ref().err().map(|e| e.to_string()),
    };
    (result, step)
}

/// Tolera lo mismo que el buzon: un bloque de codigo alrededor o una frase antes.
pub(crate) fn parse_object(text: &str) -> Result<Value, String> {
    let text = text.trim();
    let (Some(start), Some(end)) = (text.find('{'), text.rfind('}')) else {
        return Err("la respuesta no trae ningun objeto JSON".to_string());
    };
    if end < start {
        return Err("la respuesta no trae ningun objeto JSON completo".to_string());
    }
    let value: Value = serde_json::from_str(&text[start..=end])
        .map_err(|e| format!("no es JSON valido: {e}"))?;
    if value.is_object() {
        Ok(value)
    } else {
        Err("no es un objeto JSON".to_string())
    }
}

/// Quita de cualquier lista toda entrada con un `"id"` que no este en
/// `allowed`, y anota los descartados. Una entrada sin `id` se queda (lo que
/// "no esta implementado" no cita nada).
pub(crate) fn keep_known_ids(value: &mut Value, allowed: &HashSet<String>, discarded: &mut Vec<String>) {
    match value {
        Value::Array(items) => {
            items.retain(|item| match item.get("id").and_then(Value::as_str) {
                Some(id) if !allowed.contains(id) => {
                    if !discarded.iter().any(|d| d == id) {
                        discarded.push(id.to_string());
                    }
                    false
                }
                _ => true,
            });
            for item in items {
                keep_known_ids(item, allowed, discarded);
            }
        }
        Value::Object(map) => {
            for child in map.values_mut() {
                keep_known_ids(child, allowed, discarded);
            }
        }
        _ => {}
    }
}

/// Todos los ids que cita una salida, en cualquier profundidad.
pub(crate) fn cited_ids(value: &Value) -> Vec<String> {
    let mut out = Vec::new();
    collect_ids(value, &mut out);
    out
}

fn collect_ids(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::Array(items) => items.iter().for_each(|i| collect_ids(i, out)),
        Value::Object(map) => {
            if let Some(id) = map.get("id").and_then(Value::as_str) {
                if !out.iter().any(|o| o == id) {
                    out.push(id.to_string());
                }
            }
            map.values().for_each(|v| collect_ids(v, out));
        }
        _ => {}
    }
}

/// Las busquedas que pide un agente (`queries` del lector, `requery` del
/// critico).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct Queries {
    pub notes: Vec<String>,
    pub findings: Vec<String>,
    pub commits: Vec<String>,
}

impl Queries {
    pub fn from_value(value: &Value, key: &str, max_each: usize) -> Self {
        let block = value.get(key);
        let list = |name: &str| -> Vec<String> {
            block
                .and_then(|b| b.get(name))
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .take(max_each)
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default()
        };
        Queries {
            notes: list("notes"),
            findings: list("findings"),
            commits: list("commits"),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.notes.is_empty() && self.findings.is_empty() && self.commits.is_empty()
    }
}

pub(crate) fn reader_prompt(project: &str, today: SpanishDate, contexts: &[DocumentContext]) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "Bóveda: {project}");
    let _ = writeln!(out, "Hoy es {} ({}).", today.long(), today.short());
    documents(&mut out, contexts);
    out
}

pub(crate) fn memory_prompt(reader: &Value, candidates: &[CandidateRef]) -> String {
    let mut out = String::new();
    json_block(&mut out, "LO QUE EL LECTOR SACÓ DE LA NOTA", &without_queries(reader));
    candidates_block(&mut out, candidates);
    out
}

pub(crate) fn code_prompt(reader: &Value, candidates: &[CandidateRef]) -> String {
    memory_prompt(reader, candidates)
}

pub(crate) fn critic_prompt(
    contexts: &[DocumentContext],
    reader: &Value,
    memory: &Value,
    code: &Value,
    candidates: &[CandidateRef],
) -> String {
    let mut out = String::new();
    documents(&mut out, contexts);
    json_block(&mut out, "LECTOR", &without_queries(reader));
    json_block(&mut out, "MEMORIA", memory);
    json_block(&mut out, "CÓDIGO", code);
    candidates_block(&mut out, candidates);
    out
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn synthesizer_prompt(
    today: SpanishDate,
    contexts: &[DocumentContext],
    reader: &Value,
    memory: &Value,
    code: &Value,
    critic: &Value,
    links: &[String],
    commits: &[String],
    previous: Option<&Proposal>,
    user_note: Option<&str>,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "Hoy es {} ({}).", today.long(), today.short());
    json_block(&mut out, "LECTOR", &without_queries(reader));
    json_block(&mut out, "MEMORIA", memory);
    json_block(&mut out, "CÓDIGO", code);
    json_block(&mut out, "CRÍTICO", critic);

    out.push_str("\nENLACES PERMITIDOS\n");
    if links.is_empty() {
        out.push_str("(ninguno)\n");
    }
    for link in links {
        let _ = writeln!(out, "- {link}");
    }
    out.push_str("\nCOMMITS PERMITIDOS\n");
    if commits.is_empty() {
        out.push_str("(ninguno)\n");
    }
    for commit in commits {
        let _ = writeln!(out, "- `{commit}`");
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
    if let Some(note) = user_note.filter(|n| !n.trim().is_empty()) {
        let _ = writeln!(out, "\nNota del usuario para esta versión: {}", note.trim());
    }
    documents(&mut out, contexts);
    out
}

fn documents(out: &mut String, contexts: &[DocumentContext]) {
    out.push_str("\nFICHEROS\n");
    for doc in contexts {
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
}

fn candidates_block(out: &mut String, candidates: &[CandidateRef]) {
    out.push_str("\nCANDIDATOS\n");
    if candidates.is_empty() {
        out.push_str("(ninguno)\n");
    }
    for c in candidates {
        let date = c.date.as_deref().map(|d| format!(", {d}")).unwrap_or_default();
        let _ = writeln!(out, "[{}] ({}{date}) {}\n    {}", c.id, c.kind, c.title, c.snippet);
    }
}

fn json_block(out: &mut String, title: &str, value: &Value) {
    let _ = writeln!(
        out,
        "\n{title}\n{}",
        serde_json::to_string_pretty(value).unwrap_or_default()
    );
}

fn without_queries(reader: &Value) -> Value {
    let mut copy = reader.clone();
    if let Some(map) = copy.as_object_mut() {
        map.remove("queries");
    }
    copy
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn ids_that_were_not_candidates_are_dropped_and_reported() {
        let mut output = json!({
            "related": [
                {"id": "n:temas/drift.md#0", "why": "si"},
                {"id": "n:inventada.md#3", "why": "no existe"}
            ],
            "not_implemented": [{"what": "sin id, se queda"}],
            "nested": {"pending": [{"id": "c:X@1234567", "task": "t"}]}
        });
        let allowed: HashSet<String> = ["n:temas/drift.md#0".to_string()].into();
        let mut discarded = Vec::new();
        keep_known_ids(&mut output, &allowed, &mut discarded);

        assert_eq!(output["related"].as_array().unwrap().len(), 1);
        assert_eq!(output["not_implemented"].as_array().unwrap().len(), 1);
        assert!(output["nested"]["pending"].as_array().unwrap().is_empty());
        discarded.sort();
        assert_eq!(discarded, vec!["c:X@1234567", "n:inventada.md#3"]);
        assert_eq!(cited_ids(&output), vec!["n:temas/drift.md#0"]);
    }

    #[test]
    fn queries_are_trimmed_and_capped() {
        let reader = json!({"queries": {"notes": ["  malla 3D ", "", "a", "b", "c", "d"], "commits": ["tanda R"]}});
        let q = Queries::from_value(&reader, "queries", 4);
        assert_eq!(q.notes, vec!["malla 3D", "a", "b", "c"]);
        assert!(q.findings.is_empty());
        assert_eq!(q.commits, vec!["tanda R"]);
        assert!(Queries::from_value(&json!({}), "requery", 3).is_empty());
    }

    #[test]
    fn parse_object_accepts_fences_and_refuses_arrays() {
        assert!(parse_object("```json\n{\"a\":1}\n```").is_ok());
        assert!(parse_object("[1,2]").is_err());
        assert!(parse_object("nada").is_err());
    }

    #[test]
    fn every_agent_has_its_own_prompt_and_the_synthesizer_gets_more_room() {
        let prompts: HashSet<&str> = [Agent::Reader, Agent::Memory, Agent::Code, Agent::Critic, Agent::Synthesizer]
            .iter()
            .map(|a| a.system_prompt())
            .collect();
        assert_eq!(prompts.len(), 5);
        assert!(Agent::Synthesizer.options().max_tokens > Agent::Reader.options().max_tokens);
    }
}
