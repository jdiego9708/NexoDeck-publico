# 00-README.md

vLLM Multi-Agent Stack — RTX 5060 Ti (SM120)

Stack de inferencia LLM local con vLLM para múltiples agentes concurrentes, con enrutamiento semántico, kernels NVFP4/AWQ adaptados a SM120, y una capa de auto-mejora recursiva (RSIAgent + Dream-RSI).

---

## Hardware Objetivo

| Componente | Valor |
|:---|:---|
| **GPU** | NVIDIA RTX 5060 Ti 16 GB (Blackwell, compute_cap **12.0** / SM120) |
| **CPU** | AMD Ryzen 7 5700X (8c/16t) |
| **RAM** | 32 GB DDR4 |
| **Driver** | NVIDIA 591.86 / CUDA 13.1 |
| **OS** | Windows 11 Pro (Build 26200) |
| **WSL2** | v2.7.13 con Ubuntu |
| **Docker** | v29.8.1 (Docker Engine dentro de Ubuntu; Docker Desktop desinstalado, ver `11-mejoras-y-decisiones.md`) |
| **Python** | 3.12.10 (global en `D:\DevTools\Python312`) |
| **PyTorch** | 2.11.0+cu128 (venv `palm-training`) |

---

## Arquitectura del Stack
Tu App / Agentes
│
▼
┌──────────────────────────────────┐
│ vLLM Semantic Router (8888) │
│ ├─ Meta-agente: Qwen 3.5 4B │
│ │ (NVFP4, puerto 8002) │
│ ├─ Rápido: Gemma 4 12B │
│ │ (AWQ, puerto 8001) │
│ └─ Complejo: Qwen3-Coder-30B │
│ (NVFP4, puerto 8000) │
│ ├─ Texto (perfil C): Qwen 3.5 9B │
│ (AWQ, puerto 8003) │
└──────────────────────────────────┘
│
▼
┌──────────────────────────────────┐
│ RSIAgent (puerto 8890) │
│ ├─ Curriculum Agent (Qwen 4B) │
│ ├─ Actor Agent (Gemma/Qwen3) │
│ └─ Verifier Agent (Qwen 4B) │
└──────────────────────────────────┘
│
▼
┌──────────────────────────────────┐
│ Simulador de Replay — 3 Niveles │
│ ├─ Nivel 1: Básico (vLLM-SR) │
│ ├─ Nivel 2: Moderado (APEX-EM) │
│ └─ Nivel 3: Alto (Dream-RSI) │
└──────────────────────────────────┘
│
▼
RTX 5060 Ti 16 GB (SM120)
Sleep Mode + Continuous Batching

---

## Modelos y Cuantizaciones — Decisión Estratégica

| Rol | Modelo | Cuantización | Motor de Kernel | VRAM | Contexto | Uso |
|:---|:---|:---|:---|:---|:---|:---|
| **Enrutamiento** | Qwen 3.5 4B | **NVFP4** | b12x / FlashInfer | ~2.5 GB | 16k | Clasificación, tool-calling, meta-agente |
| **Rápido** | Gemma 4 12B | **AWQ (W4A16)** | **Marlin** | ~7 GB | 32k | Autocompletado, edición, consultas |
| **Complejo** | Qwen3-Coder-30B-A3B REAP-50 | **NVFP4** | b12x | ~10 GB | 16k | Razonamiento, arquitectura, debugging |
| **Texto (perfil C)** | Qwen 3.5 9B | **AWQ (W4A16)** | Marlin | ~11.5 GB | 32k | Preguntas, redaccion y conocimiento general. **Corre solo**, con la GPU entera |

### ¿Por qué esta combinación de cuantizaciones?

**1. Modelo Rápido → AWQ (no NVFP4)**

El benchmark independiente sobre RTX 5090 (SM120, misma arquitectura que tu 5060 Ti) muestra que **AWQ int4 con Marlin es sistemáticamente más rápido que NVFP4** en decode:

| Cuantización | Kernel | batch 1 | batch 8 | batch 32 |
|:---|:---|:---|:---|:---|
| **AWQ int4** | **awq-marlin** | **150 tok/s** | **1188 tok/s** | **3937 tok/s** |
| FP8 | fp8-marlin | 90 tok/s | 711 tok/s | 2647 tok/s |
| NVFP4 | nvfp4 cutlass (JIT) | 100 tok/s | 801 tok/s | 3321 tok/s |

AWQ es **50% más rápido en batch-1** y **18% más rápido en batch-32** que NVFP4. Además, **no requiere JIT compilation** (Marlin usa kernels precompilados), lo que elimina los 2-5 minutos de arranque que sí necesita NVFP4.

**2. Enrutador → NVFP4**

Para el meta-agente, la **precisión de clasificación** es más importante que la velocidad pura. NVFP4 preserva mejor las capacidades de razonamiento y tool-calling que AWQ en modelos pequeños (4B), y su huella es mínima (~2.5 GB). Existen checkpoints NVFP4 de Qwen 3.5 4B listos para usar.

**3. Modelo Complejo → NVFP4**

Qwen3-Coder-30B es un MoE (64 expertos/layer, top-8). b12x soporta MoE NVFP4 en SM120. La combinación REAP-50 (pruning) + NVFP4 deja el modelo en ~9.9 GB, permitiendo contexto de 16k con margen para KV cache.

---

## Capacidad Real Multiagente

| Escenario | Modelo | Contexto | Agentes Concurrentes | VRAM estimada |
|:---|:---|:---|:---|:---|
| **Solo router + rápido** | Qwen 4B + Gemma 12B | 16k + 32k | 8-12 | ~9.5 GB |
| **Solo complejo** | Qwen3-Coder-30B | 16k | 4-6 | ~12 GB |
| **Mixto (Sleep Mode)** | Cualquiera | Variable | 3-4 por modelo | ~15 GB máx |

**Cálculo**: Qwen3-Coder-30B NVFP4 ocupa ~9.9 GB de pesos. Con 16 GB totales quedan ~5 GB para KV cache, overhead y contexto. A 16k tokens, cada agente consume ~0.7-1 GB de KV cache.

---

## Fases del Plan

| Fase | Archivo | Descripción | Tiempo |
|:---|:---|:---|:---|
| 1 | `01-WSL2-Docker-Setup.md` | WSL2 + Docker + NVIDIA Toolkit | 15 min |
| 2 | `02-vLLM-Installation.md` | vLLM + b12x + verificación SM120 | 20 min |
| 3 | `03-Model-Download.md` | Descarga de 3 modelos (NVFP4 + AWQ) | 45-90 min |
| 4 | `04-vLLM-Serving.md` | 3 servidores vLLM + Sleep Mode | 15 min |
| 5 | `05-Semantic-Router.md` | Enrutamiento simple/normal/complex/meta | 10 min |
| 6 | `06-Multi-Agent-Integration.md` | Endpoints OpenAI + túnel | 20 min |
| 7 | `07-Troubleshooting.md` | Errores SM120 y soluciones | Referencia |
| 8 | `08-RSIAgent-Integration.md` | **NUEVO** — Framework de auto-mejora | 20 min |
| 9 | `09-Replay-Simulator.md` | **NUEVO** — Simulador de 3 niveles | 30 min |
| 10 | `10-Dream-RSI-Loop.md` | **NUEVO** — Bucle de auto-mejora recursiva | 20 min |
| 11 | `11-mejoras-y-decisiones.md` | **Leer primero**: estado real del equipo, correcciones a esta receta, plan de medición y bitácora | Referencia |
| — | `llm-stack/scripts/` | Scripts reutilizables de todo lo ejecutado (`llm-stack/scripts/README.md`) | — |

---

## Advertencias Críticas

1. **b12x debe seleccionarse explícitamente** con `--linear-backend b12x --moe-backend b12x`. La auto-selección lo omite en SM120.
2. **Versión pinneada de b12x**: usar la que vLLM instala (1.2.6), NO la de PyPI (1.3.0).
3. **WSL2 asigna solo 50% de RAM por defecto** (16 GB de 32 GB). Editar `.wslconfig`.
4. **NVFP4 requiere JIT compilation** en el primer arranque (2-5 min). AWQ NO.
5. **b12x no cubre capas densas W4A16** — esas siguen en Marlin.
6. **El techo real es 16 GB de VRAM**, no SM120.

---

## Referencias

| Recurso | URL |
|:---|:---|
| vLLM Docs | https://docs.vllm.ai |
| vLLM b12x quantization | https://docs.vllm.ai/en/latest/features/quantization/b12x.html |
| vLLM-SR | https://vllm-sr.ai |
| RSIAgent | https://github.com/AetherLabsAI/RSIAgent |
| APEX-EM | https://ar5iv.labs.arxiv.org/html/2603.29093 |
| Modelo complejo | https://huggingface.co/AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4 |
| Modelo rápido (AWQ) | https://huggingface.co/mattbucci/gemma-4-12B-AWQ |
| Router (NVFP4) | https://huggingface.co/AxionML/Qwen3.5-4B-NVFP4 |
| Router (AWQ) | https://huggingface.co/QuantTrio/Qwen3.5-4B-AWQ |
| Benchmark AWQ vs NVFP4 | https://huggingface.co/datasets/witcheer/rtx-5090-benchmarks |