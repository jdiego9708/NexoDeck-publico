//! Clasifica prompts con el detector de código de `auto`, para validarlo contra datasets reales.
//!
//! Lee JSON Lines por stdin (`{"text": "..."}`) y escribe una línea por entrada con `1` si el
//! detector dice que es código y `0` si no. Lo usa `llm-stack/scripts/check-code-detector.py`: así el detector
//! que se mide es el de verdad y no una copia en otro lenguaje.

use std::io::{self, BufRead};

use llm_gateway::config::AutoConfig;
use llm_gateway::route::{features_from_request, is_code};
use serde_json::{json, Value};

fn main() {
    let config = AutoConfig::default();
    for line in io::stdin().lock().lines() {
        let line = line.expect("stdin legible");
        if line.trim().is_empty() {
            continue;
        }
        let entry: Value = serde_json::from_str(&line).expect("cada línea es un JSON");
        let text = entry.get("text").and_then(Value::as_str).unwrap_or("");
        let body = json!({ "messages": [{ "role": "user", "content": text }] });
        println!("{}", u8::from(is_code(&config, &features_from_request(&body))));
    }
}
