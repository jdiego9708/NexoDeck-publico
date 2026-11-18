---
name: protocol-message
description: Cómo añadir un nuevo tipo de mensaje al protocolo NexoDeck (nexodeck-protocol) sin romper la serialización postcard.
---

# protocol-message

`core/crates/nexodeck-protocol/src/lib.rs` define `NexoDeckMessage` (enum
raíz versionado) y `MessageV1` (las variantes del protocolo v1).

## Agregar una variante nueva a `MessageV1`

1. Agrega la variante al enum `MessageV1`, con los campos que necesite.
2. **No uses** `#[serde(tag = ..., content = ...)]`, `#[serde(untagged)]` ni
   `#[serde(flatten)]` en `NexoDeckMessage` ni `MessageV1` — postcard/bincode
   no soportan `deserialize_any`, así que el enum debe quedar *externally
   tagged* (el default de serde). Ver
   [`docs/architecture-decision-records/0001-postcard-sobre-json.md`](../../../docs/architecture-decision-records/0001-postcard-sobre-json.md).
3. Agrega un test de round-trip (`postcard::to_allocvec` /
   `postcard::from_bytes`) para la variante nueva, siguiendo el patrón de
   `roundtrip_ping`/`roundtrip_pong` ya existente.
4. Corre `dart run melos run rust:test` (o `cargo test -p nexodeck-protocol`)
   para confirmar el round-trip antes de exponer la variante en
   `nexodeck-ffi` o en `nexodeck-transport`.

## Cambios que rompen compatibilidad

Si una variante existente cambia de forma incompatible (reordenar campos,
cambiar tipos), considera si amerita un `NexoDeckMessage::V2` en vez de
modificar `V1` in-place — el protocolo corre entre dos binarios (PC y
Android) que pueden no actualizarse al mismo tiempo.
