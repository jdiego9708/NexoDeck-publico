# NexoDeck — Arquitectura Técnica y Plan de Implementación por Fases

**Stack final:** Rust (core compartido) + Flutter (única capa de UI: Windows, Linux, Android)
**Fecha de referencia:** julio 2026

---

## 0. Qué es NexoDeck

Un "streamdeck" virtual y multiplataforma que conecta tu PC con un dispositivo secundario (tablet/celular) como panel de control físico-virtual. No es una herramienta exclusiva para programadores: el motor de acciones (snippets/comandos) y el monitoreo de hardware sirven para cualquier flujo de trabajo que se beneficie de botones de acceso rápido y visibilidad del estado de la máquina, entre ellos:

- **Desarrolladores**: correr migraciones, levantar contenedores, pegar snippets de código.
- **Streamers / creadores en vivo**: cambiar de escena en OBS, silenciar/activar micrófono, disparar alertas de Twitch, lanzar overlays, todo mientras ves en el panel si tu CPU/GPU están al límite durante la transmisión.
- **Editores de video/audio**: aplicar presets de exportación, abrir proyectos recientes de Premiere/DaVinci/Resolve, lanzar renders en segundo plano y vigilar temperatura de GPU durante el render.
- **Cualquier flujo repetitivo de escritorio**: abrir conjuntos de apps, pegar plantillas de texto, ejecutar scripts de automatización personal.

El nombre "Nexo" refleja justamente eso: un punto central que conecta tu PC, tus acciones automatizadas y tus dispositivos secundarios, sin importar el oficio de quien lo use.

---

## 1. Resumen ejecutivo de la arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER (UI unificada)                  │
│   Windows · Linux · Android — un solo árbol de widgets       │
│   Riverpod 3 (estado) · Drift (BD local) · go_router (nav)   │
└───────────────────────────┬────────────────────────────────┘
                             │  flutter_rust_bridge 2.x (FFI)
┌───────────────────────────┴────────────────────────────────┐
│                  RUST CORE (nexodeck-core)                   │
│  ┌────────────┐ ┌──────────────┐ ┌─────────────────────┐    │
│  │  hardware  │ │   protocol    │ │      transport        │    │
│  │  sysinfo   │ │  serde+bincode│ │  usb (adb-tunnel/AOA)  │    │
│  │  nvml-wrap │ │  mensajes v1  │ │  ble (btleplug)         │    │
│  │  (Windows/ │ │  pairing      │ │  wifi (tokio-tungstenite│    │
│  │   Linux)   │ │  auth         │ │        + mdns)         │    │
│  └────────────┘ └──────────────┘ └─────────────────────┘    │
│  ┌────────────┐ ┌──────────────┐                            │
│  │  actions   │ │   secrets     │                            │
│  │  engine    │ │  vault (age/  │                            │
│  │  (clipboard│ │  chacha20)    │                            │
│  │  / exec)   │ │               │                            │
│  └────────────┘ └──────────────┘                            │
└────────────────────────────────────────────────────────────┘
```

**Principio rector:** Rust es el único lugar donde vive lógica sensible a rendimiento, seguridad o hardware. Flutter es el único lugar donde vive UI. Nada se duplica entre plataformas.

> Nota de nomenclatura: renombré internamente el módulo antes llamado "snippets engine" a **"actions engine"**, porque el concepto ya no es solo "fragmento de código" — es cualquier acción disparable (comando de terminal, texto a pegar, macro de varios pasos, atajo hacia otra app). Esto se refleja en el nombre de tablas, crates y carpetas a lo largo de todo el documento.

---

## 2. Estructura de carpetas del monorepo

Uso **Melos** para gestionar el monorepo Flutter+Rust como un solo workspace con scripts compartidos (bootstrap, lint, test, build multiplataforma).

```
nexodeck/
├── melos.yaml
├── README.md
├── CLAUDE.md                       # instrucciones de proyecto para Claude Code
│
├── .claude/
│   └── skills/                     # Skills de IA específicas de ESTE proyecto
│       ├── rust-ffi-bridge/
│       │   └── SKILL.md            # cómo generar/actualizar bindings frb
│       ├── flutter-riverpod-feature/
│       │   └── SKILL.md            # scaffolding de una feature nueva (provider+repo+ui)
│       ├── drift-migration/
│       │   └── SKILL.md            # cómo crear/versionar migraciones de BD
│       ├── kotlin-android-plugin/
│       │   └── SKILL.md            # (si se necesita código Android nativo puntual)
│       └── protocol-message/
│           └── SKILL.md            # cómo añadir un nuevo tipo de mensaje al protocolo
│
├── core/                           # ---- RUST WORKSPACE ----
│   ├── Cargo.toml                  # workspace root
│   ├── crates/
│   │   ├── nexodeck-hardware/      # lectura de sensores (CPU/GPU/RAM/disco)
│   │   ├── nexodeck-protocol/      # esquema de mensajes + (de)serialización
│   │   ├── nexodeck-transport/     # USB / BLE / WiFi, trait Transport unificado
│   │   ├── nexodeck-actions/       # motor de ejecución (clipboard/terminal/admin/macros)
│   │   ├── nexodeck-vault/         # secretos cifrados
│   │   ├── nexodeck-db/            # capa de acceso a SQLite compartida (opcional)
│   │   └── nexodeck-ffi/           # crate que expone todo vía flutter_rust_bridge
│   └── tests/                      # tests de integración cross-crate
│
├── app/                            # ---- FLUTTER APP ----
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── bridge_generated/       # código autogenerado por flutter_rust_bridge (NO editar a mano)
│   │   ├── core/
│   │   │   ├── router/             # go_router
│   │   │   ├── theme/              # design tokens compartidos
│   │   │   └── di/                 # providers globales (Riverpod)
│   │   ├── data/
│   │   │   ├── local/              # Drift: tablas, DAOs
│   │   │   └── repositories/       # implementación de repos (llaman al bridge Rust)
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── repositories/       # contratos abstractos
│   │   └── features/               # feature-first
│   │       ├── dashboard/
│   │       │   ├── application/    # providers (@riverpod)
│   │       │   ├── presentation/   # widgets, pantallas
│   │       │   └── domain/
│   │       ├── actions/            # antes "snippets" — botones/tarjetas de acción
│   │       ├── pairing/
│   │       ├── settings/
│   │       ├── profiles/           # perfiles por contexto: "Streaming", "Desarrollo", "Edición"
│   │       └── compact_overlay/    # modo "deck" anclado
│   ├── android/                    # proyecto Android nativo embebido por Flutter
│   ├── windows/
│   ├── linux/
│   └── test/
│
├── docs/
│   ├── protocol-spec.md            # especificación versionada del protocolo de mensajes
│   ├── architecture-decision-records/  # ADRs (por qué Drift, por qué Riverpod, etc.)
│   └── schemas/
│       └── db-schema.dbml
│
└── scripts/
    ├── gen-bridge.sh                # regenera bindings FFI
    └── ci/
```

### ¿Por qué una carpeta `.claude/skills/` propia del proyecto?

Además de los skills públicos de Claude Code, conviene documentar **patrones específicos de tu arquitectura** como skills propias del repo. Cada vez que le pidas a Claude Code "crea una nueva acción tipo macro" o "agrega un nuevo tipo de sensor", el skill correspondiente le dice exactamente qué archivos tocar, qué convenciones seguir y qué generadores correr — esto evita que cada sesión "reinvente" la estructura y mantiene consistencia entre features generadas en momentos distintos.

---

## 3. Rust Core — arquitectura interna

### 3.1 Organización en crates (no un solo crate monolítico)

Divido el core en crates independientes dentro de un workspace de Cargo, no un solo crate gigante, por tres razones concretas: (1) tiempos de compilación — cambiar `nexodeck-actions` no recompila `nexodeck-hardware`; (2) límites de responsabilidad claros y testeables por separado; (3) permite en el futuro reutilizar, por ejemplo, `nexodeck-hardware` en otro proyecto sin arrastrar todo lo demás.

| Crate | Responsabilidad | Dependencias clave |
|---|---|---|
| `nexodeck-hardware` | Polling de CPU, GPU, RAM, disco, red | `sysinfo`, `nvml-wrapper` (NVIDIA), `wmi` (Windows extra), `sensors`/`lm-sensors` bindings (Linux) |
| `nexodeck-protocol` | Definición de mensajes, versión de esquema, (de)serialización | `serde`, `bincode` o `postcard` |
| `nexodeck-transport` | Trait `Transport` + 3 implementaciones (USB/BLE/WiFi) | `nusb`, `btleplug`, `tokio-tungstenite`, `mdns-sd` |
| `nexodeck-actions` | Motor de ejecución: portapapeles, terminal, permisos admin, macros encadenadas | `arboard` (clipboard cross-platform), `std::process::Command` |
| `nexodeck-vault` | Cifrado de secretos en reposo | `age` o `chacha20poly1305` + `argon2` para derivar clave desde PIN/contraseña maestra |
| `nexodeck-db` | (opcional) acceso a SQLite desde Rust si hay tablas que solo le interesan al core | `rusqlite` |
| `nexodeck-ffi` | Única puerta de entrada expuesta a Dart | `flutter_rust_bridge` |

**Regla de dependencia:** todos los crates dependen "hacia adentro" de `nexodeck-protocol` (los mensajes son el contrato común), pero `nexodeck-ffi` es el único punto que Flutter puede tocar — nunca se expone un crate interno directamente al bridge.

### 3.2 Patrón de concurrencia

El core corre sobre **Tokio** como runtime async. La razón: vas a tener simultáneamente un polling de hardware (cada ~1s), un listener de transporte (USB/BLE/WiFi escuchando conexiones entrantes), y comandos disparados por el usuario desde Flutter — todo debe convivir sin bloquear. `flutter_rust_bridge` 2.x tiene soporte nativo para exponer `Stream<T>` de Rust hacia Dart, así que el patrón correcto es:

```rust
// nexodeck-ffi/src/api/hardware.rs
pub fn watch_hardware_metrics() -> impl Stream<Item = HardwareSnapshot> {
    // Rust empuja snapshots cada N ms; Dart los consume como StreamProvider en Riverpod
}
```

Esto evita el antipatrón de "polling desde Dart llamando a Rust cada segundo" — en vez de eso, Rust empuja datos cuando los tiene, con backpressure manejado por el propio stream.

### 3.3 Esquema del protocolo de mensajes (resumen)

Define un enum central versionado desde el día uno, porque vas a tener el core en la PC y otro corriendo del lado Android hablando el mismo idioma sobre 3 transportes distintos:

```rust
#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum NexoDeckMessage {
    V1(MessageV1),
}

pub enum MessageV1 {
    Pairing(PairingRequest),
    HardwareSnapshot(HardwareSnapshot),
    ExecuteAction { action_id: Uuid, input: Option<String> },
    Alert { level: AlertLevel, text: String },
    Ack { message_id: Uuid },
    // ...
}
```

Serializar con **`bincode`** o **`postcard`** (más compacto, pensado para embebidos/BLE donde el MTU es limitado) en vez de JSON — para BLE especialmente, el overhead de JSON es significativo frente al ancho de banda disponible.

---

## 4. Flutter — arquitectura interna

### 4.1 Manejo de estado: Riverpod 3 con codegen

**Decisión: Riverpod 3.x con `@riverpod` (code generation), no Bloc, no Provider clásico, no GetX.**

Justificación concreta para tu caso, no genérica:

- Vas a tener **muchos streams asíncronos concurrentes** (métricas de hardware en vivo, estado de conexión del transporte, alertas entrantes). El patrón `AsyncValue` de Riverpod (`data`/`loading`/`error` unificado) encaja exactamente con "estoy escuchando un stream de Rust que puede fallar o desconectarse".
- No depende de `BuildContext`, lo cual importa porque tu modo "overlay compacto anclado" va a vivir fuera del árbol de navegación normal (una ventana separada en desktop) — necesitas leer/escribir estado sin garantía de tener un context de widget a mano.
- Seguridad de tipos en compilación: un error en cómo conectas un provider te lo marca el compilador, no en tiempo de ejecución en plena transmisión en vivo mientras pruebas un botón nuevo.
- Es la opción con más consenso actual como default razonable para proyectos nuevos, dejando Bloc como alternativa válida solo si priorizas trazabilidad estricta de eventos (más pensado para fintech/salud que para tu caso).

### 4.2 Base de datos local: ORM (Drift) sobre SQL raw puro

**Decisión: Drift, no `sqlite3`/`sqflite` con SQL escrito a mano.**

1. **Migraciones**: vas a iterar mucho el esquema al principio (tabla de acciones, tabla de perfiles, tabla de dispositivos emparejados, historial de métricas). Drift genera migraciones versionadas y verificadas en compilación.
2. **Reactividad nativa**: Drift convierte cualquier query en un `Stream` que se re-emite automáticamente cuando cambian los datos subyacentes — encaja perfecto con Riverpod para, por ejemplo, refrescar la lista de acciones en la UI en cuanto agregas una nueva, sin lógica manual de invalidación.
3. **Type-safety real**: cada tabla se convierte en clases Dart tipadas.
4. **Concurrencia segura**: Drift puede correr SQLite en un isolate separado, evitando que una query pesada bloquee el hilo de UI — relevante porque tu app necesita sentirse instantánea al estar anclada en pantalla mientras streameas o editas.

**Nota de arquitectura importante:**
- **Drift (Dart)** para todo lo que la UI necesita leer reactivamente: acciones, perfiles, historial corto de métricas, configuración de dispositivos.
- **`nexodeck-vault` (Rust)** para secretos — nunca pasan por Drift/Dart en texto plano.

### 4.3 Estructura de features (feature-first + capas)

Cada feature (`dashboard`, `actions`, `pairing`, `settings`, `profiles`) sigue la misma estructura interna:

```
features/actions/
├── domain/          # entidades puras (DeckAction, ActionType) — sin dependencias de Flutter ni Drift
├── application/      # providers @riverpod: ActionListProvider, ExecuteActionProvider
├── data/              # implementación concreta: ActionRepository (Drift + llamadas al bridge Rust)
└── presentation/      # widgets: ActionCard, ActionEditorSheet, CompactActionGrid
```

### 4.4 Modo compacto vs pantalla completa

Técnicamente, en Windows/Linux esto se resuelve con **múltiples `WindowController`** usando `desktop_multi_window` (o `window_manager` para controlar tamaño/posición/always-on-top de una sola ventana que cambia de layout). El modo compacto anclado es una ventana `alwaysOnTop: true`, sin decoración, con posición persistida en Drift (`x`, `y`, `monitor_id`). El modo pantalla completa es la ventana principal normal. Ambas comparten el mismo árbol de providers Riverpod.

En Android no aplica multi-ventana de la misma forma; ahí el "modo compacto" se traduce naturalmente a un **overlay tipo bubble** (`SYSTEM_ALERT_WINDOW`, similar a Messenger's Chat Heads) — esto sí requiere una pieza nativa Kotlin puntual, buen caso de uso para el skill `kotlin-android-plugin`.

### 4.5 Perfiles por contexto (más allá de desarrollo)

Un perfil es simplemente un conjunto de acciones visibles + configuración de alertas, activado manual o automáticamente. Ejemplos concretos que puedes precargar como plantillas:

- **Perfil "Streaming"**: botones para cambiar de escena en OBS (vía WebSocket de OBS), silenciar micrófono, disparar overlay de alerta, marcador de "clip destacado"; alerta configurada si la GPU supera cierta temperatura durante la transmisión.
- **Perfil "Edición de video"**: botones para presets de exportación, abrir carpeta de proyecto reciente, iniciar render en cola; alerta si la RAM se satura durante un render pesado.
- **Perfil "Desarrollo"**: comandos de terminal, git, snippets de código, migración de base de datos.
- **Perfil "Producción musical/podcast"**: pegar plantillas de show notes, lanzar el DAW con una plantilla de sesión, alternar interfaz de audio.

La detección de contexto (qué perfil mostrar) puede ser manual al inicio (un selector simple) y automática más adelante (detectar proceso en primer plano: OBS abierto → perfil Streaming).

---

## 5. Paquetes recomendados (verificados, estables, actualizados a julio 2026)

### 5.1 Lado Rust

| Crate | Uso | Estado |
|---|---|---|
| `flutter_rust_bridge` | Bridge FFI Rust↔Dart | Estable: **2.12.0**; hay una 2.13 en beta activa — usar la rama estable para producción |
| `sysinfo` | CPU, RAM, disco, red multiplataforma | Activo, actualizado recientemente, es el estándar de facto |
| `nvml-wrapper` | Telemetría GPU NVIDIA (temp, uso, fan, potencia) | Activo, mantenido, soporta NVML 12 |
| `nusb` | Acceso USB puro-Rust (para AOA, sin depender de libusb del sistema) | Activo, cross-platform |
| `btleplug` | BLE cross-platform (Windows/Linux/macOS/Android vía FFI) | Activo, actualizado |
| `tokio` + `tokio-tungstenite` | Runtime async + WebSocket para transporte WiFi | Estándar de la industria en Rust async |
| `mdns-sd` | Descubrimiento de dispositivos en red local | Activo, puro Rust |
| `serde` + `postcard`/`bincode` | Serialización del protocolo | Estándar |
| `age` o `chacha20poly1305` + `argon2` | Cifrado del vault de secretos | Auditados, recomendados para cifrado en reposo |
| `arboard` | Acceso al portapapeles cross-platform | Activo, usado en producción por otros proyectos Rust de escritorio |
| `rusqlite` (opcional) | SQLite desde Rust si el core necesita tocar BD directamente | Estándar, maduro |

> Nota sobre GPU AMD/Intel: `nvml-wrapper` solo cubre NVIDIA. Para AMD necesitarás leer contadores vía `sysfs` en Linux (`/sys/class/drm/`) y ADL/AGS en Windows — vale la pena tratarlo como funcionalidad de fase posterior, no bloqueante para el MVP.

### 5.2 Lado Flutter

| Paquete | Uso | Estado |
|---|---|---|
| `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` | Estado (versión 3.x, con codegen) | Recomendado como default 2026 |
| `drift` + `drift_flutter` + `sqlite3` | Base de datos local reactiva | Recomendado como default 2026, cross-platform incluyendo web si algún día lo necesitas |
| `go_router` | Navegación declarativa | Estándar recomendado por el equipo de Flutter |
| `window_manager` / `desktop_multi_window` | Control de ventana (modo compacto anclado, always-on-top) | Activos, ampliamente usados en apps de escritorio Flutter |
| `flutter_secure_storage` | Guardar tokens/claves de pairing (nunca en Drift plano) | Estándar |
| `freezed` + `json_serializable` | Modelado inmutable de entidades de dominio | Estándar, combina bien con Riverpod |
| `fl_chart` | Gráficas de métricas (historial corto de temperatura/uso) | Popular, buen rendimiento para actualizaciones frecuentes |

---

## 6. Seguridad (no negociable dado lo que hace la app)

Tu app ejecuta comandos del sistema, potencialmente como administrador, disparados desde un segundo dispositivo. Esto exige tratar la seguridad como requisito de diseño, no como afterthought:

- **Pairing con confirmación explícita**: el primer emparejamiento siempre requiere una acción física en ambos dispositivos (mostrar PIN en PC, confirmarlo en móvil), nunca auto-aceptar.
- **Todo el tráfico cifrado**, incluso en WiFi local — usa TLS con certificados autofirmados generados en el primer pairing y fijados (certificate pinning) para las conexiones siguientes.
- **Las acciones marcadas como "ejecutar como administrador" deben pedir confirmación explícita en la PC** antes de ejecutarse, no solo en el móvil.
- **Rate limiting / lista de dispositivos autorizados** revocable desde la PC en cualquier momento.
- **El vault de secretos nunca se sincroniza en texto plano** entre dispositivos.

---

## 7. Plan de implementación por fases

### Fase 0 — Cimientos (1–2 semanas)
- Setup del monorepo con Melos, workspace de Cargo, proyecto Flutter multiplataforma habilitado.
- `nexodeck-protocol`: definir el enum de mensajes v1 y escribir el ADR de por qué postcard/bincode sobre JSON.
- `nexodeck-ffi` mínimo: exponer una función de saludo Rust↔Dart para validar que el bridge compila en las 3 plataformas objetivo.
- CI básico en Windows y Linux runners.
- Escribir `CLAUDE.md` del proyecto y los primeros skills en `.claude/skills/`.

### Fase 1 — Lectura de hardware (2–3 semanas)
- `nexodeck-hardware`: snapshot de CPU, RAM, disco, red; `nvml-wrapper` para GPU NVIDIA.
- Exponer `watch_hardware_metrics()` como `Stream` vía flutter_rust_bridge.
- Feature `dashboard` con UI mínima de tarjetas de métricas.

### Fase 2 — Motor de acciones (2 semanas)
- `nexodeck-actions`: tipo "pegar en portapapeles" y tipo "ejecutar en terminal nueva" (con y sin admin).
- Modelo de datos en Drift: tabla `actions` (nombre, comando/script, action_type, requires_admin, parámetros, ícono).
- Feature `actions`: CRUD, editor de tarjetas, input dinámico para parámetros.
- Precargar 2-3 plantillas de ejemplo por perfil (dev, streaming, edición) para que el usuario vea el potencial desde el primer arranque.

### Fase 3 — Modo compacto / pantalla completa (1–2 semanas, solo desktop)
- `window_manager`/`desktop_multi_window`: alternar ventana anclada vs completa.
- Persistir posición/monitor en Drift.

### Fase 4 — Transporte WiFi + protocolo end-to-end (2–3 semanas)
- `nexodeck-transport`: WebSocket + mDNS.
- Flujo de pairing completo.
- Primera versión de la app Android para probar el protocolo de punta a punta.

### Fase 5 — Transporte USB (2 semanas)

**AOA (Android Open Accessory) nativo desde el principio — no ADB.** ADB
exige que el usuario final active Modo Desarrollador + Depuración USB en
su teléfono, inaceptable para un producto terminado; AOA es el protocolo
estándar de Android pensado exactamente para que un host hable con el
teléfono por USB sin eso. Ver
[`docs/architecture-decision-records/0002-aoa-sobre-adb.md`](./docs/architecture-decision-records/0002-aoa-sobre-adb.md).

- **Hito 0 — spike de viabilidad, YA CORRIDO contra hardware real** (Samsung
  Galaxy S928B, Windows 11): confirmado que **(b) falla siempre**. `nusb`
  no pudo reclamar NINGUNA de las 4 interfaces del dispositivo en su modo
  normal (`incompatible driver is installed for this device`) — Windows
  tenía atado el driver propietario de Samsung (`dg_ssudbus`, parte del
  paquete de driver USB que Windows Update instala automáticamente la
  primera vez que se conecta CUALQUIER Android de esa marca) a las 4
  interfaces del compuesto, incluida la de ADB (`class=0xFF subclass=0x42
  protocol=0x01`, la firma estándar de ADB) que en teoría tiene
  auto-asociación WinUSB desde Android 10.
  **Conclusión importante — esto no es un caso raro de esta máquina/este
  teléfono puntual**: el driver se asocia por Vendor ID (Samsung =
  `0x04E8`) contra el driver store de Windows, no por número de serie de
  un equipo — un segundo dispositivo Samsung nunca antes conectado, en la
  MISMA PC, pisaría exactamente igual. Y en la práctica es común que
  CUALQUIER PC Windows ya tenga instalado algún driver de fabricante
  Android (alcanza con haber conectado un teléfono una vez para "transferir
  archivos"/MTP). **Por lo tanto: el paso de instalar el driver WinUSB con
  `libwdi` no es un parche opcional para casos raros — hay que asumir que
  hace falta en el primer uso, casi siempre, en AMBAS etapas (interfaz
  original antes del handshake, Y el VID/PID de accessory mode después),
  y diseñar/probar el flujo de primer uso pensando en eso desde el día
  uno.**
- **Handshake AOA** (emitido por la PC/host contra el teléfono en su modo
  normal, 3 control transfers vendor-specific en EP0):
  1. `ACCESSORY_GET_PROTOCOL` (0x33, IN) — versión soportada.
  2. `ACCESSORY_SEND_STRING` (0x34, OUT) × N — manufacturer/model
     obligatorios (índices 0/1); description/version/uri/serial opcionales.
  3. `ACCESSORY_START` (0x35, OUT) — el teléfono se desconecta y se
     re-enumera como VID `0x18D1` (Google), PID `0x2D00` (accessory puro)
     o `0x2D01` (accessory + ADB si además está habilitado). A partir de
     ahí es un dispositivo USB genérico con 2 endpoints bulk in/out.
- **`nexodeck-transport::usb`** (nuevo módulo, rol PC/host, análogo a
  `server.rs`/`client.rs`): hace el handshake sobre `nusb`, y tras la
  re-enumeración corre el mismo loop de lectura/escritura enmarcada
  (`wire.rs`, sin cambios — USB es solo un canal de bytes distinto) que
  ya usan `server.rs`/`client.rs` para WebSocket, emitiendo los mismos
  `ConnectionEvent`. Se multiplexa junto a WiFi en `watch_connection_events`
  (`nexodeck-ffi/src/api/connection.rs`), igual que hoy ya multiplexa
  host+client de WiFi.
- **Lado Android (Kotlin)**: sigue el patrón de la skill
  `kotlin-android-plugin` (mismo `MainActivity.kt` que ya tiene
  `MulticastLock` de Fase 4). Manifest con
  `<uses-feature android.hardware.usb.accessory>` + intent-filter
  `USB_ACCESSORY_ATTACHED` + `accessory_filter.xml`. Al recibir el
  intent, `UsbManager.openAccessory()` y pasar el **file descriptor
  crudo** (`ParcelFileDescriptor.detachFd()`) a Rust vía FFI — nunca
  proxear bytes del protocolo a través de Dart; Rust envuelve el fd
  directo (`File::from_raw_fd`) y corre el mismo loop de framing.
- **El problema real de Windows (confirmado con hardware real, ver Hito 0
  arriba)**: hace falta instalar WinUSB por código con **`libwdi`** (la
  librería detrás de Zadig) en DOS momentos distintos del primer uso:
  1. Sobre el dispositivo en su modo normal (VID/PID del fabricante,
     ej. `04E8:6860`), reemplazando el driver de fabricante que
     probablemente ya esté atado — necesario para poder mandar el
     handshake AOA en absoluto.
  2. Sobre el VID/PID de accessory mode (`18D1:2D00`/`2D01`) una vez
     hecho el handshake — porque el driver de kernel de accessory mode
     (`f_accessory.c`, AOSP) no implementa Microsoft OS Descriptors, así
     que ese dispositivo aparece siempre como "Unknown device", sin
     asociación automática.
  Ambos casos usan el mismo mecanismo: `libwdi` genera e instala el
  driver con un solo UAC, sin mostrarle Zadig al usuario, con un
  coinstalador WinUSB ya firmado por Microsoft (no requiere certificado
  propio). El paso (1) sí se puede/debe ofrecer apenas se detecta el
  teléfono conectado (no hay que esperar al handshake); el paso (2) recién
  cuando aparece el nuevo VID/PID. Se integra en el instalador de Fase 10,
  pero es utilizable ya en desarrollo.
- **Linux**: no tiene este problema — una regla de udev
  (`SUBSYSTEM=="usb", ATTRS{idVendor}=="18d1", MODE="0666"`) alcanza, sin
  driver de kernel adicional. Se incluye en el paquete `.deb`/`AppImage`
  de Fase 10.

### Fase 6 — Transporte Bluetooth (2 semanas)
- BLE con `btleplug` + plugin Kotlin del lado Android.

### Fase 7 — Vault de secretos y acciones con variables dinámicas (1–2 semanas)
- Cifrado con `age`/`chacha20poly1305` + `argon2`.
- Variables dinámicas: rama git activa, fecha, clipboard actual, nombre de escena activa en OBS, etc.

### Fase 8 — Alertas bidireccionales y notificaciones (1–2 semanas)
- Mensajes `Alert` en ambas direcciones; reglas configurables de umbral (temperatura, uso de RAM/disco).

### Fase 9 — Perfiles por contexto y macros (2–3 semanas)
- Perfiles (Streaming, Edición, Desarrollo, personalizados) con detección manual y luego automática por proceso activo.
- Macros: cadenas de acciones ejecutadas en secuencia.
- Historial con gráficas (`fl_chart`).
- Export/import de "decks" en JSON para compartir configuraciones.

### Fase 10 — Empaquetado, firma y distribución (1–2 semanas)
- Windows: instalador (`.msix` o Inno Setup), firma de código.
- Linux: `.deb`/`.AppImage`/Flatpak.
- Android: firma de APK/AAB.
- Congelar `docs/protocol-spec.md` como v1 estable.

---

## 8. Resumen de decisiones clave (para referencia rápida)

| Decisión | Elegido | Alternativa descartada | Por qué |
|---|---|---|---|
| Nombre del proyecto | **NexoDeck** | DevDeck | Enfoque ampliado: no solo desarrolladores, sino streamers, editores, creadores y cualquier flujo de escritorio |
| Lenguaje del core | Rust | C++ | Memory-safety + ecosistema de crates ya maduro |
| UI multiplataforma | Flutter único | Tauri+Svelte / KMP / React Native | Una sola base de UI para desktop+Android, con Rust como cerebro compartido vía FFI |
| Puente Rust↔Flutter | flutter_rust_bridge 2.x | JNI a mano | Generador de bindings maduro, con soporte de Streams |
| Estado | Riverpod 3 (codegen) | Bloc / GetX / Provider | Mejor ajuste para múltiples streams async concurrentes, sin BuildContext |
| Base de datos | Drift (ORM) | SQL raw (sqflite/sqlite3) | Migraciones seguras, reactividad nativa, type-safety, modelo relacional |
| Transporte primario | USB (AOA nativo, sin ADB) | Túnel ADB forward/reverse | ADB exige Modo Desarrollador + Depuración USB en el teléfono, inaceptable para un producto terminado; AOA es el protocolo estándar de Android para esto |
| Transporte secundario | BLE (btleplug) | Bluetooth Classic | Mejor soporte cross-platform en Rust |
| Transporte terciario | WebSocket + mDNS | Solo ADB | Fallback simple sin cable ni pairing BLE |
| Serialización protocolo | postcard/bincode | JSON | Mucho más compacto, crítico para BLE |
| Secretos | Vault cifrado en Rust (age/chacha20) | Guardar en Drift plano | Nunca exponer secretos en texto plano ni en BD ni en tránsito |

---

Este documento está pensado como referencia viva: a medida que avances por las fases, actualiza la sección de ADRs en `docs/architecture-decision-records/` cada vez que una decisión aquí descrita cambie con la realidad del desarrollo.
