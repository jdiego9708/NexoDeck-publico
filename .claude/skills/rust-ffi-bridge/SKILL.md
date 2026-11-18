---
name: rust-ffi-bridge
description: Cómo agregar o regenerar funciones expuestas de Rust (nexodeck-ffi) hacia Dart vía flutter_rust_bridge.
---

# rust-ffi-bridge

Regla no negociable: **solo `core/crates/nexodeck-ffi` se expone a Dart**.
Ningún otro crate del workspace se importa directamente desde `app/`.

## Agregar una función nueva expuesta a Dart

1. Define la función pública en `core/crates/nexodeck-ffi/src/api/` (crea un
   módulo nuevo si no encaja en uno existente, y decláralo en `src/api/mod.rs`).
2. Si la función necesita usar tipos de otro crate del workspace (ej.
   `nexodeck-hardware::HardwareSnapshot`), **no los expongas directo** — define
   un struct DTO local en `nexodeck-ffi` con un `impl From<...>` que convierta,
   como en `api/hardware.rs`. `nexodeck-ffi` es el único lugar donde vive la
   forma exacta del dato que cruza el bridge.
3. Regenera los bindings:
   ```sh
   dart run melos run bridge:gen
   ```
   (equivalente a `flutter_rust_bridge_codegen generate` desde `app/`).
   Hazlo ANTES de `cargo build`: el struct/función nuevo no tiene los
   `impl SseEncode`/`SseDecode` que genera el codegen hasta que corres esto
   — si compilas antes vas a ver un error de "trait bound not satisfied".
4. Verifica que `app/lib/src/rust/api/` se actualizó y que
   `flutter run -d windows` sigue compilando.
5. Comitea tanto el código Rust como los archivos regenerados en
   `app/lib/src/rust/` — SÍ se comitean (práctica estándar de frb para que
   el repo compile sin correr codegen primero).

## Exponer un Stream (datos que Rust empuja continuamente)

El patrón NO es devolver `impl Stream<Item = T>` — es tomar un
`StreamSink<T>` como parámetro y llamar a `sink.add(valor)` en un loop.
Importa `StreamSink` desde `crate::frb_generated::StreamSink` (no desde la
raíz de `flutter_rust_bridge`). Ver `api/hardware.rs::watch_hardware_metrics`
como ejemplo real: usa `tokio::time::interval` para el ritmo y rompe el loop
cuando `sink.add(...)` devuelve `Err` (el lado Dart cerró el stream). No
hace falta configurar un runtime tokio propio — frb ya corre las funciones
`async` dentro de su propio `tokio::runtime::Runtime`.

## Manejo de errores

Las funciones que pueden fallar devuelven `Result<T, String>` (no el tipo de
error interno del crate, ej. `ActionError`) -- mismo principio que los DTOs:
`nexodeck-ffi` no expone tipos internos, y `String` siempre es serializable
sin depender de que el tipo de error implemente traits de frb. Un `Err` se
convierte en una excepción del lado Dart (`try/catch` normal). Ver
`api/actions.rs::execute_clipboard_action`.

## Versión pinneada

flutter_rust_bridge está fijado en `2.12.0` (estable) en tres lugares: el
CLI (`cargo install flutter_rust_bridge_codegen --version 2.12.0`), el
`Cargo.toml` de `nexodeck-ffi`, y `app/pubspec.yaml`. No subir a 2.13 (beta)
sin evaluarlo explícitamente.
