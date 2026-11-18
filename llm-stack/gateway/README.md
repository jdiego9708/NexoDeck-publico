# llm-gateway

Pasarela autenticada delante de los servidores vLLM del stack multiagente. Es lo **único** que se
ofrece a los clientes (NexoDeck, agentes, herramientas): los servidores vLLM quedan atados a
`127.0.0.1` y sin autenticación propia.

## Por qué existe

- La receta usaba `api_key: "dummy"`, que no protege nada.
- El Sleep Mode exige `VLLM_SERVER_DEV_MODE=1`, que abre endpoints de administración (`/sleep`,
  `/wake_up`, `/collective_rpc`) que no deben llegar a nadie más que a quien administra el equipo.
- Da un único punto de entrada estable (`:8888`) aunque cambie qué modelos están levantados.

Ver `../11-mejoras-y-decisiones.md` (apartados 3 y 6).

## Qué hace

| | |
|---|---|
| Autenticación | `Authorization: Bearer ndk_…`. Solo se guarda el **hash SHA-256** de cada clave; comparación en tiempo constante; sin claves, nadie entra |
| Rutas | Solo `POST /v1/chat/completions`, `POST /v1/completions`, `POST /v1/feedback`, `GET /v1/models` y `GET /health`. Todo lo demás da **404** con clave válida |
| Enrutado | Por el campo `model` de la petición (`router`, `fast`, `complex`) a su servidor vLLM |
| Streaming | El cuerpo se reenvía como flujo: el SSE llega token a token y no se acumula en memoria |
| Modelo apagado | **503** con un mensaje claro, en vez de una conexión rechazada |
| Límites | Cuerpo máximo de 8 MiB (413 por encima) |
| Registro | Marca de hora, clave, modelo, estado y tiempo. **Nunca prompts ni respuestas ni claves** |

## Modelo virtual `auto`

Un cliente que no quiere elegir modelo pide `"model": "auto"` y la pasarela decide. Es la fase 5 de
la receta (enrutado semántico) **simplificada**: como el Rápido y el Complejo no conviven, un perfil
solo tiene dos niveles, no tres modelos (ver `../11-mejoras-y-decisiones.md`, apartado 7.22).

| Decisión (prioridad) | Regla | Nivel |
|---|---|---|
| `meta` (300) | el texto contiene `classify`, `route`, `tool`, `function call`… | **ligero** (Router) |
| `complex_keywords` (210) | contiene `refactor`, `architecture`, `optimize`, `multi-file`… y sus equivalentes en español | **trabajador** |
| `complex` (200) | más de 800 caracteres | trabajador |
| `simple` (100) | menos de 150 caracteres | **ligero** |
| `normal` (50, por defecto) | el resto | trabajador |

El **trabajador** es el primero de `workers` que esté levantado (`complex`, luego `fast`), así que
sirve igual con el perfil B que con el A. Si el nivel elegido está apagado **conmuta al otro**
(registrado como `fallback`); si no hay nada, 503.

- **Enrutado por dominio** (`code_routing`, activo por defecto): el código, aunque sea corto, va
  siempre al trabajador (`code`); y si el trabajador está en `specialists` (por defecto `complex`, el
  Qwen3-Coder podado, que en conocimiento general saca 37 % frente al 70 % del Router), lo que
  **no** parece código pasa al ligero (`not_code`). Con Gemma de trabajador solo se redirige el
  código. `meta` no cambia. Las marcas están en `code_markers` y se validan con
  `../scripts/check-code-detector.py`. Ver `../11-mejoras-y-decisiones.md`, apartado 7.27.
- La longitud se mide en **caracteres** de todo el texto de la petición (como en la receta).
- Se **reescribe el campo `model`** con el modelo real antes de reenviar (vLLM no conoce `auto`);
  el resto del cuerpo pasa intacto. Las peticiones con un modelo explícito no se tocan.
- La respuesta lleva `x-nexodeck-decision` y `x-nexodeck-model` para saber qué se eligió.
- `/v1/models` ofrece `auto` solo si hay algún modelo levantado.
- Umbrales, palabras clave, `light` y `workers` se cambian en el bloque `auto` de `gateway.json`
  (opcional: un `gateway.json` anterior sin él sigue leyéndose).

### Registro de decisiones y resultados (`decisions.jsonl`)

Un fichero JSON Lines junto a `gateway.json`, con **dos tipos de línea unidos por `id`**:

- **`decision`**, una por petición `auto`: qué decisión, qué modelo, si conmutó, estado HTTP,
  milisegundos hasta la primera respuesta, caracteres y si traía herramientas. **Nunca el texto.**
- **`outcome`**, el **resultado verificado** de esa petición, que informa quien la comprobó (tests,
  compilación, revisión…). La pasarela no puede saber si una respuesta es buena; quien la verifica, sí.
  Sin este dato, las decisiones registradas no dicen si fueron acertadas.

```json
{"type":"decision","id":"req_457403e448b6a612","decision":"normal","model":"complex","fallback":false,"first_byte_ms":520,"has_tools":false,"key":"nexodeck","prompt_chars":437,"status":200,"time":"2026-09-19 23:34:44Z","unix":1789860884}
{"type":"outcome","id":"req_457403e448b6a612","verified":true,"verifier":"mmlu-letter","score":null,"key":"nexodeck","time":"2026-09-19 23:34:45Z","unix":1789860885}
```

Cada respuesta `auto` trae `x-nexodeck-request-id`. El cliente informa del resultado con:

```http
POST /v1/feedback
Authorization: Bearer ndk_...
{"request_id": "req_457403e448b6a612", "verified": true, "verifier": "tests", "score": 1.0}
```

- `verified` es obligatorio. `verifier` (≤ 40 caracteres entre letras, números, `_`, `-`, `.`) y `score`
  (0 a 1) son opcionales. **No hay campo de texto libre**: sería justo por donde se colaría el contenido
  de un prompt.
- Solo puede informar **la clave que hizo la petición**, y **una sola vez**. Una petición desconocida o
  de otra clave da 404 (no se distingue), un duplicado 409, un cuerpo mal formado 400 y uno de más de
  4 KB 413. Sin registro activo, 503: no se hace un «no hacer nada» silencioso.
- Se recuerdan los ids de las **últimas 10 000 decisiones** y se recuperan del fichero al reiniciar.

`scripts/summarize-decisions.py` une decisiones y resultados (por decisión y modelo: cuántas tienen
resultado y qué fracción pasó la verificación). Con menos de ~30 resultados no hay nada concluyente.

## Uso

```powershell
cargo build --release                       # una vez; deja target\release\llm-gateway.exe

.\target\release\llm-gateway.exe keys add nexodeck    # enseña la clave UNA sola vez: guárdala
.\target\release\llm-gateway.exe keys list            # nombre y fecha, nunca la clave
.\target\release\llm-gateway.exe keys remove nexodeck # revoca, sin reiniciar la pasarela
.\target\release\llm-gateway.exe serve                # arranca (o usa scripts\Start-Stack.ps1)
```

Ficheros: `llm-gateway paths`. Por defecto en `%LOCALAPPDATA%\nexodeck\LlmGateway\data`
(`gateway.json` y `keys.json`); `NEXODECK_GATEWAY_DIR` o `--dir` lo cambian.

`gateway.json` (se crea con esto la primera vez):

```json
{
  "listen": "127.0.0.1:8888",
  "max_body_bytes": 8388608,
  "backends": {
    "complex": "http://127.0.0.1:8000",
    "fast": "http://127.0.0.1:8001",
    "router": "http://127.0.0.1:8002"
  }
}
```

### Destinos remotos (un slot del perfil por internet)

Un backend puede ser un **servicio por internet** en vez de un servidor vLLM local. En lugar de la
cadena con la URL, se escribe un objeto:

```json
{
  "fast": {
    "url": "https://api.deepseek.com",
    "api_key_file": "C:\\Users\\<usuario>\\AppData\\Roaming\\nexodeck\\NexoDeck\\data\\ai\\keys\\remote-abc.key",
    "upstream_model": "deepseek-flash"
  }
}
```

- **`api_key_file`** es la ruta del fichero donde NexoDeck (Rust) ya guarda la clave de un proveedor
  (`nexodeck_ai::remote::api_key_path`). La pasarela lee **la ruta**, nunca la clave; por eso la
  clave no acaba ni en `gateway.json` ni en git. `api_key_env` es la alternativa por variable de
  entorno.
- La cabecera `Authorization` que manda el cliente (`Bearer ndk_…`) se **reemplaza** por la del
  servicio; el remoto no conoce las claves de la pasarela.
- **`upstream_model`** reescribe el campo `model` antes de reenviar cuando el nombre local (la clave
  del backend) no es el que espera el servicio.
- Un backend con `api_key_file`/`api_key_env` es **externo y no se sondea**: se da por disponible.
  Sondearlo cada 2 s gastaría cuota y puede no tener `/health`; si no contesta, la petición misma
  devuelve el error del servicio.
- Un backend **sin** autorización (un vLLM local) se comporta exactamente como antes.
- **El cliente HTTP necesita TLS para un `https://`.** `reqwest` va con `default-features = false`
  y la feature `rustls` en `Cargo.toml`; **sin ella, un destino remoto daba 503
  `backend_unavailable`** porque no podía abrir la conexión (se detectó en el E2E del 25-sep-2026
  contra DeepSeek). No la quites: los backends locales son `http://` y no la usan, pero cualquier
  servicio por internet sí.

Esto es lo que permite que un perfil tenga el **router local** y el **pensamiento en la nube** (o al
revés): la clave `router` o `fast` apunta al vLLM de siempre o a un servicio externo.

### Recarga en caliente de `gateway.json`

La pasarela vigila el fichero y **recarga la configuración** cuando cambia (comprueba la fecha una
vez por vuelta del sondeo, cada 2 s). Así, cuando NexoDeck guarda un perfil con otro destino, no
hace falta reiniciar la pasarela: el cambio surte efecto solo. Un fallo al releer se ignora y sigue
valiendo la configuración vigente.

Desde un cliente (cualquier SDK de OpenAI sirve, con `base_url` y la clave):

```powershell
$headers = @{ Authorization = "Bearer $env:NEXODECK_LLM_KEY" }
Invoke-RestMethod http://127.0.0.1:8888/v1/models -Headers $headers
```

## Escucha solo en loopback

`listen` es `127.0.0.1` a propósito. Si se cambia a una dirección de red, la pasarela avisa al
arrancar: HTTP sin TLS, cualquier equipo de la red podría intentar autenticarse y la clave viajaría
en claro. Para abrirla fuera de la máquina hace falta delante un túnel o un proxy con TLS
(Tailscale, Cloudflare Tunnel…), como planteaba el doc 06.

## Pruebas

```powershell
cargo test              # 50 unitarias + 36 de integración (servidores vLLM de mentira)
cargo clippy --all-targets
..\scripts\Test-Gateway.ps1   # prueba de humo contra el stack REAL, con una clave desechable
```

Las de integración comprueban, entre otras cosas, que `/sleep`, `/collective_rpc` y demás rutas de
administración **no llegan** a vLLM ni con una clave válida, que el streaming llega por trozos, que
una clave revocada deja de funcionar sin reiniciar y que un cuerpo demasiado grande se rechaza.

## Fuera de alcance por ahora

- Límite de peticiones por clave y cuotas (un solo usuario hoy).
- TLS propio (se delega en el túnel).
- Reintentos o conmutación entre servidores: un modelo, un servidor.
- Métricas Prometheus (los vLLM ya las exponen en su `/metrics`, que no se publica).
