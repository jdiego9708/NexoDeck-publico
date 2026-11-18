# NexoDeck

**Un centro de control para tu PC, desde el móvil o desde la propia pantalla.**
Un stream deck virtual multiplataforma (Windows, Linux, Android) con métricas del equipo en vivo,
acciones y macros, un asistente de IA que corre en local y un servidor MCP para que otros agentes
puedan operarlo.

> **Idea, producto y decisiones: mías. Código: escrito con IA, bajo mis reglas.**
> NexoDeck nace de una necesidad propia. La arquitectura, los límites de seguridad, las decisiones
> y la verificación en hardware real son trabajo mío; la mayor parte del código la escribe un
> agente de IA (Claude Code) siguiendo reglas que yo fijo y reviso. No lo escondo: **71 de los 96
> commits llevan la coautoría de Claude declarada** en el historial. Cómo trabajo así, y por qué
> eso importa, está en [`docs/COMO-SE-CONSTRUYO.md`](./docs/COMO-SE-CONSTRUYO.md).

Estado: **v0.1.0, en desarrollo activo** (primer commit el 17 de julio de 2026). Todavía no hay
versión publicada para descargar. Es un proyecto personal, no un producto de cliente.

---

## Qué hace

| Capacidad | Cómo |
|---|---|
| **Métricas en vivo** | CPU, RAM, disco y red; GPU NVIDIA por NVML y GPU AMD sin SDK (PDH + DXGI + ADL); temperatura de CPU con un sidecar en .NET |
| **Acciones y macros** | Terminal, portapapeles y ejecución como administrador, con parámetros `{{variable}}` y macros de varios pasos |
| **Móvil Android** | Emparejamiento por PIN en ambos lados, WebSocket sobre TLS con *certificate pinning* y descubrimiento automático por mDNS |
| **Fuera de la red local** | Un relay propio (`nexodeck-relay`) que empalma dos conexiones entrantes por token y nunca ve el contenido |
| **Por USB, sin depurar** *(en curso)* | Transporte sobre Android Open Accessory, sin pedirle al usuario Modo Desarrollador. Hecho: handshake AOA y puente del lado PC; el resto está en marcha ([ADR 0002](./docs/architecture-decision-records/0002-aoa-sobre-adb.md)) |
| **Asistente de IA local** | `llama-server` (llama.cpp) como sidecar que elige CUDA, Vulkan o CPU según el hardware; Ollama o un servicio remoto como alternativas ([ADR 0003](./docs/architecture-decision-records/0003-sidecar-llamacpp-sobre-embebido.md)) |
| **Servidor MCP local** | Un agente externo puede consultar y operar NexoDeck; con token, comparación sin fuga de tiempo y rechazo de `Host`/`Origin` ajenos aunque el token sea correcto |
| **Notas con IA** | Markdown plano compatible con Obsidian, índice en memoria, editor CodeMirror 6 en WebView2. La IA propone; **yo apruebo viendo el antes y el después** |
| **Secretos** | Nunca tocan la base de datos ni Dart en texto plano: viven cifrados en `nexodeck-vault` (Rust) |

## Arquitectura en una imagen

```
            Flutter (una sola UI: Windows, Linux, Android)
                          │  flutter_rust_bridge
                          ▼
              nexodeck-ffi  ← único crate que ve Dart
                          │
   ┌───────────┬──────────┼───────────┬───────────┬──────────┐
 hardware   actions    transport     ai        control     docs
 (métricas) (acciones) (TLS, mDNS,  (llama.cpp (servidor   (notas +
                       USB, relay)   Ollama)    MCP)        editor)
        protocolo binario con postcard · bóveda de secretos · SQLite (Drift)
```

Reglas que no se negocian, y están escritas en [`CLAUDE.md`](./CLAUDE.md):

1. Solo `nexodeck-ffi` se expone a Dart.
2. Nunca JSON en el protocolo: se serializa con `postcard` ([ADR 0001](./docs/architecture-decision-records/0001-postcard-sobre-json.md)).
3. Los secretos no pasan por Dart ni por la base de datos.

## Números (medidos en el repositorio)

| | |
|---|---|
| Crates de Rust | **14** en un workspace de Cargo |
| Código Rust | ~54.000 líneas |
| Código Dart (sin generado) | ~51.000 líneas |
| Pruebas | más de **600** de Rust y 51 ficheros de prueba de Flutter |
| Historial | 96 commits, del 17 de julio al 29 de septiembre de 2026 |
| Decisiones de arquitectura documentadas | 4 ADR y 10 notas de ideas en [`docs/`](./docs) |

## Verificado en hardware real, no solo "compila"

- **De punta a punta con un teléfono Android físico:** emparejamiento PIN a PIN, reconexión con la
  huella TLS fijada, las cinco métricas del PC en vivo en el teléfono y una acción ejecutada
  remotamente. Con capturas y registros, no con "el build no falló".
- **GPU NVIDIA y AMD** contra tarjetas reales, con valores que varían de forma plausible.
- **APK comprobado por dentro:** se verifica que `libnexodeck_ffi.so` está en las tres arquitecturas.
  Esa comprobación existe porque durante meses el APK se generaba "con éxito" sin la librería
  nativa y nadie lo notó.

## Qué falta, dicho claro

- No hay versión publicada ni instalador distribuido todavía.
- El transporte por USB está a medias: el handshake AOA y el puente del lado PC funcionan, falta cerrarlo de punta a punta.
- Un solo dispositivo emparejado activo del lado Android (la PC admite varios).
- El PIN de emparejamiento es una confirmación visual entre dos personas, no está atado
  criptográficamente a la sesión TLS: es una limitación conocida del primer contacto, documentada.
- El plan y lo pendiente están en [`docs/ESTADO-DEL-PROYECTO.md`](./docs/ESTADO-DEL-PROYECTO.md).

## Hacia dónde puede ir

Mi visión y los argumentos de por qué creo que hay recorrido están en
[`docs/VISION.md`](./docs/VISION.md). Es opinión mía, y la separo de lo ya construido.

## Cómo compilarlo

```sh
dart pub get                         # resuelve el workspace raíz (incluye Melos)
dart run melos bootstrap             # flutter pub get dentro de app/
dart run melos run setup             # dependencias del build_tool de cargokit (una vez por máquina)
dart run melos run rust:build        # cargo build de todo el workspace
dart run melos run rust:test         # cargo test de todo el workspace
dart run melos run app:analyze       # flutter analyze
dart run melos run bridge:gen        # regenera los bindings del bridge FFI
```

Para ejecutar (desde `app/`): `flutter run -d windows` (o `-d linux`, o `-d <dispositivo-android>`).
Requisitos y trampas conocidas al mover el proyecto de equipo: sección *Setup en una máquina nueva* de
[`CLAUDE.md`](./CLAUDE.md).

## Licencia

**Todos los derechos reservados.** El código es visible para que se pueda evaluar mi trabajo, pero no
se concede licencia de uso, copia ni redistribución. Detalles en [`LICENSE`](./LICENSE). Si te interesa
colaborar o hablar de usarlo, escríbeme.

## Autor

**Juan Diego Duque** · Arquitecto de software · Manizales, Colombia
[Portafolio](https://jdiego9708.github.io/portafolio) ·
[LinkedIn](https://www.linkedin.com/in/juan-diego-duque-599b1225b/) ·
[Torre](https://torre.ai/juandiegoduquelondono)
