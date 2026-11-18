//! Leer la respuesta del modelo.

use serde::Deserialize;

use crate::model::Unresolved;
use crate::ops::Operation;

#[derive(Debug, Clone, Deserialize)]
pub struct ModelOutput {
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub operations: Vec<Operation>,
    #[serde(default)]
    pub unresolved: Vec<Unresolved>,
}

/// Tolera lo que los modelos hacen aunque se les pida JSON puro: envolverlo en
/// un bloque de codigo o poner una frase antes. El error es una frase para
/// devolverle al modelo.
pub fn parse_output(text: &str) -> Result<ModelOutput, String> {
    let text = text.trim();
    let (Some(start), Some(end)) = (text.find('{'), text.rfind('}')) else {
        return Err("la respuesta no trae ningun objeto JSON; devuelve solo el objeto pedido".to_string());
    };
    if end < start {
        return Err("la respuesta no trae ningun objeto JSON completo".to_string());
    }
    serde_json::from_str(&text[start..=end])
        .map_err(|e| format!("la respuesta no es el JSON pedido: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_json_wrapped_in_a_code_fence() {
        let text = "Aqui va:\n```json\n{\"summary\":\"s\",\"operations\":[{\"op\":\"set_last_updated\",\"file\":\"a.md\",\"date\":\"hoy\"}]}\n```";
        let out = parse_output(text).unwrap();
        assert_eq!(out.summary, "s");
        assert_eq!(out.operations.len(), 1);
    }

    #[test]
    fn an_unknown_operation_is_explained() {
        let err = parse_output(r#"{"operations":[{"op":"rewrite_file","file":"a.md"}]}"#).unwrap_err();
        assert!(err.contains("rewrite_file"), "{err}");
    }

    #[test]
    fn plain_text_is_refused() {
        assert!(parse_output("no puedo hacerlo").is_err());
    }
}
