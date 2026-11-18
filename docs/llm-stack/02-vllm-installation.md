---
date: 2026-09-17
---
# 02-vLLM-Installation

# 02-vLLM-Installation — Instalación de vLLM con Kernels b12x para SM120

Documentación completa para instalar vLLM con soporte nativo de NVFP4 y AWQ en tu RTX 5060 Ti (Blackwell, SM120). Incluye la instalación del backend `b12x`, la verificación de kernels, y los criterios exactos para confirmar que el entorno está listo para servir modelos.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Decisiones Arquitectónicas](#2-decisiones-arquitectónicas)
3. [Paso 1 — Crear Entorno Virtual con uv](#3-paso-1--crear-entorno-virtual-con-uv)
4. [Paso 2 — Instalar vLLM con Backend CUDA 13.0](#4-paso-2--instalar-vllm-con-backend-cuda-130)
5. [Paso 3 — Instalar b12x (Kernels NVFP4 Nativos)](#5-paso-3--instalar-b12x-kernels-nvfp4-nativos)
6. [Paso 4 — Pinear nvidia-cutlass-dsl](#6-paso-4--pinear-nvidia-cutlass-dsl)
7. [Paso 5 — Verificar Kernels para SM120](#7-paso-5--verificar-kernels-para-sm120)
8. [Paso 6 — Verificar Selección Explícita de Backends](#8-paso-6--verificar-selección-explícita-de-backends)
9. [Paso 7 — Recopilar Información del Entorno](#9-paso-7--recopilar-información-del-entorno)
10. [Paso 8 — Matriz de Cuantizaciones Soportadas](#10-paso-8--matriz-de-cuantizaciones-soportadas)
11. [Checklist Final](#11-checklist-final)
12. [Advertencias Críticas](#12-advertencias-críticas)
13. [Referencias](#13-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `01-TOOLS.md`. Debes tener:

- WSL2 con Ubuntu funcionando.
- Docker Engine 29.x instalado (no Docker Desktop).
- NVIDIA Container Toolkit configurado.
- GPU RTX 5060 Ti accesible desde WSL2 y desde contenedores Docker.
- Compute capability reportada como **12.0**.
- Directorios `~/vllm-stack/` y `~/models/` creados.

El objetivo de esta fase es **instalar vLLM y sus kernels optimizados para Blackwell** dentro de un entorno virtual Python (no en el contenedor Docker todavía; el contenedor se usará en fases posteriores para servir modelos, pero aquí instalamos vLLM en el host WSL2 para poder verificar la instalación con `vllm collect-env` y otros comandos de diagnóstico).

### ¿Por qué instalar vLLM en el host WSL2 si vamos a usar Docker?

Hay dos razones:

1. **Diagnóstico temprano**: Es más fácil verificar versiones, kernels y compatibilidad sin la capa de Docker. Si algo falla aquí, sabes que es un problema de instalación, no de contenedor.
2. **Fallback para desarrollo**: Puedes usar vLLM directamente desde el host para pruebas rápidas, sin arrancar contenedores.

En la **Fase 4** (serving), los modelos se servirán desde contenedores Docker con la imagen oficial `vllm/vllm-openai:latest`, usando las mismas versiones que verifiques aquí.

---

## 2. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Entorno virtual con `uv`** | `pip` + `venv` estándar | `uv` es 10-100x más rápido, resuelve dependencias mejor, y permite fijar el backend CUDA correctamente |
| **Python 3.12** | 3.10, 3.11, 3.13 | vLLM 0.29+ soporta 3.10–3.13, pero 3.12 es el más estable con CUDA 13 y kernels b12x |
| **Backend CUDA 13.0** | CUDA 12.x | SM120 (Blackwell) requiere CUDA 13.0 para kernels NVFP4 y b12x |
| **b12x como dependencia opcional** | PyPI directo | vLLM pinea a una versión específica (1.2.6). Instalar desde PyPI trae 1.3.0, que tiene problemas de compatibilidad |
| **Cutlass DSL pineado a 4.4.2** | 4.5.0 | 4.5.0 genera PTX incorrecto para SM121 |
| **Selección explícita de backend** | Auto-selección | La auto-selección de vLLM omite b12x en SM120 y cae en Marlin |

---

## 3. Paso 1 — Crear Entorno Virtual con uv

### 3.1 ¿Qué es `uv`?

`uv` es un gestor de paquetes y entornos virtuales Python escrito en Rust. Es un reemplazo directo de `pip` y `venv`, pero 10-100x más rápido y con mejor resolución de dependencias.

### 3.2 ¿Por qué `uv` y no `pip`?

- **Velocidad**: Resuelve e instala dependencias en segundos en lugar de minutos.
- **Resolución determinista**: Genera un `uv.lock` que garantiza reproducibilidad.
- **Manejo correcto de backends CUDA**: `uv pip install --torch-backend=cu130` instala automáticamente la versión correcta de PyTorch con el backend CUDA especificado.
- **Sin conflictos de dependencias**: Resuelve el grafo completo antes de instalar.

curl -LsSf https://astral.sh/uv/install.sh | sh
Recargar el PATH:

bash
source $HOME/.local/bin/env
Verificar:

bash
uv --version
Salida esperada: uv 0.9.x (o superior).

3.4 Crear directorio y entorno virtual
bash
# Ir al directorio del stack
cd ~/vllm-stack

# Crear venv con Python 3.12
uv venv --python 3.12 --seed

# Activar el venv
source .venv/bin/activate
Verificar:

bash
python --version
which python
Salida esperada:

text
Python 3.12.x
/home/juan/vllm-stack/.venv/bin/python
Nota: --seed instala pip y setuptools dentro del venv, por si alguna herramienta los requiere. No es estrictamente necesario con uv, pero evita problemas con paquetes antiguos.

4. Paso 2 — Instalar vLLM con Backend CUDA 13.0
4.1 ¿Por qué CUDA 13.0?
SM120 (Blackwell) requiere CUDA 13.0 para que los kernels NVFP4 y b12x funcionen correctamente. El wheel estándar de PyPI puede usar CUDA 12.x y fallar con:

text
RuntimeError: no kernel image is available for execution on the device
Este error indica que el binario compilado no incluye soporte para SM120.

4.2 Instalación
Con el venv activado:

bash
uv pip install vllm --torch-backend=cu130
¿Qué hace --torch-backend=cu130?

Le dice a uv que instale la versión de PyTorch compilada con CUDA 13.0. Esto garantiza que:

Los kernels nativos incluyan soporte para SM120.

Los bindings de CUDA coincidan con tu driver 591.86 / CUDA 13.1.

No haya conflictos entre la versión de PyTorch y los kernels de vLLM.

4.3 Verificar la instalación
bash
python -c "import vllm; print(f'vLLM: {vllm.__version__}')"
Salida esperada: vLLM: 0.29.x (o superior).

bash
python -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA disponible: {torch.cuda.is_available()}'); print(f'Compute Capability: {torch.cuda.get_device_capability(0)}')"
Salida esperada:

text
PyTorch: 2.13.x+cu130
CUDA disponible: True
Compute Capability: (12, 0)
Si torch.cuda.is_available() devuelve False:

Verifica que nvidia-smi funciona en WSL2.

Verifica que el venv está activado.

Reinstala PyTorch con el backend correcto:

bash
uv pip uninstall torch torchvision torchaudio
uv pip install torch --torch-backend=cu130
Si Compute Capability no es (12, 0):

Verifica el driver NVIDIA en Windows (debe ser 570.x o superior).

Verifica que WSL2 está usando el driver correcto (nvidia-smi dentro de WSL2).

5. Paso 3 — Instalar b12x (Kernels NVFP4 Nativos)
5.1 ¿Qué es b12x?
Es una librería de kernels CUDA optimizados para GPUs NVIDIA SM120 y SM121 (familia Blackwell). Proporciona:

NVFP4 dense GEMM para capas lineales.

NVFP4 MoE fused para modelos Mixture-of-Experts.

FP8 block-scaled para cuantización FP8.

MXFP8 para formatos microscaling.

Sin b12x, vLLM cae en Marlin para NVFP4, que es funcional pero significativamente más lento (2-3x menos throughput).

5.2 ¿Por qué instalar como dependencia opcional de vLLM?
vLLM pinea a una versión específica de b12x (actualmente 1.2.6). Si instalas directamente desde PyPI, obtienes 1.3.0, que tiene incompatibilidades con los bindings de vLLM y puede causar errores como:

text
AttributeError: module 'b12x' has no attribute 'cutlass_scaled_mm'
Instalar como dependencia opcional garantiza que obtienes la versión correcta.

5.3 Instalación
bash
uv pip install "vllm[b12x]"
¿Qué hace?

Instala b12x con la versión pineada por vLLM.

Instala dependencias adicionales (nvidia-cutlass-dsl, flashinfer, etc.) en versiones compatibles.

Configura los registros de kernels para que vLLM los detecte automáticamente.

5.4 Verificar versión exacta
bash
python -c "import b12x; print(f'b12x: {b12x.__version__}')"
Salida esperada: b12x: 1.2.6.

Si muestra 1.3.0:

bash
uv pip uninstall b12x
uv pip install "vllm[b12x]" --reinstall
5.5 Verificar que b12x detecta SM120
bash
python << 'EOF'
from vllm.model_executor.kernels.linear.nvfp4.b12x import B12xNvFp4LinearKernel

ok, reason = B12xNvFp4LinearKernel.is_supported(compute_capability=120)
print(f'b12x NVFP4 soportado: {ok}')
print(f'Razón: {reason}')
EOF
Salida esperada:

text
b12x NVFP4 soportado: True
Razón: None
Si ok es False, la razón indicará el problema:

"B12X kernels require a Blackwell 12x device" → El compute capability no es 12.x. Verifica con nvidia-smi.

"b12x library not found" → La instalación falló. Reinstala con uv pip install "vllm[b12x]" --reinstall.

"cutlass-dsl version mismatch" → La versión de nvidia-cutlass-dsl es incorrecta. Ve al paso 6.

5.6 Verificar kernels FP8 y MXFP8
bash
python << 'EOF'
from vllm.model_executor.kernels.linear.scaled_mm.b12x import B12xFp8BlockScaledMMKernel
from vllm.model_executor.kernels.linear.mxfp8.b12x import B12xMxfp8LinearKernel

fp8_ok, fp8_reason = B12xFp8BlockScaledMMKernel.is_supported(compute_capability=120)
print(f'B12X FP8: {fp8_ok} — {fp8_reason}')

mxfp8_ok, mxfp8_reason = B12xMxfp8LinearKernel.is_supported(compute_capability=120)
print(f'B12X MXFP8: {mxfp8_ok} — {mxfp8_reason}')
EOF
Salida esperada:

text
B12X FP8: True — None
B12X MXFP8: True — None
Ambos deben ser True.

6. Paso 4 — Pinear nvidia-cutlass-dsl
6.1 ¿Qué es nvidia-cutlass-dsl?
Es una librería de NVIDIA que permite escribir kernels CUDA en Python usando el DSL (Domain-Specific Language) de CUTLASS. b12x la usa para compilar kernels NVFP4 en tiempo de ejecución (JIT).

6.2 ¿Por qué pinear a 4.4.2?
La versión 4.5.0 de nvidia-cutlass-dsl tiene un bug que genera PTX (Parallel Thread Execution, el assembly de NVIDIA) incorrecto para SM121, y también afecta a SM120 en ciertos casos. Esto produce errores como:

text
CUDA error: an illegal instruction was encountered
o

text
RuntimeError: Failed to compile kernel with cutlass-dsl
La versión 4.4.2 es la última verificada como estable para SM120.

6.3 Verificar versión actual
bash
python -c "import cutlass; print(f'cutlass-dsl: {cutlass.__version__}')"
Si muestra 4.5.0 o superior, pinealo:

bash
uv pip install \
  nvidia-cutlass-dsl==4.4.2 \
  nvidia-cutlass-dsl-libs-base==4.4.2 \
  nvidia-cutlass-dsl-libs-cu13==4.4.2
6.4 Verificar pineado
bash
python -c "import cutlass; print(f'cutlass-dsl: {cutlass.__version__}')"
Salida esperada: cutlass-dsl: 4.4.2.

7. Paso 5 — Verificar Kernels para SM120
7.1 Matriz de kernels disponibles
Kernel	Backend	Cuantización	Uso
B12xNvFp4LinearKernel	b12x	NVFP4	Dense GEMM para capas lineales
B12xFp8BlockScaledMMKernel	b12x	FP8	Block-scaled K128 GEMM
B12xMxfp8LinearKernel	b12x	MXFP8	Microscaling FP8
FlashInferCuteDSLSM12xExperts	flashinfer	NVFP4	MoE fused (expertos)
Marlin	marlin	AWQ, GPTQ, FP8	Dense W4A16 (fallback)
7.2 Limitaciones documentadas de b12x
❌ Dense W4A16 no soportado → esas capas van a Marlin automáticamente.

❌ MoE b12x sin expert parallelism → irrelevante con 1 GPU (TP=1).

❌ MoE b12x solo NVFP4 o MXFP4 → no soporta otros formatos.

✅ JIT compila y cachea en el primer uso (lento la primera vez).

7.3 Verificar kernels cargados
bash
python << 'EOF'
from vllm.model_executor.kernels.linear.nvfp4.b12x import B12xNvFp4LinearKernel
from vllm.model_executor.kernels.linear.scaled_mm.b12x import B12xFp8BlockScaledMMKernel
from vllm.model_executor.kernels.linear.mxfp8.b12x import B12xMxfp8LinearKernel

kernels = {
    "NVFP4": B12xNvFp4LinearKernel,
    "FP8": B12xFp8BlockScaledMMKernel,
    "MXFP8": B12xMxfp8LinearKernel,
}

print("Kernels b12x disponibles en SM120:")
for name, kernel in kernels.items():
    ok, reason = kernel.is_supported(compute_capability=120)
    status = "✓" if ok else "✗"
    print(f"  {status} {name}: {ok} {reason if reason else ''}")
EOF
Salida esperada:

text
Kernels b12x disponibles en SM120:
  ✓ NVFP4: True
  ✓ FP8: True
  ✓ MXFP8: True
8. Paso 6 — Verificar Selección Explícita de Backends
8.1 ¿Por qué es crítico?
La documentación oficial de vLLM confirma que b12x no se selecciona automáticamente en SM120. El backend auto omite b12x y cae en Marlin.

Esto significa que si no especificas explícitamente --linear-backend b12x --moe-backend b12x, perderás el rendimiento de los kernels nativos.

8.2 Verificar que los flags existen
bash
vllm serve --help | grep -A2 "linear-backend"
vllm serve --help | grep -A2 "moe-backend"
Salida esperada (abreviada):

text
--linear-backend {auto,b12x,marlin,...}
                      Backend for linear layers. (default: auto)
--moe-backend {auto,b12x,marlin,...}
                      Backend for MoE layers. (default: auto)
Si b12x no aparece en las opciones:

b12x no se instaló correctamente. Reinstala con uv pip install "vllm[b12x]".

La versión de vLLM es demasiado antigua (<0.24). Actualiza con uv pip install --upgrade vllm.

8.3 Verificar auto-selección
bash
python << 'EOF'
from vllm.model_executor.kernels.linear.nvfp4 import get_nvfp4_linear_kernel

# Simular auto-selección para SM120
kernel = get_nvfp4_linear_kernel(compute_capability=120, backend="auto")
print(f"Kernel auto-seleccionado: {kernel.__class__.__name__}")

# Simular selección explícita b12x
kernel_b12x = get_nvfp4_linear_kernel(compute_capability=120, backend="b12x")
print(f"Kernel b12x explícito: {kernel_b12x.__class__.__name__}")
EOF
Salida esperada:

text
Kernel auto-seleccionado: MarlinNvFp4LinearKernel
Kernel b12x explícito: B12xNvFp4LinearKernel
Esto confirma que la auto-selección no elige b12x. Debes forzarlo explícitamente al lanzar servidores.

9. Paso 7 — Recopilar Información del Entorno
9.1 ¿Por qué?
vllm collect-env genera un informe completo con versiones de CUDA, PyTorch, Transformers, kernels disponibles, y configuración del sistema. Es útil para:

Diagnóstico de problemas.

Reportar bugs a vLLM.

Comparar entornos entre máquinas.

9.2 Ejecutar
bash
vllm collect-env > ~/vllm-stack/logs/env-report.txt
9.3 Verificar contenido
bash
head -60 ~/vllm-stack/logs/env-report.txt
Salida esperada (parcial):

text
Collecting environment information...
PyTorch version: 2.13.x+cu130
Is debug build: False
CUDA used to build PyTorch: 13.0
...
vLLM version: 0.29.x
...
GPU properties:
  Name: NVIDIA GeForce RTX 5060 Ti
  Compute capability: 12.0
  Total memory: 16.00 GB
...
Kernels available:
  - B12xNvFp4LinearKernel: True
  - B12xFp8BlockScaledMMKernel: True
  - B12xMxfp8LinearKernel: True
  - MarlinNvFp4LinearKernel: True
...
9.4 Guardar para referencia
Este archivo es tu "foto" del entorno. Guárdalo. Si algo falla en fases posteriores, compáralo con el estado actual.

10. Paso 8 — Matriz de Cuantizaciones Soportadas
10.1 Resumen de formatos
Cuantización	Motor en SM120	Precisión	Velocidad (batch-1)	Velocidad (batch-32)	Uso recomendado
NVFP4	b12x / FlashInfer	Pérdida mínima	~100 tok/s	~3321 tok/s	Router + modelo complejo
AWQ (INT4)	Marlin	Pérdida baja	~150 tok/s	~3937 tok/s	Modelo rápido
FP8	b12x / Marlin	Pérdida <0.5%	~90 tok/s	~2647 tok/s	Alternativa a NVFP4
GPTQ (INT4)	Marlin	Pérdida baja	Competitivo	Competitivo	Alternativa a AWQ
MXFP4	b12x	Similar a NVFP4	Similar	Similar	Requiere tensor-parallel
10.2 Decisión para tu stack
Rol	Modelo	Cuantización	Razón
Router	Qwen 3.5 4B	NVFP4	Máxima precisión de clasificación con mínima VRAM
Rápido	Gemma 4 12B	AWQ	Máximo rendimiento sostenido (50% más rápido que NVFP4)
Complejo	Qwen3-Coder-30B	NVFP4	MoE con b12x, precisión máxima
10.3 Selección de backend por cuantización
Cuantización	Flag --linear-backend	Flag --moe-backend	Flag --quantization
NVFP4	b12x	b12x	modelopt_fp4
AWQ	marlin (o auto)	N/A	awq_marlin
FP8	b12x (o auto)	N/A	fp8
GPTQ	marlin (o auto)	N/A	gptq_marlin
10.4 Verificación de cuantización soportada
bash
python -c "from vllm.model_executor.layers.quantization import QUANTIZATION_METHODS; print(sorted(QUANTIZATION_METHODS))"
Salida esperada (parcial):

text
['aqlm', 'awq', 'awq_marlin', 'bitsandbytes', 'compressed-tensors', 'deepspeedfp', 'fp8', 'fbgemm_fp8', 'gguf', 'gptq', 'gptq_marlin', 'marlin', 'modelopt', 'modelopt_fp4', 'mxfp4', ...]
Debe incluir al menos: awq_marlin, gptq_marlin, modelopt_fp4, mxfp4, fp8.

11. Checklist Final
Antes de pasar a la Fase 3 (descarga de modelos), verificar:

Entorno virtual
□ uv instalado y en PATH
□ venv creado en ~/vllm-stack/.venv
□ venv activado (source .venv/bin/activate)
□ python --version muestra 3.12.x
vLLM
□ python -c "import vllm; print(vllm.__version__)" funciona
□ Versión >= 0.29.0
□ Instalado con --torch-backend=cu130
PyTorch
□ torch.__version__ incluye +cu130
□ torch.cuda.is_available() devuelve True
□ torch.cuda.get_device_capability(0) devuelve (12, 0)
□ torch.cuda.get_device_name(0) devuelve NVIDIA GeForce RTX 5060 Ti
b12x
□ b12x.__version__ es 1.2.6 (NO 1.3.0)
□ B12xNvFp4LinearKernel.is_supported(120) devuelve True
□ B12xFp8BlockScaledMMKernel.is_supported(120) devuelve True
□ B12xMxfp8LinearKernel.is_supported(120) devuelve True
Cutlass DSL
□ cutlass.__version__ es 4.4.2
Flags de vLLM
□ vllm serve --help muestra --linear-backend con opción b12x
□ vllm serve --help muestra --moe-backend con opción b12x
Informe de entorno
□ ~/vllm-stack/logs/env-report.txt generado
□ Contiene información de la RTX 5060 Ti con compute capability 12.0
12. Advertencias Críticas
12.1 NO instalar vLLM desde PyPI sin --torch-backend=cu130
Si instalas con pip install vllm sin especificar el backend CUDA, obtendrás una versión compilada para CUDA 12.x que no funcionará en SM120 y fallará con no kernel image is available.

12.2 NO instalar b12x directamente desde PyPI
La versión 1.3.0 de PyPI tiene incompatibilidades con vLLM. Siempre usar uv pip install "vllm[b12x]".

12.3 NO usar nvidia-cutlass-dsl 4.5.0 o superior
Genera PTX incorrecto para SM121 y ciertos casos de SM120. Pinear a 4.4.2.

12.4 SIEMPRE especificar --linear-backend b12x --moe-backend b12x
La auto-selección omite b12x. Si no lo fuerzas, vLLM cae en Marlin y pierdes el rendimiento nativo.

12.5 La primera ejecución con NVFP4 tarda 2-5 minutos
FlashInfer y b12x JIT-compilan kernels en el primer uso. Esto es normal. La GPU parecerá idle y un core de CPU estará al 100%. NO interrumpas.

12.6 NVFP4 requiere VLLM_ATTENTION_BACKEND=TRITON_ATTN
En SM120, el backend de atención por defecto (FLASH_ATTN) puede fallar con NVFP4. Siempre exportar VLLM_ATTENTION_BACKEND=TRITON_ATTN antes de lanzar servidores con NVFP4.

12.7 Los kernels b12x JIT no se cachean entre contenedores
Si sirves modelos desde contenedores Docker, cada contenedor nuevo JIT-compila los kernels desde cero. Para evitar esto, monta un volumen compartido para el caché de JIT:

bash
-v ~/.cache/vllm:/root/.cache/vllm
13. Referencias
Recurso	URL
vLLM Docs	https://docs.vllm.ai
vLLM b12x quantization	https://docs.vllm.ai/en/latest/features/quantization/b12x.html
vLLM installation	https://docs.vllm.ai/en/latest/getting_started/installation.html
uv documentation	https://docs.astral.sh/uv/
PyTorch CUDA 13 wheels	https://download.pytorch.org/whl/cu130
b12x PyPI	https://pypi.org/project/b12x/
nvidia-cutlass-dsl	https://pypi.org/project/nvidia-cutlass-dsl/
FlashInfer	https://github.com/flashinfer-ai/flashinfer
Marlin kernels	https://github.com/IST-DASLab/marlin
PR #40191 (SM120 linking fix)	https://github.com/vllm-project/vllm/pull/40191
PR #52018 (b12x 1.2.6 pin)	https://github.com/vllm-project/vllm/pull/52018
PR #54666 (b12x auto-select)	https://github.com/vllm-project/vllm/pull/54666
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 3: Descarga de Modelos.

El siguiente archivo de documentación (03-Model-Download.md) asume:

vLLM instalado y verificado (>= 0.29.0).

b12x pineado a 1.2.6.

Cutlass DSL pineado a 4.4.2.

Kernels NVFP4, FP8 y MXFP8 verificados como soportados en SM120.

~/models/ creado.

Al menos 35 GB libres en disco.