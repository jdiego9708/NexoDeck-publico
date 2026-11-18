---
date: 2026-09-17
---
# 04-vLLM-Serving

# 04-vLLM-Serving — Servidores vLLM con Sleep Mode

Documentación completa para lanzar los tres servidores vLLM del stack multiagente con selección explícita de backends b12x, gestión de VRAM mediante Sleep Mode, y criterios de verificación antes de integrar con el router semántico.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Decisiones Arquitectónicas](#2-decisiones-arquitectónicas)
3. [Paso 1 — Entender Sleep Mode](#3-paso-1--entender-sleep-mode)
4. [Paso 2 — Variables de Entorno Críticas](#4-paso-2--variables-de-entorno-críticas)
5. [Paso 3 — Lanzar Modelo Complejo (Qwen3-Coder-30B)](#5-paso-3--lanzar-modelo-complejo-qwen3-coder-30b)
6. [Paso 4 — Lanzar Modelo Rápido (Gemma 4 12B AWQ)](#6-paso-4--lanzar-modelo-rápido-gemma-4-12b-awq)
7. [Paso 5 — Lanzar Modelo Router (Qwen 3.5 4B NVFP4)](#7-paso-5--lanzar-modelo-router-qwen-35-4b-nvfp4)
8. [Paso 6 — Verificar los 3 Servidores](#8-paso-6--verificar-los-3-servidores)
9. [Paso 7 — Gestionar Sleep/Wake vía API](#9-paso-7--gestionar-sleepwake-vía-api)
10. [Paso 8 — Monitorear VRAM y Rendimiento](#10-paso-8--monitorear-vram-y-rendimiento)
11. [Paso 9 — Matriz de Combinaciones Válidas](#11-paso-9--matriz-de-combinaciones-válidas)
12. [Checklist Final](#12-checklist-final)
13. [Advertencias Críticas](#13-advertencias-críticas)
14. [Referencias](#14-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `03-Model-Download.md`. Debes tener:

- venv en `~/vllm-stack/.venv` activado.
- vLLM >= 0.29.0 con kernels b12x verificados.
- Tres modelos descargados y validados:
  - `~/models/qwen3-coder-30b-reap50-nvfp4/` (~9.9 GB, NVFP4)
  - `~/models/gemma-4-12b-awq/` (~6.8 GB, AWQ)
  - `~/models/qwen3.5-4b-nvfp4/` (~2.5 GB, NVFP4)
- Al menos 15 GB libres en disco.

El objetivo de esta fase es **lanzar los tres servidores vLLM** con selección explícita de backends, configurar Sleep Mode para gestionar VRAM, y verificar que cada endpoint responde correctamente antes de integrar el router semántico.

### Topología de puertos

| Puerto | Modelo | Cuantización | Backend | Rol |
|:---|:---|:---|:---|:---|
| **8000** | Qwen3-Coder-30B-A3B REAP-50 | NVFP4 | b12x | Complejo |
| **8001** | Gemma 4 12B | AWQ | Marlin | Rápido |
| **8002** | Qwen 3.5 4B | NVFP4 | b12x | Router / Meta |

Todos los servidores exponen la API OpenAI-compatible en `/v1/chat/completions`.

---

## 2. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Tres servidores independientes** | Un solo vLLM con múltiples modelos | vLLM no soporta múltiples modelos en un solo proceso con VRAM compartida. Sleep Mode permite alternar sin recargar desde disco. |
| **Sleep Mode habilitado** | Cargar/descargar modelos manualmente | Sleep Mode mantiene los pesos en RAM del sistema y los mueve a VRAM en <1s. Cargar desde disco tarda 30-120s. |
| **`--enforce-eager` en el complejo** | `torch.compile` por defecto | torch.compile falla en SM120 con NVFP4 MoE. `--enforce-eager` evita crashes. |
| **`--linear-backend b12x` explícito** | `auto` | La auto-selección omite b12x en SM120 y cae en Marlin. |
| **`--moe-backend b12x` explícito (complejo)** | `auto` | Igual que arriba. Aplica solo a modelos MoE. |
| **`--quantization awq_marlin` (rápido)** | `auto` | Fuerza kernels Marlin precompilados, evitando JIT de otros backends. |
| **`VLLM_ATTENTION_BACKEND=TRITON_ATTN`** | `FLASH_ATTN` | NVFP4 en SM120 requiere Triton attention. FlashAttention falla con NVFP4. |
| **`--max-model-len 16384` (complejo)** | 32768 | Techo real para 30B en 16 GB con margen para KV cache. |
| **`--max-model-len 32768` (rápido)** | 131072 | Gemma 4 12B es denso y cabe con contexto largo. Reduce a 16k si hay OOM. |

---

## 3. Paso 1 — Entender Sleep Mode

### 3.1 ¿Qué es Sleep Mode?

Es una funcionalidad de vLLM que permite **descargar los pesos del modelo de VRAM a RAM** sin destruir el proceso del servidor. Cuando se necesita de nuevo, los pesos se mueven de vuelta a VRAM en <1 segundo.

**¿Por qué es crítico para tu stack?** Tienes tres modelos que suman ~19.5 GB de VRAM, pero solo 16 GB disponibles. Sleep Mode permite tener los tres cargados en RAM del sistema, y solo el activo en VRAM.

### 3.2 Niveles de Sleep

| Nivel | Qué descarga | Tiempo de despertar | Uso |
|:---|:---|:---|:---|
| **Level 1** | Pesos → CPU RAM, KV cache descartado | <1s | Alternar mismo modelo sin perder pesos |
| **Level 2** | Pesos descartados, buffers en CPU | <1s + reload | Cambiar entre modelos (requiere `reload_weights`) |

**Diferencia clave**:

- **Level 1** mantiene los pesos en RAM. Despertar es instantáneo.
- **Level 2** descarta los pesos de RAM pero mantiene el proceso vivo. Despertar requiere recargar desde disco (o desde un buffer si se especifica).

### 3.3 Requisitos

- Variable de entorno `VLLM_SERVER_DEV_MODE=1`.
- Flag `--enable-sleep-mode` al lanzar el servidor.

**Sin `VLLM_SERVER_DEV_MODE=1`, los endpoints `/sleep` y `/wake_up` devuelven 404.**

### 3.4 Endpoints de Sleep

| Endpoint | Método | Descripción |
|:---|:---|:---|
| `/sleep?level=N` | POST | Duerme el modelo (N=1 o 2) |
| `/wake_up` | POST | Despierta el modelo |
| `/is_sleeping` | GET | Estado actual (true/false) |
| `/reload_weights` | POST | Recarga pesos (necesario tras Level 2) |
| `/reset_prefix_cache` | POST | Limpia el caché de prefijos tras wake |

---

## 4. Paso 2 — Variables de Entorno Críticas

### 4.1 ¿Por qué son críticas?

Los kernels NVFP4 y b12x requieren configuración específica de atención y backend. Sin estas variables, vLLM puede:

- Fallar al compilar kernels (`RuntimeError`).
- Caer en backends más lentos silenciosamente (Marlin).
- Producir resultados incorrectos por kernels inestables.

### 4.2 Variables por servidor

**Modelo complejo (Qwen3-Coder-30B NVFP4)**:

export VLLM_ATTENTION_BACKEND=TRITON_ATTN
export VLLM_USE_FLASHINFER_MOE_FP4=1
export VLLM_SERVER_DEV_MODE=1
export VLLM_LOGGING_LEVEL=INFO
export VLLM_NO_USAGE_STATS=1

Modelo rápido (Gemma 4 12B AWQ):

bash
export VLLM_ATTENTION_BACKEND=TRITON_ATTN
export VLLM_SERVER_DEV_MODE=1
export VLLM_LOGGING_LEVEL=INFO
export VLLM_NO_USAGE_STATS=1
Modelo router (Qwen 3.5 4B NVFP4):

bash
export VLLM_ATTENTION_BACKEND=TRITON_ATTN
export VLLM_SERVER_DEV_MODE=1
export VLLM_LOGGING_LEVEL=INFO
export VLLM_NO_USAGE_STATS=1
4.3 Explicación de cada variable
Variable	Valor	Razón
VLLM_ATTENTION_BACKEND	TRITON_ATTN	NVFP4 en SM120 requiere Triton attention. FLASH_ATTN falla con NVFP4.
VLLM_USE_FLASHINFER_MOE_FP4	1	Activa kernels FlashInfer para MoE FP4 (necesario para Qwen3-Coder-30B).
VLLM_SERVER_DEV_MODE	1	Habilita endpoints /sleep, /wake_up, /collective_rpc. Requisito para Sleep Mode.
VLLM_LOGGING_LEVEL	INFO	Nivel de detalle en logs. DEBUG para troubleshooting.
VLLM_NO_USAGE_STATS	1	Desactiva telemetría a vLLM.
4.4 Persistencia (opcional)
Añadir a ~/.bashrc para que estén siempre disponibles:

bash
cat >> ~/.bashrc << 'EOF'

# vLLM environment variables
export VLLM_ATTENTION_BACKEND=TRITON_ATTN
export VLLM_USE_FLASHINFER_MOE_FP4=1
export VLLM_SERVER_DEV_MODE=1
export VLLM_LOGGING_LEVEL=INFO
export VLLM_NO_USAGE_STATS=1
EOF

source ~/.bashrc
Advertencia: VLLM_SERVER_DEV_MODE=1 habilita endpoints que pueden ser peligrosos si se exponen a Internet (por ejemplo, /collective_rpc). Nunca expongas los puertos 8000/8001/8002 directamente a Internet. Solo el puerto del router (8888) se expone vía túnel.

5. Paso 3 — Lanzar Modelo Complejo (Qwen3-Coder-30B)
5.1 ¿Por qué en puerto 8000?
Es el modelo más pesado y el que más tarda en arrancar (por JIT de kernels NVFP4). Asignarle el puerto 8000 (el primero) facilita la organización.

5.2 Comando de lanzamiento
En una terminal Ubuntu nueva:

bash
source ~/vllm-stack/.venv/bin/activate

vllm serve ~/models/qwen3-coder-30b-reap50-nvfp4 \
  --served-model-name qwen3-coder-30b \
  --linear-backend b12x \
  --moe-backend b12x \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.90 \
  --enforce-eager \
  --enable-sleep-mode \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --port 8000 \
  --host 0.0.0.0
5.3 Explicación de cada flag
Flag	Valor	Razón
--served-model-name	qwen3-coder-30b	Nombre lógico para la API (distinto del path).
--linear-backend b12x	Explícito	Auto-selección omite b12x en SM120.
--moe-backend b12x	Explícito	Igual. Aplica solo a modelos MoE.
--max-model-len 16384	16k	Techo real para 30B en 16 GB con margen para KV cache.
--gpu-memory-utilization 0.90	90%	Deja 10% para overhead del driver y otros procesos.
--enforce-eager	—	Evita torch.compile que falla con NVFP4 MoE en SM120.
--enable-sleep-mode	—	Habilita /sleep y /wake_up.
--enable-auto-tool-choice	—	Permite que el modelo decida usar herramientas.
--tool-call-parser qwen3_coder	—	Parser específico para el formato de tool-calling de Qwen3-Coder.
--port 8000	8000	Puerto de la API OpenAI-compatible.
--host 0.0.0.0	—	Escucha en todas las interfaces (necesario para WSL2 → Windows).
5.4 Primera ejecución: JIT compilation
La primera vez que arranques este servidor, verás:

GPU idle (0% usage).

Un core de CPU al 100%.

El log muestra Compiling kernels... o similar.

Tarda entre 2 y 5 minutos.

Esto es normal. FlashInfer y b12x compilan kernels NVFP4 para SM120 en el primer uso, y los cachean para futuros arranques.

NO interrumpas el proceso. Si lo haces, el caché queda incompleto y el próximo arranque vuelve a empezar.

5.5 Verificar caché de kernels
Tras el primer arranque exitoso, el caché queda en:

bash
ls -la ~/.cache/vllm/
ls -la ~/.cache/flashinfer/
En arranques posteriores, el servidor estará listo en ~15 segundos.

5.6 Verificar que arrancó
En otra terminal:

bash
curl http://localhost:8000/v1/models | python -m json.tool
Salida esperada:

json
{
    "object": "list",
    "data": [
        {
            "id": "qwen3-coder-30b",
            "object": "model",
            "created": 1726608000,
            "owned_by": "vllm",
            "root": "qwen3-coder-30b",
            "parent": null,
            "max_model_len": 16384
        }
    ]
}
5.7 Test de inferencia
bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-30b",
    "messages": [
      {"role": "user", "content": "Write a Python function to merge two sorted lists."}
    ],
    "temperature": 0.7,
    "top_p": 0.8,
    "max_tokens": 300
  }' | python -m json.tool
Salida esperada: JSON con choices[0].message.content conteniendo el código Python.

5.8 Verificar uso de VRAM
En otra terminal:

bash
nvidia-smi
Salida esperada:

Memory-Usage: ~11-12 GB (pesos + KV cache + overhead).

GPU-Util: variable según carga.

6. Paso 4 — Lanzar Modelo Rápido (Gemma 4 12B AWQ)
6.1 ¿Por qué en puerto 8001?
Es el segundo modelo más pesado, pero arranca más rápido que el complejo (no requiere JIT de NVFP4 porque usa Marlin).

6.2 Comando de lanzamiento
En una terminal Ubuntu nueva (segunda):

bash
source ~/vllm-stack/.venv/bin/activate

vllm serve ~/models/gemma-4-12b-awq \
  --served-model-name gemma-4-12b \
  --quantization awq_marlin \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.85 \
  --enable-sleep-mode \
  --enable-prefix-caching \
  --port 8001 \
  --host 0.0.0.0
6.3 Explicación de cada flag
Flag	Valor	Razón
--served-model-name	gemma-4-12b	Nombre lógico para la API.
--quantization awq_marlin	Explícito	Fuerza kernels Marlin precompilados. Evita JIT.
--max-model-len 32768	32k	Gemma 4 12B es denso y cabe con contexto largo.
--gpu-memory-utilization 0.85	85%	Menos agresivo porque puede convivir con el router.
--enable-sleep-mode	—	Habilita /sleep y /wake_up.
--enable-prefix-caching	—	Reutiliza prefijos comunes entre agentes concurrentes. Reduce latencia y consumo de tokens.
--port 8001	8001	Puerto de la API.
--host 0.0.0.0	—	Escucha en todas las interfaces.
6.4 ¿Por qué no lleva --moe-backend?
Gemma 4 12B es un modelo denso, no MoE. No tiene capas de expertos, así que el flag --moe-backend no aplica.

6.5 ¿Por qué --enable-prefix-caching?
Cuando varios agentes comparten el mismo system prompt (por ejemplo, "You are a senior Python developer..."), el caché de prefijos reutiliza los estados KV de ese prefijo. Esto reduce latencia y consumo de tokens en escenarios multiagente.

6.6 Tiempo de arranque
~20-30 segundos. No requiere JIT compilation porque Marlin usa kernels precompilados.

6.7 Verificar que arrancó
bash
curl http://localhost:8001/v1/models | python -m json.tool
Salida esperada: JSON con gemma-4-12b.

6.8 Test de inferencia
bash
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-4-12b",
    "messages": [
      {"role": "user", "content": "Explain the Observer pattern in 3 sentences."}
    ],
    "temperature": 0.7,
    "max_tokens": 200
  }' | python -m json.tool
7. Paso 5 — Lanzar Modelo Router (Qwen 3.5 4B NVFP4)
7.1 ¿Por qué en puerto 8002?
Es el modelo más ligero. Asignarle el último puerto (8002) facilita la organización.

7.2 Comando de lanzamiento
En una terminal Ubuntu nueva (tercera):

bash
source ~/vllm-stack/.venv/bin/activate

vllm serve ~/models/qwen3.5-4b-nvfp4 \
  --served-model-name qwen3.5-4b \
  --linear-backend b12x \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.75 \
  --enable-sleep-mode \
  --port 8002 \
  --host 0.0.0.0
7.3 Explicación de cada flag
Flag	Valor	Razón
--served-model-name	qwen3.5-4b	Nombre lógico para la API.
--linear-backend b12x	Explícito	Qwen 3.5 4B NVFP4 usa capas densas, necesita b12x.
--max-model-len 16384	16k	Suficiente para clasificación y tool-calling. Reduce VRAM.
--gpu-memory-utilization 0.75	75%	Menos agresivo porque convive con el rápido por defecto.
--enable-sleep-mode	—	Habilita /sleep y /wake_up.
--port 8002	8002	Puerto de la API.
--host 0.0.0.0	—	Escucha en todas las interfaces.
7.4 Tiempo de arranque
~1-2 minutos en el primer arranque (JIT de kernels NVFP4 para capas densas). Arranques posteriores: ~10 segundos.

7.5 Verificar que arrancó
bash
curl http://localhost:8002/v1/models | python -m json.tool
7.6 Test de inferencia
bash
curl http://localhost:8002/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [
      {"role": "user", "content": "Classify this prompt: Write a function to sort a list."}
    ],
    "temperature": 0.1,
    "max_tokens": 50
  }' | python -m json.tool
8. Paso 6 — Verificar los 3 Servidores
8.1 Verificar que todos están corriendo
bash
for port in 8000 8001 8002; do
  echo -n "Puerto $port: "
  curl -s http://localhost:$port/v1/models | python -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "✗ No responde"
done
Salida esperada:

text
Puerto 8000: qwen3-coder-30b
Puerto 8001: gemma-4-12b
Puerto 8002: qwen3.5-4b
8.2 Verificar procesos
bash
ps aux | grep "vllm serve" | grep -v grep
Salida esperada: 3 procesos vllm serve con diferentes --port.

8.3 Verificar uso de VRAM total
bash
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv
Salida esperada (si los 3 están activos):

text
memory.used [MiB], memory.free [MiB], memory.total [MiB]
15XXX MiB, XXX MiB, 16311 MiB
Si el total usado supera los 16 GB, uno de los modelos ha fallado al cargar o hay OOM.

8.4 Test de inferencia paralela
bash
for port in 8000 8001 8002; do
  echo "=== Puerto $port ==="
  curl -s http://localhost:$port/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "auto",
      "messages": [{"role": "user", "content": "Say hello."}],
      "max_tokens": 20
    }' | python -c "import sys, json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
done
9. Paso 7 — Gestionar Sleep/Wake vía API
9.1 Verificar estado de sleep
bash
for port in 8000 8001 8002; do
  echo -n "Puerto $port: "
  curl -s http://localhost:$port/is_sleeping
  echo ""
done
Salida esperada (todos despiertos al arrancar):

text
Puerto 8000: {"is_sleeping": false}
Puerto 8001: {"is_sleeping": false}
Puerto 8002: {"is_sleeping": false}
9.2 Dormir un modelo (Level 1)
bash
curl -X POST http://localhost:8001/sleep?level=1
Efecto: Los pesos de Gemma 4 12B se mueven a RAM. VRAM usada baja ~7 GB.

Verificar:

bash
nvidia-smi --query-gpu=memory.used --format=csv
curl http://localhost:8001/is_sleeping
Salida esperada:

text
memory.used [MiB]
XXXX MiB  (bajó ~7 GB)
{"is_sleeping": true}
9.3 Despertar un modelo
bash
curl -X POST http://localhost:8001/wake_up
Tiempo: <1 segundo (los pesos están en RAM).

9.4 Dormir un modelo (Level 2)
Level 2 descarta los pesos de RAM, pero mantiene el proceso vivo.

bash
curl -X POST http://localhost:8000/sleep?level=2
Para despertar tras Level 2:

bash
curl -X POST http://localhost:8000/wake_up
curl -X POST http://localhost:8000/reload_weights
curl -X POST http://localhost:8000/reset_prefix_cache
Tiempo: ~5-10 segundos (recarga desde disco).

9.5 Secuencia de cambio de modelo
Escenario: Tienes Router + Rápido activos. Quieres usar el Complejo.

bash
# 1. Dormir Rápido (Level 1, mantiene pesos en RAM)
curl -X POST http://localhost:8001/sleep?level=1

# 2. Verificar VRAM liberada
nvidia-smi --query-gpu=memory.used --format=csv

# 3. Despertar Complejo (si estaba dormido)
curl -X POST http://localhost:8000/wake_up

# 4. Verificar
curl http://localhost:8000/is_sleeping
Escenario inverso: Volver a Router + Rápido.

bash
# 1. Dormir Complejo
curl -X POST http://localhost:8000/sleep?level=1

# 2. Despertar Rápido
curl -X POST http://localhost:8001/wake_up

# 3. Verificar
curl http://localhost:8001/is_sleeping
9.6 Combinaciones de estado
Estado	Router	Rápido	Complejo	VRAM usada
Todos despiertos	Awake	Awake	Awake	✗ OOM
Router + Rápido	Awake	Awake	Sleeping	~9.5 GB
Router + Complejo	Awake	Sleeping	Awake	~12.5 GB
Solo Rápido	Sleeping	Awake	Sleeping	~9 GB
Solo Complejo	Sleeping	Sleeping	Awake	~12 GB
Solo Router	Awake	Sleeping	Sleeping	~4.5 GB
9.7 Detener servidores
Si necesitas detener un servidor específico:

bash
# Encontrar PID por puerto
ps aux | grep "vllm serve" | grep "port 8001" | grep -v grep

# Matar el proceso
kill <PID>
Para detener todos:

bash
pkill -f "vllm serve"
10. Paso 8 — Monitorear VRAM y Rendimiento
10.1 Monitoreo en tiempo real
bash
watch -n 2 nvidia-smi
Salida esperada: actualización cada 2 segundos del uso de VRAM, temperatura, y procesos.

10.2 Consultas específicas
bash
# Uso de memoria
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# Procesos usando GPU
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# Temperatura y potencia
nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit --format=csv
10.3 Logs de cada servidor
bash
# Complejo
tail -f ~/vllm-stack/logs/complex.log

# Rápido
tail -f ~/vllm-stack/logs/fast.log

# Router
tail -f ~/vllm-stack/logs/router-model.log
10.4 Métricas de vLLM
vLLM expone métricas Prometheus en /metrics:

bash
curl http://localhost:8000/metrics | head -50
Métricas útiles:

vllm:num_requests_running: peticiones en ejecución.

vllm:num_requests_waiting: peticiones en cola.

vllm:gpu_cache_usage_perc: uso del KV cache.

vllm:avg_prompt_throughput_toks_per_s: throughput de prompt.

vllm:avg_generation_throughput_toks_per_s: throughput de generación.

10.5 Test de carga concurrente
bash
# 8 peticiones concurrentes al modelo rápido
for i in $(seq 1 8); do
  curl -s http://localhost:8001/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"gemma-4-12b\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello $i\"}], \"max_tokens\": 20}" \
    > /dev/null &
done
wait
echo "8 peticiones concurrentes completadas"
Verificar en nvidia-smi que el uso de VRAM no supera los 16 GB.

11. Paso 9 — Matriz de Combinaciones Válidas
11.1 VRAM por modelo
Modelo	Pesos	KV cache (16k)	Overhead	Total
Router (Qwen 3.5 4B NVFP4)	~2.5 GB	~0.5 GB	~0.5 GB	~3.5 GB
Rápido (Gemma 4 12B AWQ)	~6.8 GB	~1.5 GB	~0.7 GB	~9 GB
Complejo (Qwen3-Coder-30B NVFP4)	~9.9 GB	~1.5 GB	~0.6 GB	~12 GB
11.2 Combinaciones
Combinación	Suma	¿Cabe en 16 GB?	Notas
Router + Rápido	~12.5 GB	✓ Sí	Deja ~3.5 GB para picos. Configuración por defecto recomendada.
Router + Complejo	~15.5 GB	⚠️ Justo	Deja ~0.5 GB. Riesgo de OOM bajo carga.
Rápido + Complejo	~21 GB	✗ No	—
Router + Rápido + Complejo	~24.5 GB	✗ No	—
Solo Complejo	~12 GB	✓ Sí	Deja ~4 GB para contexto extendido.
Solo Rápido	~9 GB	✓ Sí	Deja ~7 GB para contexto extendido.
Solo Router	~3.5 GB	✓ Sí	Deja ~12.5 GB libres.
11.3 Estrategia recomendada
Estado por defecto: Router + Rápido (~12.5 GB).

Razón: Cubre el 90% de las tareas (autocompletado, edición, consultas, clasificación). El router decide entre rápido y normal; ambos usan Gemma 4 12B.

Cambio a Complejo: cuando el router detecta una tarea complex (prompt largo o palabras clave de arquitectura). En ese momento:

Dormir Rápido (curl -X POST http://localhost:8001/sleep?level=1).

Despertar Complejo (curl -X POST http://localhost:8000/wake_up).

Vuelta a estado por defecto: tras N segundos sin peticiones complejas.

12. Checklist Final
Antes de pasar a la Fase 5 (router semántico), verificar:

Variables de entorno
□ VLLM_ATTENTION_BACKEND=TRITON_ATTN exportado
□ VLLM_USE_FLASHINFER_MOE_FP4=1 exportado
□ VLLM_SERVER_DEV_MODE=1 exportado
□ VLLM_NO_USAGE_STATS=1 exportado
Servidor complejo (Qwen3-Coder-30B)
□ Arrancó sin errores
□ curl http://localhost:8000/v1/models responde
□ Inferencia de prueba funciona
□ --linear-backend b12x y --moe-backend b12x presentes
□ JIT compilation completada (primera ejecución)
□ `--enable-sleep-mode` presente (**no se usa**: ver el doc 11, apartado 7.17)

---

> **Continuación escrita el 19-sep-2026.** El original de este documento se cortaba aquí, a mitad de línea, y no se ha podido recuperar. Lo que sigue **no es la receta original**: es lo que se comprobó al montar el stack en el equipo real, para cerrar el documento sin inventar. Donde este documento y el `11-mejoras-y-decisiones.md` discrepen, manda el 11.

## 12b. Checklist verificado (lo que hay que comprobar de verdad)

Todo esto tiene un script en `llm-stack/scripts/` (ver su `README.md`).

```
Antes de arrancar
□ check-cuda.sh termina en "CUDA OK"  (si no, la GPU bajo WSL2 está rota: wsl --shutdown)
□ Start-WslKeepAlive.ps1 lanzado      (sin una sesión abierta WSL2 apaga la distro y los servidores mueren solos)
□ vllm-image.lock y la imagen derivada con b12x (build-vllm-image.sh)

Arrancar
□ serve-profile.sh A | B | complex-solo  (o Start-Stack.ps1 desde Windows)
□ Los servidores solo escuchan en 127.0.0.1 (nada expuesto)

Comprobar DESPUÉS de arrancar
□ chat-check.py: ningún modelo genera BASURA          (bench.py no lo ve: un modelo corrupto rinde igual)
□ tools-check.py en Router y Complejo                 (sin los flags de tool calling, HTTP 400)
□ bench.py con 1, 4 y 8 clientes
□ nvidia-smi DESPUÉS de dar carga, no en reposo       (en reposo infravalora: doc 11, 7.9)
```

## 13. Advertencias críticas (verificadas en el equipo)

1. **No fuerces `--moe-backend b12x` en el Complejo.** Rompe los grafos CUDA (`illegal memory access`); con `--enforce-eager` va a 7 tok/s. Usa `--moe-backend flashinfer_cutlass` (~100 tok/s). El kernel lineal sí es `b12x`. (7.11)
2. **`VLLM_WSL2_ENABLE_PIN_MEMORY=1` es obligatorio bajo WSL2**; sin él, `UVA is not available` al arrancar. (7.4)
3. **Con dos instancias en la GPU no uses `--gpu-memory-utilization`**: bajo WSL2 cada instancia ve la GPU casi libre y vLLM nunca detecta el desbordamiento. Fija el KV en bytes con `--kv-cache-memory` (y una fracción baja para superar el chequeo de arranque). (7.9, 7.12)
4. **`--max-num-batched-tokens` acota el pico de activaciones**: sin acotar se comía ~1.3 GiB en el Router; con 256 el Complejo pierde un 25 % de rendimiento, con 512 no. (7.5, 7.14)
5. **El KV de Gemma tiene un suelo de ~1.6 GiB**: necesita ≥ 1.75 GiB para cualquier contexto de 8k o más. (7.9)
6. **Sleep Mode: el nivel 1 funciona pero llena la RAM de WSL2 (15.8 de 16 GB) y no caben dos modelos dormidos; el nivel 2 corrompe el modelo NVFP4 en silencio** (rinde igual y genera basura). No se usa: los perfiles se cambian parando y arrancando. (7.17)
7. **`--kv-offloading-size` falla bajo WSL2** (`illegal memory access` en la primera petición) y puede dejar CUDA roto hasta un `wsl --shutdown`. (7.15)
8. **El offload de un modelo denso a RAM es inviable** (Router a 3 tok/s con 1.5 GiB fuera). (7.13)
9. **Para que un agente con herramientas funcione hacen falta `--enable-auto-tool-choice` y un parser** (`qwen3_coder` en el Router y el Complejo); sin ellos, HTTP 400. El parser de Gemma (`gemma4`) sigue sin añadir ni probar. (7.21)
10. **Los puertos de vLLM no se publican**: con `VLLM_SERVER_DEV_MODE=1` (que Sleep Mode exige) se abren endpoints de administración. Lo único que se ofrece es la pasarela con clave (`llm-stack/gateway/`). (7.19)

## 14. Referencias

| Recurso | Dónde |
|:---|:---|
| Arranque de un modelo / de un perfil | `llm-stack/scripts/serve-model.sh`, `llm-stack/scripts/serve-profile.sh` |
| Arranque completo desde Windows | `llm-stack/scripts/Start-Stack.ps1`, `Stop-Stack.ps1` |
| Diagnóstico | `llm-stack/scripts/log-summary.sh`, `check-cuda.sh`, `grep-vllm-source.sh`, `vllm-help.sh` |
| Todo lo medido y decidido | `11-mejoras-y-decisiones.md` |
