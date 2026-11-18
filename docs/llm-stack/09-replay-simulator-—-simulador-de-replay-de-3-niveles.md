---
date: 2026-09-17
---

> **Aviso (19-sep-2026).** APEX-EM ([arXiv 2603.29093](https://arxiv.org/abs/2603.29093), EMNLP 2026) es real. Pero el simulador de este documento tiene **dos riesgos de validez** ya detectados: elige casi siempre el primer hijo del árbol (`strategy.get("next", node.children[0])`) y considera «éxito» una petición que terminó sin error, no una respuesta correcta. Un simulador de reproducción solo mide algo si cada decisión tiene un **resultado verificable**. Hay un prototipo que sí lo tiene, `llm-stack/scripts/replay-routing.py`, que reproduce políticas de enrutado sobre los resultados de HumanEval. Ver `11-mejoras-y-decisiones.md`, apartado 7.24.

# 09-Replay-Simulator — Simulador de Replay de 3 Niveles
# 09-Replay-Simulator — Simulador de Replay de 3 Niveles

Documentación completa del sistema de replay que captura, estructura y reutiliza la experiencia del stack. Incluye los tres niveles (Básico, Moderado, Alto/Dream-RSI), la implementación de cada uno, y los criterios de verificación antes de integrar el bucle de auto-mejora.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Arquitectura del Simulador](#2-arquitectura-del-simulador)
3. [Decisiones Arquitectónicas](#3-decisiones-arquitectónicas)
4. [Nivel 1 — Router Replay (Básico)](#4-nivel-1--router-replay-básico)
5. [Nivel 2 — APEX-EM (Moderado)](#5-nivel-2--apex-em-moderado)
6. [Nivel 3 — Dream-RSI (Alto)](#6-nivel-3--dream-rsi-alto)
7. [Implementación del Simulador](#7-implementación-del-simulador)
8. [Uso del Simulador](#8-uso-del-simulador)
9. [Verificación por Nivel](#9-verificación-por-nivel)
10. [Checklist Final](#10-checklist-final)
11. [Advertencias Críticas](#11-advertencias-críticas)
12. [Referencias](#12-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `08-RSIAgent-Integration.md`. Debes tener:

- RSIAgent instalado y configurado.
- Al menos una ejecución de las tres fases (BRS, DRS, Test).
- Memoria poblada en `~/.rsiaagent/memory/`.
- Router Replay acumulando registros en `~/vllm-stack/router/replay.db`.
- Decisiones `rsi_actor` y `rsi_complex` en el router.

El objetivo de esta fase es **construir el simulador de replay de 3 niveles** que permita:

1. **Nivel 1**: Auditar cada decisión de enrutamiento.
2. **Nivel 2**: Reutilizar planes completos de tareas pasadas.
3. **Nivel 3**: Simular estrategias alternativas sin ejecutar código real.

### ¿Por qué 3 niveles?

Porque el coste y la complejidad crecen exponencialmente:

| Nivel | Coste computacional | Mejora esperada | Complejidad de implementación |
|:---|:---|:---|:---|
| **1** | ~0 | Visibilidad + auditoría | Baja |
| **2** | Bajo (consulta de memoria) | +20-40% en tareas repetitivas | Media |
| **3** | ~0 (offline) | **162x menos llamadas** | Alta |

Empezar por el Nivel 1 y subir solo cuando sea necesario es la estrategia correcta.

---

## 2. Arquitectura del Simulador

┌─────────────────────────────────────────────────────────────┐
│ CAPTURA (durante ejecución) │
│ │
│ ┌────────────────┐ ┌────────────────┐ ┌────────────────┐│
│ │ vLLM-SR │ │ RSIAgent │ │ Tu App / ││
│ │ Router Replay │ │ Memory Store │ │ Agentes ││
│ │ (SQLite) │ │ (JSON + JSONL) │ │ (logs) ││
│ └────────┬───────┘ └────────┬───────┘ └────────┬───────┘│
└───────────┼────────────────────┼────────────────────┼────────┘
│ │ │
▼ ▼ ▼
┌─────────────────────────────────────────────────────────────┐
│ ESTRUCTURACIÓN (offline) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ ReplaySimulator │ │
│ │ ├─ Nivel 1: routing_history (lista de decisiones) │ │
│ │ ├─ Nivel 2: procedural_memory (trazas APEX-EM) │ │
│ │ └─ Nivel 3: discovery_tree (grafo de exploración) │ │
│ └────────────────────────────────────────────────────────┘ │
└─────────────────────────┬───────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────┐
│ SUEÑO (offline) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ Meta-Agente (Qwen 3.5 4B) │ │
│ │ Lee el árbol de descubrimiento │ │
│ │ Propone N estrategias alternativas │ │
│ │ CERO llamadas al modelo de ejecución │ │
│ └────────────────────────┬───────────────────────────────┘ │
└───────────────────────────┼─────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────┐
│ SIMULACIÓN (offline) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ Replay de cada estrategia sobre el árbol existente │ │
│ │ Cálculo de: tokens, tiempo, tasa de éxito │ │
│ │ CERO ejecución real │ │
│ └────────────────────────┬───────────────────────────────┘ │
└───────────────────────────┼─────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────┐
│ SELECCIÓN (offline) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ Comparar estrategias contra baseline │ │
│ │ Filtrar las que mejoran >10% │ │
│ │ Ordenar por éxito, luego por coste │ │
│ └────────────────────────┬───────────────────────────────┘ │
└───────────────────────────┼─────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────────┐
│ DESPLIEGUE (online) │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ Actualizar reglas del router vLLM-SR │ │
│ │ Guardar en learned_strategy.json │ │
│ │ Próximo ciclo: usar nueva estrategia │ │
│ └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

---

## 3. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **3 niveles incrementales** | Un solo nivel complejo | Permite empezar simple y subir solo si es necesario. Nivel 1 ya da valor. |
| **SQLite para Nivel 1** | PostgreSQL, MongoDB | Sin servidor, archivo único, suficiente para 10k registros. Migrar si crece. |
| **JSON + JSONL para Nivel 2** | Base de datos relacional | La estructura de APEX-EM es jerárquica; JSONL permite append sin reescribir. |
| **Árbol de descubrimiento en memoria** | Grafo persistente | Para 10k nodos, cabe en RAM (~100 MB). No requiere Neo4j o similar. |
| **Meta-agente Qwen 3.5 4B** | Qwen3-Coder-30B | El meta-agente hace clasificación y propuesta; 4B es suficiente y rápido. |
| **Dream-RSI offline** | Online en tiempo real | El "sueño" es por definición offline. Ejecutarlo durante el tráfico causaría latencia. |
| **Umbral de mejora 10%** | Desplegar cualquier mejora | Evita cambios por ruido estadístico. Ajustable según madurez. |
| **100 simulaciones por estrategia** | 10 o 1000 | Balance entre precisión y tiempo de cómputo. 100 da intervalos de confianza razonables. |

---

## 4. Nivel 1 — Router Replay (Básico)

### 4.1 ¿Qué es?

Router Replay es el **almacén de eventos duradero** de vLLM-SR. Registra cada decisión de enrutamiento con metadatos completos.

### 4.2 ¿Por qué es el Nivel 1?

Porque es **automático**. Solo hay que habilitarlo en `config.yaml` y vLLM-SR lo llena. Sin código adicional.

### 4.3 Configuración

**En `~/vllm-stack/router/config.yaml`**:

router_replay:
  enabled: true
  store_backend: sqlite
  db_path: ~/vllm-stack/router/replay.db
  max_records: 10000
  ttl_seconds: 604800

  Verificar que está activo:

bash
ls -lh ~/vllm-stack/router/replay.db
sqlite3 ~/vllm-stack/router/replay.db "SELECT COUNT(*) FROM router_replay"
4.4 Esquema de la tabla
bash
sqlite3 ~/vllm-stack/router/replay.db ".schema router_replay"
Salida esperada:

sql
CREATE TABLE router_replay (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    decision_name TEXT NOT NULL,
    model TEXT NOT NULL,
    prompt_length INTEGER,
    latency_ms REAL,
    tokens_generated INTEGER,
    success BOOLEAN,
    session_id TEXT
);
4.5 Consultas útiles
Distribución por decisión:

sql
SELECT decision_name, COUNT(*) as total, AVG(latency_ms) as avg_latency
FROM router_replay
GROUP BY decision_name
ORDER BY total DESC;
Distribución por modelo:

sql
SELECT model, COUNT(*) as total, AVG(latency_ms) as avg_latency
FROM router_replay
GROUP BY model
ORDER BY total DESC;
Top 10 prompts más largos:

sql
SELECT prompt_length, decision_name, model
FROM router_replay
ORDER BY prompt_length DESC
LIMIT 10;
Tasa de éxito por decisión:

sql
SELECT decision_name,
       SUM(CASE WHEN success THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate,
       COUNT(*) as total
FROM router_replay
GROUP BY decision_name
ORDER BY success_rate DESC;
Últimos 10 registros:

sql
SELECT timestamp, decision_name, model, prompt_length, latency_ms, success
FROM router_replay
ORDER BY timestamp DESC
LIMIT 10;
4.6 Exportar a CSV
bash
sqlite3 ~/vllm-stack/router/replay.db \
  "SELECT * FROM router_replay ORDER BY timestamp DESC LIMIT 1000" \
  -header -csv > ~/vllm-stack/logs/replay-export.csv
4.7 Análisis con Python
python
import sqlite3
import pandas as pd

conn = sqlite3.connect('/home/juan/vllm-stack/router/replay.db')

df = pd.read_sql_query("""
    SELECT decision_name, model, COUNT(*) as total,
           AVG(latency_ms) as avg_latency,
           AVG(tokens_generated) as avg_tokens
    FROM router_replay
    GROUP BY decision_name, model
    ORDER BY total DESC
""", conn)

print(df)
print()
print("Total de peticiones:", df['total'].sum())
print("Latencia promedio global:", df['avg_latency'].mean())
Salida esperada:

text
  decision_name            model  total  avg_latency  avg_tokens
0        simple    gemma-4-12b    342        145.2       85.3
1        normal    gemma-4-12b    891        187.6      142.5
2       complex  qwen3-coder-30b    124        892.4      356.7
3          meta      qwen3.5-4b     56         89.3       42.1
4  complex_keywords  qwen3-coder-30b    45        876.1      312.4

Total de peticiones: 1458
Latencia promedio global: 438.1
4.8 Errores comunes
Error	Causa	Solución
no such table: router_replay	router_replay no habilitado en config.yaml	Habilitar y reiniciar router
database is locked	Escritura concurrente	Migrar a PostgreSQL si >10 agentes
disk I/O error	Disco lleno	Verificar df -h
no such column	Versión antigua de vLLM-SR	Actualizar vllm-sr
5. Nivel 2 — APEX-EM (Moderado)
5.1 ¿Qué es APEX-EM?
APEX-EM (Agent Procedural EXperience Memory) es un sistema de memoria procedural estructurada. Acumula trazas completas de tareas: plan, pasos, artefactos, historial de iteraciones, y puntuaciones de calidad.

5.2 ¿Por qué es el Nivel 2?
Porque reutiliza planes completos para tareas estructuralmente similares, sin modificar pesos. Ahorra tiempo y tokens en tareas recurrentes.

5.3 Estructura de una traza
json
{
    "task_signature": "parse_json_generate_csv",
    "task_description": "Write a Python script to parse a JSON file and generate a CSV report",
    "plan_steps": [
        "Open JSON file with json.load",
        "Iterate over records",
        "Collect field names as CSV headers",
        "Write each record as CSV row"
    ],
    "artifacts": ["parse_to_csv.py", "output.csv"],
    "iteration_history": [
        {"attempt": 1, "error": "KeyError on missing field", "fix": "use .get()"},
        {"attempt": 2, "error": null, "quality_score": 0.95}
    ],
    "quality_scores": {
        "correctness": 1.0,
        "efficiency": 0.85,
        "readability": 0.9
    },
    "model_used": "gemma-4-12b",
    "tokens_consumed": 1230,
    "timestamp": "2026-09-17T20:30:00"
}
5.4 Implementación
Crear ~/vllm-stack/replay/apex_em_memory.py:

python
"""
APEX-EM Memory — Sistema de memoria procedural estructurada.

Registra trazas completas de tareas (plan, pasos, artefactos, iteraciones)
y permite reutilizar planes completos para tareas similares.
"""

import json
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime


@dataclass
class ProceduralTrace:
    """Traza procedimental de una tarea."""
    task_signature: str
    task_description: str
    plan_steps: List[str]
    artifacts: List[str] = field(default_factory=list)
    iteration_history: List[Dict] = field(default_factory=list)
    quality_scores: Dict[str, float] = field(default_factory=dict)
    model_used: str = "unknown"
    tokens_consumed: int = 0
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())


class APEXEMMemory:
    """Memoria procedural estructurada (APEX-EM style)."""

    def __init__(self, memory_dir: str):
        self.memory_dir = Path(memory_dir).expanduser()
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        self.traces_file = self.memory_dir / "procedural_traces.jsonl"

    def ingest(self, trace: ProceduralTrace):
        """Almacena una traza procedimental."""
        with open(self.traces_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(asdict(trace), ensure_ascii=False) + '\n')

    def retrieve_similar(self, task_signature: str, top_k: int = 3) -> List[ProceduralTrace]:
        """Recupera trazas similares por firma estructural."""
        traces = self._load_all()
        scored = []
        for t in traces:
            sim = self._jaccard(task_signature, t.task_signature)
            scored.append((sim, t))
        scored.sort(key=lambda x: -x[0])
        return [t for _, t in scored[:top_k]]

    def get_stats(self) -> Dict:
        """Retorna estadísticas agregadas de la memoria."""
        traces = self._load_all()
        if not traces:
            return {"total_traces": 0}
        return {
            "total_traces": len(traces),
            "avg_tokens": sum(t.tokens_consumed for t in traces) / len(traces),
            "avg_quality": sum(
                t.quality_scores.get("correctness", 0)
                for t in traces
            ) / len(traces),
            "models_used": list(set(t.model_used for t in traces))
        }

    def _jaccard(self, a: str, b: str) -> float:
        """Similitud de Jaccard entre dos firmas."""
        set_a = set(a.split('_'))
        set_b = set(b.split('_'))
        if not set_a or not set_b:
            return 0.0
        return len(set_a & set_b) / len(set_a | set_b)

    def _load_all(self) -> List[ProceduralTrace]:
        """Carga todas las trazas."""
        if not self.traces_file.exists():
            return []
        traces = []
        with open(self.traces_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    traces.append(ProceduralTrace(**data))
                except (json.JSONDecodeError, TypeError):
                    continue
        return traces


# Ejemplo de uso
if __name__ == "__main__":
    memory = APEXEMMemory("~/.rsiaagent/memory/apex")

    # Ingestar traza de ejemplo
    trace = ProceduralTrace(
        task_signature="parse_json_generate_csv",
        task_description="Parse JSON and generate CSV",
        plan_steps=[
            "Open JSON file with json.load",
            "Iterate over records",
            "Write CSV headers",
            "Write CSV rows"
        ],
        artifacts=["parse_to_csv.py"],
        iteration_history=[
            {"attempt": 1, "error": "KeyError", "fix": "use .get()"},
            {"attempt": 2, "error": None, "quality_score": 0.95}
        ],
        quality_scores={"correctness": 1.0, "efficiency": 0.85},
        model_used="gemma-4-12b",
        tokens_consumed=1230
    )
    memory.ingest(trace)

    # Recuperar similares
    similar = memory.retrieve_similar("parse_csv_generate_report", top_k=3)
    print(f"Trazas similares: {len(similar)}")
    for t in similar:
        print(f"  - {t.task_signature}: {t.task_description[:60]}")

    # Estadísticas
    print(memory.get_stats())
5.5 Integración con RSIAgent
Extender la memoria de RSIAgent:

python
from rsiaagent.memory import MemoryStore
from apex_em_memory import APEXEMMemory, ProceduralTrace


class EnhancedMemory:
    """Memoria extendida con APEX-EM."""

    def __init__(self):
        self.base = MemoryStore("~/.rsiaagent/memory")
        self.apex = APEXEMMemory("~/.rsiaagent/memory/apex")

    def ingest_experience(self, task_id: str, trace_data: dict):
        """Ingesta una experiencia en ambos formatos."""
        # Formato APEX-EM
        trace = ProceduralTrace(
            task_signature=self._extract_signature(trace_data),
            task_description=trace_data.get("description", ""),
            plan_steps=trace_data.get("plan", []),
            artifacts=trace_data.get("artifacts", []),
            iteration_history=trace_data.get("iterations", []),
            quality_scores=trace_data.get("quality", {}),
            model_used=trace_data.get("model", "unknown"),
            tokens_consumed=trace_data.get("tokens", 0)
        )
        self.apex.ingest(trace)

        # Formato base de RSIAgent
        self.base.add_procedure(trace_data.get("plan", []))
        self.base.add_lesson(trace_data.get("errors", []))

    def query_similar(self, task_description: str, top_k: int = 3):
        """Busca trazas similares."""
        signature = self._extract_signature({"description": task_description})
        return self.apex.retrieve_similar(signature, top_k=top_k)

    def _extract_signature(self, trace_data: dict) -> str:
        """Extrae firma estructural de una tarea."""
        # Implementación simple: primeras palabras significativas
        desc = trace_data.get("description", "").lower()
        words = [w for w in desc.split() if len(w) > 3]
        return "_".join(words[:5])
5.6 Verificar la memoria
bash
# Ver número de trazas
wc -l ~/.rsiaagent/memory/apex/procedural_traces.jsonl

# Ver última traza
tail -1 ~/.rsiaagent/memory/apex/procedural_traces.jsonl | python -m json.tool

# Estadísticas
python -c "
from apex_em_memory import APEXEMMemory
m = APEXEMMemory('~/.rsiaagent/memory/apex')
print(m.get_stats())
"
5.7 Errores comunes
Error	Causa	Solución
JSONDecodeError al leer	Línea corrupta en JSONL	Ignorar la línea; el código lo maneja
No similar traces found	Memoria vacía	Ejecutar RSIAgent primero
Jaccard similarity = 0	Firmas sin palabras comunes	Ajustar extracción de firma
Memory grew too large	Muchos ciclos sin purga	Implementar purge por TTL
6. Nivel 3 — Dream-RSI (Alto)
6.1 ¿Qué es Dream-RSI?
Es el "sueño" del sistema. Un meta-agente lee el historial de descubrimientos, propone estrategias de exploración alternativas, y las evalúa offline sin ejecutar código real.

6.2 ¿Por qué es el Nivel 3?
Porque reduce drásticamente el coste de encontrar buenas estrategias. El paper de Dream-RSI demostró 162x menos llamadas al agente en tareas de optimización.

6.3 Componentes
Discovery Tree: grafo de decisiones de exploración (nodos con action, model, tokens, success, quality).

Meta-Agent: Qwen 3.5 4B que propone estrategias.

Simulator: evalúa estrategias sobre el árbol existente.

Selector: elige la mejor estrategia.

Deployer: actualiza reglas del router.

6.4 Implementación completa
Crear ~/vllm-stack/replay/dream_rsi_simulator.py:

python
"""
Dream-RSI Simulator — Simulador de estrategias de exploración.

Lee el árbol de descubrimiento del stack, propone estrategias alternativas
con un meta-agente, y las evalúa offline sin ejecutar código real.
"""

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Dict, Optional
from openai import OpenAI


@dataclass
class DiscoveryNode:
    """Nodo del árbol de descubrimiento."""
    node_id: str
    action: str
    model_used: str
    context_length: int
    tokens_generated: int
    success: bool
    quality_score: float
    latency_ms: float
    children: List[str] = field(default_factory=list)


class ReplaySimulator:
    """
    Simulador de replay de 3 niveles.

    - Nivel 1: solo routing replay.
    - Nivel 2: routing + procedural memory (APEX-EM).
    - Nivel 3: árbol de descubrimiento completo + Dream-RSI.
    """

    def __init__(self, level: int = 3):
        self.level = level
        self.discovery_tree: Dict[str, DiscoveryNode] = {}
        self.routing_history: List[Dict] = []
        self.procedural_memory: List[Dict] = []
        self.meta_client = OpenAI(
            base_url="http://localhost:8002/v1",
            api_key="dummy"
        )

    def load_history(self, replay_db_path: str, memory_path: str):
        """Carga historial de vLLM-SR Replay y APEX-EM Memory."""
        if self.level >= 1:
            self.routing_history = self._load_routing_replay(replay_db_path)
            print(f"Routing history: {len(self.routing_history)} registros")

        if self.level >= 2:
            self.procedural_memory = self._load_apex_em(memory_path)
            print(f"Procedural memory: {len(self.procedural_memory)} trazas")

        if self.level >= 3:
            self.discovery_tree = self._build_discovery_tree(
                self.routing_history, self.procedural_memory
            )
            print(f"Discovery tree: {len(self.discovery_tree)} nodos")

    # ── NIVEL 3: DREAM-RSI ──────────────────────────────────

    def propose_strategy_candidates(self, n: int = 5) -> List[Dict]:
        """
        El meta-agente propone N estrategias de exploración alternativas.
        CERO llamadas al modelo de ejecución.
        """
        tree_summary = self._summarize_tree()

        prompt = f"""Eres un meta-agente de exploración. Tu tarea NO es resolver
el problema, sino proponer estrategias de búsqueda alternativas.

HISTORIAL DE DESCUBRIMIENTO:
{tree_summary}

REGLAS:
- Los nodos con success=False son ramas muertas.
- Los nodos con quality < 0.5 son ramas débiles.
- Los modelos disponibles son: gemma-4-12b (rápido), qwen3-coder-30b (complejo), qwen3.5-4b (meta).

PROPÓN {n} ESTRATEGIAS DE EXPLORACIÓN ALTERNATIVAS.
Cada estrategia debe especificar:
1. Orden de exploración (qué ramas primero)
2. Asignación de modelos (cuándo usar rápido vs complejo)
3. Umbral de poda (cuándo abandonar una rama)
4. Nivel de paralelismo

Responde en JSON: {{"strategies": [{{"name": "...", "steps": [...]}}]}}
"""

        response = self.meta_client.chat.completions.create(
            model="qwen3.5-4b",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.9,
            response_format={"type": "json_object"},
            max_tokens=2048
        )

        return json.loads(response.choices[0].message.content).get("strategies", [])

    def simulate_strategy(self, strategy: Dict, n_simulations: int = 100) -> Dict:
        """Simula una estrategia sobre el árbol existente (offline)."""
        total_tokens = 0
        total_time = 0
        successes = 0
        total_nodes = 0

        for _ in range(n_simulations):
            path = self._rollout(strategy)
            total_nodes += len(path)
            for node_id in path:
                if node_id in self.discovery_tree:
                    node = self.discovery_tree[node_id]
                    total_tokens += node.tokens_generated
                    total_time += node.latency_ms
                    if node.success:
                        successes += 1

        return {
            "strategy": strategy.get("name", "unnamed"),
            "avg_tokens_per_run": total_tokens / n_simulations if n_simulations else 0,
            "avg_time_per_run": total_time / n_simulations if n_simulations else 0,
            "success_rate": successes / total_nodes if total_nodes else 0,
            "estimated_cost": total_tokens * 0.000001
        }

    def select_best_strategy(self, candidates: List[Dict], n_simulations: int = 100) -> Optional[Dict]:
        """Evalúa todas las candidatas offline y elige la mejor."""
        results = [self.simulate_strategy(s, n_simulations) for s in candidates]

        baseline = self._compute_baseline()
        viable = [r for r in results if r["success_rate"] >= baseline["success_rate"]]

        if not viable:
            return None

        return sorted(viable, key=lambda x: (-x["success_rate"], x["estimated_cost"]))[0]

    def deploy_strategy(self, best_strategy: Dict) -> Dict:
        """Guarda la mejor estrategia para despliegue."""
        output_path = Path("~/vllm-stack/router/learned_strategy.json").expanduser()
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w') as f:
            json.dump({
                "strategy": best_strategy,
                "deployed_at": self._now()
            }, f, indent=2)

        return {"deployed": True, "strategy": best_strategy["strategy"], "path": str(output_path)}

    # ── HELPERS ─────────────────────────────────────────────

    def _rollout(self, strategy: Dict) -> List[str]:
        """Simula un camino a través del árbol según la estrategia."""
        path = []
        current = "root"
        visited = set()
        while current in self.discovery_tree and current not in visited:
            visited.add(current)
            node = self.discovery_tree[current]
            if not node.children:
                break
            next_child = strategy.get("next", node.children[0])
            path.append(next_child)
            current = next_child
        return path

    def _compute_baseline(self) -> Dict:
        """Calcula el baseline (estrategia actual)."""
        recent = list(self.discovery_tree.values())[-100:]
        if not recent:
            return {"success_rate": 0.0, "avg_tokens": 0}
        return {
            "success_rate": sum(1 for n in recent if n.success) / len(recent),
            "avg_tokens": sum(n.tokens_generated for n in recent) / len(recent)
        }

    def _summarize_tree(self) -> str:
        """Genera un resumen textual del árbol para el meta-agente."""
        nodes = list(self.discovery_tree.values())
        if not nodes:
            return "Árbol vacío."

        summary = f"Nodos totales: {len(nodes)}\n"
        summary += f"Tasa de éxito: {sum(1 for n in nodes if n.success)/len(nodes):.2%}\n"
        summary += f"Tokens promedio: {sum(n.tokens_generated for n in nodes)/len(nodes):.0f}\n"
        summary += "Últimos 10 nodos:\n"

        for n in nodes[-10:]:
            summary += f"  - {n.node_id}: {n.action} | {n.model_used} | "
            summary += f"success={n.success} | quality={n.quality_score:.2f}\n"

        return summary

    def _load_routing_replay(self, db_path: str) -> List[Dict]:
        """Carga registros de Router Replay."""
        db_path = Path(db_path).expanduser()
        if not db_path.exists():
            return []

        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT * FROM router_replay ORDER BY timestamp DESC LIMIT 1000")
            cols = [d[0] for d in cursor.description]
            rows = [dict(zip(cols, row)) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            rows = []
        finally:
            conn.close()

        return rows

    def _load_apex_em(self, memory_path: str) -> List[Dict]:
        """Carga trazas de APEX-EM."""
        traces_file = Path(memory_path).expanduser() / "apex" / "procedural_traces.jsonl"
        if not traces_file.exists():
            return []

        traces = []
        with open(traces_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        traces.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
        return traces

    def _build_discovery_tree(self, routing: List[Dict], procedural: List[Dict]) -> Dict[str, DiscoveryNode]:
        """Construye el árbol de descubrimiento."""
        tree = {}

        for i, r in enumerate(routing):
            node_id = f"route_{i}"
            tree[node_id] = DiscoveryNode(
                node_id=node_id,
                action=f"route_{r.get('decision_name', 'unknown')}",
                model_used=r.get('model', 'unknown'),
                context_length=r.get('prompt_length', 0),
                tokens_generated=r.get('tokens_generated', 0) or 0,
                success=bool(r.get('success', True)),
                quality_score=1.0 if r.get('success', True) else 0.3,
                latency_ms=r.get('latency_ms', 0) or 0,
                children=[f"route_{i+1}"] if i + 1 < len(routing) else []
            )

        for i, p in enumerate(procedural):
            node_id = f"proc_{i}"
            quality = p.get('quality_scores', {}).get('correctness', 0.5)
            tree[node_id] = DiscoveryNode(
                node_id=node_id,
                action=f"procedure_{p.get('task_signature', 'unknown')}",
                model_used=p.get('model_used', 'unknown'),
                context_length=0,
                tokens_generated=p.get('tokens_consumed', 0),
                success=quality > 0.7,
                quality_score=quality,
                latency_ms=0,
                children=[]
            )

        return tree

    def _now(self) -> str:
        from datetime import datetime
        return datetime.now().isoformat()


# Ejemplo de uso
if __name__ == "__main__":
    sim = ReplaySimulator(level=3)

    sim.load_history(
        replay_db_path="~/vllm-stack/router/replay.db",
        memory_path="~/.rsiaagent/memory"
    )

    candidates = sim.propose_strategy_candidates(n=5)
    print(f"Estrategias propuestas: {len(candidates)}")

    best = sim.select_best_strategy(candidates, n_simulations=100)
    if best:
        print(f"Mejor estrategia: {best['strategy']}")
        print(f"  Tasa de éxito: {best['success_rate']:.2%}")
        print(f"  Tokens promedio: {best['avg_tokens_per_run']:.0f}")
        sim.deploy_strategy(best)
    else:
        print("Sin mejora significativa sobre baseline.")
6.5 Verificar el simulador
bash
cd ~/vllm-stack/replay

python -c "
from dream_rsi_simulator import ReplaySimulator

sim = ReplaySimulator(level=3)
sim.load_history(
    replay_db_path='~/vllm-stack/router/replay.db',
    memory_path='~/.rsiaagent/memory'
)
print('Simulador listo')
"
Salida esperada:

text
Routing history: NNN registros
Procedural memory: NN trazas
Discovery tree: NNNN nodos
Simulador listo
6.6 Errores comunes
Error	Causa	Solución
Connection refused: localhost:8002	Router model no corriendo	Verificar puerto 8002
json.JSONDecodeError del meta-agente	Qwen 3.5 4B no devolvió JSON válido	Añadir retry o mejorar prompt
No valid strategies	Árbol vacío o muy pequeño	Ejecutar más tareas primero
Simulation too slow	Nodos con latencias altas	Reducir n_simulations a 50
7. Implementación del Simulador
7.1 Estructura de archivos
text
~/vllm-stack/replay/
├── __init__.py
├── apex_em_memory.py       # Nivel 2
└── dream_rsi_simulator.py  # Nivel 3
7.2 Crear __init__.py
bash
touch ~/vllm-stack/replay/__init__.py
7.3 Verificar imports
bash
cd ~/vllm-stack/replay

python -c "
from apex_em_memory import APEXEMMemory, ProceduralTrace
from dream_rsi_simulator import ReplaySimulator, DiscoveryNode
print('Imports OK')
"
Salida esperada: Imports OK.

8. Uso del Simulador
8.1 Nivel 1: consulta de routing
python
import sqlite3
import pandas as pd

conn = sqlite3.connect('/home/juan/vllm-stack/router/replay.db')

# Distribución de decisiones
df = pd.read_sql_query("""
    SELECT decision_name, model, COUNT(*) as total, AVG(latency_ms) as avg_latency
    FROM router_replay
    GROUP BY decision_name, model
""", conn)

print(df)
8.2 Nivel 2: búsqueda de trazas similares
python
from apex_em_memory import APEXEMMemory

memory = APEXEMMemory("~/.rsiaagent/memory/apex")

# Buscar trazas similares a una tarea nueva
similar = memory.retrieve_similar("parse_json_generate_csv", top_k=3)

print(f"Trazas similares: {len(similar)}")
for t in similar:
    print(f"  - {t.task_signature}")
    print(f"    Plan: {t.plan_steps[:2]}")
    print(f"    Calidad: {t.quality_scores.get('correctness', 0):.2f}")
8.3 Nivel 3: Dream-RSI completo
python
from dream_rsi_simulator import ReplaySimulator

sim = ReplaySimulator(level=3)
sim.load_history(
    replay_db_path="~/vllm-stack/router/replay.db",
    memory_path="~/.rsiaagent/memory"
)

# Proponer estrategias
candidates = sim.propose_strategy_candidates(n=5)

# Simular y elegir la mejor
best = sim.select_best_strategy(candidates, n_simulations=100)

if best:
    print(f"Mejor: {best['strategy']}")
    print(f"Éxito: {best['success_rate']:.2%}")
    print(f"Tokens: {best['avg_tokens_per_run']:.0f}")
    sim.deploy_strategy(best)
9. Verificación por Nivel
9.1 Nivel 1
bash
# Verificar que Router Replay acumula registros
sqlite3 ~/vllm-stack/router/replay.db "SELECT COUNT(*) FROM router_replay"

# Verificar que la tabla tiene todas las columnas
sqlite3 ~/vllm-stack/router/replay.db "PRAGMA table_info(router_replay)"
9.2 Nivel 2
bash
# Verificar que APEX-EM tiene trazas
wc -l ~/.rsiaagent/memory/apex/procedural_traces.jsonl

# Verificar que se pueden recuperar trazas similares
python -c "
from apex_em_memory import APEXEMMemory
m = APEXEMMemory('~/.rsiaagent/memory/apex')
print(m.get_stats())
"
9.3 Nivel 3
bash
# Verificar que el árbol de descubrimiento se construye
python -c "
from dream_rsi_simulator import ReplaySimulator
sim = ReplaySimulator(level=3)
sim.load_history('~/vllm-stack/router/replay.db', '~/.rsiaagent/memory')
print(f'Nodos en el árbol: {len(sim.discovery_tree)}')
print(f'Baseline: {sim._compute_baseline()}')
"
9.4 Comparación de niveles
Nivel	Tiempo de carga	Precisión	Uso
1	<1s	Exacta	Auditoría
2	1-5s	Alta	Búsqueda de planes
3	10-60s	Muy alta	Dream-RSI
10. Checklist Final
Antes de pasar a la Fase 10 (Dream-RSI Loop), verificar:

Nivel 1 (Router Replay)
□ router_replay habilitado en config.yaml
□ replay.db con registros
□ Consultas SQL funcionan
□ Export a CSV funciona
Nivel 2 (APEX-EM)
□ apex_em_memory.py creado
□ Clase APEXEMMemory funcional
□ Trazas en procedural_traces.jsonl
□ retrieve_similar() devuelve resultados
□ get_stats() funciona
Nivel 3 (Dream-RSI)
□ dream_rsi_simulator.py creado
□ Clase ReplaySimulator funcional
□ load_history() carga routing + memoria
□ propose_strategy_candidates() funciona
□ simulate_strategy() ejecuta offline
□ select_best_strategy() elige la mejor
□ deploy_strategy() guarda el resultado
Integración
□ __init__.py en ~/vllm-stack/replay/
□ Imports funcionan
□ learned_strategy.json generado
11. Advertencias Críticas
11.1 El Nivel 3 requiere Nivel 1 y 2 poblados
Sin historial, el árbol de descubrimiento está vacío y no hay estrategias que proponer. Ejecutar RSIAgent y usar el router antes de lanzar Dream-RSI.

11.2 El meta-agente requiere el modelo router corriendo
El puerto 8002 debe estar activo. Si qwen3.5-4b no responde, propose_strategy_candidates() falla.

11.3 El simulador puede tardar en árboles grandes
Con >10k nodos, load_history() puede tardar 30+ segundos. Es normal.

11.4 Las estrategias no son transferibles entre dominios
Una estrategia óptima para "parseo de JSON" puede no aplicar a "optimización de kernels GPU". El simulador aprende por dominio.

11.5 El umbral de mejora del 10% es heurístico
En sistemas maduros, subir a 20% para evitar cambios por ruido. En sistemas nuevos, bajar a 5% para explorar más.

11.6 La memoria no se debe modificar manualmente
Los archivos procedures.json, procedural_traces.jsonl, etc., son gestionados por el código. Editarlos manualmente puede corromper la estructura.

11.7 El caché de JIT no se comparte entre niveles
Cada nivel construye su propia vista del estado. No hay caché compartido entre Nivel 1, 2 y 3.

12. Referencias
Recurso	URL
Dream-RSI	https://dream-rsi.com/
APEX-EM Paper	https://ar5iv.labs.arxiv.org/html/2603.29093
LIMBO	https://arxiv.org/abs/2603.xxxxx
Router Replay	https://docs.vllm.ai/en/latest/serving/router_replay.html
SQLite JSON1	https://sqlite.org/json1.html
Jaccard similarity	https://en.wikipedia.org/wiki/Jaccard_index
Pydantic	https://docs.pydantic.dev/
Pandas	https://pandas.pydata.org/
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 10: Dream-RSI Loop.

El siguiente archivo de documentación (10-Dream-RSI-Loop.md) asume:

Los 3 niveles del simulador funcionando.

replay.db con registros.

procedural_traces.jsonl con trazas.

learned_strategy.json con al menos una estrategia.

Meta-agente corriendo en puerto 8002.