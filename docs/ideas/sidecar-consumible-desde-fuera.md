# Sidecar consumible desde fuera

**Especificación para otro agente. Escrita el 23 de septiembre de 2026. No contiene código.**

> Contexto: una tubería de automatización **externa** (Python + PowerShell, fuera de NexoDeck)
> necesita un motor de lenguaje. NexoDeck ya habla con tres proveedores OpenAI-compatibles, pero
> **hoy ninguno de sus motores locales es consumible desde otro programa de la máquina**. Este
> documento describe qué habría que hacer, y por qué puede que no haga falta.

---

## 1. Estado actual (verificado en el código, 23-sep-2026)

| Motor | Naturaleza | ¿Consumible desde fuera hoy? |
|---|---|---|
| **Sidecar `llama-server`** (llama.cpp propio) | Proceso hijo, HTTP en `127.0.0.1` con **puerto efímero** (`core/crates/nexodeck-ai/src/sidecar.rs:267`, `reserve_port`) | **No.** El puerto solo vive en memoria (`sidecar.rs:78-79`) y **no cruza el puente FFI** (`Engine::local_endpoint`, `engine.rs:160`, no está expuesto) |
| **Ollama** | Servicio HTTP preexistente en `http://127.0.0.1:11434` | **Sí**, directo. Y desde el 23-sep-2026 NexoDeck puede **encenderlo y apagarlo** (ver apartado 6) |
| **Remoto** (DeepSeek / OpenAI / proxy) | HTTP por internet | **Sí**, directo |
| **Servidor MCP** | HTTP en `127.0.0.1:58646`, 15 herramientas (`nexodeck-control/src/tools.rs:61-429`) | **No para inferencia**: ninguna herramienta genera texto |
| **Stack vLLM** (`llm-stack/`) | OpenAI-compatible en `llm-stack/scripts` (endpoints 8000-8002, router 8888) | **Sí**, directo |

**El sidecar no autentica nada** (`ChatProvider::api_key()` solo devuelve clave para `Remote`,
`provider.rs:58-65`) y **no se publica** en ningún fichero. Además, por diseño, **NexoDeck no lo
arranca desde el trabajador del buzón** para no quitarle la GPU a una tanda de ODM
(`engine.rs:154-166`). Ver también el [ADR 0003](../architecture-decision-records/0003-sidecar-llamacpp-sobre-embebido.md).

---

## 2. La decisión que hay que tomar **antes** de tocar nada

> **Si vLLM va a ser el motor de la tubería externa, NO hay que publicar el sidecar.**

La tubería Python puede hablar directo con el router vLLM (OpenAI-compatible, 8888) sin pasar por
NexoDeck. Eso es más simple, desacopla, y es el camino que ya está documentado en
`llm-stack/`. **Publicar el sidecar solo tiene sentido si se quiere usar el
`llama-server` de NexoDeck como backend** (por ejemplo, para aprovechar el modelo ya descargado y
el plan de runtime por hardware que NexoDeck resuelve solo).

Si la decisión es publicarlo, el plan es el del apartado 3.

---

## 3. Plan para publicar el sidecar (si se decide)

### Paso 1 — Autenticación y puerto (`sidecar.rs`)

- Pasar **`--api-key <token>`** al spawn (`sidecar.rs:118-136`). `llama-server` lo soporta; hoy no
  se usa.
- Decidir entre **puerto fijo configurable** o **mantener el efímero y publicarlo**. La
  recomendación es lo segundo: el comentario de `reserve_port` (`sidecar.rs:261-266`) explica por
  qué el puerto efímero es deliberado (un puerto fijo "choca de verdad y a menudo"). Publicar el
  que el SO ya eligió conserva ese razonamiento.

### Paso 2 — Publicar `{base_url, port, token}`

- Escribir un fichero, por ejemplo `ai/sidecar.json`, bajo `ai_root()`
  (`core/crates/nexodeck-ai/src/paths.rs`).
- **Precedente exacto:** `control_token.txt` en `nexodeck-control/src/lib.rs:337-363` (token
  persistido en el directorio de datos del usuario, no en Drift).
- Escritura **atómica** (temporal + `sync_all` + `rename`) y **borrado al apagar** el sidecar, para
  que un fichero presente signifique "hay un motor vivo".

### Paso 3 — Que el sidecar lleve clave

- `ChatProvider::api_key()` (`provider.rs:58-65`) debe devolver la clave **también para
  `Sidecar`**, no solo para `Remote`. `openai::list_models`/`stream_chat` ya ponen `bearer_auth`
  cuando la hay (`openai/mod.rs:52-54`).

### Paso 4 — Exponer el endpoint por FFI

- `Engine::local_endpoint()` (`engine.rs:160`) es el punto natural, pero **hoy no cruza el
  puente**. Añadir un DTO + comando en `core/crates/nexodeck-ffi/src/api/ai.rs`, siguiendo el
  patrón de `AiOllamaInstallation` (`ai.rs:150` y `ai.rs:701`), que devuelva `base_url`, `port` y
  `token`.
- **Regenerar los bindings:** `dart run melos run bridge:gen` (el `cargo check` de `nexodeck_ffi`
  falla en `frb_generated.rs` hasta regenerar).

### Paso 5 — UI (opcional)

- Mostrar la dirección y el token donde ya se muestra el estado de la IA (`aiSetupStateProvider`,
  `app/lib/features/ai_assistant/application/ai_providers.dart:128`). No existe hoy un panel de
  estado del sidecar.

---

## 4. Cuidados (no romper lo que ya está resuelto)

- **Mantener el Job Object** (`sidecar.rs:309-396`) y el apagado ordenado (`shutdown`,
  `sidecar.rs:245-248`): son la red de seguridad contra un cierre de golpe de NexoDeck.
- **No relajar el diseño del puerto efímero** sin justificarlo por escrito; el comentario de
  `reserve_port` es la razón.
- **El token va al directorio de datos del usuario**, nunca a Drift ni al repo (regla de secretos
  del proyecto; `nexodeck-vault` sigue siendo un stub, Fase 7).
- **Android:** `nexodeck-ai` entra bajo `cfg(not(target_os = "android"))`; las funciones FFI
  existen en las tres plataformas y en Android devuelven error claro (patrón de `api/ai.rs:10-20`).
- **No arrancar el sidecar desde el trabajador del buzón** (`engine.rs:154-166`): la GPU es
  compartida con las tandas de ODM.

---

## 5. Verificación

- Rust: test inline del nuevo fichero de publicación (patrón de `sidecar.rs:420-495`).
- `dart run melos run rust:test` y `dart run melos run app:analyze`.
- Manual: levantar el sidecar, leer `ai/sidecar.json`, hacer un `POST /v1/chat/completions` con el
  token desde un cliente externo (PowerShell `Invoke-RestMethod`), comprobar 401 sin token y 200
  con él.

---

## 6. Lo que ya está hecho: encender/apagar Ollama (23-sep-2026)

Como parte del mismo trabajo, Ollama dejó de ser "solo detección": ahora se puede **encender y
apagar desde el menú «Más»** de NexoDeck.

- **Rust:** `core/crates/nexodeck-ai/src/ollama.rs` (`status()`, `start()`, `stop()`,
  `find_binary()`); variantes nuevas en `error.rs`.
- **FFI:** `AiOllamaControlStatus`, `ollama_control_status`, `start_ollama`, `stop_ollama`
  (`api/ai.rs`).
- **Dart:** `ai_repository.dart`, `ollama_control_controller.dart` y el item en `main.dart`.
- **Decisión:** se controla **la instalación del usuario**, no un Ollama propio. Consecuencia:
  **apagarlo apaga el Ollama de toda la máquina**. El subtítulo del menú lo dice.
- **Decisión de alcance:** el item solo aparece con el asistente de IA activado, para respetar la
  regla de no llamar al puente de IA con el flag en `false`.
- **Estado:** compila (`cargo check`, `flutter analyze` limpio en los ficheros tocados). **No
  verificado en vivo** contra la app corriendo.

Esto deja a Ollama como el motor local **inmediatamente consumible** por la tubería externa: basta
con encenderlo desde NexoDeck (o tenerlo encendido) y hablarle en `127.0.0.1:11434`.
