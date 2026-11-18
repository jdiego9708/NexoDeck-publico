---
date: 2026-09-17
---
# 03-Model-Download.md
# 03-Model-Download — Descarga de Modelos

Documentación completa para descargar los tres modelos del stack vLLM multiagente con sus cuantizaciones óptimas para SM120. Incluye verificación de integridad, gestión de tokens de Hugging Face, y criterios de validación antes de pasar al serving.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Decisiones Arquitectónicas](#2-decisiones-arquitectónicas)
3. [Paso 1 — Instalar huggingface_hub CLI](#3-paso-1--instalar-huggingface_hub-cli)
4. [Paso 2 — Configurar HF_TOKEN](#4-paso-2--configurar-hf_token)
5. [Paso 3 — Verificar Espacio en Disco](#5-paso-3--verificar-espacio-en-disco)
6. [Paso 4 — Descargar Modelo Complejo (Qwen3-Coder-30B NVFP4)](#6-paso-4--descargar-modelo-complejo-qwen3-coder-30b-nvfp4)
7. [Paso 5 — Descargar Modelo Rápido (Gemma 4 12B AWQ)](#7-paso-5--descargar-modelo-rápido-gemma-4-12b-awq)
8. [Paso 6 — Descargar Modelo Router (Qwen 3.5 4B NVFP4)](#8-paso-6--descargar-modelo-router-qwen-35-4b-nvfp4)
9. [Paso 7 — Verificar Integridad de los Modelos](#9-paso-7--verificar-integridad-de-los-modelos)
10. [Paso 8 — Resumen de Modelos Descargados](#10-paso-8--resumen-de-modelos-descargados)
11. [Checklist Final](#11-checklist-final)
12. [Advertencias Críticas](#12-advertencias-críticas)
13. [Referencias](#13-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `02-vLLM-Installation.md`. Debes tener:

- venv en `~/vllm-stack/.venv` activado.
- vLLM >= 0.29.0 instalado con `--torch-backend=cu130`.
- b12x pineado a 1.2.6.
- `nvidia-cutlass-dsl` pineado a 4.4.2.
- Kernels NVFP4, FP8 y MXFP8 verificados como soportados en SM120.
- `~/models/` creado.
- Al menos 35 GB libres en disco.

El objetivo de esta fase es **descargar los tres modelos** con sus cuantizaciones óptimas, verificando integridad y estructura antes de pasar al serving.

### Modelos a descargar

| Rol | Modelo | Cuantización | Tamaño | Repositorio |
|:---|:---|:---|:---|:---|
| **Complejo** | Qwen3-Coder-30B-A3B REAP-50 | NVFP4 | ~9.9 GB | `AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4` |
| **Rápido** | Gemma 4 12B | AWQ | ~6.8 GB | `mattbucci/gemma-4-12B-AWQ` |
| **Router** | Qwen 3.5 4B | NVFP4 | ~2.5 GB | `AxionML/Qwen3.5-4B-NVFP4` |

**Total en disco**: ~19 GB.

---

## 2. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Modelo complejo en NVFP4** | AWQ, FP8 | Qwen3-Coder-30B es MoE. b12x soporta MoE NVFP4 en SM120. REAP-50 + NVFP4 deja el modelo en ~9.9 GB, permitiendo contexto de 16k con margen para KV cache. |
| **Modelo rápido en AWQ** | NVFP4 | AWQ int4 con Marlin es ~50% más rápido en batch-1 y ~18% más rápido en batch-32 que NVFP4. Además, no requiere JIT compilation (arranca instantáneamente). |
| **Router en NVFP4** | AWQ, FP8 | Para clasificación y tool-calling en un modelo de 4B, la precisión es más importante que la velocidad. NVFP4 preserva mejor las capacidades de razonamiento que AWQ en modelos pequeños, con huella mínima (~2.5 GB). |
| **Descarga vía `huggingface-cli`** | `git clone`, `wget` | `huggingface-cli` maneja autenticación, resume de descargas, verificación de hashes, y estructura de directorios correctamente. |
| **Almacenamiento local en `~/models/`** | `/mnt/d/` | Mantener los modelos en el sistema de archivos de WSL2 (ext4) es más rápido para cargas repetidas. Si el disco está ajustado, se puede mover a `/mnt/d/` con impacto mínimo. |
| **Verificación de `config.json`** | Solo tamaño de archivo | Verificar `quantization_config` confirma que el modelo es realmente del formato esperado. Un archivo con el nombre correcto puede tener cuantización incorrecta. |

---

## 3. Paso 1 — Instalar huggingface_hub CLI

### 3.1 ¿Qué es?

`huggingface_hub` es la librería oficial de Hugging Face para interactuar con su API. Incluye `huggingface-cli`, la herramienta de línea de comandos para descargar modelos, datasets, y gestionar autenticación.

### 3.2 Instalación

**Con el venv activado**:
source ~/vllm-stack/.venv/bin/activate
uv pip install "huggingface_hub[cli]"

Verificar:

bash
huggingface-cli --version
Salida esperada: huggingface_hub version: 0.3x.x (o superior).

3.3 Configurar caché de Hugging Face
Por defecto, huggingface-cli cachea descargas en ~/.cache/huggingface/. Con modelos grandes, esto puede consumir mucho espacio. Es recomendable redirigir el caché a ~/models/.cache/.

Añadir a ~/.bashrc:

bash
echo 'export HF_HOME=~/models/.cache' >> ~/.bashrc
source ~/.bashrc
Verificar:

bash
echo $HF_HOME
Salida esperada: /home/juan/models/.cache.

3.4 Habilitar transferencia acelerada (opcional)
hf_transfer es un backend de Rust que acelera descargas en conexiones rápidas (>100 Mbps).

bash
uv pip install hf_transfer
echo 'export HF_HUB_ENABLE_HF_TRANSFER=1' >> ~/.bashrc
source ~/.bashrc
Verificar:

bash
echo $HF_HUB_ENABLE_HF_TRANSFER
Salida esperada: 1.

4. Paso 2 — Configurar HF_TOKEN
4.1 ¿Por qué?
Algunos modelos requieren autenticación por:

Gating: el autor debe aprobar tu acceso.

Licencia: modelos con licencias específicas que requieren aceptación.

Rate limits: usuarios autenticados tienen límites más altos.

Los tres modelos de este stack son públicos y sin gating, pero configurar HF_TOKEN es una buena práctica para evitar problemas futuros.

4.2 Obtener token
Ir a https://huggingface.co/settings/tokens

Clic en "New token".

Tipo: "Read".

Nombre: vllm-stack-local.

Copiar el token generado (empieza con hf_).

4.3 Configurar
Opción A — Variable de entorno (temporal):

bash
export HF_TOKEN="hf_tu_token_aqui"
Opción B — Persistente en ~/.bashrc:

bash
echo 'export HF_TOKEN="hf_tu_token_aqui"' >> ~/.bashrc
source ~/.bashrc
Opción C — Guardar en el CLI:

bash
huggingface-cli login --token hf_tu_token_aqui
Esto guarda el token en ~/.cache/huggingface/token y lo usa automáticamente.

4.4 Verificar
bash
huggingface-cli whoami
Salida esperada: tu nombre de usuario de Hugging Face.

5. Paso 3 — Verificar Espacio en Disco
5.1 ¿Por qué?
Los tres modelos suman ~19 GB. El caché de Hugging Face puede duplicar esto temporalmente durante la descarga (el archivo se descarga a un temporal y luego se mueve). Además, el contenedor Docker de vLLM en fases posteriores necesita ~10 GB.

Total recomendado: al menos 35 GB libres.

5.2 Verificar
bash
df -h ~
Salida esperada (ejemplo):

text
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdd       1007G  245G  712G  26% /
En este caso hay 712 GB libres, más que suficiente.

5.3 Si el disco está ajustado
Mover modelos al disco D: de Windows montado en WSL2:

bash
mkdir -p /mnt/d/vllm-models
echo 'export HF_HOME=/mnt/d/vllm-models/.cache' >> ~/.bashrc
source ~/.bashrc
Y descargar los modelos con --local-dir /mnt/d/vllm-models/<nombre>.

Advertencia: /mnt/d/ es más lento que el sistema de archivos nativo de WSL2 (ext4). La carga de modelos desde /mnt/d/ puede ser 2-3x más lenta. Si es posible, mantener los modelos en ~/models/.

5.4 Verificar después de cada descarga
bash
df -h ~
6. Paso 4 — Descargar Modelo Complejo (Qwen3-Coder-30B NVFP4)
6.1 ¿Por qué este modelo?
Qwen3-Coder-30B-A3B es un modelo Mixture-of-Experts (MoE) con:

64 expertos por capa, top-8 activos.

48 capas.

3B parámetros activos de 30B totales.

Especializado en generación de código, con benchmarks destacados:

HumanEval: 0.909

MBPP: 0.839

REAP-50 es una técnica de pruning que reduce el número de expertos a la mitad, manteniendo la calidad. Combinado con NVFP4, el modelo queda en ~9.9 GB, dejando ~5 GB de VRAM para KV cache y overhead en tu RTX 5060 Ti.

NVFP4 es el formato de cuantización de 4 bits nativo de Blackwell. Los kernels b12x lo soportan directamente para MoE, dando el mejor rendimiento y precisión en SM120.

6.2 Repositorio
Hugging Face: AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4

Característica	Valor
Arquitectura	Qwen3-MoE (64 expertos/layer, top-8)
Capas	48
Formato	NVFP4 4-bit (group size 16) + FP8 KV cache
Tamaño en disco	~9.9 GB
Contexto nativo	262,144 tokens
Contexto recomendado	16,384 tokens (por VRAM)
6.3 Descargar
bash
cd ~/models

huggingface-cli download AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4 \
  --local-dir ~/models/qwen3-coder-30b-reap50-nvfp4 \
  --local-dir-use-symlinks False
¿Qué hacen los flags?

--local-dir: especifica el directorio destino.

--local-dir-use-symlinks False: copia los archivos en lugar de crear symlinks al caché. Esto hace que el directorio sea autocontenido.

6.4 Verificar estructura
bash
ls -lh ~/models/qwen3-coder-30b-reap50-nvfp4/
Salida esperada:

text
total 9.9G
-rw-r--r-- 1 juan juan  1.2K config.json
-rw-r--r-- 1 juan juan   234 generation_config.json
-rw-r--r-- 1 juan juan  9.9G model.safetensors
-rw-r--r-- 1 juan juan  2.5M tokenizer.json
-rw-r--r-- 1 juan juan  1.5K tokenizer_config.json
...
6.5 Verificar cuantización
bash
cat ~/models/qwen3-coder-30b-reap50-nvfp4/config.json | python -m json.tool | grep -A5 "quantization"
Salida esperada:

json
"quantization_config": {
    "quant_method": "modelopt_fp4",
    "group_size": 16,
    "desc_act": false,
    ...
}
Si quant_method no es modelopt_fp4 o similar (puede ser nvfp4, modelopt), el modelo es de otro formato. Revisa el repositorio.

6.6 Verificar tamaño total
bash
du -sh ~/models/qwen3-coder-30b-reap50-nvfp4/
Salida esperada: ~9.9G.

7. Paso 5 — Descargar Modelo Rápido (Gemma 4 12B AWQ)
7.1 ¿Por qué este modelo?
Gemma 4 12B es un modelo denso de Google, con buen rendimiento en tareas generales de código y texto. No es tan potente como Qwen3-Coder-30B en tareas complejas, pero es mucho más rápido y suficiente para autocompletado, edición, y consultas cotidianas.

¿Por qué AWQ y no NVFP4?

El benchmark independiente sobre RTX 5090 (SM120) muestra que AWQ int4 con Marlin es sistemáticamente más rápido que NVFP4 en decode:

Cuantización	batch 1	batch 8	batch 32
AWQ int4	150 tok/s	1188 tok/s	3937 tok/s
FP8	90 tok/s	711 tok/s	2647 tok/s
NVFP4	100 tok/s	801 tok/s	3321 tok/s
AWQ es 50% más rápido en batch-1 y 18% más rápido en batch-32 que NVFP4. Además, no requiere JIT compilation (Marlin usa kernels precompilados), lo que elimina los 2-5 minutos de arranque que sí necesita NVFP4.

Para un modelo que atenderá la mayoría de peticiones concurrentes (8-12 agentes), la velocidad sostenida es la métrica más importante.

7.2 Repositorio
Hugging Face: mattbucci/gemma-4-12B-AWQ

Característica	Valor
Arquitectura	Gemma 4 dense
Parámetros	12B
Formato	AWQ W4A16 (group 128)
Tamaño en disco	~6.8 GB
Contexto nativo	32,768 tokens
7.3 Descargar
bash
cd ~/models

huggingface-cli download mattbucci/gemma-4-12B-AWQ \
  --local-dir ~/models/gemma-4-12b-awq \
  --local-dir-use-symlinks False
7.4 Alternativa si el repo no está disponible
Si mattbucci/gemma-4-12B-AWQ no existe o ha sido eliminado, usar:

bash
huggingface-cli download nicklas373/Huihui-gemma-4-12B-it-abliterated-AWQ \
  --local-dir ~/models/gemma-4-12b-awq \
  --local-dir-use-symlinks False
Nota: abliterated significa que el modelo ha sido modificado para eliminar rechazos de contenido. Si esto no es deseable, buscar otra versión AWQ del modelo base.

7.5 Verificar estructura
bash
ls -lh ~/models/gemma-4-12b-awq/
Salida esperada:

text
total 6.8G
-rw-r--r-- 1 juan juan  1.5K config.json
-rw-r--r-- 1 juan juan  6.8G model.safetensors
-rw-r--r-- 1 juan juan  2.3M tokenizer.json
-rw-r--r-- 1 juan juan  1.4K tokenizer_config.json
...
7.6 Verificar cuantización
bash
cat ~/models/gemma-4-12b-awq/config.json | python -m json.tool | grep -A5 "quantization"
Salida esperada:

json
"quantization_config": {
    "quant_method": "awq",
    "bits": 4,
    "group_size": 128,
    "zero_point": true,
    ...
}
Si quant_method no es awq, el modelo es de otro formato.

7.7 Verificar tamaño total
bash
du -sh ~/models/gemma-4-12b-awq/
Salida esperada: ~6.8G.

8. Paso 6 — Descargar Modelo Router (Qwen 3.5 4B NVFP4)
8.1 ¿Por qué este modelo?
Qwen 3.5 4B es un modelo pequeño pero potente, con arquitectura híbrida (Gated DeltaNet + Attention). Es ideal para tareas de clasificación, enrutamiento y tool-calling por su alta precisión en benchmarks específicos:

Modelo	Precisión enrutamiento	Tool-calling	VRAM
Qwen 3.5 4B	90.5%	85.5%	~2.5 GB
Gemma 4 12B	75%	Requiere shim	~7 GB
Gemma 4 E4B	75%	Limitado	~4 GB
¿Por qué NVFP4? Para el meta-agente, la precisión de clasificación es más importante que la velocidad pura. NVFP4 preserva mejor las capacidades de razonamiento y tool-calling que AWQ en modelos pequeños, y su huella es mínima (~2.5 GB).

8.2 Repositorio
Hugging Face: AxionML/Qwen3.5-4B-NVFP4

Característica	Valor
Arquitectura	Qwen 3.5 (híbrida Gated DeltaNet + Attention)
Parámetros	4B
Formato	NVFP4 4-bit
Tamaño en disco	~2.5 GB
Contexto nativo	262,144 tokens
8.3 Descargar
bash
cd ~/models

huggingface-cli download AxionML/Qwen3.5-4B-NVFP4 \
  --local-dir ~/models/qwen3.5-4b-nvfp4 \
  --local-dir-use-symlinks False
8.4 Alternativa AWQ
Si el repo NVFP4 no está disponible, usar la versión AWQ:

bash
huggingface-cli download QuantTrio/Qwen3.5-4B-AWQ \
  --local-dir ~/models/qwen3.5-4b-awq \
  --local-dir-use-symlinks False
Nota: Los checkpoints AWQ de Qwen 3.5 usan compressed-tensors pack-quantized. vLLM los auto-detecta sin necesidad de --quantization flag.

8.5 Verificar estructura
bash
ls -lh ~/models/qwen3.5-4b-nvfp4/
Salida esperada:

text
total 2.5G
-rw-r--r-- 1 juan juan  1.3K config.json
-rw-r--r-- 1 juan juan  2.5G model.safetensors
-rw-r--r-- 1 juan juan  2.1M tokenizer.json
-rw-r--r-- 1 juan juan  1.3K tokenizer_config.json
...
8.6 Verificar cuantización
bash
cat ~/models/qwen3.5-4b-nvfp4/config.json | python -m json.tool | grep -A5 "quantization"
Salida esperada:

json
"quantization_config": {
    "quant_method": "modelopt_fp4",
    "group_size": 16,
    ...
}
8.7 Verificar tamaño total
bash
du -sh ~/models/qwen3.5-4b-nvfp4/
Salida esperada: ~2.5G.

9. Paso 7 — Verificar Integridad de los Modelos
9.1 Verificar que los archivos safetensors son válidos
Los archivos .safetensors tienen un header JSON que describe los tensores. Se puede verificar sin cargar el modelo completo:

bash
python << 'EOF'
from safetensors import safe_open
import os

models = [
    ("~/models/qwen3-coder-30b-reap50-nvfp4/model.safetensors", "Qwen3-Coder-30B"),
    ("~/models/gemma-4-12b-awq/model.safetensors", "Gemma 4 12B"),
    ("~/models/qwen3.5-4b-nvfp4/model.safetensors", "Qwen 3.5 4B"),
]

for path, name in models:
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"✗ {name}: archivo no encontrado en {path}")
        continue
    try:
        with safe_open(path, framework="pt") as f:
            keys = list(f.keys())
            print(f"✓ {name}: {len(keys)} tensores válidos")
    except Exception as e:
        print(f"✗ {name}: error al leer — {e}")
EOF
Salida esperada:

text
✓ Qwen3-Coder-30B: XXXX tensores válidos
✓ Gemma 4 12B: XXXX tensores válidos
✓ Qwen 3.5 4B: XXXX tensores válidos
9.2 Verificar hashes (opcional pero recomendado)
Hugging Face publica hashes SHA256 de cada archivo. Se pueden verificar manualmente:

bash
cd ~/models/qwen3-coder-30b-reap50-nvfp4
sha256sum model.safetensors
Comparar con el valor en https://huggingface.co/AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4/tree/main.

Nota: Verificar hashes de archivos de ~10 GB puede tardar varios minutos. Es opcional pero recomendado si sospechas de corrupción durante la descarga.

9.3 Verificar carga rápida con vLLM (sin inferencia)
bash
python << 'EOF'
from transformers import AutoConfig

models = [
    ("~/models/qwen3-coder-30b-reap50-nvfp4", "Qwen3-Coder-30B"),
    ("~/models/gemma-4-12b-awq", "Gemma 4 12B"),
    ("~/models/qwen3.5-4b-nvfp4", "Qwen 3.5 4B"),
]

import os
for path, name in models:
    path = os.path.expanduser(path)
    try:
        config = AutoConfig.from_pretrained(path)
        print(f"✓ {name}: {config.model_type} ({config.num_hidden_layers} capas)")
    except Exception as e:
        print(f"✗ {name}: {e}")
EOF
Salida esperada:

text
✓ Qwen3-Coder-30B: qwen3_moe (48 capas)
✓ Gemma 4 12B: gemma (48 capas)
✓ Qwen 3.5 4B: qwen3 (32 capas)
Los números exactos de capas pueden variar según la versión del modelo.

10. Paso 8 — Resumen de Modelos Descargados
10.1 Tabla resumen
Rol	Modelo	Cuantización	Disco	VRAM	Contexto	Repositorio
Complejo	Qwen3-Coder-30B-A3B REAP-50	NVFP4	9.9 GB	~10 GB	16k	AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4
Rápido	Gemma 4 12B	AWQ	6.8 GB	~7 GB	32k	mattbucci/gemma-4-12B-AWQ
Router	Qwen 3.5 4B	NVFP4	2.5 GB	~2.5 GB	16k	AxionML/Qwen3.5-4B-NVFP4
Total en disco: ~19.2 GB.
Total en VRAM (si todos activos): ~19.5 GB — no caben en 16 GB.

Esto justifica el uso de Sleep Mode en fases posteriores: solo uno o dos modelos activos a la vez en VRAM.

10.2 Combinaciones viables de VRAM
Combinación	VRAM total	Cabe en 16 GB
Router + Rápido	~9.5 GB	✓ Sí (deja 6.5 GB para KV cache)
Router + Complejo	~12.5 GB	✓ Sí (deja 3.5 GB para KV cache)
Rápido + Complejo	~17 GB	✗ No
Router + Rápido + Complejo	~19.5 GB	✗ No
Solo Complejo	~10 GB	✓ Sí (deja 6 GB para KV cache)
Estrategia recomendada: mantener Router + Rápido activos por defecto (~9.5 GB), y alternar a Complejo con Sleep Mode cuando se necesite razonamiento avanzado.

10.3 Verificar espacio total usado
bash
du -sh ~/models/
Salida esperada: ~19G.

bash
df -h ~
Debe mostrar al menos 15 GB libres después de las descargas.

11. Checklist Final
Antes de pasar a la Fase 4 (serving), verificar:

huggingface_hub
□ huggingface-cli instalado
□ HF_HOME=~/models/.cache configurado
□ HF_TOKEN configurado (opcional pero recomendado)
□ huggingface-cli whoami responde
Modelo complejo (Qwen3-Coder-30B NVFP4)
□ Descargado en ~/models/qwen3-coder-30b-reap50-nvfp4/
□ model.safetensors de ~9.9 GB presente
□ config.json con quant_method: modelopt_fp4
□ Safetensors válido (sin errores al leer)
□ AutoConfig.from_pretrained() funciona
Modelo rápido (Gemma 4 12B AWQ)
□ Descargado en ~/models/gemma-4-12b-awq/
□ model.safetensors de ~6.8 GB presente
□ config.json con quant_method: awq
□ Safetensors válido
□ AutoConfig.from_pretrained() funciona
Modelo router (Qwen 3.5 4B NVFP4)
□ Descargado en ~/models/qwen3.5-4b-nvfp4/
□ model.safetensors de ~2.5 GB presente
□ config.json con quant_method: modelopt_fp4
□ Safetensors válido
□ AutoConfig.from_pretrained() funciona
Disco
□ du -sh ~/models/ muestra ~19 GB
□ df -h ~ muestra al menos 15 GB libres
□ No hay archivos temporales de descarga pendientes
12. Advertencias Críticas
12.1 NO usar git clone para modelos grandes
git clone de repositorios con archivos .safetensors de 10 GB es extremadamente lento y propenso a fallos. Usar siempre huggingface-cli download.

12.2 NO asumir que un archivo con el nombre correcto tiene la cuantización correcta
Siempre verificar quant_method en config.json. Un repositorio puede llamarse "model-awq" pero contener pesos en otro formato.

12.3 NO ignorar el espacio en disco durante las descargas
huggingface-cli descarga a un temporal y luego mueve. Con modelos de 10 GB, esto puede requerir hasta 20 GB libres temporalmente.

12.4 El caché de Hugging Face se duplica si no usas --local-dir-use-symlinks False
Por defecto, huggingface-cli crea symlinks al caché. Con --local-dir-use-symlinks False, copia los archivos. La segunda opción usa más disco pero hace el directorio autocontenido.

12.5 Los modelos NVFP4 con bfloat16 en el nombre pueden ser falsos
Algunos repositorios usan nombres engañosos. Verificar quant_method en config.json es la única forma confiable.

12.6 No mezclar modelos de diferentes fuentes sin verificar compatibilidad
Los checkpoints NVFP4 de diferentes autores pueden usar versiones distintas de modelopt o compressed-tensors. Verificar la versión de vllm y de las librerías de cuantización.

12.7 Los modelos con gating requieren aprobación manual
Si un repositorio requiere gating, la descarga fallará con 401 Unauthorized hasta que el autor apruebe tu acceso. Verificar el repositorio en el navegador antes de descargar.

13. Referencias
Recurso	URL
Hugging Face Hub CLI	https://huggingface.co/docs/huggingface_hub/guides/cli
Hugging Face Tokens	https://huggingface.co/settings/tokens
hf_transfer	https://github.com/huggingface/hf_transfer
Modelo Qwen3-Coder-30B	https://huggingface.co/AminFa12/qwen3-coder-30b-a3b-reap50-nvfp4
Modelo Gemma 4 12B AWQ	https://huggingface.co/mattbucci/gemma-4-12B-AWQ
Modelo Qwen 3.5 4B NVFP4	https://huggingface.co/AxionML/Qwen3.5-4B-NVFP4
Modelo Qwen 3.5 4B AWQ	https://huggingface.co/QuantTrio/Qwen3.5-4B-AWQ
Safetensors	https://github.com/huggingface/safetensors
Benchmark AWQ vs NVFP4	https://huggingface.co/datasets/witcheer/rtx-5090-benchmarks
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 4: Servidores vLLM con Sleep Mode.

El siguiente archivo de documentación (04-vLLM-Serving.md) asume:

Los 3 modelos descargados y verificados.

config.json de cada modelo confirma la cuantización esperada.

Al menos 15 GB libres en disco.

venv de vLLM activado.

Docker Engine funcionando con GPU passthrough verificado.

text

Si quieres, puedo darte también el siguiente archivo (`04-vLLM-Serving.md`) en el mismo formato, o puedo generarte los tres archivos que faltan (`04`, `05`, `06`) en un solo bloque.