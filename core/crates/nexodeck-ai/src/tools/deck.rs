//! Que botones ya tiene el deck.
//!
//! Los datos los inyecta Dart con `set_ai_deck_context` (Rust no lee Drift: por
//! la regla de arquitectura, la base es del lado Flutter). Sirve para dos
//! cosas: que el asistente no proponga un boton que ya existe, y que pueda
//! reusar los nombres y el estilo de los que ya hay.

use serde_json::{Value, json};

use crate::openai::types::ToolDef;
use crate::tools::{Tool, ToolContext};

pub struct ListExistingActions;

impl Tool for ListExistingActions {
    fn name(&self) -> &'static str {
        "list_existing_actions"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "list_existing_actions",
            "Lista los botones que el usuario ya tiene en su deck. \
             Usala para no proponer uno duplicado y para seguir su forma de nombrarlos.",
            json!({ "type": "object", "properties": {} }),
        )
    }

    fn call(&self, _args: &Value, ctx: &ToolContext) -> Value {
        let deck = ctx.deck();
        if deck.is_empty() {
            return json!({
                "ok": true,
                "actions": [],
                "hint": "El deck esta vacio: este seria el primer boton del usuario."
            });
        }

        json!({
            "ok": true,
            "actions": deck.iter().map(|action| json!({
                "name": action.name,
                "kind": action.kind,
                "description": action.description,
            })).collect::<Vec<_>>()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::DeckActionRef;
    use std::path::PathBuf;

    fn ctx(deck: Vec<DeckActionRef>) -> ToolContext {
        let ctx = ToolContext::new(
            vec![PathBuf::from(std::env::temp_dir())],
            nexodeck_hardware::HostOs::Windows,
        );
        ctx.set_deck(deck);
        ctx
    }

    #[test]
    fn un_deck_vacio_lo_dice_explicitamente() {
        let result = ListExistingActions.call(&json!({}), &ctx(Vec::new()));

        assert_eq!(result["ok"], true);
        assert!(result["actions"].as_array().unwrap().is_empty());
        assert!(result["hint"].as_str().unwrap().contains("primer boton"));
    }

    /// El id **no** se expone: en v1 el asistente no puede encadenar botones
    /// existentes (haria falta que copiara un uuid exacto, que es la parte mas
    /// fragil), asi que darle el id solo invitaria a alucinarlo.
    #[test]
    fn se_listan_los_botones_sin_exponer_los_ids() {
        let result = ListExistingActions.call(
            &json!({}),
            &ctx(vec![DeckActionRef {
                id: "6f3d-uuid".into(),
                name: "Analizar proyecto".into(),
                kind: "terminal".into(),
                description: Some("corre flutter analyze".into()),
            }]),
        );

        let actions = result["actions"].as_array().unwrap();
        assert_eq!(actions.len(), 1);
        assert_eq!(actions[0]["name"], "Analizar proyecto");
        assert!(
            actions[0].get("id").is_none(),
            "exponer el id invita al modelo a inventarlo"
        );
    }
}
