//! Enrutado del modelo virtual `auto`: decide a qué nivel va una petición.
//!
//! Las decisiones y sus prioridades son las del doc 05 (`meta` 300 > `complex_keywords` 210 >
//! `complex` 200 > `simple` 100 > `normal` 50, con `normal` por defecto), para que el registro de
//! decisiones siga siendo comparable con lo que diseñó la receta. Lo que cambia es el **destino**:
//! la receta enrutaba entre tres modelos, pero el Rápido y el Complejo no conviven (doc 11, 7.10 y
//! 7.14), así que un perfil solo tiene dos niveles:
//!
//! - `Light`: el Router (4B), para lo simple y lo de clasificación.
//! - `Worker`: el modelo trabajador del perfil activo (Complejo en el B, Rápido en el A).
//!
//! Este módulo es **puro** (sin red ni disco): recibe el cuerpo de la petición y devuelve una
//! decisión, para poder probarlo a fondo. Resolver qué modelo concreto hay levantado le toca a
//! `proxy.rs`.

use serde_json::Value;

use crate::config::AutoConfig;

/// Nombre del modelo virtual. Un cliente pide `"model": "auto"` y la pasarela elige.
pub const AUTO_MODEL: &str = "auto";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    /// El modelo ligero (Router).
    Light,
    /// El modelo trabajador del perfil activo.
    Worker,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Decision {
    /// Nombre de la decisión, el mismo que en el doc 05.
    pub name: &'static str,
    pub tier: Tier,
}

/// Lo que se mira de una petición. Nunca se guarda su texto: solo estas medidas.
#[derive(Debug, Clone)]
pub struct Features {
    /// Caracteres de todo el texto de la petición (el doc 05 mide en caracteres, no en tokens).
    pub prompt_chars: usize,
    /// La petición trae `tools`: es un agente, no una pregunta suelta.
    pub has_tools: bool,
    /// Texto en minúsculas, solo para buscar palabras clave. No sale de este módulo.
    text_lower: String,
}

/// Acumula el texto de una petición. Los caracteres se cuentan aparte del texto: entre trozos se
/// inserta un salto de línea (para que una palabra clave no se forme uniendo el final de un
/// mensaje con el principio del siguiente), pero ese separador es un invento nuestro y **no debe
/// contar** como longitud del prompt.
#[derive(Default)]
struct TextAccumulator {
    text: String,
    chars: usize,
}

impl TextAccumulator {
    fn add(&mut self, piece: &str) {
        self.chars += piece.chars().count();
        self.text.push_str(piece);
        self.text.push('\n');
    }

    /// Un valor `content`: una cadena o una lista de partes con `text` (formato multimodal de
    /// OpenAI).
    fn add_content(&mut self, content: &Value) {
        match content {
            Value::String(text) => self.add(text),
            Value::Array(parts) => {
                for part in parts {
                    if let Some(text) = part.get("text").and_then(Value::as_str) {
                        self.add(text);
                    }
                }
            }
            _ => {}
        }
    }
}

/// Mide una petición de `/v1/chat/completions` (campo `messages`) o de `/v1/completions` (campo
/// `prompt`, cadena o lista de cadenas).
pub fn features_from_request(body: &Value) -> Features {
    let mut accumulator = TextAccumulator::default();

    if let Some(messages) = body.get("messages").and_then(Value::as_array) {
        for message in messages {
            if let Some(content) = message.get("content") {
                accumulator.add_content(content);
            }
        }
    }
    match body.get("prompt") {
        Some(Value::String(prompt)) => accumulator.add(prompt),
        Some(Value::Array(prompts)) => {
            for prompt in prompts.iter().filter_map(Value::as_str) {
                accumulator.add(prompt);
            }
        }
        _ => {}
    }

    let has_tools = body
        .get("tools")
        .and_then(Value::as_array)
        .is_some_and(|tools| !tools.is_empty());

    Features {
        prompt_chars: accumulator.chars,
        has_tools,
        text_lower: accumulator.text.to_lowercase(),
    }
}

fn matches_any(text_lower: &str, keywords: &[String]) -> bool {
    keywords
        .iter()
        .any(|keyword| !keyword.is_empty() && text_lower.contains(&keyword.to_lowercase()))
}

/// Evalúa las decisiones por prioridad, de mayor a menor, y devuelve la primera que coincide.
pub fn decide(config: &AutoConfig, features: &Features) -> Decision {
    // 300: clasificación y llamadas a funciones. Al ligero, sin importar la longitud.
    if matches_any(&features.text_lower, &config.meta_keywords) {
        return Decision { name: "meta", tier: Tier::Light };
    }
    // 210: palabras clave de arquitectura y optimización. Antes que la longitud, para que
    // "optimize this query" (corto) vaya igualmente al trabajador.
    if matches_any(&features.text_lower, &config.complex_keywords) {
        return Decision { name: "complex_keywords", tier: Tier::Worker };
    }
    // 200: prompts largos.
    if features.prompt_chars > config.long_min_chars {
        return Decision { name: "complex", tier: Tier::Worker };
    }
    // 100: prompts muy cortos, al ligero (en la receta iban al Rápido, que ahora es el trabajador).
    if features.prompt_chars < config.simple_max_chars {
        return Decision { name: "simple", tier: Tier::Light };
    }
    // 50 y por defecto: lo mediano, al trabajador.
    Decision { name: "normal", tier: Tier::Worker }
}

/// ¿La petición trata de código? Solo mira las marcas de `code_markers`: nunca se guarda ni sale el
/// texto.
pub fn is_code(config: &AutoConfig, features: &Features) -> bool {
    matches_any(&features.text_lower, &config.code_markers)
}

/// Enrutado por dominio (doc 11, 7.25 y 7.28): corrige la decisión por longitud.
///
/// - **El código va al trabajador aunque sea corto** (`code`), sea cual sea: la longitud no predice
///   la dificultad (7.24) y en HumanEval el Router saca 75-79 % frente al 89-90 % del Complejo y al
///   92,7 % de Gemma (7.28).
/// - **Lo que no es código no llega a un especialista** (`not_code`): pasa al ligero. Con un
///   generalista de trabajador (Gemma) no se toca: rinde bien en todo.
/// - `meta` no cambia. Sin trabajador levantado o con `code_routing` apagado tampoco.
pub fn apply_domain(
    config: &AutoConfig,
    decision: Decision,
    features: &Features,
    worker: Option<&str>,
) -> Decision {
    let Some(worker) = worker else { return decision };
    if !config.code_routing || decision.name == "meta" {
        return decision;
    }
    let specialist = config.specialists.iter().any(|name| name == worker);
    match (is_code(config, features), decision.tier) {
        (true, Tier::Light) => Decision { name: "code", tier: Tier::Worker },
        (false, Tier::Worker) if specialist => Decision { name: "not_code", tier: Tier::Light },
        _ => decision,
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn chat(text: &str) -> Value {
        json!({ "model": "auto", "messages": [{ "role": "user", "content": text }] })
    }

    fn decide_for(body: Value) -> Decision {
        decide(&AutoConfig::default(), &features_from_request(&body))
    }

    /// Un texto de la longitud pedida sin ninguna palabra clave.
    fn filler(chars: usize) -> String {
        "la casa es azul y el sol brilla. ".repeat(chars / 33 + 1).chars().take(chars).collect()
    }

    #[test]
    fn a_short_prompt_goes_to_the_light_model() {
        let decision = decide_for(chat("Cuanto es 17 + 25?"));
        assert_eq!(decision, Decision { name: "simple", tier: Tier::Light });
    }

    #[test]
    fn a_medium_prompt_goes_to_the_worker_as_normal() {
        let decision = decide_for(chat(&filler(400)));
        assert_eq!(decision, Decision { name: "normal", tier: Tier::Worker });
    }

    #[test]
    fn a_long_prompt_goes_to_the_worker_as_complex() {
        let decision = decide_for(chat(&filler(2000)));
        assert_eq!(decision, Decision { name: "complex", tier: Tier::Worker });
    }

    #[test]
    fn the_thresholds_are_150_and_800_characters_as_in_the_recipe() {
        // "simple" es estrictamente menor que 150; "complex" estrictamente mayor que 800.
        assert_eq!(decide_for(chat(&filler(149))).name, "simple");
        assert_eq!(decide_for(chat(&filler(150))).name, "normal");
        assert_eq!(decide_for(chat(&filler(800))).name, "normal");
        assert_eq!(decide_for(chat(&filler(801))).name, "complex");
    }

    #[test]
    fn a_short_prompt_with_an_architecture_keyword_still_goes_to_the_worker() {
        // Es el caso de la receta: "Optimize this SQL query" es corto, pero es de los pesados.
        for text in ["Optimize this SQL query", "Design the architecture", "Refactor this module"] {
            let decision = decide_for(chat(text));
            assert_eq!(decision, Decision { name: "complex_keywords", tier: Tier::Worker }, "{text}");
        }
    }

    #[test]
    fn the_keywords_also_work_in_spanish() {
        for text in ["Refactoriza este módulo", "Optimiza esta consulta", "Diseña la arquitectura del sistema"] {
            assert_eq!(decide_for(chat(text)).name, "complex_keywords", "{text}");
        }
    }

    #[test]
    fn meta_keywords_win_over_everything_else() {
        // Prioridad 300: va al ligero aunque sea largo y lleve palabras de arquitectura.
        let text = format!("Classify this. Refactor the architecture. {}", filler(2000));
        assert_eq!(decide_for(chat(&text)), Decision { name: "meta", tier: Tier::Light });
    }

    #[test]
    fn keyword_matching_ignores_case() {
        assert_eq!(decide_for(chat("OPTIMIZE THIS")).name, "complex_keywords");
        assert_eq!(decide_for(chat("Please CLASSIFY the ticket")).name, "meta");
    }

    #[test]
    fn the_whole_conversation_counts_not_only_the_last_message() {
        let body = json!({
            "model": "auto",
            "messages": [
                { "role": "system", "content": filler(900) },
                { "role": "user", "content": "hola" },
            ]
        });
        assert_eq!(decide_for(body).name, "complex");
    }

    #[test]
    fn content_given_as_a_list_of_parts_is_read() {
        let body = json!({
            "model": "auto",
            "messages": [{ "role": "user", "content": [
                { "type": "text", "text": "Refactor" },
                { "type": "image_url", "image_url": { "url": "data:..." } },
            ] }]
        });
        assert_eq!(decide_for(body).name, "complex_keywords");
    }

    #[test]
    fn a_plain_completions_prompt_is_measured_too() {
        let body = json!({ "model": "auto", "prompt": filler(1000) });
        assert_eq!(decide_for(body).name, "complex");
        let list = json!({ "model": "auto", "prompt": ["hola", "que tal"] });
        assert_eq!(decide_for(list).name, "simple");
    }

    #[test]
    fn a_request_without_text_is_simple_and_does_not_panic() {
        assert_eq!(decide_for(json!({ "model": "auto" })).name, "simple");
        assert_eq!(decide_for(json!({ "model": "auto", "messages": [{ "role": "user" }] })).name, "simple");
    }

    #[test]
    fn tools_are_detected_but_do_not_change_the_decision_by_themselves() {
        let body = json!({
            "model": "auto",
            "tools": [{ "type": "function", "function": { "name": "x" } }],
            "messages": [{ "role": "user", "content": "hola" }]
        });
        let features = features_from_request(&body);
        assert!(features.has_tools);
        assert_eq!(decide(&AutoConfig::default(), &features).name, "simple");
        assert!(!features_from_request(&json!({ "tools": [] })).has_tools);
    }

    #[test]
    fn empty_keywords_never_match() {
        let config = AutoConfig { meta_keywords: vec![String::new()], ..AutoConfig::default() };
        assert_ne!(decide(&config, &features_from_request(&chat("hola"))).name, "meta");
    }

    #[test]
    fn characters_are_counted_not_bytes() {
        // 200 letras de dos bytes cada una: 200 caracteres (normal), no 400 bytes.
        let text = "ñ".repeat(200);
        let features = features_from_request(&chat(&text));
        assert_eq!(features.prompt_chars, 200);
    }

    #[test]
    fn the_separator_between_messages_is_not_counted_as_text() {
        let body = json!({ "messages": [
            { "role": "user", "content": "abc" },
            { "role": "assistant", "content": "de" },
        ] });
        assert_eq!(features_from_request(&body).prompt_chars, 5);
    }

    fn domain_for(text: &str, worker: Option<&str>) -> Decision {
        let config = AutoConfig::default();
        let features = features_from_request(&chat(text));
        apply_domain(&config, decide(&config, &features), &features, worker)
    }

    #[test]
    fn with_a_specialist_worker_non_code_goes_to_the_light_model() {
        // Un texto mediano que sin dominio iría al trabajador (`normal`).
        let decision = domain_for(&filler(400), Some("complex"));
        assert_eq!(decision, Decision { name: "not_code", tier: Tier::Light });
    }

    #[test]
    fn with_a_specialist_worker_short_code_goes_to_it() {
        let decision = domain_for("Write a function in Python that reverses a string", Some("complex"));
        assert_eq!(decision, Decision { name: "code", tier: Tier::Worker });
    }

    #[test]
    fn a_generalist_worker_keeps_non_code_but_still_gets_the_code() {
        // Lo que no es código sigue por longitud: Gemma rinde bien en todo.
        assert_eq!(domain_for(&filler(400), Some("fast")).name, "normal");
        // El código corto va a Gemma, no al Router (92,7 % frente a 75-79 % en HumanEval).
        assert_eq!(
            domain_for("Write a function in Python", Some("fast")),
            Decision { name: "code", tier: Tier::Worker }
        );
        // Sin trabajador levantado no se toca nada.
        assert_eq!(domain_for(&filler(400), None).name, "normal");
        assert_eq!(domain_for("Write a function in Python", None).name, "simple");
    }

    #[test]
    fn meta_stays_with_the_light_model_even_if_it_mentions_code() {
        assert_eq!(domain_for("Classify this python snippet", Some("complex")).name, "meta");
    }

    #[test]
    fn code_routing_can_be_turned_off() {
        let config = AutoConfig { code_routing: false, ..AutoConfig::default() };
        let features = features_from_request(&chat(&filler(400)));
        let decision = apply_domain(&config, decide(&config, &features), &features, Some("complex"));
        assert_eq!(decision.name, "normal");
    }

    #[test]
    fn a_code_fence_marks_code() {
        let config = AutoConfig::default();
        assert!(is_code(&config, &features_from_request(&chat("mira:\n```\nx = 1\n```"))));
        assert!(!is_code(&config, &features_from_request(&chat("La capital de Francia es Paris"))));
    }

    #[test]
    fn a_keyword_cannot_be_formed_across_two_messages() {
        // "refac" + "tor" no es "refactor": el separador entre mensajes lo impide.
        let body = json!({ "messages": [
            { "role": "user", "content": "refac" },
            { "role": "user", "content": "tor" },
        ] });
        assert_eq!(decide(&AutoConfig::default(), &features_from_request(&body)).name, "simple");
    }
}
