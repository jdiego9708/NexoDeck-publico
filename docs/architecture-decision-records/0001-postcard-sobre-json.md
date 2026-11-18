# ADR 0001 — Serialización del protocolo: postcard sobre JSON/bincode

## Contexto

`nexodeck-protocol` define los mensajes que viajan entre el core en la PC y
el core en el dispositivo secundario (Android), sobre 3 transportes:
USB, BLE y WiFi. BLE en particular tiene un MTU limitado, así que el overhead
por mensaje importa de forma directa en throughput y latencia.

## Decisión

Se serializa con **postcard**, no JSON ni bincode.

- **JSON** queda descartado: es texto, verboso, y su overhead es significativo
  frente al ancho de banda disponible en BLE.
- **postcard** sobre **bincode**: postcard fue diseñado para entornos
  embebidos/`no_std` (firmware BLE, microcontroladores), y produce salidas
  más compactas que bincode en structs/enums con campos opcionales — el caso
  típico de `NexoDeckMessage`. Es además la opción que prioriza el documento
  de arquitectura del proyecto.

## Consecuencias

**postcard y bincode son formatos binarios no autodescriptivos** (no
soportan `deserialize_any`). Esto impone una restricción real sobre cómo se
puede modelar el enum de mensajes:

- **No se puede usar** `#[serde(tag = "type", content = "payload")]`
  (representación *adjacently tagged*) — el snippet original del documento
  de arquitectura lo usaba como ejemplo ilustrativo, pero fallaría en
  runtime la primera vez que se intentara un round-trip real con postcard.
- **No se puede usar** `#[serde(untagged)]` ni `#[serde(flatten)]` por la
  misma razón.
- Todo el esquema de mensajes (`NexoDeckMessage`, `MessageV1` y las
  variantes futuras: `Pairing`, `HardwareSnapshot`, `ExecuteAction`, `Alert`,
  `Ack`) debe modelarse con la representación **externally tagged** por
  defecto de serde (el índice de variante viaja como prefijo del payload).

Ver `core/crates/nexodeck-protocol/src/lib.rs` para el enum actual y su test
de round-trip.
