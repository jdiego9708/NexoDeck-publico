# ADR 0003 — Inferencia local: sidecar `llama-server` sobre runtime embebido

## Contexto

El asistente de IA que crea acciones y macros a partir de lenguaje natural
tiene que correr **local y offline**, en las máquinas de los usuarios finales,
que son hardware de consumo heterogéneo: NVIDIA, AMD, Intel, o ninguna GPU
utilizable. El requisito explícito es que **use toda la capacidad de la
gráfica cuando la haya, y que aproveche bien la CPU cuando no**.

NexoDeck se distribuye como una app Flutter cuyo core Rust lo compila
**cargokit** durante `flutter build`, incluidas las 3 ABIs de Android. El
`CLAUDE.md` del proyecto ya documenta lo frágil que es ese build al moverse
entre máquinas (cachés de CMake con rutas absolutas del JDK anterior,
`package_config.json` apuntando al pub cache de otro perfil, etc.).

Se evaluaron cuatro caminos.

## Decisión

Usar el **binario preconstruido `llama-server` de llama.cpp como proceso
hijo (sidecar)**, descargado y gestionado por NexoDeck en runtime, hablándole
por HTTP OpenAI-compatible en `127.0.0.1` con puerto efímero.

NexoDeck detecta el hardware (`nexodeck-hardware::capabilities`), elige el
backend (`CUDA` para NVIDIA con NVML, `Vulkan` para AMD/Intel/genérico,
`CPU-AVX2` o `CPU-baseline` si no hay GPU utilizable), descarga el zip de
release oficial que corresponde más el `.gguf` del modelo de la gama, y lanza:

```
llama-server --model <gguf> --host 127.0.0.1 --port <efímero> --jinja
             --n-gpu-layers <calculado desde la VRAM> --threads <núcleos físicos>
             --ctx-size <según gama>
```

El crate `nexodeck-ai` abstrae esto detrás de un `trait ChatProvider`, de modo
que un **Ollama ya instalado** en la máquina del usuario sea un segundo
proveedor con la misma API (también OpenAI-compatible), sin descargar nada.

## Alternativas descartadas

- **vLLM** — servidor de datacenter: Python + CUDA, orientado a *continuous
  batching* de muchas peticiones concurrentes, con preasignación de VRAM por
  paged-attention. NexoDeck es un usuario con una petición corta a la vez, y
  vLLM prácticamente no tiene camino de CPU ni de GPU AMD/Intel en Windows.
  Sería empaquetar un stack de Python para no usar nada de lo que lo hace
  bueno.
- **mistral.rs** — es Rust y hace tool calling, pero su aceleración es CUDA
  (con `nvcc` en tiempo de build) o Metal; **Vulkan no está**. Eso deja a todo
  usuario con Radeon o gráfica Intel corriendo en CPU, exactamente lo
  contrario del requisito. Además habría que compilarlo dentro de cargokit.
- **llama.cpp embebido (`llama-cpp-2`)** — el backend de GPU se fija en
  **compile-time**: un binario CUDA no corre en AMD y viceversa, así que
  habría que publicar varios builds del producto o resignar la GPU. Y mete
  CMake/C++ dentro del build de cargokit, ×3 ABIs de Android.

## Consecuencias

- **El backend de GPU se decide al ejecutar, no al compilar.** La misma
  instalación de NexoDeck usa CUDA en una máquina y Vulkan en otra. Esto es lo
  que hace posible el sistema de gamas: `plan_runtime()` mira el hardware real
  y elige binario, modelo y `-ngl`.
- **Cero dependencias C/C++/CMake nuevas en el workspace.** `cargokit` no se
  entera de que existe la IA. Es la razón principal de la decisión.
- **La primera ejecución descarga entre 2,5 y 19 GB** (runtime + modelo, según
  gama). No hay forma de esconderlo: el wizard muestra el número exacto antes
  de empezar, corta si el disco libre no alcanza con 20 % de margen, y la
  descarga es reanudable con verificación SHA256.
- **Hay que mantener una matriz de releases de llama.cpp** (`catalog.rs`:
  `RUNTIMES` por `(Backend, HostOs)`). Es una tabla de constantes con test de
  consistencia, no código; el costo de actualizarla es bajo y explícito.
- **Windows Defender / SmartScreen puede marcar un `.exe` recién descargado.**
  Mitigación: se guarda en el data dir del usuario (nunca en `Program Files`),
  se verifica el SHA256 y la UI explica el origen. En equipos con política
  corporativa restrictiva, el camino Ollama es la salida.
- **Un proceso hijo más que administrar.** `sidecar.rs` lo mata en `Drop` y
  por idle timeout, guarda un ring de las últimas líneas de stderr para poder
  explicar un fallo, y usa puerto efímero + espera de `/health` en vez de un
  puerto fijo — el proyecto ya sabe lo que duele un puerto ocupado (58643).
- **`--jinja` es obligatorio**: sin él la plantilla de chat del modelo no emite
  tool calls bien formados, y todo el mecanismo de salida estructurada
  (`propose_action`) deja de funcionar.
- **Android queda fuera.** `nexodeck-ai` entra en `nexodeck-ffi` bajo
  `[target.'cfg(not(target_os = "android"))'.dependencies]`, igual que `nusb` y
  `arboard`. El teléfono podrá usar el motor de la PC más adelante a través del
  transporte que ya existe.
- **El modo online futuro no cambia nada de esto**: es un tercer
  `ChatProvider` con la misma API OpenAI-compatible. Lo único nuevo sería la
  clave, que por la regla de secretos del proyecto va a `nexodeck-vault`, nunca
  a Drift.
