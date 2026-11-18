---
date: 2026-09-18
---
# 11 — Mejoras y decisiones sobre la receta

Este documento no sustituye a los 00-10: los **corrige y los ordena** tras leerlos enteros, comprobar el equipo real y decidir con el usuario. Donde discrepe de un documento anterior, manda este.

Cada afirmación va marcada: **[medido]** (comprobado en el equipo el 18-sep-2026), **[documentado]** (dicho por la receta o por una fuente, sin medir aquí) o **[por medir]** (hipótesis que decide el benchmark del apartado 7).

---

## Regla de uso: al terminar, liberar el hardware

**Cuando ya no se necesite el perfil A o B, hay que limpiar todos los procesos y dejar libre el hardware, y comprobarlo** (petición del usuario, 19-sep-2026). Los modelos ocupan ~15 GiB de VRAM y 8+ GB de RAM de WSL2 y compiten con ODM, entrenamientos y juegos; con Windows desalojando memoria de la GPU en silencio (7.9), dejarlos cargados «por si acaso» ralentiza todo sin que nadie lo vea.

```powershell
.\scripts\Stop-Stack.ps1 -ReleaseWsl     # debe acabar en "LIMPIO"
```

`Stop-Stack.ps1` **verifica** la limpieza (pasarela, keep-alive, distro de WSL2 y nivel de la GPU) y sale con código 1 si queda algo. Se ejecuta al acabar, sin esperar a que lo pidan.

## 0. Estado por fases (19-sep-2026)

Las fases son las de la tabla del `00-README.md`. Los tiempos que estimaba la receta (15-30 minutos por fase) se han quedado muy cortos: las fases 1-4 y la pasarela han llevado dos sesiones largas.

| Fase | Estado | Qué queda o qué cambió |
|:---|:---|:---|
| 1. WSL2 + Docker + toolkit | **Hecha** | 16 GB de RAM, no 28. Docker Engine dentro de Ubuntu 26.04 |
| 2. vLLM + b12x + SM120 | **Hecha, con desvíos** | vLLM 0.29.0 en imagen derivada con b12x. No hace falta fijar cutlass-dsl; el kernel lineal es b12x pero **el MoE no** (rompe los grafos CUDA) |
| 3. Descarga de modelos | **Hecha** | Los tres modelos exactos, verificados. El Router pesa 4.2 GB, no 2.5 |
| 4. Servidores + Sleep Mode | **Hecha a medias** | Perfiles A y B funcionando y medidos. **Sleep Mode: el nivel 1 funciona pero llena la RAM; el 2 corrompe el modelo**: se cambia de perfil parando y arrancando. El doc 04 se cerró con una continuación (checklist y advertencias verificadas) |
| 5. Router semántico (vLLM-SR) | **Hecha, simplificada** | Modelo virtual `auto` en la pasarela (Router para lo simple, el trabajador del perfil para el resto) con registro de decisiones; sin vLLM-SR. Ver 7.22 |
| 6. Integración multiagente y túnel | **Parcial** | Hecho: endpoint OpenAI con autenticación real (`llm-stack/gateway/`), arranque permanente, guía de concurrencia medida y **el preset `custom` en NexoDeck** para apuntarlo a la pasarela (7.21, 2026-09-23). Falta: el alta a mano en la UI, integrar OpenCode/Continue/Aider y probar el túnel. El doc 06 se cerró con una continuación |
| 7. Troubleshooting | **Hecha** | El doc 07 se cerró con una continuación: tabla de 21 errores por síntoma (todos vistos en este equipo), diagnóstico rápido y reset completo |
| — Calidad de Gemma | **Evaluada** | HumanEval 92,7 %, MMLU 73 % (es) / 77 % (en): **domina al Complejo en calidad**; el perfil B solo gana en velocidad y contexto. Ver 7.28 |
| — Calidad del Complejo | **Evaluada** | Código (HumanEval): 89-90 %, validado (Router 75-79 %). **Conocimiento general (MMLU): 37 % frente al 70 % del Router**: es un especialista de código, su poda se calibró solo con código. Ver 7.23 y 7.25 |
| 8. RSIAgent | **Verificada, no adoptada** | RSIAgent existe (arXiv 2609.15364) pero es un arnés de OSWorld/ALE y su README no confirma la API del doc 08. Se propone el patrón, no el repositorio (7.24) |
| 9. Simulador de replay (3 niveles) | **Prototipo** | `replay-routing.py` reproduce políticas de enrutado sobre resultados verificados de HumanEval. Hallazgos en 7.24: la longitud no predice la dificultad; una cascada con verificador iguala al Complejo usándolo el 21-25 % |
| 10. Bucle Dream-RSI | **No empezada, y no conviene aún** | Dream-RSI existe (arXiv 2609.14858) pero la analogía con el enrutado es nuestra. Faltan verificador realista, conjunto reservado, datos acumulados y *canary* (7.24) |

**Sobre la fase 5.** El doc 05 enruta «simple → Gemma» y «complejo → Qwen3-Coder» dentro de un mismo stack. Con la decisión de que **el Rápido y el Complejo no conviven** (y no caben juntos), un solo perfil solo tiene **un modelo trabajador**: Gemma en el A, Qwen3-Coder en el B. El enrutado que sí tiene sentido es de **dos niveles**: preguntas simples al Router (4B, ~80 tok/s) y el resto al trabajador del perfil activo. Se puede hacer dentro de la pasarela con un modelo virtual `auto` (por longitud y palabras clave, como ya hacía el doc 05) en pocas líneas, sin desplegar vLLM-SR aparte (cuyo puerto por defecto, el 8888, además ya ocupa la pasarela).

## 1. Estado real del entorno (18-sep-2026)

| Dato | Receta | Equipo real | Estado |
|:---|:---|:---|:---|
| RAM de WSL2 | 28 GB, 12 procesadores | **16 GB, 8 hilos** (`.wslconfig`) | [medido] Decidido: se sube de 12 a 16 GB y no a 28, para no dejar sin RAM a ODM y a los entrenamientos |
| Docker | Docker Engine dentro de Ubuntu | Docker Engine 29.8.1 instalado en Ubuntu 26.04; Docker Desktop **desinstalado** | [medido] |
| NVIDIA Container Toolkit | sí | 1.20.1; `docker run --gpus all` ve la RTX 5060 Ti con `compute_cap` 12.0 | [medido] |
| Usuario de Ubuntu | `/home/juan` | **`/home/usuario`** | [medido] Ajustar las rutas al copiar comandos |
| Storage driver de Docker | `overlay2` | `overlayfs` (snapshotter de containerd de Docker 29) | [medido] Sin efecto en lo que sigue |
| VRAM libre para el stack | 16 GB | **~13.9 GB**: Windows ya usa ~2.4 GB con el escritorio | [medido] Ver apartado 2 |
| `autoMemoryReclaim` | en `[experimental]` | estaba en `[wsl2]` y WSL lo ignoraba con un aviso; se quitó | [medido] Falta añadirlo en `[experimental]` si se quiere |
| Espacio en el disco virtual de WSL2 | ≥ 35 GB | 955 GB libres | [medido] |

---

## 2. Presupuesto de VRAM: gigabytes medidos, no fracciones

**El problema.** vLLM comprueba al arrancar que haya libre la fracción pedida de la VRAM total. Con ~13.9 GB libres, el `--gpu-memory-utilization 0.90` del modelo complejo pide 14.4 GB y **no arranca**. Además las tres utilizaciones de la receta (0.90 + 0.85 + 0.75) suman más de 1 aunque nunca deban convivir.

**Decisión.** Dos perfiles con presupuesto fijo, y un techo conjunto de **~0.80 de la VRAM total (~13 GB)**:

| Perfil | Modelos vivos | Pesos | Margen para KV y overhead |
|:---|:---|:---|:---|
| **A — cotidiano** | Router + Rápido | ~12 GB [medido: 4.2 + 7.8 GB de pesos en disco] | ~1.9 GB (**justo**) |
| **B — razonamiento** | Router + Complejo | ~14.1 GB [medido: 4.2 + 9.9 GB] | **negativo sin offload**: no cabe en los ~13.9 GB libres. Con `--cpu-offload-gb` de ~3-4 GB entre los dos (decisión del usuario, apartado 5.1) queda ~1.5-2 GB |

Estas cifras salen de los tamaños reales de los repos (apartado 7.1) y **sustituyen** a las de la receta (9.5 y 12.5 GB), que partían de un Router de 2.5 GB.

- El **Rápido y el Complejo nunca conviven** (decisión del usuario). El Router acompaña siempre a uno de los dos.
- **Las instancias se arrancan de una en una.** El perfilado de memoria de vLLM con dos instancias arrancando a la vez no es fiable.
- El perfil B **no cabe** con el Router multimodal actual (ver apartado 7.1). Lo razonable es que el Complejo corra **solo** y el Router se apague mientras, o buscar un Router de solo texto.
- Las cifras de VRAM de los documentos se contradicen (Router+Rápido figura como 9.5 y como 12.5 GB). **Vale la que salga del benchmark.**

**Sobre el MoE.** Qwen3-Coder-30B-A3B solo activa ~3B parámetros por token, lo que abarata el **cálculo**, no la **memoria**: los pesos completos (~10 GB) tienen que estar residentes porque cada token puede elegir otros expertos.

---

## 3. Estabilidad

1. **Un solo modo de ejecución: contenedores.** El doc 02 instala vLLM en un venv y el 04 sirve desde el venv, mientras el 01 promete contenedores. Con Docker ya instalado se usa la imagen de vLLM **fijada por digest**, no `:latest`, para que los pines (b12x 1.2.6, `nvidia-cutlass-dsl` 4.4.2) queden reproducibles. El venv se conserva solo para diagnóstico (`vllm collect-env`).
2. **Caché de JIT persistente.** Un volumen montado en `/root/.cache/vllm` evita recompilar los kernels b12x (2-5 min) en cada contenedor nuevo (doc 02 §12.7).
3. **`VLLM_SERVER_DEV_MODE=1` no se expone.** El Sleep Mode lo exige y activa endpoints peligrosos (`/collective_rpc`). Los vLLM van atados a `127.0.0.1` o a una red interna de Docker, nunca a `0.0.0.0` como dice el doc 04; solo la pasarela (apartado 6) sale al exterior y solo deja pasar `/v1/*`.
4. **Autenticación real.** `api_key: "dummy"` no protege nada. La pasarela exige una clave y los vLLM internos no son alcanzables desde fuera.
5. **Arranque y salud.** Reinicio acotado (`--restart on-failure:3`) y *healthcheck* por contenedor (`serve-model.sh`); la pasarela, supervisada aparte (`Start-Gateway.ps1`). Se descartaron las unidades systemd: no resuelven el ciclo de vida de la distro (el keep-alive sigue haciendo falta) y pelean con el arranque dinámico por perfiles. Docker **no** reinicia por *healthcheck*, solo lo expone, así que un contenedor «vivo pero insano» pediría un vigilante (nivel 2, pendiente). Con 2-5 minutos de JIT en el primer arranque, un reinicio ciego provoca bucles, de ahí el tope.
6. **Router Replay en SQLite:** activar **WAL** desde el principio (con más de 10 agentes aparece `database is locked`); PostgreSQL solo si `replay.db` pasa de 100 MB.
7. **Verificar la procedencia de los modelos antes de descargar.** Los tres repositorios son de autores individuales y ninguno ha sido comprobado. Antes de bajar 19 GB se consulta la API de HuggingFace (solo lectura): que el repo exista, el tamaño, el `quant_method` del `config.json`, que los pesos sean `safetensors` y que no requieran código remoto. **No** se usa la variante *abliterated* que propone el doc 03 §7.4 como alternativa: quita los rechazos de contenido.
8. **Los kernels dependen de versiones exactas.** Cualquier actualización de vLLM, b12x o cutlass-dsl se prueba primero contra el benchmark, nunca en el arranque.

---

## 4. Rendimiento: palancas a medir, una por una

Ninguna se da por buena sin medir. Todas son [por medir].

| Palanca | Por qué encaja | Riesgo |
|:---|:---|:---|
| `--kv-cache-dtype fp8` | El KV cache es lo escaso (3-6 GB); FP8 casi duplica contexto o concurrencia | Comprobar compatibilidad con el backend de atención en SM120 |
| Quitar `--enforce-eager` | Penaliza el rendimiento; puede estar resuelto en versiones recientes | Si `torch.compile` sigue fallando con NVFP4 MoE, se vuelve a eager |
| Decodificación especulativa por n-gramas | Barata y buena en código, que es el uso del Complejo | Verificar que la versión instalada la soporta |
| `--max-num-seqs` de 8-12 | Evita que un pico de agentes agote el KV y provoque expulsiones | Ajustar con el benchmark |
| `--enable-prefix-caching` en las tres instancias | Los agentes comparten *system prompt*; la receta solo lo activa en Gemma | Ninguno relevante |
| Prefill troceado (`--enable-chunked-prefill`) | Evita que un prompt largo bloquee la decodificación de los demás agentes | Puede venir activo por defecto en la versión instalada |

Los tok/s de la receta (AWQ 150 / NVFP4 100 en batch-1) son de una **RTX 5090**, no de la 5060 Ti: se rehacen.

---

## 5. ¿Sirve el NVMe como «RAM» para hacer offload?

Consulta del usuario. Respuesta: **no como extensión de la VRAM para generar texto; sí para arrancar y cambiar de modelo, y para desbordar la caché de prefijos.** Las cifras son órdenes de magnitud teóricos [documentado], no medidas aquí.

### Por qué no sirve para decodificar

Cada token obliga a leer los pesos activos, así que los tokens por segundo quedan limitados por el ancho de banda del lugar donde vivan:

| Dónde están los pesos | Ancho de banda aprox. | Latencia de acceso |
|:---|:---|:---|
| VRAM (GDDR7 de la 5060 Ti) | ~450 GB/s | nanosegundos |
| RAM DDR4 a través de PCIe (la tarjeta va en PCIe 5.0 x8) | ~25-30 GB/s en la práctica | ~100 ns |
| NVMe PCIe 4.0 | ~5-7 GB/s secuencial; mucho menos en lecturas aleatorias | ~100 µs |

- **Denso (Gemma 12B, 6.8 GB):** desde NVMe, menos de 1 token/s; desde RAM, unos 3-4. Inservible para agentes interactivos.
- **MoE (Qwen3-Coder, ~3B activos):** por token se leen ~1.5-2 GB. Es el único caso razonable, pero con los expertos calientes en VRAM y el resto en **RAM**, no en disco: los expertos elegidos cambian en cada token y las lecturas aleatorias a NVMe son las peores.
- **vLLM no ofrece offload de pesos a NVMe.** Su `--cpu-offload-gb` usa RAM y cuesta mucho rendimiento. Las herramientas que sí usan NVMe (ZeRO-Infinity, FlexGen) están pensadas para rendimiento por lotes enormes, no para latencia.

### Dónde sí ayuda

1. **Cambiar de modelo más rápido.** Los modelos van en el sistema de ficheros nativo de WSL2 (`~/models`), no en `/mnt/d/` (mucho más lento por el puente de red de 9P). Así la recarga tras un Sleep nivel 2 (5-10 s) no se alarga por el disco.
2. **Desbordar la caché de prefijos y el KV cache.** Con muchos agentes compartiendo prompts largos, guardar esos KV en RAM o disco evita recalcularlos. Ayuda a la latencia inicial, no a la velocidad de generación. Hay que verificar qué soporta la versión de vLLM que se instale (por ejemplo, herramientas como LMCache) [por medir].

### KV cache en NVMe (consulta del usuario, 18-sep-2026)

- **Para generar, no:** cada token lee el KV de todo el contexto. En Gemma, 16 000 tokens son ~1.8 GiB (~0.11 MiB por token, medido); desde NVMe (~6 GB/s) serían ~0.3 s por token, ~3 tok/s frente a los 44 medidos en VRAM.
- **Para sesiones inactivas, sí:** con solo 1.5-2.5 GiB de KV en GPU, los prompts largos compartidos entre agentes pierden su KV y hay que recalcularlo. Recargar 1.8 GiB cuesta ~0.07 s desde RAM y ~0.3 s desde NVMe, frente a varios segundos de prefill [estimado].
- **En vLLM 0.29** (`vllm/config/cache.py`): `--kv-offloading-size` (GiB) con backend `native` (RAM) o `lmcache` (componente externo, que sí permite otras capas; no viene en la imagen). No hay NVMe nativo.
- **Plan:** primero RAM (`native`, ~4 GiB; la memoria fijada ya está activada), medir con `bench.py --shared-prefix` con y sin offload, y solo si la RAM se queda corta valorar NVMe con `lmcache`. Pendiente tras cerrar el perfil A.

### Precauciones

- El KV a disco **escribe mucho** y desgasta el NVMe.
- El NVMe de `D:` ya lo usan ODM y los entrenamientos: compartirlo crea contención.
- El swap de 8 GB de WSL2 vive en un disco virtual. Si un modelo aparcado desborda la RAM, el sistema **se arrastra** en vez de fallar.

**Decisión.** Con 16 GB de RAM en WSL2, el Sleep nivel 1 (pesos aparcados en RAM) solo cabe para **uno** de los dos modelos pesados. El otro va con nivel 2. El NVMe no se usa como nivel de memoria. Se reabre solo si el benchmark demuestra que la recarga o el prefill son el cuello de botella.

### 5.1 Offload a RAM en el perfil B (decisión del usuario, 18-sep-2026)

El usuario quiere Router y Complejo **a la vez**, con «un poco de offload a la RAM o al NVMe». Como el NVMe no sirve para pesos en vLLM (apartado 5), el offload es **a RAM** con `--cpu-offload-gb` en cada instancia.

- **Cuánto.** Pesos 14.1 GB + KV mínimo ~1.5 GB + activaciones y overhead ~1 GB frente a ~13.9 GB libres: faltan **~3-4 GB** que salir de la GPU. La RAM de WSL2 (16 GB) los admite; la memoria fijada («pinned») es RAM que ODM no puede usar mientras el perfil B esté activo.
- **Qué offloadear primero.** Lo que menos se toca:
  - En el Router, la **torre visual** (no se le mandan imágenes) y los embeddings. Si vLLM lee la memoria de host bajo demanda, lo no usado no cuesta nada [por medir].
  - En el Complejo, una parte de los expertos: por token solo se usan 8 de 64 por capa, así que en teoría se leen pocos, pero con varios agentes concurrentes casi todos se tocan [por medir].
- **Coste.** Lo offloadeado se lee por PCIe (~25-30 GB/s) en cada paso de decodificación; una parte de 2 GB añade del orden de decenas de ms **por token generado**. Aceptable para el Router (salidas cortas), delicado para el Complejo. Si el rendimiento del Complejo cae demasiado, se prueba: (a) offload solo del Router, (b) reducir contexto y `--max-num-seqs`, (c) llama.cpp con `--n-cpu-moe`, que está pensado para dejar expertos MoE en RAM.
- **No se sabe** si `--cpu-offload-gb` de la versión instalada lee por UVA bajo demanda o copia el módulo entero en cada paso: es lo que decide si funciona bien con MoE, y se mide.
- **Criterio de aceptación:** el perfil B arranca sin OOM, atiende 4 clientes con contexto de 16k y la caída de tok/s frente al Complejo solo es ≤ 30 %. Si no, el Complejo corre solo.

---

## 6. Proyecto

- **Árbitro de GPU con ODM y los entrenamientos.** Esos trabajos ocupan la GPU durante horas y el stack compite con ellos. Cuando arranque uno, el stack pasa a Sleep nivel 2 (libera casi toda la VRAM) y despierta al terminar. Es el mismo conflicto de recursos que llevó a limitar WSL2 a 12 GB.
- **Pasarela propia en Rust en lugar del `ModelManager` de Python** (doc 06 §6). Se encarga de autenticación real, de orquestar el sueño y el despertar, de la cola y de las métricas. Encaja con el resto de NexoDeck y permite **cambiar de motor sin tocar a los clientes**.
- **NexoDeck lo consume como un `ChatProvider` más** (`nexodeck-ai/src/provider.rs`, mismo patrón que `Ollama` y `Remote`), sin depender del crate de ningún motor. El ADR 0003 descartó vLLM y mistral.rs para el asistente **embebido**; este stack es aparte y no lo contradice.
- **Router de 4B.** El enrutamiento del doc 05 usa longitud y palabras clave, sin LLM. El Qwen 3.5 4B se justifica como meta-agente, curriculum y verificador. Si el routing no lo necesita, no debe ocupar VRAM de forma permanente en el perfil B.
- **Validez de Dream-RSI: es el mayor riesgo de la idea, y no es del motor.**
  - Hoy «éxito» solo significa que la petición terminó sin error, no que la respuesta fuera correcta.
  - El simulador casi siempre elige el primer hijo del árbol (`strategy.get("next", node.children[0])`), así que la «mejora» no depende de la estrategia propuesta.
  - Antes de dejar el bucle solo: un verificador ejecutable (tests, no juicio del propio modelo), un conjunto de tareas **reservado** para evaluar, y despliegue de cada estrategia como *canary* con vuelta atrás automática.
  - Las cifras del paper («162x menos llamadas») y la API concreta de RSIAgent (`rsiaagent.config`, `MemoryStore.initialize`) **no están verificadas**; las referencias del paper llevan `xxxxx` en la URL.

---

## 7. Plan de medición

Orden y criterio de aceptación. **No se pasa al siguiente sin cumplir el anterior.**

| Paso | Qué se hace | Se acepta si |
|:---|:---|:---|
| 0 | Verificar por API los tres repos (existencia, tamaño, `quant_method`, `safetensors`) | Los tres existen y coinciden; si no, se busca equivalente **antes** de descargar |
| 1 | Perfil A (Router + Rápido, ~9 GB) en contenedores con presupuesto en GB | Arranca sin OOM; VRAM real ≤ 13 GB; tok/s con 1, 4 y 8 clientes con `vllm bench serve` |
| 2 | Descargar el Complejo y medir el perfil B y la conmutación entre perfiles | Latencia de cambio A→B y B→A medida; sin OOM con contexto de 16k |
| 3 | Probar, de una en una, FP8 KV, sin `--enforce-eager` y n-gramas | Cada palanca se conserva solo si mejora sin romper estabilidad |
| 4 | Pasarela, autenticación y árbitro de GPU | Solo con los números del 1 al 3 en la mano |
| 5 | Completar los docs 04, 06 y 07 (truncados) y corregir sus cifras | **Hecho el 19-sep-2026**: el texto original es irrecuperable, así que cada uno acaba con una «Continuación» marcada (checklist y advertencias verificadas en el 04; autenticación por la pasarela, monitoreo y concurrencia medida en el 06; errores por síntoma, diagnóstico y reset en el 07) en lugar de inventar la receta que faltaba |

### 7.1 Resultado del paso 0 (18-sep-2026, API de HuggingFace, solo lectura)

Los tres repos existen, son `safetensors`, sin gating, sin pesos pickle y sin código remoto (`auto_map`). Lo que no coincide con la receta:

| Rol | Repo | Tamaño real | Receta | `model_type` / `quant_method` | Observaciones |
|:---|:---|:---|:---|:---|:---|
| Complejo | `AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4` | 9.24 GiB (≈ 9.9 GB) | ~9.9 GB | `qwen3_moe` / `modelopt` | Coincide. 250 descargas: poco contrastado. Licencia apache-2.0 |
| Rápido | `mattbucci/gemma-4-12B-AWQ` | 7.25 GiB (≈ 7.8 GB) | ~6.8 GB | `gemma4_unified` / `awq` (4 bits, grupo 128) | **Multimodal**; etiquetado `sglang`, no vLLM. Licencia `gemma` (con términos de uso). El `model_type` de la receta (`gemma`) no coincide |
| Router | `AxionML/Qwen3.5-4B-NVFP4` | **3.90 GiB (≈ 4.2 GB)** | ~2.5 GB | `qwen3_5` / `modelopt` | **Multimodal** (imagen-texto); etiquetado `sglang`. Es 1.7 GB más de lo previsto |
| Router (alt.) | `QuantTrio/Qwen3.5-4B-AWQ` | 5.65 GiB | ~2.5 GB | `qwen3_5` / `awq` | Aún más grande; 66 200 descargas |

Consecuencias:

1. **El perfil B (Router + Complejo) no cabe** con el Router actual: 14.1 GB de pesos frente a ~13.9 GB libres. Opciones, por orden de preferencia: (a) el Complejo corre **solo**, con el Router apagado (el enrutamiento del doc 05 no necesita LLM); (b) un Router realmente de ~2.5 GB, es decir, de solo texto; (c) liberar la VRAM que ocupa Windows.
2. **El perfil A queda a ~1.9 GB para KV cache**, muy justo para 8-12 agentes. El FP8 KV y un contexto menor pasan de «mejora» a necesidad.
3. **Soporte de arquitecturas en vLLM.** La documentación de vLLM (`supported_models`, consultada el 18-sep-2026) lista `Gemma4UnifiedForConditionalGeneration`, `Qwen3_5ForConditionalGeneration` y `Qwen3MoeForCausalLM`, así que las tres **existen** en vLLM. Lo que no está confirmado es que los checkpoints NVFP4 de terceros (etiquetados para sglang) carguen con la versión instalada: se comprueba en el paso 1 con `vllm serve`, y se descarta el modelo si falla.
4. Si vLLM permite desactivar la parte visual (por ejemplo limitando los medios por prompt a cero), la huella de los dos modelos multimodales baja [por medir]. No se asume.

### 7.2 Descarga e integridad (18-sep-2026) [medido]

Los tres modelos se descargaron en ~4 minutos a `~/models` (20.6 GB, sistema de ficheros nativo de WSL2, no `/mnt/d/`). Adaptaciones al doc 03: la CLI actual es `hf` (no `huggingface-cli`) y `--local-dir-use-symlinks` está obsoleto. Se comprobaron las cabeceras de los `safetensors` (desplazamientos frente al tamaño real del fichero):

| Modelo | Tensores | Integridad | Tipos de tensor | Cuantización confirmada |
|:---|:---|:---|:---|:---|
| Router `qwen3.5-4b-nvfp4` (4.0 GB) | 1482 (297 de la parte visual) | OK | `U8` + `F8_E4M3` + `BF16` | NVFP4, grupo 16 (`modelopt`) |
| Rápido `gemma-4-12b-awq` (7.3 GB) | 1333 (10 de la parte visual) | OK | `I32` + `BF16` + `F16` | AWQ 4 bits, grupo 128 |
| Complejo `qwen3-coder-30b-reap50-nvfp4` (9.3 GB) | 37 971 | OK | `U8` + `F8_E4M3` + `F32` | NVFP4, grupo 16, KV cache FP8 |

- El Complejo confirma 48 capas, 64 expertos por capa y 8 activos, con el KV cache en FP8 ya definido en su configuración.
- La parte visual del Router es ~20 % de sus tensores: es lo primero que se intenta sacar de la GPU (apartado 5.1).
- El fichero `config.json.modelopt.bak` del Complejo indica que el autor modificó la configuración a mano: otra razón para comprobar que carga en vLLM antes de fiarse.
- Falta comprobar que **cargan** en vLLM. La integridad de los ficheros no lo garantiza.

### 7.3 La imagen de vLLM real frente a la receta (18-sep-2026) [medido]

`inspect-vllm-image.sh` sobre la imagen fijada (`vllm/vllm-openai@sha256:c2914767…`):

| Aspecto | Receta | Imagen real |
|:---|:---|:---|
| vLLM / PyTorch | ≥ 0.29 / 2.13 cu130 | 0.29.0 / 2.13.0+cu130, transformers 5.16.1, FlashInfer 0.6.18 |
| Arquitecturas | — | Las tres están registradas: `Gemma4UnifiedForConditionalGeneration`, `Qwen3_5ForConditionalGeneration`, `Qwen3MoeForCausalLM` |
| b12x | «instalar `vllm[b12x]`» | **No viene en la imagen**: `B12xNvFp4LinearKernel.is_supported(120)` daba `False`. Se construye una imagen derivada (`Dockerfile.vllm`, `build-vllm-image.sh`) que solo añade el extra |
| Qué añade `vllm[b12x]` | b12x 1.2.6 y pin de cutlass-dsl a 4.4.2 | Solo `b12x==1.2.6`; **cutlass-dsl se queda en 4.6.2**. El pin a 4.4.2 (doc 02 §6) era de una versión anterior de vLLM y no hace falta aquí |
| Kernels tras el extra | — | `B12xNvFp4LinearKernel` y `B12xFp8BlockScaledMMKernel`: `True` para SM120 |
| Flags | `--linear-backend`, `--moe-backend`, `--enable-sleep-mode`, `--cpu-offload-gb`, `--kv-cache-dtype`… | Existen todos, y además `--language-model-only`, `--kv-offloading-size` y `--speculative-config` |
| VRAM libre | ~13.9 GB (con 2.4 GB de Windows) | **14.80 GiB de 15.93 GiB**: el escritorio ocupa menos ahora. Varía, así que el presupuesto se mide en cada arranque |

**Aviso de vLLM en WSL:** al importarse imprime `Using 'pin_memory=False' as WSL is detected. This may slow down performance.` Con memoria fijada desactivada, el offload a RAM del perfil B (apartado 5.1) puede rendir peor de lo estimado: es la primera cosa a medir en ese perfil.

### 7.4 Primer arranque: `UVA is not available` en WSL2 [medido]

El primer intento del Router falló a los 68 s con `RuntimeError: UVA is not available` (`vllm/v1/worker/gpu/buffer_utils.py`). El traceback final de vLLM es siempre `Engine core initialization failed`; la causa está varias líneas antes, en el proceso `EngineCore`.

- **Causa:** vLLM 0.29 usa por defecto el ejecutor de modelos v2, que necesita memoria host mapeada (UVA). UVA exige memoria fijada, y en WSL2 vLLM la desactiva por defecto (el aviso `pin_memory=False as WSL is detected`).
- **Solución:** `VLLM_WSL2_ENABLE_PIN_MEMORY=1`. El propio `envs.py` de vLLM lo documenta: la memoria fijada está soportada en WSL2 con kernel ≥ 4.19.121 (aquí, 6.18) pero desactivada «por una pequeña pérdida de rendimiento», y hay que activarla «cuando se necesita memoria fijada o UVA (p. ej. offload a CPU o ejecutor v2)».
- **Consecuencia buena para el perfil B:** el offload a RAM (`--cpu-offload-gb`) necesita esa misma variable, así que queda habilitado. El aviso de rendimiento del apartado 7.3 sigue en pie y se mide.
- `serve-model.sh` ya la fija, y guarda el registro completo en `~/vllm-stack/logs/vllm-<rol>.log` mostrando la línea de excepción. `grep-vllm-source.sh` permite buscar en el código de vLLM de la imagen sin arrancar nada; así se llegó a la causa.

### 7.5 Router: presupuesto de memoria medido [medido]

Segundo intento (con memoria fijada), `--gpu-memory-utilization 0.28` (4.46 GiB): falló con `No available memory for the cache blocks`. Lo que dejó claro el registro:

| Dato | Valor |
|:---|:---|
| Kernel NVFP4 elegido | `B12xNvFp4LinearKernel` (b12x funciona en SM120) |
| Backend de atención | `FLASH_ATTN` sin necesidad de `VLLM_ATTENTION_BACKEND=TRITON_ATTN` (la receta lo exigía para NVFP4; con este modelo híbrido no hace falta) |
| Pesos con `--language-model-only` | **3.3 GiB** (4.0 GB en disco): quitar la parte visual ahorra ~0.6 GiB |
| KV cache disponible con 0.28 | **−0.21 GiB** → activaciones + grafos CUDA + overhead ≈ **1.4 GiB** |
| Tiempo del primer arranque | 243 s (compilación con `torch.compile` 27 s + calentamiento de kernels ~2.7 min); las cachés de `~/.cache/vllm` y `~/.cache/flashinfer` se conservan |

Consecuencia para el presupuesto de VRAM: el Router necesita ~5.7 GiB para tener ~1 GiB de KV, no los ~3.5 GB de la receta. Con **~13.4 GiB libres** (Windows ocupa 2.5 GiB) y el Rápido necesitando ~9 GiB, el perfil A **no cabe con los valores por defecto**: hay que bajar contexto, `--max-num-batched-tokens` y `--max-num-seqs`, o usar `--enforce-eager` (sin grafos CUDA). Se mide a continuación.

### 7.6 Router en marcha y medido [medido]

Tercer intento: `--gpu-memory-utilization 0.34` con `--max-num-batched-tokens 2048`. Arrancó en **171 s** (con las cachés de compilación ya calientes).

| Concepto | Valor |
|:---|:---|
| Pesos + no-torch | 3.44 GiB |
| Pico de activaciones | **0.13 GiB** (sin acotar `--max-num-batched-tokens` se comía ~1.3 GiB) |
| Grafos CUDA | 0.01 GiB |
| KV cache | 1.84 GiB = 49 152 tokens (3.0x de concurrencia a 16k) |
| VRAM total usada en la GPU | 8161 MiB (incluye ~2.5 GiB de Windows) |

Rendimiento (`bench.py`, 3 peticiones por cliente, 128 tokens por respuesta):

| Clientes | tok/s agregados | tok/s por cliente | Latencia media | p95 |
|:---|:---|:---|:---|:---|
| 1 | 78.0 | 78.1 | 1.6 s | 1.7 s |
| 4 | 296.2 | 74.1 | 1.7 s | 1.8 s |
| 8 | 538.5 | 67.4 | 1.9 s | 2.0 s |

Escala casi linealmente: con 8 agentes cada uno mantiene 67 tok/s. Es un benchmark de decodificación con prompts cortos, no de carga realista. Con esto, el Router baja a `--gpu-memory-utilization 0.27` (~0.7 GiB de KV, ~19 000 tokens) para dejar sitio al Rápido en el perfil A.

### 7.7 Perfil A: el Rápido no cabe junto al Router con los valores de la receta [medido]

Con el Router a 0.27 (arranque en 181 s, KV 18 970 tokens, 6.9 GiB usados en la GPU contando Windows) se arrancó Gemma con 0.55 (8.76 GiB). Falló con `No available memory for the cache blocks`.

| Dato de Gemma (`gemma-4-12b-awq`) | Valor |
|:---|:---|
| Kernel AWQ | `MarlinLinearKernel` (como decía la receta) |
| Backend de atención | `TRITON_ATTN` |
| Pesos con `--language-model-only` | **7.85 GiB** (7.25 GiB de checkpoint) |
| KV cache con 0.55 | **−1.23 GiB** → activaciones y overhead ≈ **2.1 GiB** |
| `torch.compile` | 75 s la primera vez (el Router: 27 s) |

Cuenta del perfil A con estos datos: Gemma necesita ~7.85 + ~2.1 + al menos ~1 GiB de KV ≈ **11 GiB**, más los ~4.3 GiB del Router ≈ **15.3 GiB**, frente a los **~13.4 GiB** que deja Windows. **No cabe tal cual.** Se mide primero Gemma en solitario para ver de dónde sale su overhead (apartado 7.8) y decidir si se recorta.

### 7.8 Gemma en solitario, y el servidor que «se cae solo» [medido]

**Desglose de Gemma sola** (`--gpu-memory-utilization 0.68`, arranque en 89 s con cachés calientes):

| Concepto | Valor |
|:---|:---|
| Pesos + no-torch | 8.02 GiB |
| Pico de activaciones (`--max-num-batched-tokens 2048`) | 0.24 GiB |
| Grafos CUDA | 0.01 GiB |
| KV cache | 2.57 GiB = 23 189 tokens (1.42x a 16k) |

El overhead real de Gemma es de **~0.4 GiB**, no los ~2.1 GiB que sugería el fallo del apartado 7.7. Ese fallo con el Router en marcha no se debía a lo que Gemma necesita sino a cómo vLLM mide la memoria cuando hay otra instancia en la misma GPU: la aritmética por fracciones no es fiable con dos instancias. La vía robusta es fijar el KV en bytes con `--kv-cache-memory` por instancia (vLLM lo sugiere en su propio registro).

**Rendimiento de Gemma sola** (`bench.py`, 3 peticiones por cliente, 128 tokens, AWQ con Marlin):

| Clientes | tok/s agregados | tok/s por cliente | Latencia media |
|:---|:---|:---|:---|
| 1 | 44.5 | 44.5 | 2.9 s |
| 4 | 172.3 | 43.1 | 3.0 s |
| 8 | 334.4 | 41.8 | 3.1 s |

Coherente con el hardware: 7.85 GiB de pesos sobre ~450 GB/s dan un techo de ~57 tok/s por flujo, y saca 44.5 (78 %). Los ~150 tok/s de la receta eran de una RTX 5090 y no aplican aquí.

**Gemma se paró sola a los ~16 s de arrancar** (servidor `health` OK y luego `shutdown triggered`, salida con código 0, sin ningún error). No era un fallo de vLLM: **WSL2 apaga la distro cuando deja de haber sesiones abiertas** y los contenedores no cuentan como sesión. Al terminar el `wsl -e ... serve-model.sh`, ~15 s después la distro se cerraba y Docker mandaba SIGTERM. El Router se libró antes solo porque el siguiente comando `wsl` llegó a tiempo.

- **Síntoma:** el servidor «se cae» poco después de arrancar, sin error alguno en el registro y con código de salida 0.
- **Solución de laboratorio:** `Start-WslKeepAlive.ps1` deja un `wsl.exe -e sleep infinity` oculto que hace de sesión. Idempotente; `-Stop` lo detiene.
- **Pendiente para dejarlo permanente:** algo que arranque con Windows (tarea programada al iniciar sesión) y lance el keep-alive y los perfiles. Va con la pasarela y el árbitro de GPU.

### 7.9 KV fijado en bytes, y dos trampas nuevas [medido]

Con `--kv-cache-memory` (vLLM se salta el perfilado y reserva justo esos bytes) el Router arrancó en 160 s con **0.65 GiB de KV = 17 246 tokens** y ~4.0 GiB en total. El primer intento de Gemma a su lado (KV 1.5 GiB, contexto 12 288) falló:

- **`To serve at least one request with the model's max seq len (12288), 1.75 GiB KV cache is needed`**: una petición de longitud máxima necesita más KV que la media repartida entre peticiones (2.57 GiB / 23 189 tokens).
- **Corrección de mi regla inicial** (no es proporcional al contexto). Segundo intento con contexto 8 192 y KV 1.25 GiB: `1.69 GiB KV cache is needed`. Con los dos puntos medidos (8 192 → 1.69 GiB; 12 288 → 1.75 GiB) el KV de Gemma crece solo ~15 KiB por token y tiene un **suelo de ~1.6 GiB** (capas de ventana deslizante). **Gemma necesita ≥ 1.75 GiB de KV con cualquier contexto de 8k o más**, así que reducir el contexto ahorra casi nada. Se fija KV 1.75 GiB y contexto 8 192.
- **`nvidia-smi` puede infravalorar la VRAM bajo WSL2.** Con el Router sano marcaba 2.3 GiB en vez de ~5.4: WDDM (el gestor de memoria de Windows) desalojó a RAM parte de sus asignaciones al haber presión durante el arranque de Gemma. Sin error y sin OOM; al volver a usarse el Router recuperó su rendimiento (76.5 tok/s frente a 78). **Consecuencia:** pasarse de la VRAM física no da OOM, se paga en silencio con paginación. El total de las instancias tiene que quedar **por debajo** de los ~15.9 GiB menos lo que use Windows (1.4-2.5 GiB), y hay que medir tok/s, no fiarse solo de `nvidia-smi`.

### 7.10 Perfil A funcionando: Router + Rápido a la vez [medido]

Configuración que arranca (`serve-model.sh`, KV fijado en bytes, `--max-num-batched-tokens 2048`, memoria fijada de WSL2 activada):

| Instancia | Contexto | KV | Total en GPU aprox. | Arranque (cachés calientes) |
|:---|:---|:---|:---|:---|
| Router `qwen3.5-4b-nvfp4` (b12x) | 16 384 | 0.65 GiB (17 246 tokens) | ~4.2 GiB | 160 s |
| Rápido `gemma-4-12b-awq` (Marlin) | **8 192** | 1.75 GiB | ~10.0 GiB | 73 s |

Con ambas cargadas la GPU marca **15 547 MiB de 16 311** (margen de ~0.75 GiB, incluidos ~1.4 GiB de Windows). Es el máximo que admite este hardware: cualquier crecimiento del escritorio lo desborda y se paga en paginación silenciosa (apartado 7.9).

**Rendimiento con las dos instancias cargadas, una a una** (3 peticiones por cliente, 128 tokens):

| Clientes | Router (tok/s) | Gemma (tok/s) |
|:---|:---|:---|
| 1 | 81.9 | 40.8 |
| 4 | 297.3 | 155.5 |
| 8 | 544.3 | 299.1 |

El Router no se resiente frente a su marca en solitario (78 / 296 / 538). Gemma pierde ~8 % (44.5 / 172 / 334 en solitario), atribuible a la poca holgura de memoria.

**Bajo carga simultánea** (4 clientes en cada una a la vez, 256 tokens):

| | tok/s agregados | Frente a su marca con 4 clientes en solitario |
|:---|:---|:---|
| Router | 126.6 | 43 % de 297 |
| Gemma | 102.1 | 66 % de 155 |

43 % + 66 % ≈ 1.09: **las dos instancias se reparten la GPU en el tiempo**, sin ganar ni perder rendimiento total. No hay «doble capacidad» por tener dos modelos activos; lo que se gana es no pagar recargas al alternar entre ellos. Para el diseño: si el tráfico del Router es ligero (clasificación, respuestas cortas), Gemma apenas lo nota.

**Límites del perfil A tal como está:** Gemma a 8 192 de contexto (no los 32k de la receta) y Router a 16 384. Subir cualquiera exige quitar memoria a la otra o liberar VRAM de Windows.

### 7.11 Complejo (Qwen3-Coder-30B NVFP4 MoE): primer intento [medido]

Arrancado solo, sin Router (`--gpu-memory-utilization 0.75`, sin flags de eager). Falló a los 130 s con **`CUDA error: an illegal memory access was encountered`**.

| Dato | Valor |
|:---|:---|
| Backend MoE | `B12X` NvFp4 (el pedido con `--moe-backend b12x`) |
| Kernel lineal | `B12xNvFp4LinearKernel` |
| Backend de atención | `FLASHINFER` (el modelo trae KV cache en FP8: `kv_cache_dtype=fp8_e4m3`) |
| Pesos | **9.33 GiB** |
| Dónde falla | `profile_cudagraph_memory → capture_model`: al **capturar grafos CUDA**, tras cargar el modelo |

Coincide con lo que avisaba la receta (doc 02 §12.6 y doc 04): en SM120, los grafos CUDA / `torch.compile` fallan con NVFP4 MoE y hay que usar `--enforce-eager`. Se prueba así primero para tener una base que funcione, y después se mide cuánto rendimiento cuesta (apartado 4, palanca «quitar `--enforce-eager`»).

**Segundo intento, con `--enforce-eager`: arranca, pero rinde muy mal.**

| Dato | Valor |
|:---|:---|
| Arranque | 83 s |
| Pesos + no-torch | 9.51 GiB (pesos 9.33 GiB) |
| Pico de activaciones | 0.08 GiB |
| KV cache en FP8 con 0.75 | 2.35 GiB = **51 328 tokens** (3.13x a 16k), ~46 KiB por token |
| Rendimiento (1 / 4 clientes) | **7.3 / 27.7 tok/s** agregados (latencia 17 s por 128 tokens) |

El KV del Complejo es muy eficiente (FP8, atención con pocos cabezales KV: 0.8 GiB bastan para una petición de 16k). Pero 7.3 tok/s con solo 3B parámetros activos es una fracción de lo esperable (Router: 78, Gemma: 44.5): sin grafos CUDA cada token lanza miles de kernels desde Python, y la CPU se convierte en el cuello de botella. **`--enforce-eager` funciona pero no es utilizable**: hay que arreglar los grafos CUDA. Se prueba `--attention-backend TRITON_ATTN` (la receta lo exigía para NVFP4) sin eager.

**Tercer intento, `--attention-backend TRITON_ATTN` sin eager: falla igual** (`illegal memory access` al capturar grafos). Descarta la atención: no es FlashInfer con KV en FP8. El sospechoso pasa a ser el backend MoE `b12x` dentro de los grafos CUDA. Alternativas válidas en vLLM 0.29 (`vllm/config/kernel.py`): `flashinfer_cutlass`, `flashinfer_b12x`, `flashinfer_cutedsl`, `flashinfer_trtllm`, `cutlass`, `marlin`, `triton`. Se prueban de una en una, sin eager.

**Cuarto intento, `--moe-backend flashinfer_cutlass` con grafos CUDA: funciona y es 14 veces más rápido que eager.**

| Clientes | `--enforce-eager` + b12x | Grafos + `flashinfer_cutlass` |
|:---|:---|:---|
| 1 | 7.3 tok/s | **100.0 tok/s** |
| 4 | 27.7 | **257.7** |
| 8 | — | 258.3 (tope de `--max-num-seqs 4`; se encolan) |

Arranque 119 s. Memoria: pesos 9.33 GiB (+0.17 no-torch), **pico de activaciones 1.08 GiB** (con b12x eran 0.08: el espacio de trabajo del MoE de FlashInfer es mucho mayor), grafos 0.09 GiB, KV 1.37 GiB = 29 808 tokens a 0.75 de utilización.

**Conclusión: el `--moe-backend b12x` que la receta obliga a forzar es el que rompe los grafos CUDA en esta versión.** El kernel lineal sigue siendo `B12xNvFp4LinearKernel`, solo el MoE cambia. La receta (doc 04, advertencia 12.4) «SIEMPRE especificar `--linear-backend b12x --moe-backend b12x`» queda corregida: para el MoE, `flashinfer_cutlass`. No se probaron `flashinfer_b12x`, `flashinfer_cutedsl` ni `marlin` porque ya hay uno que funciona bien.

El coste de esta elección es memoria: 1.08 GiB de activaciones con `--max-num-batched-tokens 2048`. Se acota a 1024 en `serve-model.sh` para el perfil B.

### 7.12 Perfil B: primer arranque y una trampa de WSL2 [medido]

Con `serve-model.sh complex` (KV fijado a 0.85 GiB, `--max-num-batched-tokens 1024`, `flashinfer_cutlass`): arranca en 119 s, KV = 18 560 tokens (1.13x a 16k), y la GPU marca 12 813 MiB en total (el Complejo son ~11.4 GiB, sin Windows).

Después el Router (con `--cpu-offload-gb 1.5`, contexto 8 192, KV 0.4 GiB) **falló** con `Free memory on device cuda:0 (14.23/15.93 GiB) on startup is less than desired GPU memory utilization (0.92, 14.65 GiB)`. Dos lecciones:

1. **`--kv-cache-memory` no evita el chequeo de la fracción por defecto (0.92).** Antes el Router pasaba solo por suerte (14.8 GiB libres ≥ 14.65). Se corrige en `serve-model.sh`: en modo KV se pasa también `--gpu-memory-utilization 0.5`, que no se usa para nada más.
2. **Bajo WSL2 cada instancia ve casi toda la GPU como libre.** El Router leyó 14.23 GiB libres teniendo ya cargado el Complejo (~11 GiB); igual le pasó a Gemma con el Router al lado (14.8 GiB). Consecuencia: **vLLM nunca detecta que te pasas de memoria entre instancias**, y el único freno es la aritmética propia (más el reparto medido, apartado 7.10). Pasarse no da OOM: da paginación silenciosa (apartado 7.9).

### 7.13 Offload a RAM del Router: probado y descartado [medido]

Perfil B con `--cpu-offload-gb 1.5` en el Router (contexto 8 192, KV 0.4 GiB) junto al Complejo. Arrancaron los dos, pero:

| | Con el otro cargado | Referencia (solo) |
|:---|:---|:---|
| Complejo, 1 / 4 clientes | 98.2 / 257.0 tok/s | 100 / 258 (sin efecto) |
| **Router con offload**, 1 / 4 / 8 clientes | **3.0 / 11.8 / 13.9 tok/s** (latencia 42 s por 128 tokens) | 78 / 296 / 538 |
| Arranque del Router | 259 s | 160 s |

**El offload de un modelo denso es inviable.** Cada token lee todos los pesos; sacar 1.5 GiB de la GPU obliga a traerlos por PCIe en cada paso. El ancho de banda efectivo medido bajo WSL2 es de ~4.5 GB/s (no los ~25 GB/s teóricos de PCIe 5.0 x8), así que **cada GiB offloadeado cuesta ~0.2 s por token**: 1.5 GiB → 0.33 s → 3 tok/s. La estimación del apartado 5.1 («decenas de ms por token») se quedaba corta en un orden de magnitud.

Tampoco hay parte «barata» que sacar en el Router: `tie_word_embeddings: true`, así que su tabla de embeddings (248 320 × 2560 en BF16 = 1.18 GiB) se lee entera en cada token para calcular la salida.

vLLM 0.29 ofrece dos mecanismos más finos (`vllm/config/offload.py`): **UVA con `cpu_offload_params`** (elegir parámetros por nombre) y **prefetch** (`--offload-group-size`, `--offload-num-in-group`, `--offload-prefetch-step`, precarga capas mientras calcula). Ambos siguen limitados por el mismo ancho de banda si lo offloadeado se lee en cada token; solo tendrían sentido para los **expertos del MoE** del Complejo, donde por token solo se leen 8 de 64 por capa. No probado.

**Conclusión sobre la petición del usuario** («Router y Complejo juntos con un poco de offload»): juntos sí caben, pero **no con offload del Router**. La alternativa es recortar contextos y `--max-num-batched-tokens` para que quepan sin offload (apartado 7.14).

### 7.14 Perfil B sin offload: Router + Complejo juntos [medido]

Configuración (sin `--cpu-offload-gb`), recortando lo recortable:

| Instancia | Contexto | `--max-num-batched-tokens` | KV | Arranque |
|:---|:---|:---|:---|:---|
| Complejo (`flashinfer_cutlass`, grafos CUDA) | **8 192** | 256 | 0.45 GiB | 129 s |
| Router (b12x) | 8 192 | 512 | 0.4 GiB | 239 s |

Con las dos cargadas la GPU marca **15 739 MiB de 16 311** (margen de ~0.57 GiB con Windows incluido): **caben, con el margen más justo de todo el trabajo.**

| Clientes | Router | Complejo | Referencia en solitario |
|:---|:---|:---|:---|
| 1 | 82.9 tok/s | 74.6 tok/s | 78 / 100 |
| 4 | 280.3 | 182.8 | 296 / 258 |
| 8 | 334.2 | — | 538 / — |

Se descartó que la caída del Router sea por presión de memoria: **parando el Complejo y midiendo el Router con la misma configuración recortada da lo mismo** (82.4 / 288.4 / 326.6 tok/s). Es su KV de 0.4 GiB, que solo admite unas pocas peticiones simultáneas (el Router es un modelo híbrido: cada petición reserva también estado propio), y las demás se encolan. El descenso del Complejo (100 → 75 tok/s) no está aclarado: candidatos, `--max-num-batched-tokens 256` o la presión de memoria; se repite con 512.

**Aclarado: era `--max-num-batched-tokens 256`.** Reiniciando el Complejo con **512** (mismo contexto y KV), con el Router cargado:

| Clientes | Complejo con 256 | Complejo con 512 | Solo (1024) |
|:---|:---|:---|:---|
| 1 | 74.6 tok/s | **97.1** | 100 |
| 4 | 182.8 | **262.1** | 258 |

Con 512 recupera todo su rendimiento. **Corrección de una lectura de memoria optimista:** la GPU marcó 14 914 MiB con las dos cargadas y en reposo, pero al usarlas sube (14 617 → **15 747 MiB** tras el benchmark en la validación de `serve-profile.sh`): Windows deja parte de la memoria desalojada hasta que se toca (apartado 7.9), así que las lecturas en reposo infravaloran. **El margen estable del perfil B es de ~0.56 GiB de 16.3, no de 1.4.** Mide siempre después de dar carga. **Configuración final del perfil B:** Complejo ctx 8 192, batched 512, KV 0.45 GiB; Router ctx 8 192, batched 512, KV 0.4 GiB. Está en `serve-profile.sh B`.

**Coste de que quepan:** el contexto útil del Complejo baja de 16 384 a **8 192 tokens** (poco para tareas de código sobre varios ficheros) y el Router a 8 192. Si se quiere más contexto en el Complejo hay que apagar el Router mientras.

### 7.15 KV en RAM (`--kv-offloading-size`): falla bajo WSL2 [medido]

`bench-prefix-reuse.py` manda 6 prompts largos y distintos (~2 800 tokens cada uno, ~17 000 en total frente a un KV de la GPU de ~9 800 tokens) y repite la tanda. Diseñado para que, sin offload, cada ronda tenga que recalcular todo.

**Baseline sin offload** (Complejo del perfil B):

| Ronda | Prompt | Desde caché | Latencia media |
|:---|:---|:---|:---|
| 1 | 2 822 tok | 0.0 % | 0.61 s |
| 2 | 2 822 tok | 0.0 % | 0.66 s |
| 3 | 2 822 tok | 0.0 % | 0.62 s |

Los prompts se desalojan unos a otros (0 % de aciertos) y el Complejo procesa ~2 800 tokens de prefill en 0.6 s (~4 500 tok/s). **El margen de mejora es pequeño en términos absolutos**: recargar ~130 MiB de KV desde RAM costaría ~0.03 s, así que el ahorro máximo sería ~0.55 s por petición, y solo compensa con prompts muy largos.

**Con `--kv-offloading-size 4 --kv-offloading-backend native`:** el servidor arranca (`OffloadingConnector` + `CPUOffloadingSpec`, región de 4.29 GB en `/dev/shm`), pero la **primera petición** falla con HTTP 500 y `CUDA error: an illegal memory access` en el primer paso de ejecución (`step_counter=0`), seguido de `cudaHostUnregister failed (code=700)`. Sin el conector, los mismos prompts funcionan. **Causa no aislada**; hipótesis: el conector registra esa región compartida como memoria fijada para hacer DMA y WSL2 no lo soporta. No se ha probado el backend `lmcache` (no viene en la imagen).

**Conclusión: el KV en RAM no es utilizable en este entorno con vLLM 0.29.0**, y su beneficio esperado con el Complejo era pequeño. Se descarta por ahora; se reabre si se cambia de imagen de vLLM o de plataforma.

### 7.16 Sleep Mode [primer intento INVÁLIDO; ver 7.17]

> **Corrección (19-sep-2026):** lo que sigue en este apartado se escribió con una conclusión errónea. El «cuelgue» se produjo con la GPU ya rota por el fallo del KV en RAM (apartado 7.15), no por Sleep Mode: el mismo arranque **sin** Sleep Mode se colgó igual, y una prueba mínima de CUDA también. Tras `wsl --shutdown` todo volvió a funcionar. Se conserva el texto original, con esta advertencia, por honestidad; **las conclusiones y consecuencias de diseño de este apartado quedan sustituidas por las del 7.17**. La lección general: *un fallo tras otro fallo no es un dato independiente*; ante un cuelgue sin excepción, primero `check-cuda.sh`.

Complejo del perfil B arrancado con `SLEEP_MODE=1` (`--enable-sleep-mode` más `VLLM_SERVER_DEV_MODE=1`, ambos en `serve-model.sh`). vLLM avisa de `Enabling cumem allocator because sleep mode requires it` y el servidor **no llegó a estar sano en 15 minutos**, sin ninguna excepción: el registro se detiene en `Using V2 Model Runner`, con la GPU sin una sola asignación del proceso (947 MiB usados, nada del modelo). Sin Sleep Mode el mismo arranque tarda ~2 minutos.

**Hipótesis (no comprobada):** el asignador `cumem` se apoya en la gestión de memoria virtual de CUDA (`cuMemCreate`/`cuMemMap`), que el controlador de CUDA para WSL2 no soporta bien. Es coherente con los otros fallos de esta tanda que tocaban memoria del sistema (`illegal memory access` del KV en RAM). No se ha probado ninguna vía para saltarlo.

**Consecuencias para el diseño:**
- La receta (doc 04) descansaba en Sleep Mode para alternar modelos con 16 GB de VRAM: **no es utilizable aquí**. Cambiar de perfil es **parar y arrancar** (`serve-profile.sh`): unos 2-4 minutos por modelo con cachés calientes, en lugar de <1 s (nivel 1) o 5-10 s (nivel 2).
- El plan de «árbitro de GPU» con ODM (apartado 6) se simplifica: para liberar la GPU basta **parar los contenedores** (`stop-models.sh`), que la deja sin nada; no hay «dormir». Volver a subir cuesta el arranque completo.
- Alternar entre A y B en caliente queda descartado como flujo de trabajo. Si se necesita, se tiene un perfil u otro durante un rato largo, no por petición.
- Si algún día se quiere Sleep Mode, habría que probar fuera de WSL2 (Linux nativo o Windows nativo con las ruedas comunitarias de vLLM).

### 7.17 Sleep Mode probado en limpio (GPU sana): funciona el nivel 1, el nivel 2 corrompe el modelo [medido]

**Qué pasó con el «cuelgue» del 7.16:** el fallo del KV en RAM (7.15) dejó **el estado de CUDA bajo WSL2 roto**. Síntomas: cualquier inicialización de CUDA se quedaba en un proceso al 100 % de CPU sin avanzar y sin excepción (arranque del Complejo con y sin Sleep Mode, y hasta una prueba mínima `check-cuda.sh`). Arreglo: `wsl --shutdown` (y volver a lanzar `Start-WslKeepAlive.ps1`); tras eso, CUDA inicializa en 0.46 s. **No tuvo nada que ver con Sleep Mode.** `check-cuda.sh` queda como primera comprobación ante cualquier arranque parado.

**Complejo con `SLEEP_MODE=1`** (`--enable-sleep-mode`, `VLLM_SERVER_DEV_MODE=1`): arranca en 124 s como sin él. `test-sleep-mode.py`:

| | Nivel 1 (pesos a RAM) | Nivel 2 (pesos descartados) |
|:---|:---|:---|
| Dormir | 13.5 s | 0.28 s |
| VRAM al dormir | 12 497 → **2 412 MiB** | 12 738 → **2 644 MiB** |
| Despertar | **1.87 s** | **25.9 s** (25.6 s de `reload_weights`) |
| Respuesta tras despertar | **coherente** (98 tok/s tras calentar) | **basura**: `'HereC111222222…'` |
| RAM del sistema | 4 066 → **15 790 MiB de 15 993** | sin ahorro medible |

- **Nivel 2: no usar.** Rinde igual pero genera texto sin sentido: `reload_weights` no restaura bien los pesos NVFP4 ya reempaquetados por vLLM tras cargarlos. **Es un fallo silencioso**: sin error, con buena velocidad y salida corrupta. Cualquier flujo que despierte con nivel 2 debe validar la salida.
- **Nivel 1 funciona**, con despertar de <2 s (frente a 2-4 min de parar y arrancar). La primera petición tras despertar va a ~44 tok/s (calentamiento) y a partir de ahí recupera 98 tok/s.
- **Pero el coste en RAM es el problema.** Al dormir con el nivel 1 el sistema pasa a **15.8 de 16 GB usados**, y **los buffers no se liberan al despertar**: con el modelo despierto sigue en 15.4 GB usados, 128 MB libres y 2.1 GB en swap. Con 16 GB para WSL2 solo cabe **un** modelo con Sleep Mode a la vez, sin holgura para el Router ni para nada más; y un modelo dormido de 9.3 GiB ocupa más de 11 GiB de RAM.
- **Consecuencia para el diseño:** alternar Rápido ↔ Complejo dormidos a la vez (9 + 7.8 GiB de pesos en RAM) **no cabe** en 16 GB de RAM. Sleep Mode nivel 1 solo sirve para **liberar la GPU temporalmente** (p. ej. para ODM) con un único modelo durmiendo, tolerando ~15 GB de RAM ocupados. Subir la RAM de WSL2 (apartado 1) lo aliviaría a costa de ODM.

### 7.18 Comprobación de coherencia de las respuestas [medido]

`bench.py` solo mide tokens por segundo: el nivel 2 de Sleep Mode (7.17) rindió 93 tok/s generando basura. `chat-check.py` hace tres preguntas con respuesta verificable (17 + 25, capital de Francia, contar del 1 al 5) a cada servidor levantado, con temperatura 0, y distingue **BASURA** (caracteres repetidos: modelo corrupto, fallo técnico) de una respuesta **incorrecta** (calidad del modelo). Sale con código 1 solo si hay basura.

Perfil B recién arrancado con `serve-profile.sh B` (tras `wsl --shutdown`):

| Modelo | 17 + 25 | Capital de Francia | Contar 1-5 |
|:---|:---|:---|:---|
| Router (Qwen 3.5 4B NVFP4) | OK | OK (`París`) | OK |
| Complejo (Qwen3-Coder-30B REAP-50 NVFP4) | OK | **incorrecta** (`'France'` la primera vez; `'Capital of France is a term used in the context of financial'` la segunda) | OK |

Ningún modelo genera basura, así que el perfil B está técnicamente sano. **Observación de calidad, no un fallo técnico:** el Complejo falla una pregunta trivial de cultura general y, con temperatura 0, no responde igual dos veces. Es un modelo de código con la mitad de los expertos podados (REAP-50) y cuantizado a 4 bits, y ahí se pierde conocimiento general. Tres preguntas no bastan para juzgar su calidad **en código**, que es para lo que se eligió: hace falta una evaluación real (por ejemplo un subconjunto de HumanEval o tareas del propio proyecto) antes de fiarse de él, en línea con el riesgo de validez del apartado 6.

RAM tras el reinicio limpio: 8.0 GB usados y 8.0 GB disponibles con los dos modelos cargados (sin Sleep Mode).

### 7.19 Pasarela autenticada (`llm-stack/gateway/`) [medido]

Crate de Rust independiente (`llm-stack/gateway/`, fuera del workspace de `core/`): axum 0.8, reqwest 0.13 sin TLS, tokio. **Es lo único que se ofrece a los clientes**; los vLLM quedan atados a `127.0.0.1`. README propio en `llm-stack/gateway/README.md`.

| Decisión | Motivo |
|:---|:---|
| Claves `ndk_…` (256 bits del sistema), guardadas **solo como hash SHA-256**, comparación en tiempo constante recorriendo todas | Un `keys.json` filtrado no da acceso; el tiempo de respuesta no delata si una clave existe |
| Sin ninguna clave, nadie entra; un `keys.json` corrupto también deniega | El estado por defecto es denegar |
| Clave ausente y clave incorrecta dan **la misma respuesta** | No se dice cuál de las dos falló |
| Solo `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/health`; **todo lo demás 404 aunque la clave sea válida** | Los endpoints de `VLLM_SERVER_DEV_MODE=1` (`/sleep`, `/collective_rpc`…) no deben llegar a ningún cliente |
| Enrutado por el campo `model`; 404 con la lista si no existe, 503 claro si está apagado | El perfil activo decide qué modelos hay |
| Streaming como flujo, sin acumular | El SSE llega token a token |
| El registro no lleva prompts, respuestas ni claves | Pueden contener código o datos privados |
| Escucha en `127.0.0.1:8888`; avisa si se cambia a otra dirección | HTTP sin TLS: para salir de la máquina hace falta un túnel |
| Claves revocables **en caliente** (relee `keys.json` al cambiar su fecha) | Sin reiniciar la pasarela |

**Pruebas:** 12 unitarias + 14 de integración con servidores vLLM de mentira (`cargo test`), `cargo clippy --all-targets` limpio, y `llm-stack/scripts/Test-Gateway.ps1` (prueba de humo contra el stack real, con una clave desechable en un directorio temporal): `/health`, 401 sin clave y con clave mala, `/v1/models`, generación en **Router y Complejo** a través de la pasarela desde Windows, streaming SSE con `[DONE]`, 404 en `/sleep`, `/wake_up`, `/collective_rpc`, `/metrics` y `/is_sleeping`, 503 con Gemma apagada, revocación en caliente y registro sin prompts ni claves. **Todo OK.**

**Un fallo que solo apareció al arrancar el stack de verdad:** `/health` sondeaba los servidores dentro de la propia petición, con 2 s de espera por sondeo. Con los modelos apagados tardaba **2.05 s**, más de lo que espera un healthcheck, así que `Start-Stack.ps1` (espera 2 s) nunca la veía sana y habría abortado antes de arrancar los modelos. Ni los tests ni la prueba de humo lo vieron porque en ambos los modelos apagados rechazaban la conexión al instante; con WSL2 recién arrancado tarda. **Arreglo:** un sondeo en segundo plano cada 2 s y `/health` responde al instante con lo último sabido (`up`/`down`/`unknown` en los primeros instantes). Test nuevo: un modelo que acepta la conexión y no contesta no puede retrasar `/health` más de 500 ms.

### 7.20 Arranque permanente [medido parcialmente]

Tres scripts de PowerShell en `llm-stack/scripts/` (ASCII puro: Windows PowerShell 5.1 lee mal los `.ps1` UTF-8 sin BOM):

| Script | Qué hace |
|:---|:---|
| `Start-Stack.ps1 -Profile A\|B\|complex-solo\|none` | Sesión de WSL2 (keep-alive) → espera a Docker → **pasarela** → modelos del perfil → comprobación por `/health`. La pasarela va antes que los modelos: mientras cargan (2-6 min) los clientes reciben un 503 claro en vez de «conexión rechazada». Registro en `%LOCALAPPDATA%\nexodeck\LlmGateway\logs` |
| `Stop-Stack.ps1 [-KeepGateway] [-ReleaseWsl]` | Para los contenedores y la pasarela; con `-ReleaseWsl` cierra la sesión y termina la distro, devolviendo la RAM a Windows. Es la forma de hacer sitio a ODM, entrenamientos o juegos |
| `Install-StackTask.ps1 [-Profile …] [-Remove] [-Status] [-WhatIf]` | Registra la tarea `NexoDeckLlmStack`: al iniciar sesión, con retraso de 60 s, ejecuta `Start-Stack.ps1`. Como tu usuario, sin elevar, reversible |

**Advertencia de diseño:** un perfil con modelos ocupa ~15 GiB de VRAM y 8+ GB de RAM de WSL2 **en cada inicio de sesión** y compite con ODM, entrenamientos y juegos; no se pueden dormir (7.17). Por eso el perfil por defecto de la tarea es `none` (solo pasarela, casi gratis) y los modelos se arrancan cuando hacen falta.

Comprobado: `Stop-Stack.ps1 -ReleaseWsl` deja la GPU en 811 MiB (solo Windows) y a Windows con 14.8 GB de RAM libre; `Start-Stack.ps1` levanta WSL2 en frío, espera a Docker (5 s) y arranca la pasarela.

**Cambio de decisión (2026-09-24):** la tarea `NexoDeckLlmStack` quedó **deshabilitada** (`Disable-ScheduledTask -TaskName "NexoDeckLlmStack"`). El disparo automático al iniciar sesión de Windows resultó indeseado: levantaba WSL2/`vmmemWSL` en cada arranque aunque no se fuera a usar NexoDeck ni sus funciones de IA en esa sesión.

**Regla vigente:** `NexoDeckLlmStack` se habilita **únicamente cuando se abre el programa NexoDeck y se van a usar sus funciones de IA** — no al iniciar sesión de Windows en general. En la práctica: habilitar la tarea (o correr `Start-Stack.ps1` directamente) justo antes de usar IA dentro de NexoDeck, y volver a deshabilitarla (o `Stop-Stack.ps1 -ReleaseWsl`) al cerrar NexoDeck o terminar de usar esas funciones. Queda pendiente que NexoDeck mismo dispare este arranque/apagado al abrir/cerrar la app (en vez de depender de la tarea de inicio de sesión); hasta entonces es un paso manual.

### 7.21 NexoDeck como cliente: no hace falta código, sí *tool calling* [medido]

Se revisó cómo se conecta NexoDeck a un servicio de IA (`nexodeck-ai/src/remote.rs`, `provider.rs`, `remote_provider_dialog.dart`):

- **No hace falta código nuevo.** Ya existe la variante `ChatProvider::Remote` y un preset **`custom`** pensado para «un proxy propio». En el diálogo de proveedor remoto basta elegir *custom* con dirección `http://127.0.0.1:8888` (`normalize_base_url` acepta `http://`), modelo `router` o `complex`, y la clave `ndk_…`. Al guardar comprueba la clave con `GET /v1/models`, que la pasarela sirve. Lo que planeaba como «una variante de `ChatProvider`» ya está hecho.
- **Sí hay un hueco en el servidor, y no se veía sin probarlo con la petición real.** El agente de NexoDeck manda `tools` + `tool_choice: auto`. Los dos modelos, tal como estaban arrancados, contestaban **HTTP 400**: `"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set`. La receta sí llevaba esos flags; mis scripts de arranque no. Habría fallado el primer mensaje con herramientas.
- **`Remote` nunca manda `enable_thinking: false`** (`disable_thinking()` es `false` para los remotos). El Router (Qwen 3.5) razona por defecto, con lo que cada respuesta iría precedida de un razonamiento largo. Se desactiva en el servidor con `--default-chat-template-kwargs '{"enable_thinking": false}'`.

Cambios en `serve-model.sh` (comprobados contra la ayuda real de vLLM 0.29.0 con `vllm-help.sh`, que necesita `--gpus all` o `vllm serve --help` muere con «Failed to infer device type»):

| Rol | Flags añadidos |
|:---|:---|
| Router | `--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 --default-chat-template-kwargs '{"enable_thinking": false}'` |
| Complejo | `--enable-auto-tool-choice --tool-call-parser qwen3_coder` |
| Rápido (Gemma) | **Pendiente**: existe el parser `gemma4`, pero no se ha probado y el perfil A ya funcionaba; se añade cuando se vuelva a arrancar |

`tools-check.py` reproduce la forma de petición del agente (por la pasarela): comprueba que el servidor **acepta** `tools`, que el modelo **llama** a la herramienta y que los **argumentos** llegan como JSON válido, e informa de si razona en voz alta. Repite la petición con `stream: true` (NexoDeck **siempre** hace streaming SSE) y recompone la llamada a partir de los `delta.tool_calls`.

**Resultado tras reiniciar el perfil B con los flags nuevos:**

| Modelo | Acepta `tools` | Llama a la herramienta | Argumentos | Streaming SSE | Razona en voz alta |
|:---|:---|:---|:---|:---|:---|
| Router | sí (HTTP 200) | sí | `get_disk_usage({"drive": "D"})` | 6 trozos + `[DONE]`, llamada recompuesta | no |
| Complejo | sí (HTTP 200) | sí | `get_disk_usage({"drive": "D"})` | 6 trozos + `[DONE]`, llamada recompuesta | no |

`Test-Gateway.ps1` y `chat-check.py` siguen en verde (el Complejo sigue fallando la pregunta de cultura general, sin basura). Los flags no cambiaron el arranque: Complejo 72 s, Router 151 s.

**Limitación:** se ha emulado la petición del agente con `tools-check.py`, pero **no se ha probado desde la interfaz de NexoDeck** (no hay automatización de UI del diálogo de proveedor remoto). Falta darlo de alta a mano: «proveedor remoto» → *custom*, `http://127.0.0.1:8888`, modelo `router` o `complex`, y la clave.

**Actualización (2026-09-23): el hueco de código está cerrado.** `CUSTOM_PRESET_ID` existía en `nexodeck-ai/src/remote.rs` pero **no lo devolvía `presets()`**, así que la UI no ofrecía «custom» (el párrafo de arriba lo daba por hecho y no era cierto). Ahora sí se devuelve («Otro (proxy propio)», sin dirección, modelo ni página de claves fijos: los escribe el usuario) y el diálogo no enseña «Copiar dónde sacarla» cuando el proveedor no tiene página. Verificado a nivel de pasarela con una clave nueva: `tools-check.py --model auto` da **HTTP 200, llama a `get_disk_usage`, sin razonar en voz alta, y con `stream: true` recompone la llamada** (`cargo test -p nexodeck-ai`: 180; `flutter analyze` sin avisos nuevos). **Queda el alta a mano en la UI** —proveedor remoto → *Otro (proxy propio)* → `http://127.0.0.1:8888`, modelo `auto`, clave `ndk_…`— y el chat real, que no se automatizan aquí.

### 7.22 Modelo virtual `auto` y registro de decisiones (fase 5, simplificada) [medido]

Implementado en la pasarela (`llm-stack/gateway/src/route.rs`, `decisions.rs`, `proxy.rs`); detalle y reglas en `llm-stack/gateway/README.md`. Las decisiones y sus prioridades son las del doc 05 (`meta` 300 › `complex_keywords` 210 › `complex` 200 › `simple` 100 › `normal` 50, con los umbrales de 150 y 800 **caracteres**), con dos cambios que salen de lo medido:

1. **Dos niveles, no tres modelos.** El Rápido y el Complejo no conviven, así que el destino es `Light` (Router) o `Worker` (el primero de `workers` que esté levantado: Complejo en el perfil B, Gemma en el A). `simple` pasa del Rápido al **Router**; antes de eso el Router solo servía de meta-agente.
2. **Palabras clave también en español**, porque los prompts reales lo son (`refactoriza`, `arquitectura`, `optimiza`, `varios ficheros`…). Se busca como subcadena, sin distinguir mayúsculas. Es tosco (`tool` también casa con `toolbar`); se afina con los datos del registro.

Si el nivel elegido está apagado **conmuta al otro** y lo registra (`fallback: true`); si no hay nada levantado, 503.

**Decisiones de diseño pequeñas que importan:**
- **El separador entre mensajes no cuenta como longitud.** Un primer intento sumaba un salto de línea por mensaje y un texto de 149 caracteres medía 150: lo cazó un test de los umbrales; se separó el conteo del texto usado para buscar palabras clave (que sí lleva separador, para que `refac` + `tor` en dos mensajes no formen `refactor`).
- **Se reescribe el campo `model`** con el nombre real antes de reenviar, porque vLLM contestaría 404 a `auto`; las peticiones con modelo explícito se reenvían intactas.
- **El registro guarda medidas, nunca texto** (`decisions.jsonl`: decisión, modelo, conmutación, estado, ms hasta la primera respuesta, caracteres, herramientas). Un test comprueba que una marca dentro del prompt no aparece en él ni en el registro de la pasarela.
- Compatible hacia atrás: el bloque `auto` de `gateway.json` es opcional.

**Pruebas:** 38 unitarias + 24 de integración (`cargo test`), clippy limpio. Las de integración cubren enrutado corto/largo/palabra clave, reescritura del `model` sin tocar el resto del cuerpo, conmutación en los dos sentidos, perfil A (Gemma como trabajador), 503 sin nada levantado, `auto` en `/v1/models`, y el registro. `Test-Gateway.ps1` gana una sección `[modelo virtual auto]` contra el stack real: los cuatro casos enrutan como se espera y el registro tiene una línea por petición sin el texto. Y `tools-check.py --model auto` con la pasarela permanente: petición de agente con herramientas y streaming, correcta, enrutada al Router por `simple`.

**Lo que esto NO resuelve:** las reglas son heurísticas de longitud y palabras, no semánticas, y las cifras 150/800 son de la receta, no medidas con tráfico real. Se ajustan con el registro tras unos días de uso, que es para lo que existe.

### 7.23 Calidad en código: HumanEval del Complejo y del Router [medido]

Motivo: el Complejo era el modelo sobre el que se iba a construir todo y había fallado una pregunta trivial de cultura general (7.18). `eval-humaneval.py` (164 problemas de Python, pass@1, temperatura 0, directo a vLLM) y `analyze-eval.py`. **El código que genera el modelo se ejecuta en un contenedor aislado**: sin red, sistema de ficheros de solo lectura, sin root, sin capacidades, con límites de memoria, CPU y procesos y `timeout`. Antes de fiarse de las cifras, `--selftest` comprueba el propio evaluador: acepta la solución canónica, rechaza una incorrecta, corta un bucle infinito y **bloquea de verdad** la red, la escritura en el montaje y en la raíz, y no corre como root.

| Modelo | 1.ª pasada | 2.ª pasada | Rango |
|:---|:---|:---|:---|
| **Complejo** (Qwen3-Coder-30B REAP-50 NVFP4) | 148/164 = 90.2 % | 146/164 = 89.0 % | **89-90 %** |
| **Router** (Qwen 3.5 4B NVFP4) | 130/164 = 79.3 % | 123/164 = 75.0 % | **75-79 %** |

- **Con temperatura 0 los resultados no se repiten** (Router −7 problemas, Complejo −2 entre pasadas): con varias peticiones a la vez el orden del lote cambia el redondeo y puede cambiar un token. Por eso se dan rangos, no una cifra. La diferencia entre modelos (~11-14 puntos) es mayor que ese ruido; la del Complejo entre pasadas (1.2 puntos) no es distinguible de él.
- **La poda y la cuantización del Complejo apenas costaron en código**: la receta citaba 90.9 % para el Qwen3-Coder-30B sin podar (dato de la propia receta, no comprobado aquí) y la medida es 89-90 %. **Su fallo de cultura general no se traslada a código.**
- **Solapamiento (2.ª pasada):** los resuelven los dos 121; solo el Complejo, 25; solo el Router, 2; ninguno, 16 (32, 54, 75, 91, 93, 115, 118, 120, 126, 127, 129, 130, 132, 145, 160, 163).
- **Modo de fallo del Router:** los 7 `SyntaxError` de la 2.ª pasada (5 en la 1.ª) son **todos respuestas cortadas a los 1024 tokens por un bucle de repetición** (`if a == 91: return False`, `if a == 92: …` sin fin), no un fallo de extracción. Es un vicio conocido de los modelos pequeños con decodificación voraz. En uso real vLLM aplica por defecto el `generation_config.json` del modelo cuando la petición no fija muestreo, así que no es representativo de cómo lo usaría NexoDeck; sí lo es de lo que pasa con temperatura 0.
- El Router genera más tokens por problema (230-239 frente a 152-160) y tarda más (140-147 s frente a 115-124 s) precisamente por esos bucles.

**Consecuencias para el diseño:**
1. El Complejo **queda validado para código**: se puede seguir construyendo sobre él.
2. El Router es **bastante mejor de lo que cabía esperar de un 4B** (75-79 %), lo que respalda mandarle lo simple desde `auto` (7.22); pero **pierde ~11-14 puntos** frente al Complejo en código, así que las tareas de código no triviales van al trabajador. Es lo que hacen las reglas `complex_keywords` y `complex`.
3. Cualquier bucle de auto-mejora (fases 8-10) que use el Router como verificador o generador debe **fijar `temperature > 0` o una penalización de repetición** y un tope de tokens, o heredará estos bucles.

**Límites de lo que mide:** HumanEval son funciones cortas y autocontenidas, y es un benchmark conocido (puede estar en los datos de entrenamiento). Sirve para comparar modelos y descartar problemas graves, **no** como garantía sobre código real del proyecto ni sobre *tool calling* multi-paso. Una sola muestra por problema (pass@1); con 164 problemas el error estándar es de ~2-3 puntos. No se evaluó Gemma (perfil A).

### 7.24 Fases 8-10: qué es real, qué se puede probar sin GPU y qué NO conviene hacer todavía [medido]

**1. Las referencias de la receta, comprobadas (19-sep-2026):**

| Referencia | ¿Existe? | Lo que realmente es |
|:---|:---|:---|
| RSIAgent — [arXiv 2609.15364](https://arxiv.org/abs/2609.15364), repo `AetherLabsAI/RSIAgent` (Apache-2.0, Python 3.12, 351 estrellas) | **Sí** | Marco *sin entrenamiento* con tres agentes (Curriculum, Actor, Verifier) que **explora entornos digitales nuevos** (OSWorld-v2, Agent's Last Exam) y congela una memoria. Su README documenta `run_osworld.py` y `run_ale.py`; **no confirma** la API `rsiaagent.config`, `MemoryStore.initialize` ni `--phase brs/drs` del doc 08 |
| APEX-EM — [arXiv 2603.29093](https://arxiv.org/abs/2603.29093) (EMNLP 2026) | **Sí** | Memoria procedimental-episódica; +7.6 puntos en BigCodeBench **con GPT-4o** (no con modelos pequeños locales) |
| Dream-RSI — [arXiv 2609.14858](https://arxiv.org/html/2609.14858v1) (Google/DeepMind) | **Sí** | «Hasta 162x menos llamadas» en ingeniería de algoritmos, optimización y kernels de GPU con Gemini-3.1-Pro, reproduciendo árboles de descubrimiento **con resultados puntuados** (p. ej. 51 200 llamadas → 317 en un solver Lasso) |

Consecuencias: (a) los comandos y módulos del doc 08 siguen **sin verificar** y el marco de RSIAgent está orientado a otro problema (explorar entornos), no a afinar un asistente local; (b) trasladar Dream-RSI a «optimizar las decisiones de un enrutador» es una **analogía nuestra**, no lo que hace el paper; (c) ambas ideas solo funcionan si cada decisión tiene un **resultado verificable**. Eso, que la receta no tenía, ya existe: el evaluador aislado con tests (7.23).

**2. Prototipo de «reproducción» sin GPU** (`llm-stack/scripts/replay-routing.py`): con los resultados por problema ya medidos de HumanEval (2 pasadas por modelo) se evalúan políticas de enrutado leyendo lo guardado en vez de volver a generar. Es la idea de Dream-RSI a escala pequeña.

| Dato | Valor |
|:---|:---|
| El Router acierta **siempre** (en las 2 pasadas) | 118/164 (**72 %**); el Complejo también en 117 de ellos |
| Techo teórico (oráculo, no realizable) | 0.905 mandando **81 %** al Router: igualaría al Complejo (0.896) casi sin usarlo |
| `auto` actual aplicado a estos prompts | manda solo el **3 %** al Router: un enunciado de código (firma + docstring) supera los 150 caracteres |
| ¿Predice la longitud del enunciado la dificultad? | **No.** Con umbrales del 10 al 70 % más cortos al Router, todos quedan **indistinguibles del azar** (lift entre −0.008 y +0.004, con IC95 % que incluyen el 0) |

Es decir: el ahorro potencial es grande, pero **los umbrales de 150/800 caracteres de la receta no sirven para reconocer las tareas fáciles de código**.

**3. Cascada con verificador** (Router primero; si su respuesta no pasa los tests, se escala al Complejo):

| Pasada | Cascada | Complejo solo | Escala al Complejo |
|:---|:---|:---|:---|
| 1 | **91.5 %** | 90.2 % | 21 % |
| 2 | **90.2 %** | 89.0 % | 25 % |

Iguala o supera al Complejo usándolo solo en el 21-25 % de los problemas. **Advertencia grave:** aquí el verificador son los tests del propio benchmark, es decir, **un verificador perfecto**; son cifras de techo. En uso real, sin tests, un verificador más débil (que compile, un linter, tests visibles) aceptará respuestas malas y rechazará buenas. La ganancia real está por medir con un verificador realista.

**4. Un hallazgo incómodo: el Router no es más barato en este hardware.** Por flujo va a 78-84 tok/s frente a 98-100 del Complejo (un MoE con solo 3B parámetros activos por token, que por inferencia lee menos pesos por token que el 4B denso; eso no se ha medido, la velocidad sí) y genera más tokens por problema (230-239 frente a 152-160, por los bucles de 7.23); HumanEval tardó 140-147 s con el Router frente a 115-124 s con el Complejo. **Enrutar «lo simple» al Router no ahorra tiempo aquí.** Su valor puede estar en otro sitio: el Router responde bien preguntas de conocimiento general que el Complejo falla (7.18, solo 3 preguntas: hipótesis, no medida). Si eso se confirma, **la señal útil de enrutado sería el dominio (código o no), no la longitud**, que es lo contrario de lo que asume la receta. Falta una evaluación de conocimiento general para los dos modelos.

**5. Lo que sí y lo que no, para las fases 8-10:**

| Fase | Recomendación |
|:---|:---|
| 8. RSIAgent | **No adoptar el repositorio tal cual** (su arnés es OSWorld/ALE). Sí el patrón (Curriculum, Actor, Verifier), que aquí se reduce a: elegir tareas, resolverlas y **verificarlas ejecutando tests** (ya existe). El experimento honesto es: ¿mejora el acierto en un **conjunto reservado** al inyectar una memoria construida en otro conjunto? Sin esa comparación (con rangos, por el ruido de 7.23) no se puede hablar de auto-mejora |
| 9. Simulador de replay | `replay-routing.py` es el prototipo. Para que sea más que un ejercicio hace falta **registrar el resultado verificado de cada decisión** (`decisions.jsonl` guardaba la decisión pero no si la respuesta era buena): **resuelto en 7.26** con `POST /v1/feedback` |
| 10. Bucle Dream-RSI | **No ponerlo en marcha.** Falta lo anterior, datos reales acumulados y un despliegue con *canary* y vuelta atrás. Con 164 problemas y 2 pasadas, cualquier «mejora» descubierta hoy sería en buena parte ruido |

**Límites de todo este apartado:** HumanEval es un solo benchmark de funciones cortas y conocido; 164 problemas y 2 pasadas por modelo dan un error de 2-3 puntos y resultados que no se repiten con exactitud; la simulación no tiene un conjunto reservado, así que cualquier política elegida mirando estos datos estaría sobreajustada a ellos.

### 7.25 Conocimiento general (MMLU): el Complejo es un especialista de código y el Router es el generalista [medido]

Motivo: 7.24 planteaba como hipótesis (3 preguntas) que el enrutado útil sería por **dominio** y no por longitud. `prepare-mmlu.py` (muestra estratificada de MMLU, 10 preguntas por materia × 57 = 570, semilla fija, licencia MIT), `eval-mmlu.py` (opción múltiple, cero ejemplos, temperatura 0, directo a vLLM) y `analyze-mmlu.py` (categorías con intervalos por remuestreo). Dos pasadas por modelo.

| Categoría | n | Complejo | Router | Diferencia (C−R) [IC95 %] |
|:---|:---|:---|:---|:---|
| **Todo** | 570 | **37.2 %** (37.2, 37.2) | **70.0 %** (70.2, 69.8) | **−32.8** [−37.9, −28.2] |
| STEM | 180 | 37.8 % | 70.6 % | −32.8 [−41.7, −23.1] |
| Humanidades | 130 | 33.1 % | 69.6 % | −36.5 [−46.2, −26.9] |
| Ciencias sociales | 120 | 42.5 % | 73.8 % | −31.3 [−41.2, −22.1] |
| Otras (salud, negocios, general) | 140 | 35.7 % | 66.4 % | −30.7 [−41.8, −19.3] |
| Materias de código (CS, seguridad, ML) | 40 | 56.2 % | 65.0 % | −8.8 [−26.3, +10.0]: sin diferencia clara |

- **Fuera del código, el Complejo ha perdido casi todo el conocimiento general**: 37 % con el azar en 25 %. El Router (Qwen 3.5 4B) saca 70 %. La diferencia es de ~33 puntos y su intervalo no se acerca al 0 en ninguna categoría (salvo en las materias de código, donde son pocas preguntas).
- **No es un artefacto de la evaluación.** Las respuestas del Complejo son letras limpias (`'C\n'`, `'A'`), sin problemas de análisis; pero **responde «A» el 59 % de las veces cuando la correcta es «A» el 27 %**: el sesgo de quien adivina. Dejándole razonar antes (`--reason`, 512 tokens) sigue en ~38 % entre las respuestas que llegó a dar (34 de 89 legibles), mientras el Router sube a ~84 % (69 de 82 legibles; muchas respuestas de ambos se cortaron por longitud porque las primeras preguntas son de álgebra). Es conocimiento, no formato.
- **La causa está en la ficha del modelo** (`AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4`): la poda REAP al 50 % puntúa cada experto sobre un conjunto de calibración **«personal»: ~100 transcripciones de agentes de código más `evol-codealpaca` y `SWE-smith`**, «so the surviving experts are the ones *this* workload actually exercises»; y la cuantización NVFP4 se calibró con los mismos datos. Se conservaron los expertos de código y se quitaron los demás. **Su evaluación publicada solo mide código** (HumanEval 0.909 en bf16, que coincide con nuestro 89-90 % en NVFP4: la cuantización no costó nada en código).
- **Corrige el apartado 7.18 y la hipótesis de 7.24:** el fallo de cultura general del Complejo no era una anécdota de 3 preguntas, y el Router no es «el modelo simple» sino **el generalista**.

**Enrutado por dominio (reproduciendo lo medido, sin GPU):**

| Política | Precisión esperada en MMLU |
|:---|:---|
| Todo al Complejo | 37.2 % |
| Todo al Router | 70.0 % |
| Oráculo (no realizable) | 78.2 % |
| Solo STEM al Complejo, el resto al Router | 59.6 % |

En MMLU el Router gana en todas partes, así que «todo al Router» es casi óptimo; el Complejo solo aporta en **código** (HumanEval 89-90 % frente a 75-79 %, 7.23).

**Consecuencias para el diseño:**
1. **La señal de enrutado útil es el dominio (¿es una tarea de código?), no la longitud del enunciado** (7.24: la longitud no predice nada). Las reglas actuales de `auto` (150/800 caracteres) mandan casi todo al «trabajador», que en el perfil B es el Complejo: **mandan las preguntas generales al modelo que peor las responde.**
2. **El Complejo no debería recibir nada que no sea código.** Para el asistente de NexoDeck (notas, documentación, chat) el Router es claramente mejor; el Complejo solo se justifica para generar o revisar código.
3. **Con el perfil A el trabajador es Gemma (un generalista)**: allí la regla de dominio no aplica igual. La regla debe depender de si el trabajador es un especialista (nueva opción de configuración), no fijarse.
4. **Antes de implementar el detector de código** hay que validarlo: no hay hoy un conjunto de prompts reales etiquetados en español; con HumanEval (código) y MMLU (no código, más 40 preguntas de CS ambiguas) solo se puede medir sobre inglés de benchmark.

**Límites:** MMLU es opción múltiple en inglés y un benchmark conocido; 10 preguntas por materia no permiten juzgar materias sueltas; con temperatura 0 los resultados no son deterministas bajo carga (aquí las dos pasadas del Complejo coincidieron en el total, 212/570, pero eso no garantiza nada); no se evaluó Gemma (perfil A); no se ha evaluado español, que es el idioma de los prompts reales.

### 7.26 Resultado verificado de cada decisión (`POST /v1/feedback`) [medido]

**El hueco:** `decisions.jsonl` guardaba qué había decidido `auto`, pero no si la respuesta era buena; sin eso, las fases 9 y 10 no tienen nada que optimizar (7.24). La pasarela no puede saberlo (no conoce la respuesta correcta); **quien verifica, sí**. Diseño: cada respuesta `auto` trae `x-nexodeck-request-id`, el cliente informa con `POST /v1/feedback {request_id, verified, verifier, score?}`, y el resultado se guarda como una línea `outcome` unida a la `decision` por el id. Detalle y formato en `llm-stack/gateway/README.md`.

**Decisiones de seguridad y de diseño** (todas con test): no hay campo de texto libre (por ahí se colaría el contenido de un prompt); `verifier` y `request_id` solo admiten caracteres simples y longitud corta; cuerpo máximo de 4 KB; solo informa la clave que hizo la petición (otra clave recibe 404, indistinguible de «no existe», y su intento no gasta el resultado de la dueña); una sola vez por petición (409); sin registro activo, 503 en vez de no hacer nada; los ids de las últimas 10 000 decisiones se recuerdan y **se recuperan del fichero al reiniciar**, para que un reinicio de la pasarela no corte el vínculo.

**Pruebas:** 44 unitarias + 34 de integración (`cargo test`), clippy limpio; `Test-Gateway.ps1` contra el stack real: id en la cabecera, resultado registrado, 409 en el duplicado, 401 sin clave, 404 en una petición desconocida, y la línea `outcome` unida por el id.

**Datos reales por primera vez** (`feedback-e2e.py`, `summarize-decisions.py`): 100 preguntas de MMLU por la pasarela con `auto`, cada respuesta verificada contra su letra correcta (98 % de las decisiones con resultado):

| Decisión | Modelo elegido | Peticiones | Con resultado | Verificadas | Tasa |
|:---|:---|:---|:---|:---|:---|
| `normal` | complex | 89 | 89 | 33 | **37 %** |
| `complex` | complex | 11 | 11 | 3 | 27 % |

`auto`, con las reglas actuales, mandó **las 100 preguntas generales al Complejo** (son «normales» o «largas» por caracteres, y el trabajador del perfil B es el Complejo), y solo el **36 %** pasó la verificación: coincide con el 37 % de MMLU medido aparte (7.25). Es el fallo de diseño que se señaló, ahora **visible en el propio registro** y no solo en una evaluación offline: una confirmación independiente, y la prueba de que el circuito mide lo que debe.

**Límites:** el verificador de este experimento es una comparación exacta de letras (perfecto y barato); en uso real el verificador será más débil. Con 100 resultados las tasas por decisión tienen un error grande (±10 puntos). Y las preguntas son de un benchmark en inglés, no tráfico real de NexoDeck.

`log-summary.sh <rol> [contexto]` resume un registro (kernels elegidos, memoria, excepciones) sin volcar cientos de líneas.

Si mistral.rs va a competir con vLLM, **el mismo benchmark** se le aplica: carga y descarga en caliente, 8 clientes concurrentes, JSON estricto, y confirmar que compila y usa la GPU en Windows con SM120 (su documentación no lo confirma, y tampoco NVFP4).

### 7.27 Enrutado por dominio en `auto` (código o no) [medido]

Consecuencia directa de 7.25: con el Complejo como trabajador, `auto` le mandaba todo lo «normal» o «largo» y solo el 36 % de lo general salía bien. Ahora, **si el trabajador levantado es un especialista de código** (`auto.specialists`, por defecto `complex`), la pasarela corrige la decisión por longitud con el dominio:

| Petición | Antes (longitud) | Ahora, con el Complejo levantado |
|---|---|---|
| No es código y iba al trabajador | Complejo | **Router**, decisión `not_code` |
| Es código y iba al ligero (por corta) | Router | **Complejo**, decisión `code` |
| `meta` (clasificar, `tool`…) | Router | Router (no cambia) |
| Cualquier cosa con el Rápido de trabajador (perfil A) | — | no interviene: Gemma es generalista |

Se apaga con `auto.code_routing: false`; las marcas están en `auto.code_markers` (subcadenas, sin distinguir mayúsculas). El detector es **solo de marcas fuertes** (```` ``` ````, `def `, `python`, `#include`, `traceback`…) y no de palabras sueltas como `class`, `function` o `import`, que salen en cualquier texto.

**Validación** (`llm-stack/scripts/check-code-detector.py`, que invoca el detector real por `cargo run --example classify`):

| Conjunto | Resultado |
|---|---|
| HumanEval (164 problemas, todos de código) | **164/164** detectados |
| MMLU (570 preguntas) | 2 detectadas, ambas de materias de programación; **0 falsos positivos** |

La primera versión de la lista daba 9 falsos positivos en MMLU. Las causas eran marcas que son subcadena de palabras corrientes: `rust` en «trust», `git ` en «digit », `compile` y `compilation` en informes de contabilidad. Se acotaron con espacios o con frases más específicas hasta llegar a 0.

**El español (medido el mismo día).** Con solo marcas en inglés el detector fallaba en español: **16/34 (47 %)** en 34 peticiones de código escritas a mano (`llm-stack/scripts/data/code-prompts-es.jsonl`), y en MMLU en español (MMMLU, `prepare-mmlu-es.py`) daba 3 falsos positivos por «código moral» y similares. Se añadieron marcas españolas con determinante o frase (`este código`, `una función que`, `búsqueda binaria`, `expresión regular`, `bucle infinito`…) porque «código», «función» o «clase» sueltos salen en filosofía, matemáticas e historia. Una regresión intermedia lo enseñó: `commit` casaba con «committee» (8 falsos positivos en inglés); ahora es `commit `. Resultado final: **30/34 (88 %)** en español, **0 falsos positivos en MMLU en español y en inglés**, HumanEval 164/164. Las 4 peticiones que faltan (una consulta SQL sin la palabra, «recursión», un bucle lento…) no se persiguieron: ajustar más sobre 34 ejemplos que yo mismo escribí sería sobreajustar.

**Prueba de extremo a extremo con los modelos reales** (perfil B, por la pasarela, `llm-stack/scripts/eval-auto-mixed.py`, 100 preguntas por idioma; resultados en `decisions.jsonl` con su feedback):

| Conjunto | Por `auto` | Precisión |
|---|---|---|
| MMLU español | 97 `not_code` → Router, 2 `meta` → Router, 1 → Complejo | Router **68,0 %** en las 97 |
| MMLU inglés | 99 `not_code` → Router, 1 `meta` → Router | Router **74,7 %** en las 99 |
| MMLU español, modelo explícito (mismas 100) | — | **Router 68,0 %, Complejo 29,0 %** |
| HumanEval (30, inglés) | **30/30 → Complejo** (`normal` 24, `complex` 5, `code` 1) | sin verificar aquí |
| Código en español (34) | **30/34 → Complejo**, 4 → Router (`simple`) | sin verificar aquí |

Antes de este cambio las 100 preguntas de MMLU iban al Complejo y solo el 36 % salía bien (7.26); ahora **van al Router y salen en torno al 68-75 %**. Y el español confirma que el Complejo es un especialista también ahí: **29 % en español frente al 68 % del Router**, con el azar en 25 %.

**Límites, sin adornos:**

- **La calidad del código enrutado no se verificó aquí**: solo a qué modelo va cada prompt. Los 4 prompts de código en español que fueron al Router son el coste medido del recall del 88 %; contra ~15 puntos menos de acierto en código (75-79 % frente a 89-90 %), y solo en esa fracción.
- **Los prompts de código en español los escribí yo** (34, variados pero pocos), y las marcas se ajustaron mirándolos; los de inglés vienen de HumanEval, que tiene un formato muy uniforme (docstrings con `def `). **Tráfico real de NexoDeck** (chat del asistente, agentes con herramientas, ficheros pegados sin ninguna de las marcas) **sigue sin validarse**: un fichero pegado sin marcas iría al Router.
- Las preguntas *sobre* programación sin código (MMLU de informática) caen casi todas en el Router (2 detectadas): son conceptuales y el Router es el generalista.
- **Gemma (perfil A) sigue sin evaluarse**; con ella el enrutado por dominio no interviene.
- 100 preguntas por idioma dan un error de ±9 puntos por celda: la diferencia Router-Complejo (39 puntos) es inequívoca, la de español frente a inglés del Router (68 frente a 75) no.

### 7.28 Gemma (perfil A) evaluada: la mejor en código y buena en general [medido]

Gemma era la única pieza sin medir. Perfil A, por la pasarela y en el sandbox de HumanEval, con la misma metodología que 7.23 y 7.25:

| | HumanEval | MMLU español | MMLU inglés | Velocidad (1 cliente) | Contexto |
|---|---|---|---|---|---|
| **Gemma 4 12B AWQ** (Rápido) | **92,7 %** (152/164) | **73 %** | **77 %** | 44,5 tok/s | 8 192 |
| Qwen3-Coder REAP (Complejo) | 89-90 % | 29 % | 37 % | ~100 tok/s | 16 384 |
| Qwen3.5-4B (Router) | 75-79 % | 64-68 % | 70-75 % | 78 tok/s | 16 384 |

(MMLU: 100 preguntas por idioma, error de ±9 puntos por celda; el Router dio 64 % y 68 % en dos tandas del mismo subconjunto por el no determinismo bajo carga. HumanEval: un solo intento, los rangos anteriores vienen de 2-3.)

**Consecuencia grande: Gemma domina al Complejo en calidad**, tanto en código (+3 puntos, dentro del ruido) como sobre todo en conocimiento general (+36 puntos). **El perfil B solo se justifica por velocidad (2,2× más tokens/s) y por el contexto de 16k**; para calidad, el perfil A (Router + Gemma) es el mejor. Es un cambio de recomendación respecto a lo que se asumía al empezar («el Complejo es el modelo pesado, luego el mejor»): la poda REAP a 50 % y la cuantización lo dejan en un especialista estrecho. La receta pedía los tres modelos y están todos; lo que estos números aportan es **cuál usar por defecto**.

**Tool calling de Gemma.** Sin parser el servidor contestaba 400 (como al Router y al Complejo, 7.21). Con `--enable-auto-tool-choice --tool-call-parser gemma4` (el parser existe en vLLM 0.29.0; se añadió a `serve-model.sh`): `tools-check.py` **OK**, llamada bien formada (`get_disk_usage({"drive": "D"})`), también con `stream: true`, sin razonamiento en voz alta.

**Efecto en `auto` con Gemma de trabajador.** Con solo la longitud, 33 de 34 peticiones de código en español (cortas) iban al Router, el peor en código. Se generalizó el enrutado por dominio: **el código va siempre al trabajador** (`code`), sea especialista o no; lo que no es código solo se desvía al Router si el trabajador es un especialista (`not_code`). Medido con Gemma: código en español **29/34 al trabajador (antes 1/34)**. Los tests son 50 + 36.

**Límites.** El código de Gemma en español no se verificó (HumanEval es inglés); el MMLU por `auto` con Gemma (72-77 %) no lo mejora el enrutado, porque va todo a Gemma salvo `meta`; y el contexto de 8k de Gemma frente a los 16k del Complejo no se midió en tareas largas.

---

## 8. Bitácora y scripts

**Regla:** todo lo que se ejecute sobre el equipo queda como script en [`llm-stack/scripts/`](llm-stack/scripts/README.md) y como línea en esta bitácora. Los comandos sueltos no cuentan como hechos.

| Fecha | Paso | Script | Resultado |
|:---|:---|:---|:---|
| 2026-09-18 | `.wslconfig`: memoria 12 → 16 GB, sin `autoMemoryReclaim` en `[wsl2]` | `Set-WslResources.ps1` | WSL2 ve 15 GiB y 8 hilos [medido] |
| 2026-09-18 | Docker Engine 29.8.1 + NVIDIA Container Toolkit 1.20.1 en Ubuntu 26.04 | `install-docker-engine.sh` | `docker run --gpus all` ve la RTX 5060 Ti (`compute_cap` 12.0); reejecutado y es idempotente [medido] |
| 2026-09-18 | Directorios del stack | `setup-directories.sh` | Creados; `docker` sin sudo OK [medido] |
| 2026-09-18 | Verificar los tres repos de HuggingFace | `verify-hf-repos.py` | Existen, `safetensors`, sin gating, sin código remoto (apartado 7.1) [medido] |
| 2026-09-18 | Descargar Router, Rápido y Complejo (20.6 GB, ~4 min) | `download-models.sh` | Completados en `~/models`; reejecución reanuda sin volver a bajar [medido] |
| 2026-09-18 | Integridad y cuantización de los modelos | `verify-models.py` | Los tres completos y en el formato esperado (apartado 7.2) [medido] |
| 2026-09-18 | Imagen de vLLM fijada | `pull-vllm-image.sh` | `vllm/vllm-openai@sha256:c2914767…c51ae1`, 30.5 GB, creada el 2026-09-09 [medido] |
| 2026-09-18 | Inspeccionar la imagen (versiones, arquitecturas, flags, kernels) | `inspect-vllm-image.sh`, `inspect-vllm.py` | vLLM 0.29.0; sin b12x; flags OK (apartado 7.3) [medido] |
| 2026-09-18 | Ver qué añade `vllm[b12x]` sin instalar | `probe-b12x-extra.sh` | Solo `b12x==1.2.6`; cutlass-dsl sigue en 4.6.2 [medido] |
| 2026-09-18 | Imagen derivada con b12x | `Dockerfile.vllm`, `build-vllm-image.sh` | `nexodeck-vllm:0.29.0-b12x`; kernels NVFP4 y FP8 = `True` en SM120 [medido] |
| 2026-09-18 | Router: primer arranque | `serve-model.sh router` | **Falló** con `UVA is not available` (apartado 7.4) [medido] |
| 2026-09-18 | Buscar la causa en el código de vLLM de la imagen | `grep-vllm-source.sh` | `VLLM_WSL2_ENABLE_PIN_MEMORY=1` lo resuelve; ya está en `serve-model.sh` [medido] |
| 2026-09-18 | Router: segundo intento (0.28) | `serve-model.sh router` | Falló: `No available memory for the cache blocks` (KV −0.21 GiB), apartado 7.5 [medido] |
| 2026-09-18 | Router: tercer intento (0.34 + `--max-num-batched-tokens 2048`) | `serve-model.sh router` | **Funciona**: arranque 171 s, KV 49 152 tokens (apartado 7.6) [medido] |
| 2026-09-18 | Benchmark del Router (1, 4, 8 clientes) | `bench.py` | 78 / 296 / 538 tok/s agregados [medido] |
| 2026-09-18 | Perfil A: Router (0.27) + Gemma (0.55) | `serve-model.sh` | Router OK; Gemma **falló** por memoria (apartado 7.7) [medido] |
| 2026-09-18 | Gemma en solitario (0.68) | `serve-model.sh fast` | Arranca en 89 s; overhead real ~0.4 GiB (apartado 7.8) [medido] |
| 2026-09-18 | Gemma se paró sola a los 16 s | `Start-WslKeepAlive.ps1` | Causa: WSL2 apaga la distro sin sesiones abiertas; keep-alive lo evita [medido] |
| 2026-09-18 | Benchmark de Gemma sola (1, 4, 8 clientes) | `bench.py` | 44.5 / 172 / 334 tok/s agregados [medido] |
| 2026-09-18 | Perfil A con KV en bytes: Router OK, Gemma (KV 1.5 GiB, ctx 12 288) **falló** | `serve-model.sh` | Una petición de 12 288 tokens necesita 1.75 GiB de KV (apartado 7.9) [medido] |
| 2026-09-18 | Comprobar la VRAM aparente del Router | `bench.py` | `nvidia-smi` marcaba 2.3 GiB con el Router cargado: WDDM había desalojado memoria; rendimiento normal al usarlo [medido] |
| 2026-09-18 | Gemma: segundo fallo (KV 1.25 GiB, ctx 8 192) | `serve-model.sh fast` | El KV de Gemma tiene un suelo de ~1.6 GiB; 8 192 tokens piden 1.69 GiB (apartado 7.9) [medido] |
| 2026-09-18 | **Perfil A funcionando**: Router + Gemma (KV 1.75 GiB, ctx 8 192) | `serve-model.sh router`, `serve-model.sh fast` | Ambos arrancan; 15 547 / 16 311 MiB usados (apartado 7.10) [medido] |
| 2026-09-18 | Benchmark del perfil A, por separado y en carga simultánea | `bench.py` | Router 82/297/544 y Gemma 41/156/299 tok/s; a la vez se reparten la GPU en el tiempo [medido] |
| 2026-09-18 | Complejo: 1.º intento (b12x), 2.º (`--enforce-eager`), 3.º (atención Triton) | `serve-model.sh complex` | 1.º y 3.º **fallan** (`illegal memory access` en grafos CUDA); 2.º funciona a 7.3 tok/s (apartado 7.11) [medido] |
| 2026-09-18 | Complejo con `--moe-backend flashinfer_cutlass` y grafos CUDA | `serve-model.sh complex` | **Funciona: 100 / 258 tok/s** (1 / 4 clientes), 14 veces más que eager [medido] |
| 2026-09-18 | Perfil B con `--cpu-offload-gb 1.5` en el Router | `serve-model.sh` | Arranca, pero el Router va a **3 tok/s**: offload de un modelo denso inviable (apartado 7.13) [medido] |
| 2026-09-18 | Comprobar que el Router va igual sin el Complejo con su config recortada | `bench.py` | 82/288/327: la caída a 8 clientes es su KV de 0.4 GiB, no la memoria (apartado 7.14) [medido] |
| 2026-09-18 | Complejo con batched 256 → 512 | `serve-model.sh complex` | 75 → **97 tok/s**; GPU 14 914 MiB con los dos cargados [medido] |
| 2026-09-19 | Reutilización de prefijos sin offload (baseline) | `bench-prefix-reuse.py` | 0 % desde caché, 0.62 s por petición de ~2 800 tokens (apartado 7.15) [medido] |
| 2026-09-19 | KV en RAM con `--kv-offloading-size 4` | `serve-model.sh`, `bench-prefix-reuse.py` | Arranca pero la 1.ª petición da HTTP 500 (`illegal memory access`); descartado (apartado 7.15) [medido] |
| 2026-09-19 | Sleep Mode, 1.er intento | `serve-model.sh` (`SLEEP_MODE=1`) | Se colgó 15 min, **atribuido erróneamente a Sleep Mode** (7.16): la GPU estaba rota por el fallo del KV en RAM [medido] |
| 2026-09-19 | Diagnóstico del cuelgue: CUDA no inicializa | `check-cuda.sh`, `cuda-smoke.py` | Proceso al 100 % de CPU sin avanzar, incluso en una prueba mínima; `wsl --shutdown` lo arregla (0.46 s después) [medido] |
| 2026-09-19 | **Sleep Mode en limpio**: nivel 1 y nivel 2 | `serve-model.sh` (`SLEEP_MODE=1`), `test-sleep-mode.py` | Nivel 1 OK (despertar 1.9 s, pero 15.8 GB de RAM); **nivel 2 da salida basura** (apartado 7.17) [medido] |
| 2026-09-19 | Perfil B restaurado tras `wsl --shutdown` y comprobación de coherencia | `serve-profile.sh B`, `chat-check.py` | Sin basura en ningún modelo; el Complejo falla una pregunta de cultura general (apartado 7.18) [medido] |
| 2026-09-19 | Pasarela autenticada en Rust (`llm-stack/gateway/`): 12 unitarias + 14 de integración, clippy limpio | `cargo test`, `Test-Gateway.ps1` | Todo OK contra el stack real, incluido que `/sleep` y demás rutas de administración no se alcanzan (apartado 7.19) [medido] |
| 2026-09-19 | `/health` tardaba 2.05 s con los modelos apagados y abortaba el arranque | `llm-stack/gateway/src/proxy.rs` | Sondeo en segundo plano; `/health` responde al instante. Solo se vio arrancando el stack de verdad (7.19) [medido] |
| 2026-09-19 | Arranque en frío de todo el stack: WSL2 → Docker → pasarela → perfil B | `Stop-Stack.ps1 -ReleaseWsl`, `Start-Stack.ps1 -Profile B` | 3 min 46 s hasta tener los modelos; GPU a 811 MiB al parar (7.20) [medido] |
| 2026-09-19 | Tarea de inicio de sesión `NexoDeckLlmStack` (solo pasarela) y clave `nexodeck` | `Install-StackTask.ps1 -Profile none`, `llm-gateway keys add nexodeck` | La 1.ª ejecución de la tarea **falló** (`$PSScriptRoot` vacío en el valor por defecto de un parámetro con `powershell.exe -File`); corregido, resultado 0 [medido] |
| 2026-09-19 | Tres commits en la rama `feat/note-editor`, solo con las rutas de esta carpeta (117 cambios ajenos intactos) | `git` | `2aec5de` docs, `525e2fe` scripts, `6cdf9fd` pasarela [medido] |
| 2026-09-19 | NexoDeck como cliente: se revisa su conexión a servicios remotos | `remote.rs`, `provider.rs` | No hace falta código: preset `custom` con `http://127.0.0.1:8888` (apartado 7.21) |
| 2026-09-19 | El agente de NexoDeck (`tools`) da HTTP 400 en Router y Complejo | `tools-check.py` | Faltaban `--enable-auto-tool-choice` y el parser (apartado 7.21) [medido] |
| 2026-09-19 | Tool calling activado y verificado, también con streaming | `serve-model.sh`, `tools-check.py`, `vllm-help.sh` | Router y Complejo: llaman a la herramienta con argumentos válidos y sin razonar en voz alta [medido] |
| 2026-09-19 | Modelo virtual `auto` (fase 5 simplificada): `route.rs`, `decisions.rs`, reescritura de `model`, conmutación | `cargo test` (62), `Test-Gateway.ps1`, `tools-check.py --model auto` | Todo OK en tests y contra el stack real (apartado 7.22) [medido] |
| 2026-09-19 | Fallo cazado por un test: el salto de línea entre mensajes contaba como longitud (149 caracteres medían 150) | `cargo test` | Conteo separado del texto de búsqueda de palabras clave [medido] |
| 2026-09-19 | Evaluador de HumanEval con ejecución aislada y autotest | `eval-humaneval.py --selftest` | 7/7: acepta lo correcto, rechaza lo incorrecto, corta bucles, y bloquea red y escritura (apartado 7.23) [medido] |
| 2026-09-19 | HumanEval, 2 pasadas por modelo | `eval-humaneval.py`, `analyze-eval.py` | Complejo 89-90 %, Router 75-79 %; los resultados con temperatura 0 no se repiten; los `SyntaxError` del Router son bucles de repetición cortados por tokens [medido] |
| 2026-09-19 | Docs 04, 06 y 07 (truncados a mitad de línea) cerrados con una continuación marcada | edición de los propios documentos | El texto original es irrecuperable; se añadió solo lo verificado, no receta inventada (apartado 9) |
| 2026-09-19 | Verificación de las referencias de las fases 8-10 (RSIAgent, APEX-EM, Dream-RSI) | búsqueda web | Las tres existen; la API del doc 08 no está confirmada y la analogía de Dream-RSI con el enrutado es nuestra (apartado 7.24) |
| 2026-09-19 | Simulación de políticas de enrutado con resultados ya medidos, y cascada con verificador | `replay-routing.py` | Router acierta siempre 72 %; la longitud no predice la dificultad; cascada 90-92 % usando el Complejo el 21-25 % (con verificador perfecto) (7.24) [medido] |
| 2026-09-19 | MMLU (570 preguntas, 2 pasadas por modelo) y descarte de artefactos (respuestas crudas, reparto de letras, modo con razonamiento) | `prepare-mmlu.py`, `eval-mmlu.py`, `analyze-mmlu.py` | Complejo 37.2 % frente a Router 70.0 % (dif. −33 puntos); el Complejo es un especialista de código (poda calibrada solo con código, según su ficha) (apartado 7.25) [medido] |
| 2026-09-19 | Regla de uso escrita: al terminar con el perfil A o B, limpiar todos los procesos y dejar libre el hardware | `Stop-Stack.ps1` (ahora verifica la limpieza), memoria, README | Petición del usuario; ver la sección «Regla de uso» al principio de este documento |
| 2026-09-19 | Resultado verificado de cada decisión: `POST /v1/feedback`, ids recuperados al reiniciar, ruta nueva con clave/tope/una vez | `cargo test` (78), `Test-Gateway.ps1`, `feedback-e2e.py`, `summarize-decisions.py` | Todo OK; 100 preguntas MMLU por `auto`: todas al Complejo, 36 % verificadas: coincide con la evaluación offline (apartado 7.26) [medido] |
| 2026-09-19 | Limpieza completa del hardware: `Stop-Stack.ps1 -ReleaseWsl` apaga también la VM de WSL2 (`vmmemWSL`) y lo comprueba | `Stop-Stack.ps1` | Salida `LIMPIO`, código 0; GPU 1169 MiB (solo escritorio), RAM libre de Windows 21,2 GB, sin `vmmemWSL` [medido] |
| 2026-09-19 | Enrutado por dominio en `auto`: con un especialista de código de trabajador, solo el código va a él | `cargo test` (86), `check-code-detector.py`, `llm-stack/gateway/examples/classify.rs` | HumanEval 164/164 detectados; MMLU 0 falsos positivos tras acotar 4 marcas (apartado 7.27); sin probar con los modelos reales [medido offline] |
| 2026-09-19 | Español: marcas españolas del detector, MMLU en español (MMMLU) y 34 peticiones de código escritas a mano; prueba de extremo a extremo con los modelos reales y hardware liberado después | `prepare-mmlu-es.py`, `check-code-detector.py`, `eval-auto-mixed.py`, `data/code-prompts-es.jsonl`, `Start-Stack.ps1 -Profile B`, `Stop-Stack.ps1 -ReleaseWsl` | Detector en español 47 % → 88 %, 0 falsos positivos; por `auto` MMLU va al Router (68 % es, 75 % en); Complejo 29 % en español frente al 68 % del Router; código 30/30 (en) y 30/34 (es) al Complejo; salida `LIMPIO` (GPU 736 MiB, 23,4 GB libres) [medido] |
| 2026-09-19 | Gemma evaluada (perfil A): HumanEval, MMLU es/en, tool calling con `gemma4`; enrutado por dominio generalizado (el código va siempre al trabajador); hardware liberado | `serve-model.sh` (parser), `tools-check.py`, `eval-auto-mixed.py --explicit`, `eval-humaneval.py --model fast`, `Stop-Stack.ps1 -ReleaseWsl` | Gemma 92,7 % HumanEval, 73 % es / 77 % en en MMLU: domina al Complejo en calidad (apartado 7.28); código en español a Gemma 29/34 (antes 1/34); `LIMPIO` (GPU 844 MiB, 23,3 GB libres) [medido] |
| 2026-09-18 | **Perfil B reproducible, validado de cero** | `serve-profile.sh B` | Complejo 67 s + Router 156 s. Router 84/299 y Complejo 98/252 tok/s (1/4 clientes). GPU 14 617 MiB al arrancar y **15 747 MiB tras usarlos** (margen estable ~0.56 GiB) [medido] |
| 2026-09-23 | NexoDeck como cliente: el preset `custom` pasa a devolverlo `presets()` (antes definido y sin usar) y el diálogo deja de ofrecer «Copiar dónde sacarla» si el proveedor no tiene página | `cargo test -p nexodeck-ai` (180), `flutter analyze`, `tools-check.py --model auto` con clave nueva y perfil A | Tool calling + streaming por la pasarela: **OK**; el alta en la UI queda a mano (apartado 7.21) [medido] |
| 2026-09-28 | Robustez de arranque (nivel 1): reinicio acotado y `HEALTHCHECK` por contenedor, supervisor de la pasarela y comprobación final de que cada rol del perfil reporta `up` | `serve-model.sh`, `Start-Gateway.ps1` (nuevo), `Start-Stack.ps1`, `Stop-Stack.ps1` | Implementado; **sin verificar en vivo todavía** (falta `docker kill vllm-router` + `Stop-Stack.ps1 -ReleaseWsl` en el equipo, apartado 3 punto 5) [sin medir] |
| 2026-09-28 | Normalización del árbol: el código del stack sale de `docs/` (que es solo documentación) y los doc 00-11 se van con él | de `docs/ideas/multiagent_rsi_dreams/` a `llm-stack/` (`scripts/` y `gateway/`) y `docs/llm-stack/` (los `.md`); `kDefaultStackScriptsDir` en `app/` y referencias en `CLAUDE.md`, `docs/` y los propios scripts | `check-scripts.sh` TODO OK y parse de los `.ps1` OK tras el movimiento; el gateway compila igual (`cargo test` no corrido aquí, apartado 3) [sin medir] |
| 2026-09-28 | **Perfil C «Texto»**: rol `writer` (Qwen3.5-9B AWQ) para preguntas y conocimiento general, con contexto largo (32k) y sin JIT | `models.json`, `serve-model.sh`, `serve-profile.sh`, `profile-roles.py`, `profiles.json`, `gateway/src/config.rs` (backend 8003), `Start-Stack.ps1`, y en la app `StackProfile.texto` + perfiles A/B/C | Modelo elegido por `max_position_embeddings: 262144` y atención híbrida lineal (KV pequeño), AWQ (Marlin, sin JIT). `verify-hf-repos.py` midió **11.53 GiB** de pesos, así que **no cabe junto al Router**: el perfil C sirve solo el writer (el pipeline usa un único modelo). Alternativa que sí admite dos modelos: `Qwen/Qwen3-8B-AWQ` (6.1 GiB, 16k). **Pendiente de medir**: descarga, arranque real y tok/s [sin medir] |
| 2026-09-28 | Descargar un modelo del stack **desde la app**: botón «Descargar» en el selector de modelos, con barra de progreso, porcentaje y **MB/s** en el tile, y el detalle de `hf` en el panel de Ejecuciones | `Download-Model.ps1` (nuevo), `stackDownloadCommandFor`, `downloadRateMbps` (puro), `StackController.download`, `stackDownloadingProvider`, `StackCatalogRepository.modelDirBytes` y `_StackTile` del `model_picker_sheet` | Cierra el hueco que dejó anotado la exploración (solo llama.cpp tenía progreso, y era indeterminado para el stack). El porcentaje y la velocidad se miden de `~/models/<dir>` cada 2 s (`hf download --local-dir` escribe ahí directo; la cache solo guarda metadatos, 18 MB en el equipo). La descarga usa el backend Xet de alto rendimiento y sube la concurrencia de ficheros (`--max-workers 16`, ajustable con `HF_MAX_WORKERS`); se comprueba que `hf_xet` esté instalado, porque sin él `HF_XET_HIGH_PERFORMANCE` se ignora en silencio y cae a HTTP. Al terminar, la detección se refresca sola. **Sin medir en hardware**: no se ha medido el MB/s real [sin medir en hardware] |

| 2026-09-28 | Arrancar un perfil con sus modelos sin descargar falla en el acto y con motivo: guard en `serve-model.sh`, perfiles ocultos y **detección automática** al entrar a «Configura tus perfiles» (sin botón) | `serve-model.sh` (guard de `$MODELS_DIR/$MODEL_DIR`), `AiProfilesState.isProfileRunnable` + `profiles_section.dart` (`initState` → `detectInstalled`) | Seleccionar «Texto» con el `writer` sin bajar costaba 2-6 min y moría con un `HFValidationError` criptico (vLLM trata `/models/<dir>` inexistente como repo de Hugging Face). Ahora sale en <1 s diciendo qué falta y cómo bajarlo. Los perfiles se ocultan **solo cuando ya se miró WSL2** (sin detectar no se puede afirmar que falte nada). La detección corre **al montar la sección**, no con un botón: `detectInstalled` no levanta WSL2 (solo mira si está arriba y, si no, lo dice), así que es barato y el camino al «Descargar» se ve solo [sin medir en hardware] |
| 2026-09-28 | Selector por slot: aptitud Router/Pensamiento en los modelos del stack, servicio por internet para **cualquiera de los dos slots** y **clave de DeepSeek detectada sola** | `ai_profile.dart` (`stackRoleFitsSlot`), `ai_repository.dart` (`remoteKeyIdsWithSavedKey`), `ai_providers.dart` (`aiRemotePresetsProvider`/`aiRemoteKeysSavedProvider`), `model_picker_sheet.dart` (`_RemoteSlotSection`) y `profile_remote_dialog.dart` | La clave se guardaba por slot (`remote:A.router`), asi que la `deepseek.key` global que el usuario ya tenia no aparecia en el dialogo. Ahora el selector lista los servicios con clave guardada (probando `aiRemoteKeyPath` por preset, sin funcion nueva en el puente) y al elegirlos usa el id **global** del preset: la misma clave sirve para router y pensamiento sin copiarla. Cada modelo del stack marca para que slot es ideal (`router` = Router, el resto = Pensamiento). **Sin medir en hardware** |
| 2026-09-28 | Validación de VRAM **al configurar**: el selector no deja elegir dos modelos del stack que no caben juntos, y la tarjeta del perfil muestra la suma | `models.json` (`vram_gb` por rol), `StackModel.vramGb`, `ai_profile.dart` (`stackRolesVramGb`/`stackSelectionFitsVram`), `ai_providers.dart` (`aiVramBudgetProvider`), `model_picker_sheet.dart` y `profiles_section.dart` | Antes se podía guardar un perfil imposible (C como router + writer) y el fallo aparecía 2-6 min después al arrancar, con un `ValueError` de vLLM. Las huellas están calibradas para que las sumas den los totales medidos (A 15.5, B 14.9, C ~12 GiB) y se cuenta cada rol **distinto** una vez. El presupuesto es la VRAM de la GPU detectada; sin ella no se bloquea nada. **Sin medir en hardware** |
| 2026-09-28 | Un perfil **sin roles locales** para el stack al levantarlo: pasar el perfil C a DeepSeek dejo un `vllm-writer` vivo ocupando 13 GiB | `activateProfile` (`profiles_section.dart`) | `activateProfile` solo tocaba el stack cuando el slot de Pensamiento era `stack`, asi que un perfil todo-remoto nunca paraba los contenedores viejos (y la pregunta "si elegi la nube, por que usa mi VRAM"). Ahora, si ningun slot es del stack, llama a `StackProfile.apagado` (`Stop-Stack.ps1 -ReleaseWsl`), que para los modelos y libera la RAM de WSL2 [sin medir en hardware] |
| 2026-09-28 | El menu de modo pasa a **«Perfil A/B/C»** y muestra en vivo los **modelos elegidos** de cada perfil (locales o de la nube) | `StackProfile` (`label` + `profileName`), `describeProfileModels` (`ai_profiles_controller.dart`), `ProfileSwitch` (`describe`) y `ai_chat_view.dart` | Los renglones decian los modelos de la receta («Router + Gemma»), que dejan de ser ciertos en cuanto se cambia un slot, y el nombre visible era «Rápido»/«Contexto largo»/«Texto». Ahora el switch recibe un `describe` desde el chat (que si ve `aiProfilesProvider`) y muestra los modelos **elegidos** —p. ej. «Router: DeepSeek · Pensamiento: DeepSeek»—, actualizado al cambiar un slot. El enum conserva `rapido`/`contextoLargo`/`texto` porque se persisten [sin medir en hardware] |
| 2026-09-28 | El `MODO…` aplica el perfil **entero**: ademas de arrancar/parar vLLM, deja contestando el motor del slot de Pensamiento, asi un perfil de nube **apaga el llama.cpp local** | `ProfileSwitch` (`onSelect`), `_applyProfile` (`ai_chat_view.dart`) y `activateProfile` (fija `chatBackendProvider`) | Elegir Perfil C (DeepSeek en los dos slots) desde el `MODO…` solo arrancaba vLLM: el motor local `llama-server` (Qwen3-14B, ~11 GiB) seguia vivo porque el switch no tocaba el destino del chat. Son dos sistemas —los perfiles A/B/C del stack y el destino del chat—; ahora el switch llama a `activateProfile`, que instala el motor del slot de Pensamiento y con eso reemplaza (y apaga) el anterior, y fija el destino del chat [sin medir en hardware] |
| 2026-09-28 | Al arrancar **no se levanta el motor local** (llama.cpp) salvo que el destino del chat sea ese modelo | `_autoStart` (`ai_assistant_dialog.dart`) | El panel arrancaba un `startSetup()` pelado con el modelo instalado: con el destino en la nube (la pasarela del stack o DeepSeek) cargaba igual el `llama-server` (Qwen3-14B, ~11 GiB) y encima reemplazaba el proveedor remoto, asi que el selector decia una cosa y contestaba otra. Ahora mira el destino resuelto (`chatDestinationsProvider` + `chatBackendProvider`) y solo arranca el motor local si ese es el destino; si no, deja contestando el destino via `restoreDefault` [sin medir en hardware] |
| 2026-09-28 | El «quien contesta» del chat pasa a **solo lectura** y lo elige el perfil: se quita el selector manual, que era un sistema paralelo y confuso | `ai_chat_view.dart` (`_CurrentDestination` de solo lectura) y `activateProfile` (guarda el destino como predeterminado y la config remota) | El desplegable «Quien contesta» convivia con los perfiles A/B/C y podia decir una cosa distinta de la que contestaba (mostraba la pasarela mientras corria llama.cpp). Ahora el perfil manda: `activateProfile` instala el motor del slot de Pensamiento y lo deja como **destino predeterminado** (y guarda la config remota), asi `restoreDefault` lo reinstala al arrancar; el pie del chat solo muestra «Contesta: …» [sin medir en hardware] |

Pendiente: perfil B (Router + Complejo con offload a RAM, apartado 5.1), probar el KV en RAM con `--kv-offloading-size` (apartado 5), FP8 KV y quitar `--enforce-eager`, y dejarlo permanente (arranque con Windows, pasarela y árbitro de GPU). Ya hecho: los tres modelos cargan y el perfil A funciona (apartado 7.10).

---

## 9. Correcciones a documentos anteriores

| Documento | Dice | Corrección |
|:---|:---|:---|
| 00, §Hardware | «Docker Desktop con WSL2 backend» | Docker Engine dentro de Ubuntu; Docker Desktop desinstalado |
| 00, Advertencia 3 y 01 §3 | `memory=28GB`, `processors=12` | `memory=16GB`, `processors=8`; `autoMemoryReclaim` va en `[experimental]` |
| 01-10 | Rutas `/home/juan/...` | `/home/usuario/...` |
| 03 §10.2 y 04 §11.2 | VRAM de las combinaciones (9.5 vs 12.5 GB) | Vale lo medido en el paso 1 |
| 04 | `--host 0.0.0.0` con `VLLM_SERVER_DEV_MODE=1` | Atar a `127.0.0.1` o a red interna; ver apartado 3 |
| 04 | `--gpu-memory-utilization` 0.90 / 0.85 / 0.75 | Presupuesto en GB por perfil; ver apartado 2 |
| 04, 06, 07 | Terminan a mitad de línea | Completar (paso 5 del plan de medición) |
| 09 | Simulador que elige el primer hijo y «éxito» = sin error | Ver apartado 6 |
| 02 §6 | Pinear `nvidia-cutlass-dsl` a 4.4.2 | No hace falta con vLLM 0.29.0: `vllm[b12x]` solo añade `b12x==1.2.6` y cutlass-dsl se queda en 4.6.2 (7.3) |
| 02 §12.6 | `VLLM_ATTENTION_BACKEND=TRITON_ATTN` obligatorio con NVFP4 | No hace falta: el Router usa `FLASH_ATTN` y el Complejo `FLASHINFER` sin problemas (7.5, 7.11). Además la variable ya no es la vía: existe `--attention-backend` |
| 02 §12.4 y 04 | «SIEMPRE `--linear-backend b12x --moe-backend b12x`» | Lineal `b12x` sí; **MoE `b12x` rompe los grafos CUDA** del Complejo. Usar `--moe-backend flashinfer_cutlass` (7.11) |
| 04 | `--enforce-eager` para NVFP4 MoE | Funciona pero da 7 tok/s. Con `flashinfer_cutlass` no hace falta y da ~100 (7.11) |
| 00, 03 | Router ~2.5 GB de VRAM | 3.44 GiB de pesos con `--language-model-only` y ~4.2 GiB en total con KV y activaciones (7.5) |
| 00, 03 | Gemma con contexto de 32k | 8 192 en el perfil A: su KV tiene un suelo de ~1.6 GiB (7.9, 7.10) |
| 5.1 (este doc) | Offload a RAM de «decenas de ms por token» | ~0.2 s por GiB y token: el offload de un modelo denso es inviable (7.13) |
| 04 | Sleep Mode para alternar modelos | **Nivel 1 funciona** (despertar 1.9 s) pero ocupa ~15.8 de 16 GB de RAM y no caben dos modelos dormidos; **nivel 2 corrompe el modelo** (salida basura). Los perfiles se cambian parando y arrancando (`serve-profile.sh`), ~2-4 min (7.17) |
| 04 §6.2 y este doc §5 | KV en RAM / `--kv-offloading-size` | **Falla bajo WSL2**: `illegal memory access` en la primera petición (7.15) |
