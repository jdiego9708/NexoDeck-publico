//! Pasarela autenticada delante de los servidores vLLM del stack multiagente.
//!
//! Los servidores vLLM no llevan autenticación real (la receta usaba `api_key: "dummy"`) y con
//! `VLLM_SERVER_DEV_MODE=1` exponen endpoints de administración peligrosos. Esta pasarela es lo
//! único que se ofrece a los clientes: comprueba la clave, deja pasar solo las rutas OpenAI y
//! elige el servidor según el campo `model` de la petición. Ver
//! `docs/llm-stack/11-mejoras-y-decisiones.md`.

pub mod auth;
pub mod config;
pub mod decisions;
pub mod logging;
pub mod proxy;
pub mod route;

pub use proxy::{build_app, build_app_with, build_app_with_reload};
