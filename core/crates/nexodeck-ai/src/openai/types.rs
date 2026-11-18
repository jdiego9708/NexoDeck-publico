//! Tipos de la API OpenAI-compatible.
//!
//! Es el idioma que hablan `llama-server` y Ollama por igual, y por eso el
//! `trait ChatProvider` puede tener una sola implementacion de protocolo con
//! dos formas de conseguir un servidor. Tambien es lo que hace que el modo
//! online futuro sea un tercer proveedor y no un rediseno.

use serde::{Deserialize, Serialize};

/// Un mensaje de la conversacion.
///
/// Internamente etiquetado por `role`, que es exactamente el formato del cable.
/// El `content` del asistente es `Option` a proposito: cuando el modelo
/// responde **solo** con tool calls, viene nulo, y forzarlo a `String` haria
/// fallar la deserializacion en el caso mas comun del asistente.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "role", rename_all = "lowercase")]
pub enum ChatMessage {
    System {
        content: String,
    },
    User {
        content: String,
    },
    Assistant {
        #[serde(skip_serializing_if = "Option::is_none")]
        content: Option<String>,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        tool_calls: Vec<ToolCall>,
    },
    Tool {
        content: String,
        tool_call_id: String,
    },
}

impl ChatMessage {
    pub fn system(content: impl Into<String>) -> Self {
        ChatMessage::System {
            content: content.into(),
        }
    }

    pub fn user(content: impl Into<String>) -> Self {
        ChatMessage::User {
            content: content.into(),
        }
    }

    pub fn assistant_text(content: impl Into<String>) -> Self {
        ChatMessage::Assistant {
            content: Some(content.into()),
            tool_calls: Vec::new(),
        }
    }

    pub fn assistant_tool_calls(content: Option<String>, tool_calls: Vec<ToolCall>) -> Self {
        ChatMessage::Assistant {
            content,
            tool_calls,
        }
    }

    pub fn tool_result(tool_call_id: impl Into<String>, content: impl Into<String>) -> Self {
        ChatMessage::Tool {
            content: content.into(),
            tool_call_id: tool_call_id.into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCall {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub function: FunctionCall,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FunctionCall {
    pub name: String,
    /// **Un string con JSON adentro**, no un objeto. Asi lo define la API y asi
    /// lo manda el modelo; parsearlo es responsabilidad de cada herramienta,
    /// que ademas tiene que tolerar que venga mal formado.
    pub arguments: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ToolDef {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub function: FunctionDef,
}

#[derive(Debug, Clone, Serialize)]
pub struct FunctionDef {
    pub name: String,
    pub description: String,
    /// JSON Schema de los parametros.
    pub parameters: serde_json::Value,
}

impl ToolDef {
    pub fn function(
        name: impl Into<String>,
        description: impl Into<String>,
        parameters: serde_json::Value,
    ) -> Self {
        ToolDef {
            kind: "function",
            function: FunctionDef {
                name: name.into(),
                description: description.into(),
                parameters,
            },
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ChatRequest {
    pub model: String,
    pub messages: Vec<ChatMessage>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<ToolDef>,
    pub stream: bool,
    pub temperature: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<u32>,
    /// Extras de la plantilla de chat. Lo usamos para **apagar el modo de
    /// razonamiento** de los modelos hibridos (Qwen3 14B y 30B lo traen
    /// prendido por defecto): para una conversacion de aclaracion, pensar en
    /// voz alta durante 30 segundos antes de cada pregunta arruina la
    /// experiencia y no mejora el comando resultante.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chat_template_kwargs: Option<serde_json::Value>,
    /// Pedir la salida en JSON (`{"type":"json_object"}` en los servicios
    /// remotos, o un `json_schema` en llama-server). Solo lo usa quien necesita
    /// parsear la respuesta, como el buzon de documentacion; el chat no.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_format: Option<serde_json::Value>,
}

impl ChatRequest {
    pub fn new(model: impl Into<String>, messages: Vec<ChatMessage>) -> Self {
        ChatRequest {
            model: model.into(),
            messages,
            tools: Vec::new(),
            stream: true,
            // Baja pero no cero: con 0.0 los modelos chicos se enganchan en
            // bucles repitiendo la misma pregunta de aclaracion.
            temperature: 0.3,
            // Tope duro de generacion. Un turno del asistente es una pregunta
            // corta o un borrador: nada legitimo se acerca a esto. Sin tope, un
            // modelo que se engancha en un bucle genera hasta llenar el
            // contexto — verificado en vivo: minutos de GPU al 100% escribiendo
            // la misma propuesta una y otra vez, sin nada que lo corte.
            max_tokens: Some(2048),
            chat_template_kwargs: None,
            response_format: None,
        }
    }

    /// Otro tope de generacion. El de 2048 es para turnos de chat; una
    /// propuesta de documentacion con una seccion entera no entra ahi.
    pub fn with_max_tokens(mut self, max_tokens: u32) -> Self {
        self.max_tokens = Some(max_tokens);
        self
    }

    pub fn with_temperature(mut self, temperature: f32) -> Self {
        self.temperature = temperature;
        self
    }

    pub fn with_response_format(mut self, format: serde_json::Value) -> Self {
        self.response_format = Some(format);
        self
    }

    pub fn with_tools(mut self, tools: Vec<ToolDef>) -> Self {
        self.tools = tools;
        self
    }

    /// Apaga el modo de razonamiento.
    ///
    /// Solo se llama en los modelos que lo entienden (ver
    /// `ModelEntry::supports_thinking`): mandarle esta bandera a uno que no la
    /// conoce es ruido en su plantilla de chat.
    pub fn without_thinking(mut self) -> Self {
        self.chat_template_kwargs = Some(serde_json::json!({ "enable_thinking": false }));
        self
    }
}

// ---------------------------------------------------------------------
// Respuesta en streaming
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
pub struct ChatChunk {
    #[serde(default)]
    pub choices: Vec<ChunkChoice>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ChunkChoice {
    #[serde(default)]
    pub delta: Delta,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Delta {
    #[serde(default)]
    pub content: Option<String>,
    /// Razonamiento separado del contenido. Lo emite llama.cpp con
    /// `--reasoning-format` (el default en las builds actuales) para los
    /// modelos que piensan; no se le muestra al usuario.
    #[serde(default)]
    pub reasoning_content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<ToolCallDelta>,
}

/// Fragmento de un tool call. **El `index` es lo unico estable**: `id` y
/// `function.name` llegan una sola vez, en el primer fragmento, y los
/// `arguments` van goteando partidos en cualquier lado (incluso a la mitad de
/// un escape JSON). Acumular por posicion en el array en vez de por `index`
/// rompe apenas el modelo pide dos herramientas en el mismo turno.
#[derive(Debug, Clone, Deserialize)]
pub struct ToolCallDelta {
    #[serde(default)]
    pub index: usize,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub function: Option<FunctionDelta>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct FunctionDelta {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub arguments: Option<String>,
}

/// Resultado completo de un turno del modelo, ya reensamblado.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ChatCompletion {
    pub content: String,
    pub reasoning: String,
    pub tool_calls: Vec<ToolCall>,
    pub finish_reason: Option<String>,
}

impl ChatCompletion {
    pub fn wants_tools(&self) -> bool {
        !self.tool_calls.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_format_is_only_sent_when_asked_for() {
        let plain = serde_json::to_value(ChatRequest::new("m", vec![])).unwrap();
        assert!(plain.get("response_format").is_none());

        let json = ChatRequest::new("m", vec![])
            .with_response_format(serde_json::json!({ "type": "json_object" }))
            .with_max_tokens(8192);
        let json = serde_json::to_value(json).unwrap();
        assert_eq!(json["response_format"]["type"], "json_object");
        assert_eq!(json["max_tokens"], 8192);
    }

    #[test]
    fn el_mensaje_del_asistente_serializa_sin_campos_vacios() {
        let message = ChatMessage::assistant_text("hola");
        let json = serde_json::to_value(&message).unwrap();

        assert_eq!(json["role"], "assistant");
        assert_eq!(json["content"], "hola");
        assert!(
            json.get("tool_calls").is_none(),
            "un array vacio de tool_calls confunde a algunos backends"
        );
    }

    /// El caso mas comun del asistente: responde solo con tool calls y sin
    /// texto. Si `content` no fuera opcional, esto no deserializaria.
    #[test]
    fn el_asistente_puede_no_tener_contenido() {
        let json = serde_json::json!({
            "role": "assistant",
            "content": null,
            "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": { "name": "list_directory", "arguments": "{\"path\":\"E:/\"}" }
            }]
        });

        let message: ChatMessage = serde_json::from_value(json).unwrap();
        match message {
            ChatMessage::Assistant {
                content,
                tool_calls,
            } => {
                assert!(content.is_none());
                assert_eq!(tool_calls.len(), 1);
                assert_eq!(tool_calls[0].function.name, "list_directory");
            }
            other => panic!("se esperaba Assistant, salio {other:?}"),
        }
    }

    /// Por defecto **no** se manda `chat_template_kwargs`: un modelo que no
    /// conoce la bandera recibiria ruido en su plantilla.
    #[test]
    fn la_peticion_no_toca_la_plantilla_salvo_que_se_lo_pidan() {
        let request = ChatRequest::new("modelo", vec![ChatMessage::user("hola")]);
        let json = serde_json::to_value(&request).unwrap();

        assert!(json.get("chat_template_kwargs").is_none());
        assert_eq!(json["stream"], true);
        assert!(json.get("tools").is_none(), "sin herramientas no se manda el campo");

        let sin_pensar = ChatRequest::new("modelo", vec![]).without_thinking();
        let json = serde_json::to_value(&sin_pensar).unwrap();
        assert_eq!(json["chat_template_kwargs"]["enable_thinking"], false);
    }

    #[test]
    fn las_herramientas_se_serializan_como_function() {
        let request = ChatRequest::new("modelo", vec![]).with_tools(vec![ToolDef::function(
            "which_executable",
            "Busca un ejecutable en el PATH",
            serde_json::json!({ "type": "object", "properties": {} }),
        )]);
        let json = serde_json::to_value(&request).unwrap();

        assert_eq!(json["tools"][0]["type"], "function");
        assert_eq!(json["tools"][0]["function"]["name"], "which_executable");
    }
}
