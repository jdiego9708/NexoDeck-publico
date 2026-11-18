pub mod actions;
pub mod ai;
pub mod components;
pub mod connection;
pub mod control;
pub mod docs;
pub mod editor;
pub mod foreground;
pub mod hardware;
pub mod hub;
pub mod notes;
// Privado y solo de escritorio a proposito: no expone nada a Dart (no es una
// api de frb), y usa `nexodeck-docs`, que no entra en el `.so` de Android.
#[cfg(not(target_os = "android"))]
mod notes_vault;
pub mod notify;
pub mod pairing;
pub mod processes;
pub mod relay;
pub mod sensors;
pub mod simple;
pub mod usb;
