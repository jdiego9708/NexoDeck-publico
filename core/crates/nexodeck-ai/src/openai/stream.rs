//! Parser de SSE y reensamblado de la respuesta en streaming.
//!
//! Dos piezas separadas a proposito, porque fallan por motivos distintos:
//!
//! - [`SseDecoder`] convierte bytes en payloads `data:`. Los chunks de la red
//!   **no** respetan limites de linea: un evento puede llegar partido al medio
//!   de una palabra, o pueden llegar cinco eventos en un solo chunk.
//! - [`CompletionAssembler`] convierte payloads en un [`ChatCompletion`]. Lo
//!   dificil no es el texto sino los tool calls: `id` y `name` llegan una vez y
//!   los `arguments` gotean partidos, a veces **a la mitad de un escape JSON**.
//!   Se acumulan por `index`, nunca por posicion en el array.
//!
//! Las dos son puras y estan testeadas sobre fixtures que replican lo que
//! manda llama-server de verdad, incluyendo los casos que rompen: dos tool
//! calls en un mismo turno, `arguments` fragmentado, bloques `<think>` y el
//! `[DONE]` final.

use crate::openai::types::{ChatChunk, ChatCompletion, FunctionCall, ToolCall};

/// Marcador de fin de stream de la API.
const DONE_MARKER: &str = "[DONE]";

/// Convierte un flujo de bytes en payloads de eventos SSE.
#[derive(Debug, Default)]
pub struct SseDecoder {
    buffer: String,
}

impl SseDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    /// Consume un chunk y devuelve los payloads completos que quedaron
    /// disponibles. Lo incompleto queda en el buffer para el proximo chunk.
    pub fn push(&mut self, chunk: &str) -> Vec<String> {
        self.buffer.push_str(chunk);
        let mut payloads = Vec::new();

        // Se procesa por lineas terminadas: una linea sin `\n` todavia puede
        // estar a medio llegar.
        while let Some(position) = self.buffer.find('\n') {
            let line: String = self.buffer.drain(..=position).collect();
            let line = line.trim_end_matches(['\n', '\r']);

            if line.is_empty() || line.starts_with(':') {
                continue;
            }
            if let Some(payload) = line.strip_prefix("data:") {
                payloads.push(payload.trim().to_string());
            }
        }

        payloads
    }

    pub fn is_done(payload: &str) -> bool {
        payload == DONE_MARKER
    }
}

/// Acumula los chunks de un turno hasta tener la respuesta completa.
#[derive(Debug, Default)]
pub struct CompletionAssembler {
    content: String,
    reasoning: String,
    /// `(index, id, name, arguments)`. Se guarda el `index` explicito porque el
    /// modelo puede empezar el tool call 1 antes de terminar el 0.
    tool_calls: Vec<PartialToolCall>,
    finish_reason: Option<String>,
    /// Estado del filtro de `<think>`: algunos modelos meten el razonamiento
    /// dentro del `content` en vez de en `reasoning_content`, y mostrarlo en el
    /// chat lo llena de monologo interno.
    inside_think: bool,
}

#[derive(Debug, Default, Clone)]
struct PartialToolCall {
    index: usize,
    id: String,
    name: String,
    arguments: String,
}

/// Lo que hay que emitir hacia la UI a medida que llega el stream.
#[derive(Debug, Clone, PartialEq)]
pub enum StreamDelta {
    /// Texto visible para el usuario, ya sin razonamiento.
    Content(String),
    /// Razonamiento del modelo. No se muestra como respuesta; sirve para poder
    /// indicar "pensando..." sin volcar el monologo.
    Reasoning(String),
    /// El modelo empezo a pedir una herramienta. Se emite en cuanto se conoce
    /// el nombre, antes de tener los argumentos, para que la UI pueda decir
    /// "revisando el disco..." sin esperar.
    ToolCallStarted { name: String },
}

impl CompletionAssembler {
    pub fn new() -> Self {
        Self::default()
    }

    /// Procesa un payload de SSE. Devuelve lo que hay que mostrar ahora.
    pub fn push_payload(&mut self, payload: &str) -> Vec<StreamDelta> {
        if SseDecoder::is_done(payload) {
            return Vec::new();
        }

        // Un chunk mal formado no puede tumbar la conversacion entera: se
        // ignora y se sigue. Pasa con algunos backends que intercalan
        // keep-alives.
        let Ok(chunk) = serde_json::from_str::<ChatChunk>(payload) else {
            log::debug!("chunk SSE ignorado por no parsear: {payload}");
            return Vec::new();
        };

        let mut deltas = Vec::new();

        for choice in chunk.choices {
            if let Some(reason) = choice.finish_reason {
                self.finish_reason = Some(reason);
            }

            if let Some(reasoning) = choice.delta.reasoning_content {
                if !reasoning.is_empty() {
                    self.reasoning.push_str(&reasoning);
                    deltas.push(StreamDelta::Reasoning(reasoning));
                }
            }

            if let Some(content) = choice.delta.content {
                let (visible, reasoning) = self.split_think(&content);
                if !reasoning.is_empty() {
                    self.reasoning.push_str(&reasoning);
                    deltas.push(StreamDelta::Reasoning(reasoning));
                }
                if !visible.is_empty() {
                    self.content.push_str(&visible);
                    deltas.push(StreamDelta::Content(visible));
                }
            }

            for delta in choice.delta.tool_calls {
                let index = delta.index;
                let entry = match self.tool_calls.iter_mut().find(|tc| tc.index == index) {
                    Some(entry) => entry,
                    None => {
                        self.tool_calls.push(PartialToolCall {
                            index,
                            ..Default::default()
                        });
                        self.tool_calls.last_mut().expect("recien insertado")
                    }
                };

                if let Some(id) = delta.id {
                    entry.id = id;
                }
                if let Some(function) = delta.function {
                    if let Some(name) = function.name {
                        if !name.is_empty() && entry.name != name {
                            entry.name = name.clone();
                            deltas.push(StreamDelta::ToolCallStarted { name });
                        }
                    }
                    if let Some(arguments) = function.arguments {
                        entry.arguments.push_str(&arguments);
                    }
                }
            }
        }

        deltas
    }

    /// Separa el contenido visible del que va dentro de `<think>...</think>`.
    ///
    /// El estado (`inside_think`) es de la instancia y no del chunk: las
    /// etiquetas llegan partidas entre chunks todo el tiempo.
    fn split_think(&mut self, text: &str) -> (String, String) {
        const OPEN: &str = "<think>";
        const CLOSE: &str = "</think>";

        let mut visible = String::new();
        let mut reasoning = String::new();
        let mut rest = text;

        loop {
            if self.inside_think {
                match rest.find(CLOSE) {
                    Some(position) => {
                        reasoning.push_str(&rest[..position]);
                        rest = &rest[position + CLOSE.len()..];
                        self.inside_think = false;
                    }
                    None => {
                        reasoning.push_str(rest);
                        break;
                    }
                }
            } else {
                match rest.find(OPEN) {
                    Some(position) => {
                        visible.push_str(&rest[..position]);
                        rest = &rest[position + OPEN.len()..];
                        self.inside_think = true;
                    }
                    None => {
                        visible.push_str(rest);
                        break;
                    }
                }
            }

            if rest.is_empty() {
                break;
            }
        }

        (visible, reasoning)
    }

    /// Cierra el turno. Ordena los tool calls por `index` y descarta los que
    /// quedaron sin nombre (fragmentos de un stream cortado).
    pub fn finish(mut self) -> ChatCompletion {
        self.tool_calls.sort_by_key(|tc| tc.index);

        let tool_calls = self
            .tool_calls
            .into_iter()
            .filter(|tc| !tc.name.is_empty())
            .enumerate()
            .map(|(position, tc)| ToolCall {
                // Algunos backends no mandan `id` en streaming. Se sintetiza
                // uno estable: el protocolo exige que el mensaje `tool` de
                // respuesta lo referencie, y sin id el modelo pierde el hilo.
                id: if tc.id.is_empty() {
                    format!("call_{position}")
                } else {
                    tc.id
                },
                kind: "function".to_string(),
                function: FunctionCall {
                    name: tc.name,
                    arguments: if tc.arguments.is_empty() {
                        "{}".to_string()
                    } else {
                        tc.arguments
                    },
                },
            })
            .collect();

        ChatCompletion {
            content: self.content,
            reasoning: self.reasoning,
            tool_calls,
            finish_reason: self.finish_reason,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assemble(payloads: &[&str]) -> ChatCompletion {
        let mut assembler = CompletionAssembler::new();
        for payload in payloads {
            assembler.push_payload(payload);
        }
        assembler.finish()
    }

    #[test]
    fn el_decoder_junta_un_evento_partido_entre_chunks() {
        let mut decoder = SseDecoder::new();

        assert!(decoder.push("data: {\"cho").is_empty());
        assert!(decoder.push("ices\":[]}").is_empty(), "sin \\n todavia no cierra");

        let payloads = decoder.push("\n\n");
        assert_eq!(payloads, vec!["{\"choices\":[]}"]);
    }

    #[test]
    fn el_decoder_separa_varios_eventos_en_un_solo_chunk() {
        let mut decoder = SseDecoder::new();
        let payloads = decoder.push("data: {\"a\":1}\n\ndata: {\"a\":2}\n\ndata: [DONE]\n\n");

        assert_eq!(payloads, vec!["{\"a\":1}", "{\"a\":2}", "[DONE]"]);
        assert!(SseDecoder::is_done(&payloads[2]));
    }

    #[test]
    fn el_decoder_ignora_comentarios_de_keepalive() {
        let mut decoder = SseDecoder::new();
        assert!(decoder.push(": keep-alive\n\n").is_empty());
    }

    #[test]
    fn el_texto_se_concatena_en_orden() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"content":"Nece"}}]}"#,
            r#"{"choices":[{"delta":{"content":"sito la ruta"}}]}"#,
            r#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
        ]);

        assert_eq!(completion.content, "Necesito la ruta");
        assert_eq!(completion.finish_reason.as_deref(), Some("stop"));
        assert!(!completion.wants_tools());
    }

    /// El caso que rompe si se acumula por posicion en el array: el modelo
    /// abre el tool call 1 antes de terminar de mandar los argumentos del 0.
    #[test]
    fn dos_tool_calls_intercalados_se_acumulan_por_index() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"list_directory","arguments":"{\"pa"}}]}}]}"#,
            r#"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"which_executable","arguments":"{\"na"}}]}}]}"#,
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"E:/\"}"}}]}}]}"#,
            r#"{"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"me\":\"flutter\"}"}}]}}]}"#,
            r#"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ]);

        assert_eq!(completion.tool_calls.len(), 2);
        assert_eq!(completion.tool_calls[0].function.name, "list_directory");
        assert_eq!(completion.tool_calls[0].function.arguments, r#"{"path":"E:/"}"#);
        assert_eq!(completion.tool_calls[1].function.name, "which_executable");
        assert_eq!(
            completion.tool_calls[1].function.arguments,
            r#"{"name":"flutter"}"#
        );

        // Y el JSON reensamblado tiene que parsear de verdad.
        let parsed: serde_json::Value =
            serde_json::from_str(&completion.tool_calls[0].function.arguments).unwrap();
        assert_eq!(parsed["path"], "E:/");
    }

    /// Los argumentos pueden partirse en cualquier byte, incluso dentro de un
    /// escape JSON. Concatenar strings es correcto; parsear cada fragmento no.
    #[test]
    fn los_argumentos_partidos_a_la_mitad_de_un_escape_se_reensamblan() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"read_text_file","arguments":"{\"path\":\"E:\\"}}]}}]}"#,
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\Proyectos\\\\app\"}"}}]}}]}"#,
        ]);

        let parsed: serde_json::Value =
            serde_json::from_str(&completion.tool_calls[0].function.arguments)
                .expect("los argumentos reensamblados tienen que ser JSON valido");
        assert_eq!(parsed["path"], r"E:\Proyectos\app");
    }

    #[test]
    fn el_bloque_think_no_llega_al_contenido_visible() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"content":"<think>a ver"}}]}"#,
            r#"{"choices":[{"delta":{"content":" que necesito</think>Cual es"}}]}"#,
            r#"{"choices":[{"delta":{"content":" la ruta?"}}]}"#,
        ]);

        assert_eq!(completion.content, "Cual es la ruta?");
        assert_eq!(completion.reasoning, "a ver que necesito");
    }

    /// La etiqueta puede llegar completa dentro de un solo chunk y abrir y
    /// cerrar varias veces.
    #[test]
    fn varios_bloques_think_en_un_mismo_chunk() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"content":"Hola <think>x</think>mundo<think>y</think>!"}}]}"#,
        ]);

        assert_eq!(completion.content, "Hola mundo!");
        assert_eq!(completion.reasoning, "xy");
    }

    #[test]
    fn reasoning_content_separado_no_se_muestra_como_respuesta() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"reasoning_content":"pensando"}}]}"#,
            r#"{"choices":[{"delta":{"content":"listo"}}]}"#,
        ]);

        assert_eq!(completion.content, "listo");
        assert_eq!(completion.reasoning, "pensando");
    }

    #[test]
    fn un_chunk_ilegible_no_tumba_el_turno() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"content":"a"}}]}"#,
            "esto no es json",
            r#"{"choices":[{"delta":{"content":"b"}}]}"#,
        ]);

        assert_eq!(completion.content, "ab");
    }

    #[test]
    fn done_no_agrega_nada() {
        let mut assembler = CompletionAssembler::new();
        assembler.push_payload(r#"{"choices":[{"delta":{"content":"x"}}]}"#);
        assert!(assembler.push_payload("[DONE]").is_empty());
        assert_eq!(assembler.finish().content, "x");
    }

    /// Un tool call sin `id` (algunos backends no lo mandan en streaming)
    /// igual tiene que servir: el mensaje de respuesta necesita referenciarlo.
    #[test]
    fn un_tool_call_sin_id_recibe_uno_sintetico() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"list_directory","arguments":"{}"}}]}}]}"#,
        ]);

        assert_eq!(completion.tool_calls.len(), 1);
        assert!(!completion.tool_calls[0].id.is_empty());
    }

    /// Un stream cortado deja fragmentos sin nombre: son basura y no pueden
    /// llegar al agente como si fueran una llamada real.
    #[test]
    fn los_tool_calls_incompletos_se_descartan() {
        let completion = assemble(&[
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"a\":"}}]}}]}"#,
        ]);

        assert!(completion.tool_calls.is_empty());
    }

    /// Se emite el aviso apenas se conoce el nombre, sin esperar argumentos:
    /// la UI muestra "revisando el disco..." de inmediato.
    #[test]
    fn el_inicio_de_un_tool_call_se_avisa_apenas_llega_el_nombre() {
        let mut assembler = CompletionAssembler::new();
        let deltas = assembler.push_payload(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"find_project","arguments":""}}]}}]}"#,
        );

        assert_eq!(
            deltas,
            vec![StreamDelta::ToolCallStarted {
                name: "find_project".into()
            }]
        );

        // Y no se repite con cada fragmento de argumentos.
        let more = assembler.push_payload(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}"#,
        );
        assert!(more.is_empty());
    }
}
