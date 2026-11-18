---
date: 2026-09-17
---

> **Aviso (19-sep-2026).** Dream-RSI ([arXiv 2609.14858](https://arxiv.org/html/2609.14858v1), Google/DeepMind) es real, pero la cifra «162x» es un **máximo** («hasta 162x menos llamadas») medido en ingeniería de algoritmos, optimización matemática y kernels de GPU con Gemini-3.1-Pro, reproduciendo árboles de descubrimiento con resultados puntuados. **Aplicarlo a optimizar una estrategia de enrutado es una transposición nuestra, no lo que hace el paper**, y no está probada. No dejes este bucle funcionando sin supervisión ni desplegando estrategias solo: antes hace falta un verificador ejecutable, un conjunto reservado y despliegue en *canary* con vuelta atrás. Ver `11-mejoras-y-decisiones.md`, apartado 7.24.

# 10-Dream-RSI-Loop — Bucle de Auto-Mejora Recursiva

# 10-Dream-RSI-Loop — Bucle de Auto-Mejora Recursiva

Documentación completa del bucle que cierra el ciclo de auto-mejora: ejecutar → registrar → soñar → simular → desplegar → repetir. Incluye la implementación del loop, la configuración de parámetros, la integración con el stack completo, y los criterios de verificación.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Arquitectura del Bucle](#2-arquitectura-del-bucle)
3. [Decisiones Arquitectónicas](#3-decisiones-arquitectónicas)
4. [Paso 1 — Implementar el Bucle](#4-paso-1--implementar-el-bucle)
5. [Paso 2 — Configurar Parámetros](#5-paso-2--configurar-parámetros)
6. [Paso 3 — Lanzar el Bucle](#6-paso-3--lanzar-el-bucle)
7. [Paso 4 — Monitorear el Bucle](#7-paso-4--monitorear-el-bucle)
8. [Paso 5 — Verificar Estrategias Desplegadas](#8-paso-5--verificar-estrategias-desplegadas)
9. [Paso 6 — Integrar con el Router](#9-paso-6--integrar-con-el-router)
10. [Paso 7 — Ciclo de Vida Completo](#10-paso-7--ciclo-de-vida-completo)
11. [Checklist Final](#11-checklist-final)
12. [Advertencias Críticas](#12-advertencias-críticas)
13. [Referencias](#13-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `09-Replay-Simulator.md`. Debes tener:

- Los 3 niveles del simulador funcionando.
- `replay.db` con registros de Router Replay.
- `procedural_traces.jsonl` con trazas APEX-EM.
- `learned_strategy.json` con al menos una estrategia.
- Meta-agente corriendo en puerto 8002 (`qwen3.5-4b`).

El objetivo de esta fase es **cerrar el ciclo de auto-mejora recursiva**. El bucle:

1. **Ejecuta** tareas reales con el stack vLLM.
2. **Registra** decisiones y resultados.
3. **Sueña** — el meta-agente propone estrategias alternativas.
4. **Simula** — evaluación offline sin coste de cómputo real.
5. **Despliega** — si hay mejora, actualiza el router.
6. **Repite** — cada intervalo configurable.

### ¿Por qué un bucle?

Sin bucle, el sistema aprende una vez y se estanca. Con bucle, el sistema **mejora continuamente** con cada ciclo, adaptándose a cambios en el uso, en los modelos, y en el entorno.

---

## 2. Arquitectura del Bucle

┌─────────────────────────────────────────────────────────────┐
│ CICLO DE AUTO-MEJORA │
│ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 1. EJECUTAR │ │
│ │ - Tu app / agentes usan el router │ │
│ │ - Router Replay registra cada decisión │ │
│ │ - RSIAgent ejecuta tareas (opcional) │ │
│ └────────────────────────┬───────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 2. REGISTRAR │ │
│ │ - Router Replay → replay.db │ │
│ │ - RSIAgent → procedural_traces.jsonl │ │
│ │ - Logs → ~/vllm-stack/logs/ │ │
│ └────────────────────────┬───────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 3. SOÑAR (offline) │ │
│ │ - Cargar historial (Nivel 1 + 2 + 3) │ │
│ │ - Construir árbol de descubrimiento │ │
│ │ - Meta-agente (Qwen 3.5 4B) propone estrategias │ │
│ └────────────────────────┬───────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 4. SIMULAR (offline) │ │
│ │ - Evaluar cada estrategia offline │ │
│ │ - 100 simulaciones por estrategia │ │
│ │ - CERO llamadas al modelo de ejecución │ │
│ └────────────────────────┬───────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 5. DESPLEGAR (si mejora > umbral) │ │
│ │ - Guardar en learned_strategy.json │ │
│ │ - Actualizar reglas del router vLLM-SR │ │
│ │ - Registrar en logs │ │
│ └────────────────────────┬───────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌────────────────────────────────────────────────────────┐ │
│ │ 6. ESPERAR │ │
│ │ - Ciclo configurable (default: 1h) │ │
│ │ - Volver a paso 1 │ │
│ └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
---

## 3. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Bucle asíncrono con `asyncio`** | Bucle síncrono con `time.sleep` | Permite manejar timeouts, cancelaciones, y múltiples tareas en paralelo. |
| **Intervalo de 1 hora por defecto** | Ejecución continua | Evita sobrecarga. 1h es suficiente para acumular tráfico significativo. |
| **Umbral de mejora 10%** | Desplegar cualquier mejora | Evita cambios por ruido estadístico. Ajustable. |
| **Mínimo de 50 tareas antes de soñar** | Sin mínimo | Garantiza que el árbol tiene datos suficientes para ser significativo. |
| **100 simulaciones por estrategia** | 10 o 1000 | Balance entre precisión y tiempo de cómputo. 100 da intervalos de confianza razonables. |
| **5 estrategias propuestas por ciclo** | 1 o 20 | Balance entre exploración y foco. Ajustable. |
| **Guardar estrategias en JSON** | Base de datos | Simple, auditable, y versionable con Git si se desea. |
| **Despliegue guardando en archivo** | Actualización directa del router vía API | vLLM-SR no tiene hot-reload. Guardar + reiniciar router es más simple. |
| **Rotación de logs por ciclo** | Log único creciente | Facilita el análisis por ciclo y la depuración. |

---

## 4. Paso 1 — Implementar el Bucle

### 4.1 Estructura del archivo

**Crear `~/vllm-stack/replay/dream_rsi_loop.py`**:

```python
"""
Dream-RSI Loop — Bucle de auto-mejora recursiva.

Cada ciclo:
1. Carga historial (Router Replay + APEX-EM)
2. Construye árbol de descubrimiento
3. Meta-agente propone estrategias
4. Simula offline
5. Si mejora > umbral: despliega
6. Espera siguiente ciclo
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from dream_rsi_simulator import ReplaySimulator


# ── CONFIGURACIÓN ────────────────────────────────────────────

CONFIG = {
    # Ciclo
    "cycle_interval_seconds": 3600,       # 1 hora
    "min_tasks_before_dream": 50,          # Mínimo de nodos para soñar
    "improvement_threshold": 1.10,         # 10% de mejora sobre baseline

    # Dream
    "n_strategies": 5,                     # Estrategias a proponer
    "n_simulations": 100,                  # Simulaciones por estrategia

    # Rutas
    "replay_db": "~/vllm-stack/router/replay.db",
    "memory_dir": "~/.rsiaagent/memory",
    "strategy_output": "~/vllm-stack/router/learned_strategy.json",
    "log_dir": "~/vllm-stack/logs",

    # Logging
    "log_level": "INFO",
    "log_format": "%(asctime)s [%(levelname)s] %(message)s",
}


# ── LOGGING ──────────────────────────────────────────────────

def setup_logging() -> logging.Logger:
    """Configura logging a archivo y consola."""
    log_dir = Path(CONFIG["log_dir"]).expanduser()
    log_dir.mkdir(parents=True, exist_ok=True)

    log_file = log_dir / "dream_rsi_loop.log"

    logger = logging.getLogger("dream_rsi")
    logger.setLevel(CONFIG["log_level"])

    # Handler de archivo
    fh = logging.FileHandler(log_file)
    fh.setFormatter(logging.Formatter(CONFIG["log_format"]))
    logger.addHandler(fh)

    # Handler de consola
    ch = logging.StreamHandler()
    ch.setFormatter(logging.Formatter(CONFIG["log_format"]))
    logger.addHandler(ch)

    return logger


log = setup_logging()


# ── BUCLE PRINCIPAL ──────────────────────────────────────────

async def dream_rsi_cycle(cycle_count: int) -> Optional[dict]:
    """
    Ejecuta un ciclo completo de Dream-RSI.

    Returns:
        La mejor estrategia si se desplegó, None si no hubo mejora.
    """
    log.info(f"{'─' * 60}")
    log.info(f"CICLO {cycle_count}")
    log.info(f"{'─' * 60}")

    # 1. Cargar historial
    sim = ReplaySimulator(level=3)
    sim.load_history(
        replay_db_path=CONFIG["replay_db"],
        memory_path=CONFIG["memory_dir"]
    )

    n_nodes = len(sim.discovery_tree)
    log.info(f"Árbol de descubrimiento: {n_nodes} nodos")

    # 2. Verificar mínimo de tareas
    if n_nodes < CONFIG["min_tasks_before_dream"]:
        log.info(
            f"Insuficientes nodos ({n_nodes} < {CONFIG['min_tasks_before_dream']}). "
            f"Esperando más datos."
        )
        return None

    # 3. Proponer estrategias
    log.info("Soñando: proponiendo estrategias alternativas...")
    try:
        candidates = sim.propose_strategy_candidates(n=CONFIG["n_strategies"])
        log.info(f"Estrategias propuestas: {len(candidates)}")
    except Exception as e:
        log.error(f"Error al proponer estrategias: {e}")
        return None

    if not candidates:
        log.info("No se propusieron estrategias. Esperando siguiente ciclo.")
        return None

    # 4. Simular offline
    log.info(f"Simulando {len(candidates)} estrategias ({CONFIG['n_simulations']} sims cada una)...")
    try:
        best = sim.select_best_strategy(
            candidates,
            n_simulations=CONFIG["n_simulations"]
        )
    except Exception as e:
        log.error(f"Error al simular: {e}")
        return None

    if not best:
        log.info("⏸️  Sin mejora sobre baseline. Manteniendo estrategia actual.")
        return None

    # 5. Verificar umbral
    baseline = sim._compute_baseline()
    improvement = (
        best["success_rate"] / baseline["success_rate"]
        if baseline["success_rate"] > 0
        else 0
    )

    log.info(f"Mejor estrategia: {best['strategy']}")
    log.info(f"  Tasa de éxito: {best['success_rate']:.2%} (baseline: {baseline['success_rate']:.2%})")
    log.info(f"  Mejora: {improvement:.2f}x")
    log.info(f"  Tokens promedio: {best['avg_tokens_per_run']:.0f}")

    if improvement < CONFIG["improvement_threshold"]:
        log.info(
            f"⏸️  Mejora insuficiente "
            f"({improvement:.2f}x < {CONFIG['improvement_threshold']}x). No desplegando."
        )
        return None

    # 6. Desplegar
    log.info("✅ Mejora significativa. Desplegando estrategia...")
    try:
        sim.deploy_strategy(best)

        # Guardar metadata del ciclo
        metadata = {
            "cycle": cycle_count,
            "timestamp": datetime.now().isoformat(),
            "strategy": best,
            "baseline": baseline,
            "improvement": improvement,
            "n_nodes": n_nodes
        }

        metadata_path = Path(CONFIG["strategy_output"]).expanduser().parent / f"cycle_{cycle_count:04d}.json"
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)

        log.info(f"Metadata guardada en {metadata_path}")
        return best

    except Exception as e:
        log.error(f"Error al desplegar: {e}")
        return None


async def dream_rsi_loop():
    """Bucle principal infinito."""
    log.info("=" * 60)
    log.info("Iniciando Dream-RSI Loop")
    log.info(f"  Ciclo: cada {CONFIG['cycle_interval_seconds']}s")
    log.info(f"  Mínimo de nodos: {CONFIG['min_tasks_before_dream']}")
    log.info(f"  Umbral de mejora: {CONFIG['improvement_threshold']}x")
    log.info(f"  Estrategias por ciclo: {CONFIG['n_strategies']}")
    log.info(f"  Simulaciones por estrategia: {CONFIG['n_simulations']}")
    log.info("=" * 60)

    cycle_count = 0
    deployed_strategies = []

    while True:
        cycle_count += 1

        try:
            deployed = await dream_rsi_cycle(cycle_count)
            if deployed:
                deployed_strategies.append({
                    "cycle": cycle_count,
                    "strategy": deployed["strategy"],
                    "improvement": deployed.get("improvement", 0)
                })
        except KeyboardInterrupt:
            log.info("Bucle interrumpido por el usuario")
            break
        except Exception as e:
            log.error(f"Error en ciclo {cycle_count}: {e}", exc_info=True)

        log.info(f"Próximo ciclo en {CONFIG['cycle_interval_seconds']}s...")

        try:
            await asyncio.sleep(CONFIG["cycle_interval_seconds"])
        except asyncio.CancelledError:
            log.info("Bucle cancelado")
            break

    # Resumen final
    log.info("=" * 60)
    log.info(f"Bucle terminado tras {cycle_count} ciclos")
    log.info(f"Estrategias desplegadas: {len(deployed_strategies)}")
    for s in deployed_strategies:
        log.info(f"  - Ciclo {s['cycle']}: {s['strategy']} ({s['improvement']:.2f}x)")
    log.info("=" * 60)


# ── ENTRY POINT ──────────────────────────────────────────────

if __name__ == "__main__":
    try:
        asyncio.run(dream_rsi_loop())
    except KeyboardInterrupt:
        log.info("Bucle detenido por el usuario")
4.2 Verificar que el código carga
bash
cd ~/vllm-stack/replay

python -c "
from dream_rsi_loop import dream_rsi_loop, dream_rsi_cycle, CONFIG, log
print('Módulo cargado OK')
print(f'Intervalo: {CONFIG[\"cycle_interval_seconds\"]}s')
print(f'Umbral: {CONFIG[\"improvement_threshold\"]}x')
"
Salida esperada:

text
Módulo cargado OK
Intervalo: 3600s
Umbral: 1.1x
4.3 Ejecutar un solo ciclo (para verificar)
bash
cd ~/vllm-stack/replay

python -c "
import asyncio
from dream_rsi_loop import dream_rsi_cycle

result = asyncio.run(dream_rsi_cycle(cycle_count=1))
if result:
    print(f'Estrategia desplegada: {result[\"strategy\"]}')
else:
    print('Sin cambios en este ciclo')
"
Salida esperada (si hay suficientes datos):

text
[INFO] CICLO 1
[INFO] Árbol de descubrimiento: NNN nodos
[INFO] Soñando: proponiendo estrategias alternativas...
[INFO] Estrategias propuestas: 5
...
[INFO] ✅ Mejora significativa. Desplegando estrategia...
Salida esperada (si no hay suficientes datos):

text
[INFO] CICLO 1
[INFO] Árbol de descubrimiento: 12 nodos
[INFO] Insuficientes nodos (12 < 50). Esperando más datos.
Sin cambios en este ciclo
5. Paso 2 — Configurar Parámetros
5.1 Tabla completa de parámetros
Parámetro	Valor por defecto	Rango	Descripción
cycle_interval_seconds	3600 (1h)	600-86400	Frecuencia del ciclo
min_tasks_before_dream	50	10-500	Nodos mínimos para soñar
improvement_threshold	1.10	1.0-2.0	Mejora mínima para desplegar
n_strategies	5	1-20	Estrategias propuestas por ciclo
n_simulations	100	10-1000	Simulaciones por estrategia
log_level	INFO	DEBUG-ERROR	Nivel de detalle en logs
5.2 Guía de ajuste
Por volumen de tráfico:

Tráfico	Intervalo recomendado	Mínimo de nodos
Bajo (<100 req/día)	86400 (24h)	30
Medio (100-1000 req/día)	3600 (1h)	50
Alto (>1000 req/día)	1800 (30min)	100
Por tipo de uso:

Uso	Umbral	Estrategias
Exploración temprana	1.05	10
Producción estable	1.15	5
Experimentación	1.02	15
Por recursos:

Recurso	Simulaciones	Estrategias
WSL2 con poca RAM	50	3
WSL2 con RAM suficiente	100	5
Servidor dedicado	500	10
5.3 Modificar parámetros
Editar dream_rsi_loop.py:

python
CONFIG = {
    "cycle_interval_seconds": 1800,       # 30 minutos
    "min_tasks_before_dream": 100,
    "improvement_threshold": 1.15,
    "n_strategies": 7,
    "n_simulations": 200,
    ...
}
5.4 Cargar configuración desde .env
Para mayor flexibilidad, cargar desde ~/vllm-stack/.env:

python
import os
from dotenv import load_dotenv

load_dotenv(Path("~/vllm-stack/.env").expanduser())

CONFIG = {
    "cycle_interval_seconds": int(os.getenv("DREAM_CYCLE_INTERVAL", 3600)),
    "min_tasks_before_dream": int(os.getenv("DREAM_MIN_TASKS", 50)),
    "improvement_threshold": float(os.getenv("DREAM_THRESHOLD", 1.10)),
    "n_strategies": int(os.getenv("DREAM_N_STRATEGIES", 5)),
    "n_simulations": int(os.getenv("DREAM_N_SIMULATIONS", 100)),
    ...
}
Requiere:

bash
uv pip install python-dotenv
Añadir a ~/vllm-stack/.env:

bash
DREAM_CYCLE_INTERVAL=1800
DREAM_MIN_TASKS=100
DREAM_THRESHOLD=1.15
DREAM_N_STRATEGIES=7
DREAM_N_SIMULATIONS=200
6. Paso 3 — Lanzar el Bucle
6.1 Verificación previa
Antes de lanzar el bucle, verificar:

bash
# 1. Router corriendo
curl -s http://localhost:8888/v1/models > /dev/null && echo "✓ Router" || echo "✗ Router"

# 2. Meta-agente corriendo
curl -s http://localhost:8002/v1/models > /dev/null && echo "✓ Meta-agente" || echo "✗ Meta-agente"

# 3. Router Replay con registros
sqlite3 ~/vllm-stack/router/replay.db "SELECT COUNT(*) FROM router_replay" 2>/dev/null

# 4. Memoria APEX-EM
wc -l ~/.rsiaagent/memory/apex/procedural_traces.jsonl 2>/dev/null

# 5. Simulador funcional
cd ~/vllm-stack/replay && python -c "
from dream_rsi_simulator import ReplaySimulator
sim = ReplaySimulator(level=3)
sim.load_history('~/vllm-stack/router/replay.db', '~/.rsiaagent/memory')
print(f'Árbol: {len(sim.discovery_tree)} nodos')
"
Si todo responde ✓, proceder.

6.2 Lanzar en foreground (para debug)
bash
cd ~/vllm-stack/replay
source ~/vllm-stack/.venv/bin/activate

python dream_rsi_loop.py
Salida esperada (primeros segundos):

text
2026-09-17 20:45:00 [INFO] ============================================================
2026-09-17 20:45:00 [INFO] Iniciando Dream-RSI Loop
2026-09-17 20:45:00 [INFO]   Ciclo: cada 3600s
2026-09-17 20:45:00 [INFO]   Mínimo de nodos: 50
2026-09-17 20:45:00 [INFO]   Umbral de mejora: 1.1x
2026-09-17 20:45:00 [INFO]   Estrategias por ciclo: 5
2026-09-17 20:45:00 [INFO]   Simulaciones por estrategia: 100
2026-09-17 20:45:00 [INFO] ============================================================
2026-09-17 20:45:00 [INFO] ────────────────────────────────────────────────────────────
2026-09-17 20:45:00 [INFO] CICLO 1
2026-09-17 20:45:00 [INFO] ────────────────────────────────────────────────────────────
2026-09-17 20:45:01 [INFO] Routing history: NNN registros
...
Detener con Ctrl+C.

6.3 Lanzar en background
bash
cd ~/vllm-stack/replay

nohup python dream_rsi_loop.py > ~/vllm-stack/logs/dream_rsi_nohup.log 2>&1 &

echo "Dream-RSI Loop PID: $!"
echo "Log: ~/vllm-stack/logs/dream_rsi_loop.log"
echo "Nohup log: ~/vllm-stack/logs/dream_rsi_nohup.log"
6.4 Verificar que está corriendo
bash
ps aux | grep "dream_rsi_loop" | grep -v grep
Salida esperada:

text
juan  12345  0.5  1.2  ...  python dream_rsi_loop.py
6.5 Detener el bucle
bash
# Encontrar PID
ps aux | grep "dream_rsi_loop" | grep -v grep

# Matar
pkill -f "dream_rsi_loop"
7. Paso 4 — Monitorear el Bucle
7.1 Ver log en tiempo real
bash
tail -f ~/vllm-stack/logs/dream_rsi_loop.log
7.2 Ver últimos 100 ciclos
bash
grep "CICLO" ~/vllm-stack/logs/dream_rsi_loop.log | tail -100
7.3 Ver estrategias desplegadas
bash
grep "✅" ~/vllm-stack/logs/dream_rsi_loop.log
7.4 Ver errores
bash
grep -iE "(error|fail|exception)" ~/vllm-stack/logs/dream_rsi_loop.log
7.5 Rotación de logs
Para evitar que el log crezca indefinidamente, añadir rotación:

Editar setup_logging() en dream_rsi_loop.py:

python
from logging.handlers import RotatingFileHandler

def setup_logging() -> logging.Logger:
    log_dir = Path(CONFIG["log_dir"]).expanduser()
    log_dir.mkdir(parents=True, exist_ok=True)

    log_file = log_dir / "dream_rsi_loop.log"

    logger = logging.getLogger("dream_rsi")
    logger.setLevel(CONFIG["log_level"])

    # Rotación: 10 MB por archivo, 5 backups
    fh = RotatingFileHandler(
        log_file,
        maxBytes=10 * 1024 * 1024,
        backupCount=5
    )
    fh.setFormatter(logging.Formatter(CONFIG["log_format"]))
    logger.addHandler(fh)

    ch = logging.StreamHandler()
    ch.setFormatter(logging.Formatter(CONFIG["log_format"]))
    logger.addHandler(ch)

    return logger
7.6 Métricas del bucle
Añadir a un script de análisis:

python
import re
from pathlib import Path
from collections import Counter

log_file = Path("~/vllm-stack/logs/dream_rsi_loop.log").expanduser()

cycles = 0
deployed = 0
improvements = []

with open(log_file) as f:
    for line in f:
        if "CICLO" in line:
            cycles += 1
        if "✅ Mejora significativa" in line:
            deployed += 1
        match = re.search(r"Mejora: ([\d.]+)x", line)
        if match:
            improvements.append(float(match.group(1)))

print(f"Ciclos totales: {cycles}")
print(f"Estrategias desplegadas: {deployed}")
print(f"Tasa de despliegue: {deployed/cycles*100:.1f}%")
if improvements:
    print(f"Mejora promedio: {sum(improvements)/len(improvements):.2f}x")
    print(f"Mejora máxima: {max(improvements):.2f}x")
    print(f"Mejora mínima: {min(improvements):.2f}x")
8. Paso 5 — Verificar Estrategias Desplegadas
8.1 Ver estrategia actual
bash
cat ~/vllm-stack/router/learned_strategy.json | python -m json.tool
Salida esperada:

json
{
    "strategy": {
        "strategy": "prioritize_short_prompts",
        "avg_tokens_per_run": 245.3,
        "avg_time_per_run": 156.2,
        "success_rate": 0.87,
        "estimated_cost": 0.0245
    },
    "deployed_at": "2026-09-17T20:50:00"
}
8.2 Ver metadata de ciclos
bash
ls -lh ~/vllm-stack/router/cycle_*.json
Salida esperada:

text
-rw-r--r-- 1 juan juan 1234 Sep 17 20:50 cycle_0001.json
-rw-r--r-- 1 juan juan 1245 Sep 17 21:50 cycle_0002.json
...
8.3 Ver metadata de un ciclo específico
bash
cat ~/vllm-stack/router/cycle_0001.json | python -m json.tool
Salida esperada:

json
{
    "cycle": 1,
    "timestamp": "2026-09-17T20:50:00",
    "strategy": {
        "strategy": "prioritize_short_prompts",
        "avg_tokens_per_run": 245.3,
        "success_rate": 0.87
    },
    "baseline": {
        "success_rate": 0.72,
        "avg_tokens": 312.5
    },
    "improvement": 1.21,
    "n_nodes": 234
}
8.4 Comparar ciclos
python
import json
from pathlib import Path

router_dir = Path("~/vllm-stack/router").expanduser()
cycles = sorted(router_dir.glob("cycle_*.json"))

print(f"{'Ciclo':>6} {'Timestamp':<20} {'Estrategia':<25} {'Mejora':>8}")
print("-" * 65)

for cycle_file in cycles:
    with open(cycle_file) as f:
        data = json.load(f)
    print(f"{data['cycle']:>6} {data['timestamp'][:19]:<20} "
          f"{data['strategy']['strategy']:<25} {data['improvement']:>7.2f}x")
Salida esperada:

text
Ciclo Timestamp            Estrategia                  Mejora
-----------------------------------------------------------------
     1 2026-09-17T20:50:00 prioritize_short_prompts     1.21x
     2 2026-09-17T21:50:00 balance_load_between_models  1.15x
     3 2026-09-17T22:50:00 use_router_more_aggressively 1.08x
9. Paso 6 — Integrar con el Router
9.1 Cómo se aplican las estrategias
El bucle no modifica el router en tiempo real. En su lugar:

Guarda la estrategia en learned_strategy.json.

Tú (o un script externo) revisas la estrategia.

Si es razonable, actualizas config.yaml del router manualmente.

Reinicias el router.

¿Por qué manual?

Seguridad: cambios automáticos pueden degradar el servicio.

Auditoría: cada cambio queda registrado y revisable.

vLLM-SR no tiene hot-reload: requiere reinicio de todos modos.

9.2 Aplicar una estrategia
Ejemplo: la estrategia sugiere bajar el umbral de simple de 150 a 100 caracteres.

Editar ~/vllm-stack/router/config.yaml:

yaml
decisions:
  - name: simple
    priority: 100
    signals:
      - type: prompt_length
        operator: lt
        value: 100  # Antes era 150
    model: gemma-4-12b
Reiniciar el router:

bash
# Ctrl+C en la terminal del router
cd ~/vllm-stack/router
vllm-sr serve --config config.yaml
9.3 Automatizar el despliegue (opcional)
Crear ~/vllm-stack/replay/auto_deploy.py:

python
"""
Auto-deploy de estrategias aprendidas.

Lee learned_strategy.json y aplica cambios a config.yaml si son
estructuralmente válidos.
"""

import json
import yaml
from pathlib import Path


def load_learned_strategy() -> dict:
    path = Path("~/vllm-stack/router/learned_strategy.json").expanduser()
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def load_config() -> dict:
    path = Path("~/vllm-stack/router/config.yaml").expanduser()
    with open(path) as f:
        return yaml.safe_load(f)


def save_config(config: dict):
    path = Path("~/vllm-stack/router/config.yaml").expanduser()
    with open(path, 'w') as f:
        yaml.safe_dump(config, f, default_flow_style=False)


def apply_strategy(strategy: dict, config: dict) -> bool:
    """
    Aplica una estrategia al config.

    Returns:
        True si se aplicó algún cambio.
    """
    # Ejemplo: si la estrategia sugiere "prioritize_short_prompts",
    # bajar el umbral de simple
    name = strategy.get("strategy", "")

    if name == "prioritize_short_prompts":
        for decision in config.get("decisions", []):
            if decision["name"] == "simple":
                for signal in decision["signals"]:
                    if signal["type"] == "prompt_length":
                        old_value = signal["value"]
                        new_value = max(50, old_value - 25)
                        signal["value"] = new_value
                        print(f"  simple.prompt_length: {old_value} → {new_value}")
                        return True

    elif name == "use_router_more_aggressively":
        # Ajustar prioridades
        pass

    return Falseif __name__ == "__main__":
    learned = load_learned_strategy()
    if not learned:
        print("No hay estrategia aprendida.")
        exit(0)

    strategy = learned.get("strategy", {})
    print(f"Estrategia: {strategy.get('strategy', 'unknown')}")

    config = load_config()
    if apply_strategy(strategy, config):
        save_config(config)
        print("✓ Config actualizada. Reinicia el router para aplicar.")
    else:
        print("Sin cambios aplicables.")
Uso:

bash
cd ~/vllm-stack/replay
python auto_deploy.py
Reiniciar router:

bash
pkill -f "vllm-sr"
cd ~/vllm-stack/router
vllm-sr serve --config config.yaml &
9.4 Validar antes de aplicar
Añadir validación:

python
def validate_strategy(strategy: dict) -> bool:
    """Valida que una estrategia es estructuralmente válida."""
    if not strategy.get("strategy"):
        return False
    if strategy.get("success_rate", 0) < 0.5:
        return False
    if strategy.get("avg_tokens_per_run", 0) > 10000:
        return False
    return True
9.5 Rollback
Si una estrategia degrada el servicio, restaurar la anterior:

bash
# Backup antes de aplicar
cp ~/vllm-stack/router/config.yaml ~/vllm-stack/router/config.yaml.bak

# Rollback
cp ~/vllm-stack/router/config.yaml.bak ~/vllm-stack/router/config.yaml
pkill -f "vllm-sr"
cd ~/vllm-stack/router
vllm-sr serve --config config.yaml &
10. Paso 7 — Ciclo de Vida Completo
10.1 Día 1: Setup
Instalar stack (Fases 1-7).

Instalar RSIAgent (Fase 8).

Ejecutar BRS + DRS + Test.

Implementar simulador (Fase 9).

Lanzar bucle Dream-RSI (Fase 10).

Esperar.

10.2 Día 2-7: Acumulación
El bucle corre cada hora.

El router acumula tráfico.

El árbol de descubrimiento crece.

Las primeras estrategias se despliegan.

10.3 Semana 2-4: Maduración
El bucle converge a estrategias estables.

La tasa de mejora se estabiliza.

Los ciclos con despliegue son menos frecuentes.

10.4 Mes 2+: Mantenimiento
Revisar logs periódicamente.

Ajustar parámetros según uso.

Considerar migrar a PostgreSQL si replay.db crece mucho.

Considerar añadir más modelos si el uso crece.

10.5 Señales de que el bucle necesita ajuste
Señal	Ajuste
0 despliegues en 24h	Bajar improvement_threshold a 1.05
Muchos despliegues con poca mejora	Subir improvement_threshold a 1.20
Bucle tarda >5 min por ciclo	Reducir n_simulations a 50
replay.db >100 MB	Migrar a PostgreSQL
Estrategias contradictorias	Aumentar min_tasks_before_dream
11. Checklist Final
Antes de considerar el stack completo, verificar:

Implementación
□ dream_rsi_loop.py creado en ~/vllm-stack/replay/
□ Módulo carga sin errores
□ CONFIG con todos los parámetros
□ Logging configurado con rotación
Ejecución
□ Un ciclo manual ejecuta sin errores
□ Bucle en background lanzado
□ PID verificable con ps aux
□ Log escribiéndose en dream_rsi_loop.log
Monitoreo
□ tail -f funciona
□ Ciclos visibles en logs
□ Errores visibles con grep
□ Rotación de logs funcional
Despliegue
□ learned_strategy.json actualizado tras despliegue
□ cycle_NNNN.json guardados
□ Estrategia aplicable al router
□ Rollback funcional
Integración
□ auto_deploy.py funciona
□ Validación de estrategias
□ Backup antes de cambios
□ Router reiniciado tras cambios
12. Advertencias Críticas
12.1 El bucle consume tokens del meta-agente
Cada ciclo hace 1 llamada al meta-agente (Qwen 3.5 4B) para proponer estrategias. Con 24 ciclos al día, son ~24 llamadas de ~2000 tokens cada una. Coste insignificante localmente.

12.2 No lanzar el bucle si el stack no está estable
Si el router tiene errores o los modelos fallan, el bucle registrará datos ruidosos y propondrá estrategias incorrectas.

12.3 Revisar las estrategias antes de aplicarlas
El bucle no aplica cambios automáticamente por defecto. Guarda la estrategia en un archivo y espera revisión humana. Esto evita degradaciones.

12.4 El bucle no detecta cambios en el hardware
Si cambias GPU o RAM, los umbrales del bucle siguen siendo válidos, pero las estrategias aprendidas pueden no ser óptimas. Reiniciar el bucle tras cambios de hardware.

12.5 Logs pueden crecer rápido
Con log_level=DEBUG, los logs pueden llenar el disco en días. Mantener INFO por defecto y usar rotación.

12.6 El bucle no debe correr 24/7 sin supervisión
Revisar logs al menos una vez al día. Si hay errores repetidos, detener el bucle y diagnosticar.

12.7 No ejecutar múltiples instancias del bucle
Dos procesos dream_rsi_loop.py corriendo simultáneamente causarán conflictos al leer y escribir archivos. Verificar con ps aux | grep dream_rsi antes de lanzar.

12.8 La memoria persistente puede crecer indefinidamente
Con muchos ciclos, procedural_traces.jsonl puede volverse grande. Añadir purga periódica por TTL:

python
def purge_old_traces(max_age_days: int = 30):
    """Elimina trazas más antiguas que max_age_days."""
    from datetime import datetime, timedelta
    cutoff = datetime.now() - timedelta(days=max_age_days)
    traces_file = Path("~/.rsiaagent/memory/apex/procedural_traces.jsonl").expanduser()
    # Implementar lógica de purga
12.9 El bucle no reemplaza al monitoreo manual
Los logs te dicen qué pasó. La revisión humana te dice si es correcto. Combinar ambos.

12.10 Considerar límites de CPU
El bucle usa el meta-agente (Qwen 3.5 4B) que compite con el resto del stack por VRAM. Si el stack está saturado, el bucle puede fallar. Ejecutar en horarios de baja actividad o pausar el bucle durante picos.

13. Referencias
Recurso	URL
Dream-RSI	https://dream-rsi.com/
RSIAgent	https://github.com/AetherLabsAI/RSIAgent
APEX-EM	https://ar5iv.labs.arxiv.org/html/2603.29093
LIMBO	https://arxiv.org/abs/2603.xxxxx
Router Replay	https://docs.vllm.ai/en/latest/serving/router_replay.html
asyncio	https://docs.python.org/3/library/asyncio.html
RotatingFileHandler	https://docs.python.org/3/library/logging.handlers.html#rotatingfilehandler
python-dotenv	https://github.com/theskumar/python-dotenv
PyYAML	https://pyyaml.org/
Próximos pasos
Con este documento, el stack completo está documentado:

Fase	Archivo	Propósito
1	01-TOOLS.md	Entorno base (WSL2 + Docker Engine)
2	02-vLLM-Installation.md	vLLM + b12x + kernels SM120
3	03-Model-Download.md	Descarga de los 3 modelos
4	04-vLLM-Serving.md	3 servidores + Sleep Mode
5	05-Semantic-Router.md	Enrutamiento + Router Replay
6	06-Multi-Agent-Integration.md	API + concurrencia + túnel
7	07-Troubleshooting.md	Diagnóstico por capas
8	08-RSIAgent-Integration.md	Auto-mejora (RSI)
9	09-Replay-Simulator.md	Simulador de 3 niveles
10	10-Dream-RSI-Loop.md	Bucle de auto-mejora recursiva
El stack completo ofrece:

Inferencia local de 3 modelos especializados.

Enrutamiento semántico automático.

Concurrencia multiagente con Continuous Batching.

Sleep Mode para gestión de VRAM.

Router Replay para auditoría.

Memoria procedural (APEX-EM) para reutilización.

Dream-RSI para auto-mejora recursiva.

Túnel Cloudflare para acceso remoto seguro.

Próximas mejoras opcionales:

Migrar a PostgreSQL si replay.db supera 100 MB.

Añadir más modelos (Mistral, Llama) si el uso crece.

Implementar fine-tuning (LoRA) si la memoria procedural no es suficiente.

Distribuir el stack en múltiples GPUs si están disponibles.

Integrar con LangChain o LlamaIndex para flujos más complejos.
