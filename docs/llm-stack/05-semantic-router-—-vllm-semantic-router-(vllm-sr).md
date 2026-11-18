---
date: 2026-09-17
---
# 05-Semantic-Router — vLLM Semantic Router (vLLM-SR)

# 05-Semantic-Router — vLLM Semantic Router (vLLM-SR)

Documentación completa para configurar el enrutador semántico que decide qué modelo usar según la complejidad e intención de cada prompt. Incluye la lógica de enrutamiento, integración con Router Replay (Nivel 1 del simulador de replay), y criterios de verificación.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Decisiones Arquitectónicas](#2-decisiones-arquitectónicas)
3. [Paso 1 — Instalar vLLM-SR](#3-paso-1--instalar-vllm-sr)
4. [Paso 2 — Inicializar Configuración](#4-paso-2--inicializar-configuración)
5. [Paso 3 — Configurar Modelos](#5-paso-3--configurar-modelos)
6. [Paso 4 — Configurar Decisiones de Enrutamiento](#6-paso-4--configurar-decisiones-de-enrutamiento)
7. [Paso 5 — Habilitar Router Replay](#7-paso-5--habilitar-router-replay)
8. [Paso 6 — Lanzar el Router](#8-paso-6--lanzar-el-router)
9. [Paso 7 — Verificar Enrutamiento](#9-paso-7--verificar-enrutamiento)
10. [Paso 8 — Consultar Router Replay](#10-paso-8--consultar-router-replay)
11. [Paso 9 — Dashboard de Monitoreo](#11-paso-9--dashboard-de-monitoreo)
12. [Checklist Final](#12-checklist-final)
13. [Advertencias Críticas](#13-advertencias-críticas)
14. [Referencias](#14-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `04-vLLM-Serving.md`. Debes tener:

- Tres servidores vLLM corriendo y verificados:
  - Puerto 8000: Qwen3-Coder-30B NVFP4 (complejo)
  - Puerto 8001: Gemma 4 12B AWQ (rápido)
  - Puerto 8002: Qwen 3.5 4B NVFP4 (router/meta)
- Sleep Mode funcionando vía `/sleep` y `/wake_up`.
- Variables de entorno críticas exportadas.

El objetivo de esta fase es **configurar el router semántico** que decidirá automáticamente a qué modelo enviar cada petición, y habilitar **Router Replay** como base del simulador de replay de 3 niveles.

### Arquitectura del enrutamiento
Tu App / Agentes
│
▼
┌───────────────────────────┐
│ vLLM-SR (puerto 8888) │
│ │
│ Analiza el prompt y │
│ decide a qué modelo │
│ enviarlo │
└─────────────┬─────────────┘
│
┌───────────────────┼───────────────────┐
▼ ▼ ▼
SIMPLE NORMAL COMPLEX
│ │ │
▼ ▼ ▼
Gemma 4 12B Gemma 4 12B Qwen3-Coder-30B
(8001) (8001) (8000)


---

## 2. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **vLLM-SR como enrutador** | Enrutamiento manual desde la app | vLLM-SR implementa enrutamiento semántico con múltiples señales (longitud, keywords, intención) y expone una API OpenAI-compatible transparente. |
| **Puerto 8888** | Otro puerto | Es el puerto por defecto de vLLM-SR y coincide con el que se expondrá vía Cloudflare Tunnel. |
| **4 decisiones (meta, simple, normal, complex)** | Solo 3 (simple, normal, complex) | Se añade `meta` para tareas de clasificación y tool-calling que van al modelo Qwen 3.5 4B. |
| **Router Replay habilitado** | Sin replay | Router Replay es el Nivel 1 del simulador de replay de 3 niveles. Sin él, no hay base para Dream-RSI. |
| **SQLite como backend de replay** | PostgreSQL, MySQL | SQLite no requiere servidor adicional, es suficiente para volúmenes locales, y se puede migrar a PostgreSQL si crece. |
| **Prioridades explícitas** | Orden por defecto | El orden de evaluación puede causar conflictos. Prioridades explícitas garantizan determinismo. |
| **`model: auto` en la API** | Modelos nombrados explícitamente | Permite que la app no sepa qué modelo usar; el router decide. |

---

## 3. Paso 1 — Instalar vLLM-SR

### 3.1 ¿Qué es vLLM-SR?

**vLLM Semantic Router** es una extensión de vLLM que añade enrutamiento inteligente entre múltiples modelos. Expone una API OpenAI-compatible en un puerto único y decide a qué modelo backend enviar cada petición según reglas configurables.

### 3.2 ¿Por qué usarlo?

Sin enrutador, tu aplicación tendría que:

1. Analizar el prompt.
2. Decidir qué modelo usar.
3. Llamar al endpoint correcto.

Con vLLM-SR, tu aplicación solo hace:

1. Llamar a `http://localhost:8888/v1/chat/completions` con `model: auto`.

El router hace el resto.

### 3.3 Instalación

**Con el venv activado**:

source ~/vllm-stack/.venv/bin/activate
uv pip install vllm-sr

3.4 Verificar
bash
vllm-sr --version
Salida esperada: vllm-sr 0.x.x (o superior).

4. Paso 2 — Inicializar Configuración
4.1 Crear directorio del router
bash
mkdir -p ~/vllm-stack/router
cd ~/vllm-stack/router
4.2 Inicializar con valores por defecto
bash
vllm-sr init
¿Qué hace?

Crea un archivo config.yaml con una configuración mínima de ejemplo. Lo editaremos completamente en los siguientes pasos.

4.3 Verificar estructura
bash
ls -la ~/vllm-stack/router/
Salida esperada:

text
total 12
drwxr-xr-x 2 juan juan 4096 Sep 17 19:45 .
drwxr-xr-x 8 juan juan 4096 Sep 17 19:45 ..
-rw-r--r-- 1 juan juan 1234 Sep 17 19:45 config.yaml
5. Paso 3 — Configurar Modelos
5.1 Editar config.yaml
Abrir el archivo:

bash
nano ~/vllm-stack/router/config.yaml
Contenido completo de la sección models:

yaml
models:
  - name: qwen3-coder-30b
    endpoint: http://localhost:8000/v1
    model: qwen3-coder-30b
    api_key: "dummy"
    description: "Modelo complejo (NVFP4) para razonamiento y arquitectura"

  - name: gemma-4-12b
    endpoint: http://localhost:8001/v1
    model: gemma-4-12b
    api_key: "dummy"
    description: "Modelo rápido (AWQ) para tareas simples y edición"

  - name: qwen3.5-4b
    endpoint: http://localhost:8002/v1
    model: qwen3.5-4b
    api_key: "dummy"
    description: "Meta-agente (NVFP4) para clasificación y tool-calling"
5.2 Explicación de cada campo
Campo	Valor	Razón
name	Identificador lógico	Nombre que aparece en logs y decisiones.
endpoint	URL completa al servidor vLLM	Debe incluir /v1 al final.
model	Nombre exacto del --served-model-name	Debe coincidir con el flag de vllm serve.
api_key	"dummy"	vLLM local no valida API keys, pero el cliente requiere uno.
description	Texto libre	Útil para auditoría y logs.
5.3 ¿Por qué api_key: "dummy"?
vLLM no valida API keys por defecto. Sin embargo, el SDK de OpenAI requiere que se pase un valor no vacío. "dummy" es una convención común.

Si más adelante quieres añadir autenticación (por ejemplo, para el túnel Cloudflare), cambia "dummy" por una clave real y configúrala en vLLM con --api-key.

6. Paso 4 — Configurar Decisiones de Enrutamiento
6.1 ¿Qué es una decisión?
Una decisión es una regla que evalúa señales del prompt (longitud, keywords, intención) y determina a qué modelo enviarlo.

Cada decisión tiene:

name: identificador único.

priority: número mayor = se evalúa primero.

signals: lista de condiciones.

model: modelo a usar si todas las señales coinciden.

6.2 Contenido de la sección decisions
yaml
decisions:
  # META: clasificación de intención y tool-calling
  - name: meta
    priority: 300
    signals:
      - type: keyword
        operator: in
        value: ["classify", "route", "which model", "tool", "function call"]
    model: qwen3.5-4b

  # SIMPLE: prompts cortos y directos
  - name: simple
    priority: 100
    signals:
      - type: prompt_length
        operator: lt
        value: 150
    model: gemma-4-12b

  # NORMAL: prompts medianos sin palabras clave complejas
  - name: normal
    priority: 50
    signals:
      - type: prompt_length
        operator: between
        value: [150, 800]
    model: gemma-4-12b

  # COMPLEX: prompts largos
  - name: complex
    priority: 200
    signals:
      - type: prompt_length
        operator: gt
        value: 800
    model: qwen3-coder-30b

  # COMPLEX_KEYWORDS: palabras clave de arquitectura/optimización
  - name: complex_keywords
    priority: 210
    signals:
      - type: keyword
        operator: in
        value:
          - "refactor"
          - "architecture"
          - "design pattern"
          - "debug complex"
          - "optimize"
          - "multi-file"
          - "system design"
    model: qwen3-coder-30b
6.3 Explicación de las prioridades
Prioridad	Decisión	Razón
300	meta	Se evalúa primero. Si el prompt contiene palabras de clasificación o tool-calling, va al router sin importar la longitud.
210	complex_keywords	Se evalúa antes que complex para que las palabras clave de arquitectura desvíen al modelo complejo incluso si el prompt es mediano.
200	complex	Prompts largos.
100	simple	Prompts muy cortos.
50	normal	Prompts medianos. Es el caso por defecto si nada más coincide.
6.4 Explicación de los signals
prompt_length:

Operador	Descripción
lt	Menor que (<)
gt	Mayor que (>)
between	Entre dos valores [min, max]
eq	Igual a
le	Menor o igual (<=)
ge	Mayor o igual (>=)
keyword:

Operador	Descripción
in	El prompt contiene al menos una de las palabras
not_in	El prompt no contiene ninguna
6.5 ¿Por qué estas palabras clave?
Las palabras clave de complex_keywords fueron seleccionadas para capturar tareas de arquitectura, refactoring profundo, y system design, que son las que más se benefician del modelo complejo (Qwen3-Coder-30B).

Ejemplos que activan complex_keywords:

"Refactor this module to use dependency injection" → refactor.

"Design the architecture for a microservices system" → architecture, system design.

"Optimize this SQL query" → optimize.

Ejemplos que NO activan complex_keywords (van a simple o normal):

"Fix this typo" → demasiado corto y sin keywords.

"Explain what a list comprehension is" → longitud mediana sin keywords.

6.6 Ajustar umbrales según tu uso
Los valores 150 y 800 son heurísticas iniciales. Puedes ajustarlos según:

Uso más técnico: bajar simple a 100 y subir complex a 600.

Uso generalista: subir simple a 200 y complex a 1200.

Muchos agentes: mantener valores por defecto para distribuir carga.

Tras un par de días de uso, consulta Router Replay (sección 10) para ver la distribución real y ajustar.

6.7 Decisión por defecto
yaml
default_decision: normal
¿Por qué normal? Es el caso más común y va al modelo rápido. Si ninguna decisión coincide, es preferible un modelo rápido que uno lento.

7. Paso 5 — Habilitar Router Replay
7.1 ¿Qué es Router Replay?
Es un almacén de eventos duradero de vLLM-SR que registra cada decisión de enrutamiento. Es el Nivel 1 del simulador de replay de 3 niveles.

Registra:

Decisión aplicada (meta, simple, normal, complex, complex_keywords).

Modelo seleccionado.

Longitud del prompt.

Latencia de la inferencia.

Tokens generados.

Timestamp.

7.2 ¿Por qué es crítico?
Sin Router Replay:

No hay visibilidad de cómo se distribuyen las peticiones.

No se pueden hacer análisis offline para mejorar reglas.

No hay base para el simulador de replay de Nivel 2 y 3.

7.3 Configuración
Añadir al config.yaml:

yaml
router_replay:
  enabled: true
  store_backend: sqlite
  db_path: ~/vllm-stack/router/replay.db
  max_records: 10000
  ttl_seconds: 604800
7.4 Explicación de cada campo
Campo	Valor	Razón
enabled	true	Habilita el registro.
store_backend	sqlite	Backend local sin servidor. Migrar a postgres si crece.
db_path	Ruta al archivo .db	Ubicación del archivo SQLite.
max_records	10000	Límite de registros. Al superarlo, se eliminan los más antiguos.
ttl_seconds	604800	7 días. Registros más antiguos se eliminan automáticamente.
7.5 Estructura de la tabla
SQLite crea automáticamente una tabla router_replay con columnas:

Columna	Tipo	Descripción
id	INTEGER	Primary key autoincremental.
timestamp	DATETIME	Momento de la decisión.
decision_name	TEXT	Nombre de la decisión aplicada.
model	TEXT	Modelo seleccionado.
prompt_length	INTEGER	Longitud del prompt en caracteres.
latency_ms	REAL	Latencia de la inferencia en milisegundos.
tokens_generated	INTEGER	Tokens generados.
success	BOOLEAN	Si la petición se completó sin error.
session_id	TEXT	ID de sesión (si aplica).
8. Paso 6 — Lanzar el Router
8.1 Configuración completa del config.yaml
Archivo completo:

yaml
# vLLM Semantic Router — Configuración para stack multiagente
# Hardware: RTX 5060 Ti 16 GB (SM120)

listeners:
  - name: api
    address: 0.0.0.0
    port: 8888
  - name: metrics
    address: 0.0.0.0
    port: 9190

models:
  - name: qwen3-coder-30b
    endpoint: http://localhost:8000/v1
    model: qwen3-coder-30b
    api_key: "dummy"
    description: "Modelo complejo (NVFP4) para razonamiento y arquitectura"

  - name: gemma-4-12b
    endpoint: http://localhost:8001/v1
    model: gemma-4-12b
    api_key: "dummy"
    description: "Modelo rápido (AWQ) para tareas simples y edición"

  - name: qwen3.5-4b
    endpoint: http://localhost:8002/v1
    model: qwen3.5-4b
    api_key: "dummy"
    description: "Meta-agente (NVFP4) para clasificación y tool-calling"

decisions:
  - name: meta
    priority: 300
    signals:
      - type: keyword
        operator: in
        value: ["classify", "route", "which model", "tool", "function call"]
    model: qwen3.5-4b

  - name: simple
    priority: 100
    signals:
      - type: prompt_length
        operator: lt
        value: 150
    model: gemma-4-12b

  - name: normal
    priority: 50
    signals:
      - type: prompt_length
        operator: between
        value: [150, 800]
    model: gemma-4-12b

  - name: complex
    priority: 200
    signals:
      - type: prompt_length
        operator: gt
        value: 800
    model: qwen3-coder-30b

  - name: complex_keywords
    priority: 210
    signals:
      - type: keyword
        operator: in
        value:
          - "refactor"
          - "architecture"
          - "design pattern"
          - "debug complex"
          - "optimize"
          - "multi-file"
          - "system design"
    model: qwen3-coder-30b

default_decision: normal

router_replay:
  enabled: true
  store_backend: sqlite
  db_path: ~/vllm-stack/router/replay.db
  max_records: 10000
  ttl_seconds: 604800

logging:
  level: info
  format: json
8.2 Lanzar
En una terminal Ubuntu nueva (cuarta):

bash
source ~/vllm-stack/.venv/bin/activate
cd ~/vllm-stack/router

vllm-sr serve --config config.yaml
Tiempo de arranque: ~5 segundos.

Salida esperada:

text
INFO: Starting vLLM-SR server
INFO: Listeners: api=0.0.0.0:8888, metrics=0.0.0.0:9190
INFO: Loaded 3 models
INFO: Loaded 5 decisions
INFO: Router Replay enabled (sqlite: ~/vllm-stack/router/replay.db)
INFO: Ready
8.3 Verificar que arrancó
bash
curl http://localhost:8888/v1/models | python -m json.tool
Salida esperada:

json
{
    "object": "list",
    "data": [
        {"id": "qwen3-coder-30b", ...},
        {"id": "gemma-4-12b", ...},
        {"id": "qwen3.5-4b", ...},
        {"id": "auto", ...}
    ]
}
El modelo auto es el que activa el enrutamiento automático.

9. Paso 7 — Verificar Enrutamiento
9.1 Test simple (debe ir a Gemma 4 12B)
bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Hi"}]
  }' | python -m json.tool
Verificar en logs:

bash
tail -f ~/vllm-stack/router/router.log
Debe mostrar:

text
INFO: Decision 'simple' matched → model 'gemma-4-12b'
9.2 Test normal (debe ir a Gemma 4 12B)
bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Write a Python function to add two numbers. Include a docstring and a unit test."}]
  }' | python -m json.tool
Debe mostrar:

text
INFO: Decision 'normal' matched → model 'gemma-4-12b'
9.3 Test complejo por longitud (debe ir a Qwen3-Coder-30B)
bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "'"$(python -c 'print("Write a Python module that implements a red-black tree with insertion, deletion, and search operations. Include comprehensive unit tests, docstrings, and type hints. The module should handle edge cases gracefully.")'"'"'"}]
  }' | python -m json.tool
Debe mostrar:

text
INFO: Decision 'complex' matched → model 'qwen3-coder-30b'
9.4 Test complejo por keyword (debe ir a Qwen3-Coder-30B)
bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Refactor this function to use dependency injection."}]
  }' | python -m json.tool
Debe mostrar:

text
INFO: Decision 'complex_keywords' matched → model 'qwen3-coder-30b'
9.5 Test meta (debe ir a Qwen 3.5 4B)
bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Classify this prompt: What is the capital of France?"}]
  }' | python -m json.tool
Debe mostrar:

text
INFO: Decision 'meta' matched → model 'qwen3.5-4b'
9.6 Test de prioridad (keyword vs longitud)
Un prompt largo con keyword de arquitectura debe ir a complex_keywords, no a complex:

bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Refactor this code and optimize the architecture. '"$(python -c 'print("Detailed explanation " * 100)')"'"}]
  }' | python -m json.tool
Debe mostrar:

text
INFO: Decision 'complex_keywords' matched (priority 210 > 200) → model 'qwen3-coder-30b'
10. Paso 8 — Consultar Router Replay
10.1 Verificar que Router Replay está funcionando
bash
ls -lh ~/vllm-stack/router/replay.db
Salida esperada: archivo .db de varios KB.

10.2 Consultar con sqlite3
bash
sqlite3 ~/vllm-stack/router/replay.db
Dentro de sqlite:

sql
-- Ver estructura de la tabla
.schema router_replay

-- Contar registros
SELECT COUNT(*) FROM router_replay;

-- Ver últimos 10 registros
SELECT timestamp, decision_name, model, prompt_length, latency_ms
FROM router_replay
ORDER BY timestamp DESC
LIMIT 10;

-- Distribución por decisión
SELECT decision_name, COUNT(*) as total, AVG(latency_ms) as avg_latency
FROM router_replay
GROUP BY decision_name
ORDER BY total DESC;

-- Distribución por modelo
SELECT model, COUNT(*) as total, AVG(latency_ms) as avg_latency
FROM router_replay
GROUP BY model
ORDER BY total DESC;

-- Salir
.quit
10.3 Consultas útiles
Top 10 prompts más largos:

sql
SELECT prompt_length, decision_name, model
FROM router_replay
ORDER BY prompt_length DESC
LIMIT 10;
Latencia promedio por modelo:

sql
SELECT model, AVG(latency_ms) as avg_latency, COUNT(*) as total
FROM router_replay
GROUP BY model
ORDER BY avg_latency DESC;
Tasa de éxito por decisión:

sql
SELECT decision_name,
       SUM(CASE WHEN success THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate,
       COUNT(*) as total
FROM router_replay
GROUP BY decision_name;
10.4 Integración con Python
bash
python << 'EOF'
import sqlite3
import pandas as pd

conn = sqlite3.connect('/home/juan/vllm-stack/router/replay.db')

# Distribución por decisión
df = pd.read_sql_query("""
    SELECT decision_name, model, COUNT(*) as total, AVG(latency_ms) as avg_latency
    FROM router_replay
    GROUP BY decision_name, model
    ORDER BY total DESC
""", conn)

print(df)
EOF
Salida esperada:

text
  decision_name            model  total  avg_latency
0        simple    gemma-4-12b    342        145.2
1        normal    gemma-4-12b    891        187.6
2       complex  qwen3-coder-30b    124        892.4
3          meta      qwen3.5-4b     56         89.3
4  complex_keywords  qwen3-coder-30b    45        876.1
10.5 Exportar para análisis
bash
sqlite3 ~/vllm-stack/router/replay.db \
  "SELECT * FROM router_replay ORDER BY timestamp DESC LIMIT 1000" \
  -header -csv > ~/vllm-stack/logs/replay-export.csv
Este CSV es el insumo para el simulador de replay de Nivel 2 y 3.

11. Paso 9 — Dashboard de Monitoreo
11.1 Acceder al dashboard
vLLM-SR incluye un dashboard web en el puerto 8700:

text
http://localhost:8700
Desde Windows: abre el navegador en la misma URL. Gracias a localhostForwarding=true en .wslconfig, los puertos de WSL2 son accesibles desde Windows.

11.2 Qué muestra el dashboard
Distribución de decisiones: cuántas peticiones van a cada decisión.

Latencia por modelo: gráfico de latencias promedio.

Requests por minuto: throughput en tiempo real.

Errores: tasa de fallos por modelo.

Histórico: tendencias a lo largo del tiempo.

11.3 Métricas Prometheus
bash
curl http://localhost:9190/metrics | head -50
Métricas útiles:

vllm_sr_requests_total{decision="simple"}: total de peticiones por decisión.

vllm_sr_latency_seconds{model="gemma-4-12b"}: histograma de latencias.

vllm_sr_errors_total{model=...}: total de errores.

12. Checklist Final
Antes de pasar a la Fase 6 (integración multiagente), verificar:

vLLM-SR
□ vllm-sr instalado y funcional
□ config.yaml con 3 modelos y 5 decisiones
□ Router arranca sin errores
□ curl http://localhost:8888/v1/models responde
Enrutamiento
□ Test simple enruta a gemma-4-12b
□ Test normal enruta a gemma-4-12b
□ Test complex (longitud) enruta a qwen3-coder-30b
□ Test complex_keywords enruta a qwen3-coder-30b
□ Test meta enruta a qwen3.5-4b
□ Prioridad funciona (keyword gana sobre longitud)
Router Replay
□ Archivo replay.db creado
□ Tabla router_replay con columnas correctas
□ Registros acumulándose tras las pruebas
□ Consultas SQL funcionan
□ Export a CSV funciona
Dashboard
□ Accesible en http://localhost:8700
□ Muestra distribución de decisiones
□ Métricas Prometheus disponibles en :9190/metrics
13. Advertencias Críticas
13.1 NO exponer el puerto 8888 directamente a Internet sin autenticación
vLLM-SR no incluye autenticación por defecto. Si expones el puerto 8888 vía túnel, cualquiera puede usar tus modelos. En la Fase 6 se configura el túnel con consideraciones de seguridad.

13.2 NO exponer los puertos 8000, 8001, 8002
Estos puertos tienen VLLM_SERVER_DEV_MODE=1, que habilita endpoints peligrosos como /collective_rpc. Solo el puerto 8888 se expone.

13.3 Los umbrales de longitud son heurísticos
Los valores 150 y 800 son puntos de partida. Tras un par de días, consulta Router Replay y ajusta según la distribución real de tus prompts.

13.4 Router Replay con SQLite no soporta alta concurrencia
SQLite bloquea escrituras concurrentes. Si tienes >10 agentes concurrentes, migra a PostgreSQL:

yaml
router_replay:
  enabled: true
  store_backend: postgres
  db_url: postgresql://user:pass@localhost:5432/vllm_sr
13.5 El api_key: "dummy" no es seguro
Si expones el router a Internet, cambia "dummy" por una clave real y configura vLLM con --api-key. El router propagará la clave a los modelos backend.

13.6 Los cambios en config.yaml requieren reinicio
vLLM-SR no tiene hot-reload. Tras editar config.yaml, detén el router (Ctrl+C) y vuelve a lanzarlo.

13.7 Router Replay crece hasta max_records
Con 10000 registros y TTL de 7 días, la base SQLite puede llegar a ~10 MB. Si necesitas más historial, aumenta max_records y migra a PostgreSQL.

14. Referencias
Recurso	URL
vLLM-SR Docs	https://docs.vllm.ai/en/latest/serving/semantic_router.html
vLLM-SR GitHub	https://github.com/vllm-project/semantic-router
Router Replay	https://docs.vllm.ai/en/latest/serving/router_replay.html
Prometheus metrics	https://prometheus.io/docs/concepts/metric_types/
SQLite CLI	https://sqlite.org/cli.html
Pandas read_sql_query	https://pandas.pydata.org/docs/reference/api/pandas.read_sql_query.html
Cloudflare Tunnel	https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 6: Integración Multiagente y Túnel.

El siguiente archivo de documentación (06-Multi-Agent-Integration.md) asume:

Router semántico corriendo en :8888.

Router Replay acumulando registros en replay.db.

Los 3 modelos backend verificados.

Sleep Mode funcionando.

Dashboard accesible en :8700.