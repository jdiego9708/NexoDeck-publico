# ADR 0002 — Transporte USB: AOA sobre ADB

## Contexto

El documento de arquitectura especificaba originalmente la Fase 5
(transporte USB) como "túnel vía ADB forward/reverse como primera versión
funcional; documentar migración futura a AOA nativo". Antes de empezar a
implementar esa fase (100% greenfield — no hay ningún código, dependencia
ni configuración de USB/ADB/AOA en el repo todavía), se revisó ese plan.

ADB (Android Debug Bridge) requiere que el usuario final active **Modo
Desarrollador + Depuración USB** en su teléfono para que un túnel
`adb forward`/`reverse` funcione. Eso es aceptable para probar durante el
desarrollo, pero inaceptable como requisito permanente para el usuario
final de un producto terminado — expone opciones de desarrollador,
requiere pasos de configuración no triviales, y depende de que el
usuario tenga instalado el Android SDK Platform Tools o al menos el
binario `adb`.

## Decisión

Usar **AOA (Android Open Accessory)** nativo desde el principio, sin pasar
por ADB como "primera versión". AOA es el protocolo estándar de Android
(disponible desde API 12, vigente sin deprecación hasta la actualidad)
diseñado exactamente para que un host USB hable con el teléfono sin ADB
ni modo desarrollador.

Diseño resultante (detalle completo en la Fase 5 del documento de
arquitectura):

- Handshake AOA (3 control transfers vendor-specific: `ACCESSORY_GET_PROTOCOL`,
  `ACCESSORY_SEND_STRING`, `ACCESSORY_START`) implementado a mano sobre
  **`nusb`** (puro Rust, sin depender de libusb del sistema) en un nuevo
  módulo `nexodeck-transport::usb`, reusando el mismo framing (`wire.rs`)
  y los mismos `ConnectionEvent` que ya usa el transporte WiFi (Fase 4).
- Lado Android: código Kotlin mínimo (patrón de la skill
  `kotlin-android-plugin`) que abre el accessory y pasa el file
  descriptor crudo a Rust vía FFI — Dart nunca toca bytes del protocolo.

## Consecuencias

- **Windows requiere instalar un driver WinUSB, y confirmamos que hace
  falta en DOS momentos, no solo uno** (validado con un spike real contra
  un Samsung Galaxy S928B en Windows 11, no solo teoría):
  1. **Sobre el dispositivo en su modo normal.** `nusb` no pudo reclamar
     ninguna de las 4 interfaces del teléfono —
     `incompatible driver is installed for this device` — porque Windows
     ya tenía atado el driver propietario de Samsung (`dg_ssudbus`) a
     todo el compuesto, incluida la interfaz ADB (que en teoría tiene
     auto-asociación WinUSB desde Android 10, pero el driver de Samsung
     la pisa). **Esto no es un caso raro de este teléfono/esta PC**: el
     driver se asocia por Vendor ID contra el driver store de Windows —
     cualquier PC que alguna vez haya tenido un Android de esa marca
     conectado (algo tan común como "conectar el teléfono para pasar
     archivos") va a tener el mismo problema con cualquier otro
     dispositivo de esa marca.
  2. **Sobre el VID/PID de accessory mode** (`0x18D1`/`0x2D00`/`0x2D01`)
     una vez hecho el handshake — el driver de kernel de accessory mode
     de Android (`f_accessory.c`, AOSP) no implementa Microsoft OS
     Descriptors, así que ese dispositivo aparece siempre como "Unknown
     device" sin asociación automática.

  Ambos se resuelven con **`libwdi`** (la librería detrás de Zadig) para
  instalar el driver por código con un solo UAC, en vez de pedirle al
  usuario que use Zadig manualmente — no requiere certificado de firma
  propio (usa un coinstalador WinUSB ya firmado por Microsoft). El punto
  (1) se puede ofrecer apenas se detecta el teléfono conectado; el (2)
  recién cuando aparece el nuevo VID/PID tras el handshake.
- **Linux no tiene este problema** — una regla de udev simple alcanza.
- **Ya no es un riesgo abierto** (era el "Hito 0" de la Fase 5 del
  documento de arquitectura) — se corrió el spike contra hardware real y
  se confirmó el escenario más pesimista de los dos contemplados: hace
  falta instalar el driver en ambos momentos, no solo después del
  handshake. El flujo de primer uso de Fase 5/10 debe diseñarse asumiendo
  esto como el caso normal, no como corner case.
- Both ADB y AOA quedan mutuamente disponibles a nivel de protocolo del
  teléfono (el PID `0x2D01` es "accessory + ADB simultáneo"), así que
  nada impide seguir usando ADB como herramienta de *desarrollo* (logs,
  depuración) en paralelo — lo que cambia es que el producto final no
  depende de él para funcionar.
