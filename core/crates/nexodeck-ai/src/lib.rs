//! Motor de IA local de NexoDeck.
//!
//! Corre un modelo de lenguaje **en la maquina del usuario**, sin red, para
//! asistirlo en la creacion de acciones y macros a partir de lenguaje natural.
//!
//! La inferencia no se hace en proceso: se lanza el binario preconstruido
//! `llama-server` de llama.cpp como **proceso hijo** y se le habla por HTTP
//! OpenAI-compatible en `127.0.0.1`. El porque esta en
//! [`ADR 0003`](../../../../docs/architecture-decision-records/0003-sidecar-llamacpp-sobre-embebido.md);
//! el resumen es que asi el backend de GPU (CUDA / Vulkan / CPU-AVX2) se elige
//! **en runtime segun el hardware detectado** en vez de quedar fijado al
//! compilar, y que no entra ni una dependencia de C/C++/CMake al workspace
//! (que se compila dentro de cargokit durante `flutter build`).
//!
//! Este crate **no se expone a Dart**: como todos los demas, solo llega a la
//! app a traves de `nexodeck-ffi`.

pub mod agent;
pub mod catalog;
pub mod download;
pub mod draft;
pub mod engine;
pub mod error;
pub mod ollama;
pub mod openai;
pub mod paths;
pub mod plan;
pub mod prompt;
pub mod provider;
pub mod remote;
pub mod safety;
pub mod setup;
pub mod sidecar;
pub mod tools;

pub use catalog::{ModelEntry, RuntimeAsset};
pub use error::{AiError, AiResult};
pub use plan::{Backend, RuntimePlan, Tier, gpu_layers_for, plan_runtime};
