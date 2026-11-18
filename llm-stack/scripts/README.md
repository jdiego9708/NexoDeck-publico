# Scripts del stack multiagente

Todo lo que se hizo a mano para montar el entorno (docs 01-03 y 11, en `docs/llm-stack/`) está aquí como script, para poder repetirlo en otra máquina o tras un formateo. **Regla de la carpeta:** cada paso nuevo entra como script + una línea en la bitácora del doc `docs/llm-stack/11-mejoras-y-decisiones.md` (apartado 8). Los comandos sueltos no se dan por hechos.

> ## Regla: al terminar, limpiar todos los procesos y dejar el hardware libre
>
> Cuando **ya no se necesite el perfil A o B** (o cualquier prueba que cargue la GPU), hay que **limpiar todos los procesos y dejar el hardware libre**, y **comprobarlo**. Los modelos ocupan ~15 GiB de VRAM y 8+ GB de RAM de WSL2 y compiten con ODM, los entrenamientos y los juegos; dejarlos cargados «por si acaso» estorba sin que se note.
>
> ```powershell
> .\Stop-Stack.ps1 -ReleaseWsl      # para modelos y pasarela, cierra la sesión de WSL2 y termina la distro
> ```
>
> Su sección **`[limpieza]`** comprueba que no queda la pasarela, el keep-alive ni la distro de WSL2, y que la GPU está en su nivel de reposo (~1 GiB de Windows). Debe acabar en **`LIMPIO`**; si dice `NO ESTÁ LIMPIO` (código de salida 1) hay que resolver lo que liste antes de dar el trabajo por terminado. Quien use el stack (persona o agente) lo ejecuta **al acabar, sin esperar a que se lo pidan**.
>
> **La tarea programada `NexoDeckLlmStack` está deshabilitada por defecto (decisión del usuario, 2026-09-24).** No debe dispararse al iniciar sesión de Windows en general: se habilita **únicamente cuando se abre el programa NexoDeck y se van a usar sus funciones de IA**, y se vuelve a deshabilitar (o se corre `Stop-Stack.ps1 -ReleaseWsl`) al terminar. Ver `docs/llm-stack/11-mejoras-y-decisiones.md` §7.20.

Rutas: el repo está en `D:\Repositorios\NexoDeck`, que desde WSL2 es `/mnt/d/Repositorios/NexoDeck`. Abajo, `$S` es esta carpeta:

```powershell
$S = "/mnt/d/Repositorios/NexoDeck/llm-stack/scripts"
```

## Orden de ejecución

| # | Script | Dónde y cómo | Qué hace |
|:--|:---|:---|:---|
| 1 | `Set-WslResources.ps1` | Windows: `.\Set-WslResources.ps1 -MemoryGB 16 -Processors 8 -Restart` | Fija memoria, hilos y swap de WSL2 sin tocar el resto de `.wslconfig`. `-WhatIf` para ensayar |
| 2 | `install-docker-engine.sh` | `wsl -d Ubuntu -u root -e bash $S/install-docker-engine.sh` | Docker Engine + NVIDIA Container Toolkit dentro de Ubuntu; verifica GPU en contenedor |
| 3 | `setup-directories.sh` | `wsl -d Ubuntu -u <usuario> -e bash $S/setup-directories.sh` | Crea `~/vllm-stack`, `~/models`, `~/.rsiaagent/memory` y comprueba `docker` sin sudo |
| 4 | `verify-hf-repos.py` | `wsl -d Ubuntu -e python3 $S/verify-hf-repos.py` | **Antes de descargar:** comprueba por API que los repos existen y no traen pickle ni código remoto |
| 5 | `download-models.sh` | `wsl -d Ubuntu -u <usuario> -e bash $S/download-models.sh [rol ...]` | Baja los modelos de `models.json` a `~/models`. Reanudable |
| 6 | `verify-models.py` | `wsl -d Ubuntu -u <usuario> -e python3 $S/verify-models.py` | Valida que los `safetensors` estén completos y en el formato esperado |
| 7 | `pull-vllm-image.sh` | `wsl -d Ubuntu -u <usuario> -e bash $S/pull-vllm-image.sh` | Baja la imagen de vLLM y fija su digest en `vllm-image.lock` |

| 8 | `inspect-vllm-image.sh [lock\|local]` | `wsl -d Ubuntu -u <usuario> -e bash $S/inspect-vllm-image.sh local` | Versiones, GPU, arquitecturas, kernels b12x y flags de una imagen (usa `inspect-vllm.py` dentro del contenedor) |
| 9 | `build-vllm-image.sh` | `wsl -d Ubuntu -u <usuario> -e bash $S/build-vllm-image.sh` | Construye `nexodeck-vllm:<versión>-b12x` (`Dockerfile.vllm`): la imagen oficial **no** trae b12x |
| 10 | `serve-model.sh <rol>` | `wsl -d Ubuntu -u <usuario> -e bash $S/serve-model.sh router` | Arranca un modelo (`router`, `fast`, `complex`) en `127.0.0.1` y espera a que responda. De uno en uno |
| 10b | `serve-profile.sh <A\|B\|complex-solo>` | `wsl -d Ubuntu -u <usuario> -e bash $S/serve-profile.sh B` | **La forma normal de arrancar el stack**: para todo y levanta un perfil. **Los roles ya no están fijos en el script**: salen de `profiles.json` vía `profile-roles.py`. Sin ese fichero vale el mapeo histórico (A: Router + Gemma; B: Router + Complejo; complex-solo) |
| 10c | `chat-check.py` | `wsl -d Ubuntu -e python3 $S/chat-check.py` | **Ejecútalo tras arrancar o despertar cualquier modelo**: comprueba que responde de forma coherente (detecta salida basura). `bench.py` no lo ve |
| 10d | `check-cuda.sh` | `wsl -d Ubuntu -u <usuario> -e bash $S/check-cuda.sh 60` | Prueba mínima de CUDA en un contenedor, con límite de tiempo. **Primera comprobación** si un arranque se queda parado sin error |
| — | `Start-Stack.ps1 -Profile A\|B\|none` | Windows: `.\Start-Stack.ps1` (sin argumentos = perfil A) | **Levanta todo**: sesión de WSL2, pasarela y modelos del perfil. **El perfil A es el recomendado y el de por defecto** (Gemma domina al Complejo en calidad, doc 11 §7.28); el B solo para velocidad o contexto de 16k. Antes lo lanzaba la tarea de inicio de sesión con `-Profile none` (solo pasarela); desde el 2026-09-24 esa tarea está deshabilitada y `Start-Stack.ps1` se corre a mano (o con la tarea habilitada a propósito) solo al abrir NexoDeck y usar sus funciones de IA — ver `Install-StackTask.ps1` abajo |
| — | `Start-Gateway.ps1` | Windows: lo lanza `Start-Stack.ps1` (no hace falta a mano) | Envoltorio de la pasarela: la arranca y la relanza si el proceso se cae (hasta 5 reintentos con espera creciente). `Stop-Stack.ps1` lo detiene **antes** de matar la pasarela, o la resucitaria |
| — | `Download-Model.ps1 -Role <rol>` | Lo lanza la app desde el selector de modelos (tile del stack, «Falta descargar»); también a mano | Descarga un modelo del stack: resuelve la ruta en WSL2 con `wslpath` y ejecuta `download-models.sh <rol>`. El selector muestra una **barra con el porcentaje y el MB/s** (mide `~/models/<dir>` cada 2 s) y el detalle de `hf` sale en el panel de Ejecuciones. Concurrencia de ficheros por `HF_MAX_WORKERS` (16 por defecto); backend Xet de alto rendimiento (`HF_XET_HIGH_PERFORMANCE`). Reanudable |
| — | `Stop-Stack.ps1 [-ReleaseWsl]` | Windows: `.\Stop-Stack.ps1 -ReleaseWsl` | Para modelos y pasarela y libera la GPU (y con `-ReleaseWsl`, la RAM de WSL2) para ODM, entrenamientos o juegos |
| — | `Install-StackTask.ps1 [-Profile none\|A\|B] [-Remove] [-Status]` | Windows: `.\Install-StackTask.ps1 -Profile none -WhatIf` | Registra la tarea de inicio de sesión `NexoDeckLlmStack` (reversible, sin elevar). Por defecto solo pasarela. **Deshabilitada desde el 2026-09-24**: solo debe habilitarse cuando se abre NexoDeck y se van a usar sus funciones de IA, no en cada inicio de sesión de Windows — ver `docs/llm-stack/11-mejoras-y-decisiones.md` §7.20 |
| — | `Test-Gateway.ps1` | Windows: `.\Test-Gateway.ps1` | Prueba de humo de la pasarela contra el stack real, con una clave desechable |
| 10e | `tools-check.py --model router\|complex` | `python tools-check.py --model complex` (con `NEXODECK_LLM_KEY`) | Comprueba el *tool calling* con la petición del agente de NexoDeck, por la pasarela y con streaming. **Ejecútalo tras cambiar los flags de un modelo** |
| — | `vllm-help.sh <flag>...` | `wsl -d Ubuntu -e bash $S/vllm-help.sh --tool-call-parser` | Ayuda real de `vllm serve` para un flag (valores válidos incluidos). Es la fuente fiable; buscar en el código con `grep` falla |
| 10f | `eval-humaneval.py --model complex --port 8000` | `wsl -d Ubuntu -e python3 $S/eval-humaneval.py --model complex --port 8000` (`--selftest` para comprobar el evaluador) | pass@1 en HumanEval (164 problemas). **El código del modelo se ejecuta en un contenedor aislado** (sin red, solo lectura, no root, con límites). Corre el `--selftest` antes: comprueba que el evaluador falla lo que debe fallar y que el aislamiento aísla |
| 10g | `replay-routing.py` | `wsl -d Ubuntu -e python3 $S/replay-routing.py` | Simula políticas de enrutado **sin GPU** con los resultados ya medidos de `eval-humaneval.py`, comparándolas con el azar al mismo reparto (IC95 % por remuestreo) y evaluando una cascada con verificador |
| 10h | `prepare-mmlu.py` + `eval-mmlu.py --model X --port N [--reason]` + `analyze-mmlu.py` | `uv run --no-project --with pyarrow python3 prepare-mmlu.py` (una vez); luego `eval-mmlu.py` y `analyze-mmlu.py` en WSL | Conocimiento general (MMLU, 570 preguntas estratificadas) y su comparación por categoría con intervalos. `--reason` deja razonar antes de responder, para separar fallos de formato de fallos de conocimiento |
| 10i | `feedback-e2e.py` + `summarize-decisions.py` | Windows: `python feedback-e2e.py --sample "\\wsl.localhost\Ubuntu\home\<usuario>\eval\mmlu-sample.jsonl" --n 60` (con `NEXODECK_LLM_KEY`); luego `python summarize-decisions.py` | Envía preguntas MMLU por la pasarela con `auto`, verifica cada respuesta y la informa con `POST /v1/feedback`; el resumen une decisiones y resultados por modelo. Genera datos reales para `decisions.jsonl` |
| 10j | `check-code-detector.py` | Windows: `python check-code-detector.py --humaneval HumanEval.jsonl --mmlu mmlu-sample.jsonl --show` (los `.jsonl` se copian de `~/eval` en WSL) | Valida el detector de código de `auto` (`llm-stack/gateway/examples/classify.rs`, el detector real): recall sobre HumanEval y falsos positivos sobre MMLU. Rerun tras tocar `code_markers`. Con `--mmlu-es` y `--code-es data/code-prompts-es.jsonl` mide también el español |
| 10k | `prepare-mmlu-es.py` + `eval-auto-mixed.py` | Windows: `python prepare-mmlu-es.py --out mmlu-es-sample.jsonl`; con el perfil B levantado y una clave desechable (`llm-gateway keys add …`, revocarla después): `python eval-auto-mixed.py --mmlu-es … --mmlu … --humaneval … --code-es data/code-prompts-es.jsonl --n 100`. **Al acabar: `Stop-Stack.ps1 -ReleaseWsl`** | MMLU en español (MMMLU) por `auto` y por cada modelo explícito, y a dónde va cada prompt de código (inglés y español). Extremo a extremo con los modelos reales |
| 11 | `bench.py` | `wsl -d Ubuntu -e python3 $S/bench.py --port 8002 --model router --clients 1 4 8` | Mide tok/s agregados, por cliente y latencia con N clientes a la vez |
| 0 | `Start-WslKeepAlive.ps1` | Windows: `.\Start-WslKeepAlive.ps1` (`-Stop` para quitarlo) | **Lánzalo antes de arrancar modelos.** Mantiene abierta una sesión de WSL2; sin ella la distro se apaga a los ~15 s y los servidores «se caen solos» |
| — | `grep-vllm-source.sh <regex> [ruta]` | `wsl -d Ubuntu -u <usuario> -e bash $S/grep-vllm-source.sh 'UVA is not available'` | Busca en el código de vLLM de la imagen; así se encontró la causa de los fallos de arranque |
| — | `stop-models.sh [rol ...]` | `wsl -d Ubuntu -u <usuario> -e bash $S/stop-models.sh` | Para y elimina los contenedores del stack |
| — | `probe-b12x-extra.sh` | dentro del contenedor (lo usó el paso 9) | Muestra qué versiones traería `vllm[b12x]` sin instalar nada |

Extras: `check-scripts.sh` (autocomprobación de esta carpeta, sin tocar el sistema), `list-models.py` (lo usa `download-models.sh`), `profile-roles.py` (lo usa `serve-profile.sh`) y `models.json` (**única fuente** de repos, carpetas y cuantización esperada; además `display_name`, `notes`, `size_gb`, `vram_gb` y `context`, que son los que muestra la pantalla «Configura tus perfiles» de NexoDeck; `vram_gb` es la huella en VRAM y la app la suma para no dejar configurar dos modelos que no caben). `profiles.json` (**lo escribe NexoDeck**) dice qué rol llena el slot `router` y el slot `thinking` de cada perfil; un slot con `source` distinto de `stack` (llamacpp, ollama, remote, claudecode) no lo sirve vLLM.

Con `-e bash <script>` no hace falta `chmod +x`. El usuario de Ubuntu de esta máquina es `usuario`; los docs 03-10 llevan `/home/juan`, que es del autor original.

## Lo que costó descubrir

- **Nada de código dentro de un `wsl ... -e sh -c "..."`.** Las comillas se mutilan por el camino (pasó dos veces el 18-sep-2026) y el error apunta al sitio equivocado. Todo va en fichero y se lanza el fichero. Es la regla de `D:\Repositorios\CLAUDE.md`.
- **Finales de línea:** un `.sh` con CRLF falla con `$'\r': orden no encontrada`. El `.gitattributes` de esta carpeta fuerza LF; `check-scripts.sh` lo comprueba.
- **`hf`, no `huggingface-cli`.** La CLI actual se llama `hf`, y `--local-dir-use-symlinks` y `HF_HUB_ENABLE_HF_TRANSFER` están obsoletos (ahora `HF_XET_HIGH_PERFORMANCE=1`).
- **`install-docker-engine.sh` reinicia el servicio docker** al final: corta cualquier `docker pull` o contenedor en marcha. No lo lances mientras baja la imagen de vLLM.
- **`wsl --terminate <distro>` tras crear el grupo `docker`**, o el usuario sigue sin poder usarlo sin sudo.
- **La imagen de vLLM pesa 30.5 GB** (digest en `vllm-image.lock`); cuenta con ello al dimensionar el disco virtual.
- **`autoMemoryReclaim` en `[wsl2]` se ignora** con el aviso `Clave 'wsl2.autoMemoryReclaim' desconocida`. Va en `[experimental]` (`-ReclaimMemory`).

### De arrancar vLLM en WSL2 (18-sep-2026)

- **`UVA is not available`:** en WSL2 vLLM desactiva la memoria fijada y el ejecutor v2 la necesita. Va `VLLM_WSL2_ENABLE_PIN_MEMORY=1` (ya en `serve-model.sh`).
- **El traceback final de vLLM no dice nada** (`Engine core initialization failed`); la causa está antes, en el proceso `EngineCore`. `serve-model.sh` guarda el registro en `~/vllm-stack/logs/vllm-<rol>.log` y extrae la excepción.
- **Un servidor que se para solo con salida 0 y sin error** es WSL2 apagando la distro: usa `Start-WslKeepAlive.ps1`.
- **Con dos instancias en la GPU no uses fracciones** (`--gpu-memory-utilization`): vLLM las mide mal. `serve-model.sh` fija el KV en bytes (`--kv-cache-memory`).
- **El KV de Gemma tiene un suelo de ~1.6 GiB**: menos de 1.75 GiB no arranca aunque bajes el contexto.
- **`nvidia-smi` puede infravalorar la VRAM** (WDDM desaloja memoria a RAM sin avisar). Mide tok/s, no solo la memoria.
- **`--moe-backend b12x` (que la receta obliga a forzar) rompe los grafos CUDA del Complejo** (`illegal memory access`); con `--enforce-eager` va a 7 tok/s. Usa `--moe-backend flashinfer_cutlass` (~100 tok/s). El kernel lineal sigue siendo `b12x`.
- **`--cpu-offload-gb` no sirve en modelos densos**: lee todo lo offloadeado en cada token a ~4.5 GB/s efectivos bajo WSL2 (Router: 3 tok/s con 1.5 GiB fuera).
- **`--max-num-batched-tokens 256` cuesta ~25 % de rendimiento** en el Complejo; 512 no.
- **Bajo WSL2 cada instancia de vLLM ve la GPU casi libre**: no detecta que te pasas de memoria entre instancias. El presupuesto lo pones tú (`serve-profile.sh` ya lo lleva medido).
- **Con `--kv-cache-memory` hay que pasar también una `--gpu-memory-utilization` baja** (`serve-model.sh` ya lo hace), o vLLM falla al arrancar si Windows ocupa más de ~1.3 GiB.
- **No edites un script mientras corre.** Bash lo lee por posición: al cambiar su contenido a media ejecución, el arranque quedó corrupto (`line 112: -p: command not found`, código 127) y el contenedor quedó con una configuración desconocida. Espera a que termine, o escribe los cambios en un fichero nuevo.
- **`$PSScriptRoot` llega vacío en el valor por defecto de un parámetro cuando el script se lanza con `powershell.exe -File`** (como hace la tarea programada), aunque funcione con `&`. Calcula las rutas dentro del cuerpo. Los scripts probados solo a mano no lo delatan: **prueba también con el comando exacto de la tarea**.
- **Temperatura 0 no es determinista con vLLM bajo carga concurrente** (HumanEval: Router 130 → 123 aciertos entre dos pasadas idénticas). Da rangos, no una cifra; y no compares dos pasadas sueltas.
- **El Router (4B) entra en bucles de repetición con decodificación voraz** en ~4 % de los problemas de código: cualquier uso automatizado debe fijar `temperature > 0` o penalización de repetición y un tope de tokens. `analyze-eval.py` distingue estos cortes de un fallo de extracción.
- **Sin `--enable-auto-tool-choice` y `--tool-call-parser`, vLLM contesta 400 a cualquier petición con `tools`** (la que hace el agente de NexoDeck). El Router y el Complejo usan `qwen3_coder`. Gemma (`gemma4`) sigue sin añadir ni probar.
- **`vllm serve --help` sin `--gpus all` muere con «Failed to infer device type»** y no imprime nada.
- **Los `.ps1` deben ser ASCII puro**: Windows PowerShell 5.1 lee mal el UTF-8 sin BOM.
- **Un aviso por `stderr` aborta `Start-Stack.ps1`.** Corre con `$ErrorActionPreference = 'Stop'` y captura `2>&1`, y PowerShell 5.1 convierte **cualquier** línea de stderr de `wsl` en un error terminante. Un perfil todo-remoto (DeepSeek, Claude Code) hacía que `serve-profile.sh` avisara «no tiene ningún modelo local», y el arranque moría con `NativeCommandError` **aunque `stop-models` ya hubiera corrido y la GPU quedara libre**. Regla: los **avisos van a stdout**; la llamada a `wsl` baja la preferencia a `Continue` mientras corre y decide por `$LASTEXITCODE`.
- **Un healthcheck no puede sondear a otros servidores dentro de la propia petición**: con los modelos apagados tardaba 2 s y el script de arranque abortaba. La pasarela sondea en segundo plano.
- **Docker NO reinicia por healthcheck.** Una política `--restart` reacciona solo a que el *proceso* salga; un contenedor «vivo pero insano» queda así para siempre. El `HEALTHCHECK` da visibilidad (`docker inspect --format '{{.State.Health.Status}}'`), no recuperación. Por eso el reinicio va acotado (`--restart on-failure:3`, no `always`) y el healthcheck usa `python3` dentro del contenedor, no `curl` (la imagen no lo garantiza).
- **`docker rm -f` no dispara un reinicio**: `stop-models.sh` borra el contenedor, así que la regla de limpieza del `[limpieza]` sigue valiendo aunque los contenedores tengan política de reinicio.
- **Un arranque que se queda parado sin excepción (proceso al 100 % de CPU) no es un dato de vLLM**: ejecuta primero `check-cuda.sh`. Si CUDA no inicializa, la GPU bajo WSL2 está rota (pasó tras el fallo del KV en RAM): `wsl --shutdown` y volver a lanzar `Start-WslKeepAlive.ps1`. Un primer diagnóstico erróneo («Sleep Mode cuelga») costó tiempo por no comprobarlo.
- **`SLEEP_MODE=1` funciona en nivel 1** (dormir 13 s, despertar 2 s) pero deja ~15.8 GB de RAM ocupados; **el nivel 2 corrompe el modelo NVFP4** (salida basura sin ningún error). `test-sleep-mode.py --level 1|2` lo mide.
- **`--kv-offloading-size` falla bajo WSL2** (`illegal memory access` en la primera petición): no lo uses.
- **`log-summary.sh <rol>`** resume un registro de vLLM (kernels elegidos, memoria, excepciones) sin volcar cientos de líneas.
- **Los `-e sh -c "..."` con comillas se mutilan** (PowerShell + wsl): usa siempre un fichero.

## Lo que falta por scriptar

Arranque de los perfiles A y B, benchmark (`vllm bench serve`), pasarela y árbitro de GPU: se escriben aquí a medida que se ejecuten, con el mismo criterio.
