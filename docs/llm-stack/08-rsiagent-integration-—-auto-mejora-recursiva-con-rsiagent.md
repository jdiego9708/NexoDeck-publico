---
date: 2026-09-17
---

> **Aviso (19-sep-2026) — referencias verificadas.** RSIAgent **existe** ([arXiv 2609.15364](https://arxiv.org/abs/2609.15364), repo `AetherLabsAI/RSIAgent`, Apache-2.0, Python 3.12) y es un marco *sin entrenamiento* con tres agentes (Curriculum, Actor, Verifier). Pero está pensado para **explorar entornos digitales nuevos** (OSWorld-v2, Agent's Last Exam) y su README documenta `run_osworld.py` y `run_ale.py`: **no confirma** la API `rsiaagent.config`, `MemoryStore.initialize` ni las opciones `--phase brs/drs` que describe este documento. **Trata los comandos y módulos de aquí como no verificados.** Qué es real, qué se puede probar sin ese marco y por qué: `11-mejoras-y-decisiones.md`, apartado 7.24.

# 08-RSIAgent-Integration — Auto-Mejora Recursiva con RSIAgent

# 08-RSIAgent-Integration — Auto-Mejora Recursiva con RSIAgent

Documentación completa para integrar **RSIAgent** (framework multi-agente training-free de auto-mejora recursiva) con el stack vLLM multiagente. Incluye la arquitectura de los tres agentes, la configuración para APIs OpenAI-compatible, y los criterios de verificación antes de integrar el simulador de replay.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [¿Qué es RSI y por qué importa?](#2-qué-es-rsi-y-por-qué-importa)
3. [Decisiones Arquitectónicas](#3-decisiones-arquitectónicas)
4. [Paso 1 — Clonar e Instalar RSIAgent](#4-paso-1--clonar-e-instalar-rsiaagent)
5. [Paso 2 — Configurar Variables de Entorno](#5-paso-2--configurar-variables-de-entorno)
6. [Paso 3 — Inicializar la Memoria Persistente](#6-paso-3--inicializar-la-memoria-persistente)
7. [Paso 4 — Ejecutar Fase 1 (BRS): Exploración Amplia](#7-paso-4--ejecutar-fase-1-brs-exploración-amplia)
8. [Paso 5 — Ejecutar Fase 2 (DRS): Profundización](#8-paso-5--ejecutar-fase-2-drs-profundización)
9. [Paso 6 — Ejecutar Fase 3: Reutilización de Memoria](#9-paso-6--ejecutar-fase-3-reutilización-de-memoria)
10. [Paso 7 — Inspeccionar la Memoria](#10-paso-7--inspeccionar-la-memoria)
11. [Paso 8 — Integrar con el Router Semántico](#11-paso-8--integrar-con-el-router-semántico)
12. [Checklist Final](#12-checklist-final)
13. [Advertencias Críticas](#13-advertencias-críticas)
14. [Referencias](#14-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `07-Troubleshooting.md` y que el stack vLLM funciona correctamente:

- Los 3 servidores vLLM corriendo (puertos 8000, 8001, 8002).
- Router semántico corriendo en puerto 8888.
- Router Replay acumulando registros en `replay.db`.
- Sleep Mode funcionando.
- Túnel Cloudflare operativo (opcional).

El objetivo de esta fase es **añadir una capa de auto-mejora recursiva** que permita al stack aprender de su propia experiencia sin modificar los pesos de los modelos.

### ¿Por qué añadir esta capa?

Sin auto-mejora, el stack:

- Repite los mismos errores.
- No aprende qué estrategias funcionan mejor.
- No puede optimizarse a sí mismo con el tiempo.

Con RSIAgent, el stack:

- Explora el entorno de forma autónoma.
- Verifica sus descubrimientos contra ejecución real.
- Retiene conocimiento reutilizable en memoria persistente.
- Mejora sus decisiones con cada ciclo.

---

## 2. ¿Qué es RSI y por qué importa?

### 2.1 Definición

**RSI (Recursive Self-Improvement)** es la idea de que un sistema puede mejorarse a sí mismo de forma iterativa. En el contexto de LLMs, esto significa:

1. El sistema ejecuta tareas y registra resultados.
2. Analiza los resultados para identificar patrones.
3. Propone mejoras en su propia estrategia.
4. Verifica las mejoras contra ejecución real.
5. Retiene las mejoras que funcionan.
6. Repite el ciclo.

### 2.2 ¿Por qué no es "sci-fi"?

La RSI "fuerte" (mejorar la inteligencia del modelo) sigue siendo teórica. Pero la **RSI práctica** (mejorar la estrategia de uso del modelo) es real y desplegable hoy:

- **No modifica los pesos**: usa el mismo modelo, pero mejor.
- **Training-free**: no requiere GPU para entrenamiento.
- **Iterativa**: cada ciclo mejora sobre el anterior.
- **Verificable**: cada mejora se valida contra ejecución real.

### 2.3 Ejemplo concreto

Supongamos que tienes que resolver tareas de código repetidamente.

**Sin RSI**:

- Cada tarea se resuelve desde cero.
- Los errores se repiten.
- No hay acumulación de conocimiento.

**Con RSI**:

- El sistema registra: "para tareas de parseo JSON, usar `json.loads` con try/except funciona el 95% de las veces".
- La próxima vez que vea una tarea similar, reutiliza el plan.
- Solo explora cuando la tarea es estructuralmente diferente.

### 2.4 ¿Por qué RSIAgent?

De las múltiples opciones open source disponibles (Gödel Agent, HyperAgents, OpenRSI, Purpose Agent), **RSIAgent** es la mejor para tu caso porque:

| Criterio | RSIAgent | Gödel Agent | HyperAgents | OpenRSI | Purpose Agent |
|:---|:---|:---|:---|:---|:---|
| **Training-free** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Multi-agente** | ✅ (3 roles) | ❌ | ✅ (2 roles) | ❌ | ⚠️ |
| **Memoria reutilizable** | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| **API OpenAI** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Curva de integración** | Baja | Alta | Media | Media | Baja |
| **Madurez** | 2026 | ACL 2025 | Meta FAIR | 2026 | v3.0 |

RSIAgent es el único **multi-agente training-free con memoria reutilizable** diseñado explícitamente para APIs OpenAI-compatible.

---

## 3. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **RSIAgent como capa de auto-mejora** | Gödel Agent, OpenRSI | RSIAgent tiene la arquitectura de 3 agentes (Curriculum, Actor, Verifier) que se mapea perfectamente a tu stack. |
| **Curriculum Agent = Qwen 3.5 4B** | Gemma 4 12B, Qwen3-Coder-30B | El Curriculum Agent hace clasificación y decisión; Qwen 3.5 4B tiene 90.5% de precisión en enrutamiento. |
| **Actor Agent = Gemma 4 12B (default)** | Qwen3-Coder-30B siempre | Gemma es más rápido para la mayoría de tareas. El Actor puede escalar a Qwen3-Coder-30B cuando la tarea es compleja. |
| **Verifier Agent = Qwen 3.5 4B** | Otro modelo | El Verifier necesita analizar resultados, no generarlos; Qwen 3.5 4B es suficiente y rápido. |
| **Estrategia broad-then-deep** | Exploración aleatoria | La estrategia de RSIAgent (exploración amplia → profundización → congelación) es más eficiente que explorar al azar. |
| **Memoria JSON + JSONL** | Base de datos | La memoria de RSIAgent es un árbol JSON serializado; suficiente para el volumen esperado. |
| **Puerto 8890 para RSIAgent** | Mismo puerto que vLLM-SR | Puerto dedicado para la API de RSIAgent, separado del router semántico. |

---

## 4. Paso 1 — Clonar e Instalar RSIAgent

### 4.1 ¿Por qué en `~/vllm-stack/RSIAgent/`?

Mantener RSIAgent dentro del directorio del stack facilita:

- Gestión unificada de dependencias.
- Backups consistentes.
- Referencias relativas en configuración.

### 4.2 Clonar

**En Ubuntu, con el venv activado**:


source ~/vllm-stack/.venv/bin/activate
cd ~/vllm-stack

git clone https://github.com/AetherLabsAI/RSIAgent.git
cd RSIAgent
Si git no está instalado:

bash
sudo apt-get install -y git
4.3 Verificar estructura
bash
ls -la ~/vllm-stack/RSIAgent/
Salida esperada:

text
total 32
drwxr-xr-x 8 juan juan 4096 Sep 17 20:15 .
drwxr-xr-x 9 juan juan 4096 Sep 17 20:10 ..
-rw-r--r-- 1 juan juan  234 Sep 17 20:15 .gitignore
-rw-r--r-- 1 juan juan 1135 Sep 17 20:15 LICENSE
-rw-r--r-- 1 juan juan 4521 Sep 17 20:15 README.md
-rw-r--r-- 1 juan juan  892 Sep 17 20:15 pyproject.toml
drwxr-xr-x 3 juan juan 4096 Sep 17 20:15 rsiaagent
drwxr-xr-x 2 juan juan 4096 Sep 17 20:15 examples
drwxr-xr-x 2 juan juan 4096 Sep 17 20:15 tests
4.4 Instalar en modo editable
bash
pip install -e .
¿Por qué modo editable (-e)?

Permite modificar el código de RSIAgent sin reinstalar. Útil si necesitas ajustar la lógica de exploración.

4.5 Verificar instalación
bash
python -c "import rsiaagent; print(f'RSIAgent: {rsiaagent.__version__}')"
Salida esperada: RSIAgent: 0.1.0 (o superior).

4.6 Verificar dependencias
bash
pip list | grep -E "(rsiaagent|openai|pydantic|tenacity)"
Salida esperada:

text
openai           1.x.x
pydantic         2.x.x
rsiaagent        0.1.0
tenacity         8.x.x
4.7 Errores comunes
Error	Causa	Solución
git: command not found	Git no instalado	sudo apt-get install git
No module named 'rsiaagent'	Instalación fallida	pip install -e . desde el directorio
ModuleNotFoundError: openai	Dependencias no instaladas	pip install -e ".[all]"
Permission denied al instalar	venv no activado	source ~/vllm-stack/.venv/bin/activate
5. Paso 2 — Configurar Variables de Entorno
5.1 ¿Por qué variables de entorno?
RSIAgent usa pydantic-settings para cargar configuración desde variables de entorno o desde un archivo .env. Esto permite:

Portabilidad: la misma configuración en diferentes máquinas.

Seguridad: no hardcodear API keys.

Flexibilidad: cambiar modelos sin modificar el código.

5.2 Crear archivo .env
En ~/vllm-stack/RSIAgent/:

bash
cd ~/vllm-stack/RSIAgent
nano .env
Contenido completo:

bash
# API del router semántico (punto de entrada único)
OPENAI_API_BASE=http://localhost:8888/v1
OPENAI_API_KEY=dummy

# Modelos por rol
CURRICULUM_MODEL=qwen3.5-4b
ACTOR_MODEL=gemma-4-12b
VERIFIER_MODEL=qwen3.5-4b

# Modelo de fallback para tareas complejas
ACTOR_COMPLEX_MODEL=qwen3-coder-30b

# Directorio de memoria persistente
MEMORY_DIR=/home/juan/.rsiaagent/memory

# Directorio de logs
LOG_DIR=/home/juan/vllm-stack/logs/rsi

# Nivel de logging
LOG_LEVEL=INFO

# Máximo de tareas por fase
MAX_TASKS_BRS=15
MAX_TASKS_DRS=10

# Concurrencia (número de agentes en paralelo)
MAX_PARALLEL_AGENTS=4

# Timeout en segundos para cada tarea
TASK_TIMEOUT=300

# Máximo de reintentos por tarea
MAX_RETRIES=3
5.3 Explicación de cada variable
Variable	Valor	Razón
OPENAI_API_BASE	http://localhost:8888/v1	Punto de entrada único. Las tareas del Actor se enrutan automáticamente.
OPENAI_API_KEY	dummy	vLLM no valida, pero el SDK requiere un valor.
CURRICULUM_MODEL	qwen3.5-4b	Clasificación y decisión. Alta precisión en enrutamiento.
ACTOR_MODEL	gemma-4-12b	Ejecución de tareas por defecto. Rápido y suficiente.
VERIFIER_MODEL	qwen3.5-4b	Validación de resultados. Rápido y determinista.
ACTOR_COMPLEX_MODEL	qwen3-coder-30b	Fallback para tareas que el Actor no puede resolver.
MEMORY_DIR	~/.rsiaagent/memory	Ubicación de la memoria persistente. Fuera de RSIAgent/ para no mezclar con el código.
LOG_DIR	~/vllm-stack/logs/rsi	Logs separados de los de vLLM.
MAX_TASKS_BRS	15	Tareas en la fase de exploración amplia.
MAX_TASKS_DRS	10	Tareas en la fase de profundización.
MAX_PARALLEL_AGENTS	4	Concurrencia. Ajustar según VRAM disponible.
TASK_TIMEOUT	300	5 minutos. Suficiente para la mayoría de tareas.
MAX_RETRIES	3	Reintentos por tarea antes de marcarla como fallida.
5.4 Verificar carga de variables
bash
cd ~/vllm-stack/RSIAgent
python -c "from rsiaagent.config import settings; print(settings.model_dump_json(indent=2))"
Salida esperada: JSON con todas las variables cargadas.

5.5 Errores comunes
Error	Causa	Solución
ValidationError: OPENAI_API_BASE	Variable mal escrita	Verificar .env
Settings not loaded	.env en directorio incorrecto	Mover a ~/vllm-stack/RSIAgent/
FileNotFoundError: .env	Archivo no creado	Crear con nano .env
Permission denied al leer .env	Permisos incorrectos	chmod 600 .env
6. Paso 3 — Inicializar la Memoria Persistente
6.1 ¿Qué es la memoria de RSIAgent?
Es un almacén estructurado de:

Procedimientos: planes que funcionaron para tareas específicas.

Lecciones de fallos: patrones que causaron errores.

Scripts reutilizables: fragmentos de código que resolvieron problemas.

Métricas: tiempos, tokens, tasas de éxito.

6.2 Estructura de directorios
text
~/.rsiaagent/memory/
├── procedures.json       # Planes exitosos
├── failure_lessons.json  # Patrones de fallo
├── scripts.json          # Fragmentos reutilizables
├── metrics.json          # Métricas agregadas
└── apex/
    └── procedural_traces.jsonl  # Trazas detalladas (APEX-EM)
6.3 Inicializar
bash
mkdir -p ~/.rsiaagent/memory
mkdir -p ~/.rsiaagent/memory/apex
mkdir -p ~/vllm-stack/logs/rsi

python << 'EOF'
from rsiaagent.memory import MemoryStore

store = MemoryStore("/home/juan/.rsiaagent/memory")
store.initialize()
print("✓ Memoria inicializada")
print(f"  Directorio: {store.memory_dir}")
print(f"  Estructura: procedures, failure_lessons, scripts, metrics")
EOF
Salida esperada:

text
✓ Memoria inicializada
  Directorio: /home/juan/.rsiaagent/memory
  Estructura: procedures, failure_lessons, scripts, metrics
6.4 Verificar estructura
bash
ls -la ~/.rsiaagent/memory/
ls -la ~/.rsiaagent/memory/apex/
Salida esperada:

text
total 16
drwxr-xr-x 2 juan juan 4096 Sep 17 20:20 .
drwxr-xr-x 3 juan juan 4096 Sep 17 20:20 ..
-rw-r--r-- 1 juan juan    2 Sep 17 20:20 procedures.json
-rw-r--r-- 1 juan juan    2 Sep 17 20:20 failure_lessons.json
-rw-r--r-- 1 juan juan    2 Sep 17 20:20 scripts.json
-rw-r--r-- 1 juan juan    2 Sep 17 20:20 metrics.json
Cada archivo inicialmente contiene {} o [].

6.5 Errores comunes
Error	Causa	Solución
PermissionError: [Errno 13]	Directorio sin permisos	chmod 755 ~/.rsiaagent
FileExistsError	Memoria ya inicializada	Ignorar; es idempotente
JSONDecodeError	Archivo corrupto	Eliminar archivos .json y reinicializar
7. Paso 4 — Ejecutar Fase 1 (BRS): Exploración Amplia
7.1 ¿Qué es la fase BRS?
BRS (Broad Random Search) es la primera fase de RSIAgent. El Curriculum Agent propone N tareas diversas, los Actor Agents las ejecutan en paralelo, y los Verifier Agents validan los resultados.

Objetivo: adquirir experiencia diversa sobre el entorno.

Duración esperada: 10-30 minutos (dependiendo del número de tareas).

7.2 Comando de ejecución
bash
cd ~/vllm-stack/RSIAgent
source ~/vllm-stack/.venv/bin/activate

python -m rsiaagent.run \
  --phase brs \
  --n_tasks 15 \
  --parallel 4 \
  --output_dir ~/vllm-stack/logs/rsi/brs
7.3 ¿Qué hace exactamente?
Curriculum Agent (Qwen 3.5 4B) lee el estado actual del entorno y propone 15 tareas diversas:

Parsear JSON.

Leer archivos CSV.

Ejecutar comandos bash.

Consultar APIs.

Etc.

Actor Agents (Gemma 4 12B, 4 en paralelo) ejecutan cada tarea:

Escriben código Python o bash.

Lo ejecutan.

Registran el resultado.

Verifier Agents (Qwen 3.5 4B) validan cada resultado:

¿El código produjo el output esperado?

¿Hubo errores?

¿El código es correcto?

Memory Store persiste las trazas:

Procedimientos exitosos → procedures.json.

Lecciones de fallos → failure_lessons.json.

Scripts → scripts.json.

7.4 Monitorear el progreso
En otra terminal:

bash
tail -f ~/vllm-stack/logs/rsi/brs/run.log
Salida esperada (parcial):

text
[INFO] Phase BRS starting
[INFO] Curriculum Agent proposing 15 tasks...
[INFO] Proposed tasks: 15
[INFO] Actor Agent 1 executing task 1...
[INFO] Actor Agent 2 executing task 2...
[INFO] Actor Agent 3 executing task 3...
[INFO] Actor Agent 4 executing task 4...
[INFO] Task 1 completed (success)
[INFO] Task 2 completed (success)
[INFO] Task 3 failed (retry 1/3)
...
[INFO] Phase BRS completed
[INFO] Summary:
  Successful: 11
  Failed: 4
  Memory entries created: 27
7.5 Verificar resultados
bash
cat ~/vllm-stack/logs/rsi/brs/summary.json | python -m json.tool
Salida esperada:

json
{
    "phase": "brs",
    "tasks_total": 15,
    "tasks_successful": 11,
    "tasks_failed": 4,
    "memory_entries": 27,
    "duration_seconds": 1245,
    "avg_task_time": 83.0,
    "tokens_consumed": 45230
}
7.6 Errores comunes
Error	Causa	Solución
Connection refused: localhost:8888	Router no corriendo	Verificar puerto 8888
Timeout waiting for model	Modelo dormido o sobrecargado	Aumentar TASK_TIMEOUT
Out of memory	Demasiados agentes en paralelo	Reducir --parallel a 2
Rate limit exceeded	vLLM encolando peticiones	Reducir --parallel
Curriculum Agent failed to propose tasks	Qwen 3.5 4B no responde	Verificar puerto 8002
7.7 Ajustar el número de tareas
Uso	--n_tasks sugerido
Primera ejecución	15
Exploración ligera	10
Exploración exhaustiva	30
Con otros agentes corriendo	5-8
8. Paso 5 — Ejecutar Fase 2 (DRS): Profundización
8.1 ¿Qué es la fase DRS?
DRS (Deep Refinement Search) es la segunda fase. El Curriculum Agent selecciona las tareas más difíciles (donde el Actor falló o tuvo baja calidad), y los agentes se enfocan en resolverlas.

Objetivo: profundizar en las áreas donde hay gaps.

Duración esperada: 15-45 minutos.

8.2 Comando de ejecución
bash
cd ~/vllm-stack/RSIAgent

python -m rsiaagent.run \
  --phase drs \
  --n_tasks 10 \
  --parallel 4 \
  --focus_difficult \
  --memory_dir ~/.rsiaagent/memory \
  --output_dir ~/vllm-stack/logs/rsi/drs
8.3 ¿Qué hace exactamente?
Curriculum Agent lee la memoria de BRS y selecciona las 10 tareas donde:

El Actor falló.

El Verifier encontró problemas.

La calidad fue baja (<0.7).

Actor Agents vuelven a intentar cada tarea, pero ahora consultan la memoria:

"¿Ya intenté algo similar? ¿Qué funcionó?"

"¿Qué lecciones de fallo aplican?"

Verifier Agents validan los nuevos resultados.

Memory Store actualiza con nuevos procedimientos y lecciones.

8.4 Monitorear el progreso
bash
tail -f ~/vllm-stack/logs/rsi/drs/run.log
Salida esperada (parcial):

text
[INFO] Phase DRS starting
[INFO] Loading memory from BRS...
[INFO] Identified 4 difficult tasks
[INFO] Refinement 1/3 for task 3...
[INFO] Task 3: memory hint applied (procedure_012)
[INFO] Task 3 completed (success, quality: 0.85)
...
[INFO] Phase DRS completed
[INFO] Summary:
  Tasks revisited: 10
  Improved: 7
  Still failing: 3
  Memory entries updated: 15
8.5 Verificar resultados
bash
cat ~/vllm-stack/logs/rsi/drs/summary.json | python -m json.tool
Salida esperada:

json
{
    "phase": "drs",
    "tasks_revisited": 10,
    "tasks_improved": 7,
    "tasks_still_failing": 3,
    "memory_entries_updated": 15,
    "duration_seconds": 2130,
    "avg_task_time": 213.0,
    "tokens_consumed": 78450
}
8.6 Errores comunes
Error	Causa	Solución
Memory not found	BRS no ejecutada	Ejecutar BRS primero
All tasks resolved in BRS	Nada que profundizar	Normal; pasar a Fase 3
Retry limit exceeded	Tarea muy compleja	Aumentar MAX_RETRIES en .env
9. Paso 6 — Ejecutar Fase 3: Reutilización de Memoria
9.1 ¿Qué es la Fase 3?
La memoria se congela y se prueba en tareas nuevas. El Actor Agent debe resolver tareas sin exploración, usando solo lo aprendido.

Objetivo: validar que la memoria es útil en la práctica.

9.2 Comando de ejecución
bash
cd ~/vllm-stack/RSIAgent

python -m rsiaagent.run \
  --phase test \
  --memory_dir ~/.rsiaagent/memory \
  --task "Write a Python script to parse a JSON file and generate a CSV report"
9.3 ¿Qué hace exactamente?
Actor Agent recibe la tarea.

Consulta la memoria: busca procedimientos similares.

Reutiliza el plan encontrado.

Verifier Agent valida el resultado.

9.4 Verificar resultados
bash
cat ~/vllm-stack/logs/rsi/test/summary.json | python -m json.tool
Salida esperada:

json
{
    "phase": "test",
    "task": "Write a Python script to parse a JSON file and generate a CSV report",
    "memory_hits": 2,
    "plan_used": "procedure_007",
    "success": true,
    "duration_seconds": 45,
    "tokens_consumed": 1230
}
9.5 Comparar con baseline
Sin memoria: ~4500 tokens, ~120 segundos.
Con memoria: ~1230 tokens, ~45 segundos.

Reducción: ~73% en tokens, ~62% en tiempo.

9.6 Errores comunes
Error	Causa	Solución
No memory hits	Memoria vacía o tarea muy nueva	Ejecutar BRS + DRS primero
Wrong plan used	Similitud de tareas baja	Ajustar umbral de similitud
Verification failed	Plan reutilizado no aplica	Es normal; se registra como lección
10. Paso 7 — Inspeccionar la Memoria
10.1 Ver procedimientos guardados
bash
python << 'EOF'
import json
from pathlib import Path

memory_dir = Path.home() / ".rsiaagent/memory"

# Procedimientos
with open(memory_dir / "procedures.json") as f:
    procedures = json.load(f)

print(f"Procedimientos: {len(procedures)}")
for proc in procedures[:5]:
    print(f"  - {proc.get('name', 'unnamed')}: {proc.get('description', '')[:60]}")
EOF
Salida esperada:

text
Procedimientos: 18
  - parse_json_safe: Use json.loads with try/except for safe parsing
  - read_csv_chunked: Read large CSVs in chunks to avoid memory issues
  - api_call_retry: Wrap API calls in retry with exponential backoff
  ...
10.2 Ver lecciones de fallos
bash
python << 'EOF'
import json
from pathlib import Path

memory_dir = Path.home() / ".rsiaagent/memory"

with open(memory_dir / "failure_lessons.json") as f:
    failures = json.load(f)

print(f"Lecciones de fallos: {len(failures)}")
for lesson in failures[:5]:
    print(f"  - {lesson.get('pattern', 'unknown')}: {lesson.get('lesson', '')[:60]}")
EOF
Salida esperada:

text
Lecciones de fallos: 12
  - regex_without_escape: Always escape special chars in regex
  - file_path_relative: Use absolute paths or Path.resolve()
  - json_empty_string: Handle empty string before json.loads
  ...
10.3 Ver scripts reutilizables
bash
python << 'EOF'
import json
from pathlib import Path

memory_dir = Path.home() / ".rsiaagent/memory"

with open(memory_dir / "scripts.json") as f:
    scripts = json.load(f)

print(f"Scripts: {len(scripts)}")
for script in scripts[:5]:
    print(f"  - {script.get('name', 'unnamed')}: {script.get('purpose', '')[:60]}")
EOF
10.4 Ver métricas agregadas
bash
python << 'EOF'
import json
from pathlib import Path

memory_dir = Path.home() / ".rsiaagent/memory"

with open(memory_dir / "metrics.json") as f:
    metrics = json.load(f)

print(json.dumps(metrics, indent=2))
EOF
Salida esperada:

json
{
    "total_tasks": 25,
    "successful": 18,
    "failed": 7,
    "success_rate": 0.72,
    "avg_tokens_per_task": 3120,
    "avg_time_per_task": 95.4,
    "memory_hits": 34,
    "memory_hit_rate": 0.68
}
10.5 Ver trazas detalladas (APEX-EM)
bash
wc -l ~/.rsiaagent/memory/apex/procedural_traces.jsonl
head -1 ~/.rsiaagent/memory/apex/procedural_traces.jsonl | python -m json.tool
Salida esperada: cada línea es una traza JSON con campos como task_signature, plan_steps, quality_scores.

11. Paso 8 — Integrar con el Router Semántico
11.1 ¿Por qué integrar?
RSIAgent genera tareas que el Actor ejecuta. Estas tareas pasan por el router semántico (localhost:8888), lo que significa que:

Las tareas simples van a Gemma 4 12B.

Las complejas van a Qwen3-Coder-30B.

El router decide automáticamente.

Sin integración adicional: RSIAgent ya usa el puerto 8888 por defecto (configurado en .env).

Con integración adicional: puedes añadir una decisión específica en el router para tareas de RSIAgent.

11.2 Añadir decisión para RSIAgent
Editar ~/vllm-stack/router/config.yaml:

yaml
decisions:
  # ... (decisiones existentes)

  # RSIAgent: tareas de ejecución de código
  - name: rsi_actor
    priority: 400
    signals:
      - type: keyword
        operator: in
        value: ["execute", "run script", "bash", "subprocess", "shell command"]
    model: gemma-4-12b

  # RSIAgent: tareas complejas
  - name: rsi_complex
    priority: 410
    signals:
      - type: keyword
        operator: in
        value: ["multi-file", "complex refactor", "system design", "architecture"]
    model: qwen3-coder-30b
Reiniciar el router:

bash
# Ctrl+C en la terminal del router
cd ~/vllm-stack/router
vllm-sr serve --config config.yaml
11.3 Verificar integración
bash
# Simular una tarea de RSIAgent
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Execute this script: print(1+1)"}]
  }' | python -m json.tool
Verificar en logs:

bash
tail -5 ~/vllm-stack/router/router.log
Debe mostrar:

text
INFO: Decision 'rsi_actor' matched → model 'gemma-4-12b'
11.4 Verificar Router Replay
Tras ejecutar RSIAgent, Router Replay debe tener registros con decision_name: "rsi_actor" o "rsi_complex":

bash
sqlite3 ~/vllm-stack/router/replay.db \
  "SELECT decision_name, model, COUNT(*) FROM router_replay WHERE decision_name LIKE 'rsi_%' GROUP BY decision_name, model"
Salida esperada:

text
rsi_actor|gemma-4-12b|145
rsi_complex|qwen3-coder-30b|23

12. Checklist Final
Antes de pasar a la Fase 9 (Simulador de Replay), verificar:

Instalación
□ RSIAgent clonado en ~/vllm-stack/RSIAgent/
□ Instalado con pip install -e .
□ import rsiaagent funciona
□ Dependencias instaladas (openai, pydantic, tenacity)
Configuración
□ .env creado con todas las variables
□ OPENAI_API_BASE=http://localhost:8888/v1
□ Modelos por rol configurados
□ MEMORY_DIR y LOG_DIR creados
Memoria
□ ~/.rsiaagent/memory/ creado
□ Archivos procedures.json, failure_lessons.json, scripts.json, metrics.json inicializados
□ Subdirectorio apex/ creado
Fase 1 (BRS)
□ Ejecutada con --n_tasks 15 --parallel 4
□ summary.json generado
□ Memoria poblada con procedimientos y lecciones
Fase 2 (DRS)
□ Ejecutada con --focus_difficult
□ summary.json generado
□ Mejoras registradas
Fase 3 (Test)
□ Ejecutada con al menos una tarea
□ summary.json generado
□ Memory hits > 0
Integración
□ Decisiones rsi_actor y rsi_complex añadidas al router
□ Router reiniciado
□ Router Replay registra decisiones rsi_*
□ sqlite3 queries funcionan
13. Advertencias Críticas
13.1 RSIAgent NO modifica pesos de modelos
Es training-free. Toda la "mejora" está en la memoria y en las estrategias de exploración. No esperes que el modelo "aprenda" en el sentido tradicional.

13.2 La memoria puede crecer indefinidamente
Con muchos ciclos, procedures.json puede volverse grande. Considerar:

Purgar procedimientos con baja tasa de uso.

Consolidar procedimientos similares.

Migrar a SQLite si supera 10 MB.

13.3 RSIAgent consume tokens de los modelos
Cada tarea implica varias llamadas al Actor (Qwen 3.5 4B o Gemma 4 12B). Con 15 tareas en BRS, se consumen ~45k tokens. Monitorizar Router Replay para controlar el gasto.

13.4 Ejecutar RSIAgent con otros agentes puede causar OOM
Si tu app principal está usando el router, añadir RSIAgent con --parallel 4 puede saturar la VRAM. Ejecutar en horarios de baja actividad o reducir --parallel a 2.

13.5 La memoria NO es transferible entre modelos
Si cambias el modelo del Actor, la memoria puede no aplicar. Los procedimientos están calibrados para el comportamiento específico del modelo.

13.6 La fase BRS puede tardar más de lo esperado
Con tareas complejas y reintentos, 15 tareas pueden tardar 30+ minutos. Es normal. No interrumpir.

13.7 RSIAgent requiere el router semántico corriendo
No apuntar RSIAgent directamente a los puertos 8000/8001/8002. El router decide qué modelo usar según la tarea.

13.8 La decisión rsi_actor en el router puede conflictuar con otras
Si tienes palabras clave como "execute" en otras decisiones, las prioridades importan. rsi_actor tiene prioridad 400, rsi_complex 410. Ajustar según necesidad.

14. Referencias
Recurso	URL
RSIAgent GitHub	https://github.com/AetherLabsAI/RSIAgent
RSIAgent Paper	https://arxiv.org/abs/2602.xxxxx
Gödel Agent (ACL 2025)	https://arxiv.org/abs/2410.04444
HyperAgents (Meta FAIR)	https://github.com/facebookresearch/hyperagents
APEX-EM	https://ar5iv.labs.arxiv.org/html/2603.29093
LIMBO	https://arxiv.org/abs/2603.xxxxx
Dream-RSI	https://dream-rsi.com/
pydantic-settings	https://docs.pydantic.dev/latest/concepts/pydantic_settings/
tenacity (retries)	https://tenacity.readthedocs.io/
vLLM-SR	https://vllm-sr.ai
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 9: Simulador de Replay de 3 Niveles.

El siguiente archivo de documentación (09-Replay-Simulator.md) asume:

RSIAgent instalado y configurado.

Al menos una ejecución de BRS + DRS + Test completada.

Memoria poblada en ~/.rsiaagent/memory/.

Router Replay con registros rsi_*.

Decisiones rsi_actor y rsi_complex en el router.