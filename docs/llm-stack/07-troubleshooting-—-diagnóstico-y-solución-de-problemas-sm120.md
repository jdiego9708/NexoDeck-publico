---
date: 2026-09-17
---
# 07-Troubleshooting — Diagnóstico y Solución de Problemas SM120

# 07-Troubleshooting — Diagnóstico y Solución de Problemas SM120

Documentación completa de errores conocidos, causas raíz, procedimientos de diagnóstico y soluciones para el stack vLLM multiagente sobre RTX 5060 Ti (SM120) en Windows 11 + WSL2 + Docker Engine.

Este documento es **solo de referencia y diagnóstico**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Filosofía de Diagnóstico](#2-filosofía-de-diagnóstico)
3. [Capa 1 — Windows y Driver NVIDIA](#3-capa-1--windows-y-driver-nvidia)
4. [Capa 2 — WSL2 y systemd](#4-capa-2--wsl2-y-systemd)
5. [Capa 3 — Docker Engine](#5-capa-3--docker-engine)
6. [Capa 4 — NVIDIA Container Toolkit](#6-capa-4--nvidia-container-toolkit)
7. [Capa 5 — vLLM y PyTorch](#7-capa-5--vllm-y-pytorch)
8. [Capa 6 — Kernels b12x y Cuantizaciones](#8-capa-6--kernels-b12x-y-cuantizaciones)
9. [Capa 7 — Modelos y Cuantización](#9-capa-7--modelos-y-cuantización)
10. [Capa 8 — Serving y Sleep Mode](#10-capa-8--serving-y-sleep-mode)
11. [Capa 9 — Router Semántico](#11-capa-9--router-semántico)
12. [Capa 10 — Túnel Cloudflare](#12-capa-10--túnel-cloudflare)
13. [Capa 11 — Multiagente y Concurrencia](#13-capa-11--multiagente-y-concurrencia)
14. [Errores por Síntoma](#14-errores-por-síntoma)
15. [Diagnóstico Rápido (Flowchart)](#15-diagnóstico-rápido-flowchart)
16. [Reset Completo del Stack](#16-reset-completo-del-stack)
17. [Referencias](#17-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya tienes el stack funcionando parcial o totalmente. Cuando algo falla, es tentador saltar directo al error y buscar la solución. Pero en un stack con tantas capas (Windows → WSL2 → Docker → NVIDIA → vLLM → modelo), el error visible suele estar **lejos** de la causa raíz.

El objetivo de este documento es:

1. **Diagnóstico sistemático por capas**: verificar cada capa antes de culpar a la siguiente.
2. **Tabla de errores comunes** con causa y solución.
3. **Comandos de diagnóstico** para aislar el problema.
4. **Procedimientos de reset** parcial y total.

### Arquitectura del stack (capas)

┌─────────────────────────────────────────────────────┐
│ Capa 1: Windows 11 + Driver NVIDIA │
├─────────────────────────────────────────────────────┤
│ Capa 2: WSL2 + Ubuntu + systemd │
├─────────────────────────────────────────────────────┤
│ Capa 3: Docker Engine │
├─────────────────────────────────────────────────────┤
│ Capa 4: NVIDIA Container Toolkit │
├─────────────────────────────────────────────────────┤
│ Capa 5: vLLM + PyTorch + CUDA │
├─────────────────────────────────────────────────────┤
│ Capa 6: Kernels b12x y cuantizaciones │
├─────────────────────────────────────────────────────┤
│ Capa 7: Modelos y pesos │
├─────────────────────────────────────────────────────┤
│ Capa 8: Serving y Sleep Mode │
├─────────────────────────────────────────────────────┤
│ Capa 9: Router semántico vLLM-SR │
├─────────────────────────────────────────────────────┤
│ Capa 10: Túnel Cloudflare │
├─────────────────────────────────────────────────────┤
│ Capa 11: Multiagente y concurrencia │
└─────────────────────────────────────────────────────┘

**Regla de oro**: un error en la capa N casi siempre se debe a un fallo en la capa N-1. **Diagnostica de abajo hacia arriba.**

---

## 2. Filosofía de Diagnóstico

### 2.1 Principios

1. **Aislar la capa**: antes de culpar a vLLM, verifica que la GPU funciona en Windows.
2. **Reproducir mínimo**: en lugar de arrancar el stack completo, reproduce el error con un comando mínimo.
3. **Verificar versiones**: el 80% de los errores de SM120 son por versiones incompatibles.
4. **Leer el log completo**: no solo la última línea. El error real suele estar 20-30 líneas arriba.
5. **Comprobar con otro modelo**: si un modelo funciona y otro no, el problema es del modelo, no del stack.

### 2.2 Comando de diagnóstico rápido


# Ejecutar en Ubuntu
echo "=== 1. GPU ===" && nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv
echo "=== 2. WSL2 ===" && free -h | head -2
echo "=== 3. Docker ===" && docker --version && docker info 2>/dev/null | grep -E "Server Version|Cgroup"
echo "=== 4. GPU en contenedor ===" && docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L
echo "=== 5. vLLM ===" && python -c "import vllm; print(f'vLLM: {vllm.__version__}')" 2>/dev/null
echo "=== 6. b12x ===" && python -c "import b12x; print(f'b12x: {b12x.__version__}')" 2>/dev/null
echo "=== 7. CuDNN ===" && python -c "import torch; print(f'PyTorch: {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>/dev/null

Salida esperada:

text
=== 1. GPU ===
name, compute_cap, driver_version
NVIDIA GeForce RTX 5060 Ti, 12.0, 591.86
=== 2. WSL2 ===
               total        used        free
Mem:            28Gi        ...
=== 3. Docker ===
Docker version 29.x.x, build xxxxx
Server Version: 29.x.x
Cgroup Version: 2
=== 4. GPU en contenedor ===
GPU 0: NVIDIA GeForce RTX 5060 Ti (UUID: GPU-xxxxx)
=== 5. vLLM ===
vLLM: 0.29.x
=== 6. b12x ===
b12x: 1.2.6
=== 7. CuDNN ===
PyTorch: 2.13.x+cu130, CUDA: True
Si cualquiera de las líneas falla, ya sabes en qué capa buscar.

3. Capa 1 — Windows y Driver NVIDIA
3.1 Verificar driver
En PowerShell:

powershell
nvidia-smi
Salida esperada:

Driver Version: 591.86 (o superior).

CUDA Version: 13.1 (o superior).

GPU: NVIDIA GeForce RTX 5060 Ti.

3.2 Errores comunes
Error	Causa	Solución
nvidia-smi: command not found	Driver no instalado	Instalar desde https://www.nvidia.com/Download/index.aspx
Driver Version: 5xx.xx (menor a 570)	Driver antiguo	Actualizar a 570.x o superior
CUDA Version: 12.x	Driver antiguo	Actualizar driver; SM120 requiere CUDA 13.x
No devices were found	GPU deshabilitada o driver corrupto	Reinstalar driver limpio (DDU + NVIDIA installer)
Unable to determine the device handle	Proceso usando la GPU	Cerrar aplicaciones gráficas
3.3 Verificar que Windows reconoce la GPU
En PowerShell:

powershell
Get-PnpDevice -Class Display | Select-Object FriendlyName, Status
Salida esperada:

text
FriendlyName                          Status
------------                          ------
NVIDIA GeForce RTX 5060 Ti            OK
Si Status no es OK, reinstalar el driver.

3.4 Actualizar driver
Descargar de https://www.nvidia.com/Download/index.aspx.

Seleccionar: GeForce → RTX 50 Series → RTX 5060 Ti → Windows 11.

Descargar el instalador.

Ejecutar como administrador.

Seleccionar "Custom installation" → "Perform a clean installation".

Tras instalar: reiniciar Windows.

4. Capa 2 — WSL2 y systemd
4.1 Verificar WSL2
En PowerShell:

powershell
wsl --version
Salida esperada:

text
WSL version: 2.7.13.0
Kernel version: 6.18.33.2-2
...
Si la versión es menor a 2.0.0, actualizar:

powershell
wsl --update
4.2 Verificar distro Ubuntu
powershell
wsl --list --verbose
Salida esperada:

text
  NAME            STATE           VERSION
* Ubuntu          Running         2
Si Ubuntu no aparece o VERSION es 1, cambiar a WSL2:

powershell
wsl --set-version Ubuntu 2
4.3 Verificar memoria asignada
En Ubuntu:

bash
free -h
Salida esperada:

text
               total        used        free
Mem:            28Gi        ...
Si total es ~16 Gi (mitad de los 32 GB físicos), el .wslconfig no se aplicó.

Solución:

Verificar %USERPROFILE%\.wslconfig:

powershell
Get-Content $env:USERPROFILE\.wslconfig
Si no incluye memory=28GB, añadirlo:

ini
[wsl2]
memory=28GB
processors=12
swap=8GB
Reiniciar WSL:

powershell
wsl --shutdown
wsl -d Ubuntu
4.4 Verificar systemd
En Ubuntu:

bash
systemctl --version
ps -p 1 -o comm=
Salida esperada:

text
systemd 255 (o superior)
systemd
Si ps -p 1 -o comm= devuelve init en lugar de systemd, systemd no está habilitado.

Solución:

Verificar /etc/wsl.conf:

bash
cat /etc/wsl.conf
Si no incluye systemd=true:

bash
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true
EOF
Reiniciar WSL:

powershell
wsl --shutdown
wsl -d Ubuntu
4.5 Error wsl: Clave 'wsl2.autoMemoryReclaim' desconocida
Causa: autoMemoryReclaim está en la sección [wsl2] en lugar de [experimental].

Solución: editar .wslconfig para moverlo:

ini
[wsl2]
memory=28GB
processors=12
swap=8GB

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
Reiniciar WSL.

4.6 Errores comunes de WSL2
Error	Causa	Solución
The requested operation could not be completed due to a virtual disk system limitation	Disco virtual sin sparseVhd	Añadir sparseVhd=true en [experimental]
WslRegisterDistribution failed with error: 0x800701bc	Kernel WSL2 desactualizado	wsl --update
Cannot connect to the Docker daemon	Docker no arrancó	sudo systemctl start docker
WSL2 lento al arrancar	processors=16 satura CPU	Reducir a processors=12
No space left on device	Disco virtual lleno	sparseVhd=true + limpiar /tmp
5. Capa 3 — Docker Engine
5.1 Verificar Docker
En Ubuntu:

bash
docker --version
docker info | grep -E "Server Version|Storage Driver|Cgroup"
Salida esperada:

text
Docker version 29.x.x, build xxxxx
Server Version: 29.x.x
Storage Driver: overlay2
Cgroup Version: 2
5.2 Verificar que funciona sin sudo
bash
docker ps
Salida esperada: lista vacía (sin error de permisos).

Si falla con permission denied:

bash
sudo usermod -aG docker $USER
newgrp docker
Cerrar y reabrir la terminal de Ubuntu.

5.3 Verificar servicio
bash
sudo systemctl status docker
Salida esperada: Active: active (running).

Si no está activo:

bash
sudo systemctl start docker
sudo systemctl enable docker
5.4 Errores comunes
Error	Causa	Solución
docker: command not found	Docker no instalado	Instalar con apt-get install docker-ce
permission denied /var/run/docker.sock	Usuario no en grupo docker	sudo usermod -aG docker $USER + relogin
Cannot connect to the Docker daemon	Servicio detenido	sudo systemctl start docker
cgroups v1 en lugar de v2	systemd no habilitado	Habilitar systemd en WSL2
Error response from daemon: Unknown runtime specified nvidia	NVIDIA Container Toolkit no configurado	Configurar con nvidia-ctk runtime configure
pull access denied	Imagen no existe o rate limit	Verificar nombre; autenticarse en Docker Hub
5.5 Verificar que se puede descargar una imagen
bash
docker pull hello-world
docker run --rm hello-world
Salida esperada: mensaje Hello from Docker!.

5.6 Verificar daemon.json
bash
cat /etc/docker/daemon.json
Salida esperada:

json
{
  "runtimes": {
    "nvidia": {
      "args": [],
      "path": "nvidia-container-runtime"
    }
  }
}
Si no incluye nvidia, configurar con:

bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
6. Capa 4 — NVIDIA Container Toolkit
6.1 Verificar que está instalado
bash
dpkg -l | grep nvidia-container-toolkit
Salida esperada:

text
ii  nvidia-container-toolkit  1.x.x-1  ...
Si no aparece, instalar:

bash
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
6.2 Prueba de GPU en contenedor
bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
Salida esperada: la misma información de la RTX 5060 Ti.

6.3 Errores comunes
Error	Causa	Solución
docker: Error response from daemon: could not select device driver "" with capabilities: [[gpu]]	Toolkit no configurado	sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
nvidia-container-cli: initialization error: nvml error	Driver no accesible desde WSL2	Verificar nvidia-smi dentro de Ubuntu
nvidia-container-cli: mount error: file creation failed	Permisos de /var/run	Reiniciar Docker; si persiste, reiniciar WSL
nvidia-container-cli: detected unsupported NVIDIA driver version	Driver demasiado antiguo	Actualizar driver en Windows
libnvidia-ml.so.1: cannot open shared object file	Librerías de NVIDIA no accesibles	Reiniciar WSL tras actualizar driver
6.4 Verificar librerías NVIDIA en WSL2
bash
ls -la /usr/lib/wsl/lib/
Salida esperada:

text
libcuda.so
libcuda.so.1
libnvidia-ml.so.1
libnvidia-ptxjitcompiler.so.1
...
Si faltan, el driver no está propagando correctamente a WSL2.

Solución: reinstalar driver NVIDIA en Windows; reiniciar WSL.

7. Capa 5 — vLLM y PyTorch
7.1 Verificar vLLM
bash
source ~/vllm-stack/.venv/bin/activate
python -c "import vllm; print(f'vLLM: {vllm.__version__}')"
Salida esperada: vLLM: 0.29.x.

7.2 Verificar PyTorch
bash
python -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.cuda.is_available()}'); print(f'CC: {torch.cuda.get_device_capability(0)}')"
Salida esperada:

text
PyTorch: 2.13.x+cu130
CUDA: True
CC: (12, 0)
7.3 Errores comunes
Error	Causa	Solución
ModuleNotFoundError: No module named 'vllm'	venv no activado o vLLM no instalado	source .venv/bin/activate + uv pip install vllm
torch.cuda.is_available() == False	PyTorch sin CUDA o driver mal	Reinstalar con --torch-backend=cu130
no kernel image is available for execution	PyTorch no compilado para SM120	Reinstalar con --torch-backend=cu130
PyTorch: 2.x.x (sin +cu130)	Instalación con CPU-only	uv pip install torch --torch-backend=cu130
RuntimeError: CUDA out of memory	VRAM insuficiente	Ver capa 8
CUDA initialization: no CUDA-capable device is detected	WSL2 sin GPU	Ver capa 4
7.4 Verificar CUDA Toolkit
Aunque no instalamos CUDA Toolkit en WSL2, algunas librerías lo requieren en tiempo de ejecución. Verificar:

bash
ldconfig -p | grep libcuda
Salida esperada:

text
libcuda.so.1 (libc6,x86-64) => /usr/lib/wsl/lib/libcuda.so.1
Si no aparece, el driver de Windows no está propagando correctamente.

7.5 Verificar la instalación de vLLM
bash
vllm collect-env > ~/vllm-stack/logs/env-report.txt
head -60 ~/vllm-stack/logs/env-report.txt
Salida esperada: informe con versiones de PyTorch, CUDA, GPU, kernels.

8. Capa 6 — Kernels b12x y Cuantizaciones
8.1 Verificar b12x
bash
python -c "import b12x; print(f'b12x: {b12x.__version__}')"
Salida esperada: b12x: 1.2.6.

Si muestra 1.3.0:

bash
uv pip uninstall b12x
uv pip install "vllm[b12x]" --reinstall
python -c "import b12x; print(b12x.__version__)"
8.2 Verificar soporte de kernels
bash
python << 'EOF'
from vllm.model_executor.kernels.linear.nvfp4.b12x import B12xNvFp4LinearKernel
from vllm.model_executor.kernels.linear.scaled_mm.b12x import B12xFp8BlockScaledMMKernel
from vllm.model_executor.kernels.linear.mxfp8.b12x import B12xMxfp8LinearKernel

for name, kernel in [("NVFP4", B12xNvFp4LinearKernel), ("FP8", B12xFp8BlockScaledMMKernel), ("MXFP8", B12xMxfp8LinearKernel)]:
    ok, reason = kernel.is_supported(compute_capability=120)
    print(f"{name}: {ok} — {reason}")
EOF
Salida esperada:

text
NVFP4: True — None
FP8: True — None
MXFP8: True — None
8.3 Errores comunes
Error	Causa	Solución
B12X kernels require a Blackwell 12x device	compute_cap != 12.x	Verificar nvidia-smi --query-gpu=compute_cap
b12x library not found	b12x no instalado	uv pip install "vllm[b12x]"
cutlass-dsl version mismatch	nvidia-cutlass-dsl incorrecto	Pinear a 4.4.2
nvfp4_scaled_mm_sm120_kernels.cu: linking error	vLLM sin parche para SM120	Actualizar vLLM >= 0.24
MXFP4 requires tensor-parallel weights	MXFP4 con TP=1	Usar NVFP4 en su lugar
Illegal instruction encountered	nvidia-cutlass-dsl 4.5.0	Pinear a 4.4.2
8.4 Verificar nvidia-cutlass-dsl
bash
python -c "import cutlass; print(f'cutlass-dsl: {cutlass.__version__}')"
Salida esperada: cutlass-dsl: 4.4.2.

Si muestra 4.5.0 o superior:

bash
uv pip install \
  nvidia-cutlass-dsl==4.4.2 \
  nvidia-cutlass-dsl-libs-base==4.4.2 \
  nvidia-cutlass-dsl-libs-cu13==4.4.2
8.5 Verificar selección explícita de backend
bash
vllm serve --help | grep -A2 "linear-backend"
vllm serve --help | grep -A2 "moe-backend"
Salida esperada: opciones con b12x.

Si no aparece b12x, la instalación está incompleta.

8.6 Error: b12x not selected automatically
Síntoma: Los logs muestran Using MarlinNvFp4LinearKernel en lugar de B12xNvFp4LinearKernel.

Causa: La auto-selección de vLLM omite b12x en SM120.

Solución: Especificar explícitamente al lanzar el servidor:

bash
--linear-backend b12x --moe-backend b12x
8.7 Error: primera ejecución "hang"
Síntoma: vLLM arranca, pero se queda en Loading model weights... durante 2-5 minutos con la GPU idle.

Causa: FlashInfer JIT-compila kernels NVFP4 para SM120 en el primer uso.

Solución: Esperar. No interrumpir. Se cachea tras la primera compilación.

Verificar progreso:

bash
ps aux | grep -E "(ninja|nvcc|ptxas)" | grep -v grep
Si hay procesos ninja, nvcc o ptxas, la compilación está en curso.

8.8 Verificar caché de kernels
bash
ls -la ~/.cache/vllm/
ls -la ~/.cache/flashinfer/
Salida esperada: directorios con archivos .so y .ptx.

Si el caché está corrupto:

bash
rm -rf ~/.cache/vllm/
rm -rf ~/.cache/flashinfer/
Y reiniciar el servidor.

9. Capa 7 — Modelos y Cuantización
9.1 Verificar estructura de modelos
bash
ls -lh ~/models/qwen3-coder-30b-reap50-nvfp4/
ls -lh ~/models/gemma-4-12b-awq/
ls -lh ~/models/qwen3.5-4b-nvfp4/
Salida esperada: cada directorio debe tener model.safetensors, config.json, tokenizer.json, etc.

9.2 Verificar cuantización
bash
cat ~/models/qwen3-coder-30b-reap50-nvfp4/config.json | python -m json.tool | grep -A5 quantization
cat ~/models/gemma-4-12b-awq/config.json | python -m json.tool | grep -A5 quantization
cat ~/models/qwen3.5-4b-nvfp4/config.json | python -m json.tool | grep -A5 quantization
Salida esperada:

Qwen3-Coder: "quant_method": "modelopt_fp4" (o nvfp4).

Gemma 4: "quant_method": "awq".

Qwen 3.5: "quant_method": "modelopt_fp4".

9.3 Errores comunes
Error	Causa	Solución
Error no file named pytorch_model.bin	Modelo descargado incompleto	Re-descargar con huggingface-cli
Error no file named model.safetensors	Igual que arriba	Verificar ls en el directorio
quant_method not recognized	Cuantización no soportada por vLLM	Verificar versión de vLLM
Model architecture not supported	vLLM no reconoce la arquitectura	Actualizar vLLM
Config file not found	Descarga incompleta	Re-descargar
Tokenizer error: unexpected end of file	Tokenizer corrupto	Re-descargar solo el tokenizer
RuntimeError: Error(s) in loading state_dict	Mismatch de arquitectura/cuantización	Verificar que el modelo es NVFP4, no BF16
9.4 Verificar integridad de safetensors
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
        print(f"✗ {name}: archivo no encontrado")
        continue
    try:
        with safe_open(path, framework="pt") as f:
            keys = list(f.keys())
            print(f"✓ {name}: {len(keys)} tensores válidos")
    except Exception as e:
        print(f"✗ {name}: {e}")
EOF
Salida esperada: todos con ✓.

9.5 Verificar con AutoConfig
bash
python << 'EOF'
from transformers import AutoConfig
import os

models = [
    ("~/models/qwen3-coder-30b-reap50-nvfp4", "Qwen3-Coder-30B"),
    ("~/models/gemma-4-12b-awq", "Gemma 4 12B"),
    ("~/models/qwen3.5-4b-nvfp4", "Qwen 3.5 4B"),
]

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
9.6 Error: Model is not NVFP4 quantized
Síntoma: Intentas cargar un modelo NVFP4 pero vLLM dice que no lo es.

Causa: El config.json no incluye quantization_config o el modelo es de otro formato.

Solución:

bash
cat ~/models/<modelo>/config.json | python -m json.tool | head -50
Verificar que quantization_config.quant_method está presente y es el esperado.

10. Capa 8 — Serving y Sleep Mode
10.1 Verificar que los servidores arrancan
bash
for port in 8000 8001 8002; do
  echo -n "Puerto $port: "
  curl -s --max-time 5 http://localhost:$port/v1/models | python -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "✗ No responde"
done
Salida esperada:

text
Puerto 8000: qwen3-coder-30b
Puerto 8001: gemma-4-12b
Puerto 8002: qwen3.5-4b
10.2 Errores comunes
Error	Causa	Solución
Address already in use	Puerto ocupado	pkill -f "vllm serve"
CUDA out of memory	VRAM insuficiente	Ver sección 10.3
--enable-sleep-mode not recognized	vLLM demasiado antiguo	Actualizar a >= 0.29.0
wake_up: 404 Not Found	VLLM_SERVER_DEV_MODE=1 no exportado	Exportar variable
sleep: 500 Internal Server Error	Modelo no soporta sleep	Verificar que el flag está al arrancar
Timeout waiting for model to load	Modelo tarda mucho	Aumentar timeout del cliente
RuntimeError: Engine core initialization failed	Error interno de vLLM	Ver logs completos
10.3 OOM (Out of Memory)
Síntoma: torch.cuda.OutOfMemoryError: CUDA out of memory.

Diagnóstico:

bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv
Soluciones (en orden de menor a mayor impacto):

Reducir --max-model-len:

bash
--max-model-len 8192  # En lugar de 16384
Reducir --gpu-memory-utilization:

bash
--gpu-memory-utilization 0.85  # En lugar de 0.90
Dormir otro modelo:

bash
curl -X POST http://localhost:8001/sleep?level=1
Dormir con Level 2:

bash
curl -X POST http://localhost:8000/sleep?level=2
Reiniciar el servidor:

bash
pkill -f "vllm serve"
# Relanzar con menos contexto
10.4 Verificar estado de sleep
bash
for port in 8000 8001 8002; do
  echo -n "Puerto $port: "
  curl -s http://localhost:$port/is_sleeping
  echo ""
done
Salida esperada:

text
Puerto 8000: {"is_sleeping": false}
Puerto 8001: {"is_sleeping": false}
Puerto 8002: {"is_sleeping": false}
10.5 Error: wake_up no restaura VRAM
Síntoma: Tras wake_up, la VRAM usada sigue siendo baja.

Causa: Se usó Level 2 y falta reload_weights.

Solución:

bash
curl -X POST http://localhost:8000/wake_up
curl -X POST http://localhost:8000/reload_weights
curl -X POST http://localhost:8000/reset_prefix_cache
10.6 Error: sleep tarda mucho
Síntoma: curl -X POST http://localhost:8000/sleep?level=1 tarda >30s.

Causa: Level 2 descarta pesos a disco (no a RAM).

Solución: Usar siempre Level 1 salvo que necesites liberar RAM.

10.7 Logs de servidor
bash
tail -100 ~/vllm-stack/logs/complex.log
grep -iE "(error|fail|exception|traceback)" ~/vllm-stack/logs/complex.log | tail -20
10.8 Métricas de vLLM
bash
curl -s http://127.0.0.1:8000/metrics | head -n 20   # cierre del comando cortado; no comprobado en este equipo

---

> **Continuación escrita el 19-sep-2026.** El original de este documento se cortaba aquí, a mitad de línea, y no se ha podido recuperar: faltaban el resto de la capa 8, las capas 9 a 11, «Errores por síntoma», el diagrama de diagnóstico y el reset completo. Lo que sigue **no es la receta original**: cada fila es un fallo que ocurrió de verdad al montar el stack en este equipo, con su causa y su arreglo. El detalle de cada uno está en el `11-mejoras-y-decisiones.md` (apartado indicado) y los scripts en `llm-stack/scripts/` (ver su `README.md`).

## Capas 9-11: estado real

| Capa de la receta | Estado |
|:---|:---|
| 9. Router semántico (vLLM-SR) | No se despliega. El enrutado es el modelo virtual `auto` de la pasarela (doc 11, 7.22) |
| 10. Túnel Cloudflare | **No se ha probado** |
| 11. Multiagente y concurrencia | Medido con `bench.py`; ver la sección «Concurrencia» añadida al doc 06 |

## 14. Errores por síntoma (todos vistos en este equipo)

| Síntoma exacto | Causa | Arreglo | Doc 11 |
|:---|:---|:---|:---|
| `RuntimeError: UVA is not available` al arrancar | WSL2 desactiva la memoria fijada por defecto y el ejecutor v2 de vLLM 0.29 la necesita | `VLLM_WSL2_ENABLE_PIN_MEMORY=1` (ya en `serve-model.sh`) | 7.4 |
| Un servidor sano se «cae solo» a los ~15 s, sin error y con salida 0 (`shutdown triggered`) | WSL2 apaga la distro si no hay ninguna sesión abierta; los contenedores no cuentan | `Start-WslKeepAlive.ps1` | 7.8 |
| `ValueError: No available memory for the cache blocks` | Pesos + activaciones + grafos no dejan sitio al KV | Acotar `--max-num-batched-tokens`; fijar `--kv-cache-memory` | 7.5 |
| `To serve at least one request with the model's max seq len (N), X GiB KV cache is needed` | El KV reservado es menor que el mínimo (en Gemma hay un suelo de ~1.6 GiB) | Subir el KV a lo que indica el error | 7.9 |
| `Free memory on device (14.2/15.93 GiB) … is less than desired GPU memory utilization (0.92, …)` | `--kv-cache-memory` no evita el chequeo de la fracción por defecto | Pasar además `--gpu-memory-utilization 0.5` | 7.12 |
| `CUDA error: an illegal memory access` en `profile_cudagraph_memory → capture_model` (Complejo) | `--moe-backend b12x` rompe los grafos CUDA | `--moe-backend flashinfer_cutlass` | 7.11 |
| El Complejo va a ~7 tok/s | Se arrancó con `--enforce-eager` | Quitarlo, con el backend MoE anterior | 7.11 |
| **Arranque parado sin excepción, un proceso al 100 % de CPU; `check-cuda.sh` tampoco termina** | CUDA roto bajo WSL2, normalmente tras un `illegal memory access` previo | `wsl --shutdown` y volver a lanzar `Start-WslKeepAlive.ps1`. **No lo atribuyas a vLLM sin ejecutar antes `check-cuda.sh`** | 7.17 |
| `illegal memory access` en la primera petición con `--kv-offloading-size` | El conector de KV a RAM no funciona bajo WSL2 (y puede dejar CUDA roto) | No usarlo | 7.15 |
| Tras despertar de Sleep Mode **nivel 2** rinde bien pero responde `'HereC1112222…'` | `reload_weights` no restaura los pesos NVFP4 ya reempaquetados | No usar el nivel 2 | 7.17 |
| Con Sleep Mode nivel 1 la RAM de WSL2 llega al 100 % y aparece swap | Los buffers de la copia en RAM no se liberan al despertar | Un solo modelo; parar el contenedor para liberar | 7.17 |
| HTTP 400 `"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set` | Faltan los flags de *tool calling* | `--enable-auto-tool-choice --tool-call-parser qwen3_coder` | 7.21 |
| `vllm serve --help` no imprime nada / `Failed to infer device type` | Sin `--gpus all` | Añadirlo (`vllm-help.sh` ya lo hace) | 7.21 |
| `nvidia-smi` marca 2.3 GiB con el Router cargado | Windows (WDDM) desaloja memoria de la GPU a RAM sin avisar | Medir **después** de dar carga; no pasarse de la VRAM física | 7.9 |
| El Router va a ~3 tok/s | `--cpu-offload-gb` en un modelo denso: se relee todo lo offloadeado en cada token | No usarlo | 7.13 |
| Un modelo «va bien» (buen tok/s) pero responde basura | Corrupción silenciosa: el benchmark de velocidad no la ve | `chat-check.py` tras arrancar o despertar cualquier modelo | 7.17, 7.18 |
| El Router se queda sin terminar y el código sale cortado (`SyntaxError`) | Bucle de repetición con temperatura 0, cortado por `max_tokens` | Temperatura > 0 o penalización de repetición | 7.23 |
| La misma evaluación con temperatura 0 da resultados distintos | vLLM no es determinista bajo carga concurrente | Dar rangos y no comparar pasadas sueltas | 7.23 |
| `Start-Stack.ps1` desde la tarea programada falla con `Join-Path … cadena vacía` | `$PSScriptRoot` llega vacío en el valor por defecto de un parámetro con `powershell.exe -File` | Calcular la ruta en el cuerpo del script | Bitácora (§8), 19-sep |
| `serve-model.sh: line N: -p: command not found` (código 127) | Se editó el script **mientras se ejecutaba**: bash lo lee por posición | No editar un script en ejecución | `llm-stack/scripts/README.md` |
| El arranque del stack aborta antes de lanzar los modelos porque la pasarela «no responde» | (corregido) `/health` sondeaba dentro de la petición y tardaba ≥ 2 s | La pasarela sondea en segundo plano | 7.19 |

## 15. Diagnóstico rápido

```
¿No arranca o no responde?

 1. check-cuda.sh
      └─ no termina en "CUDA OK"  →  wsl --shutdown  +  Start-WslKeepAlive.ps1  →  repetir el 1
 2. docker ps -a
      └─ el contenedor no existe o está "Exited"  →  log-summary.sh <rol>
         (el traceback final de vLLM es siempre "Engine core initialization failed":
          la causa está VARIAS LÍNEAS ANTES, en el proceso EngineCore)
 3. Está "Up" pero /health no responde
      └─ ¿un proceso al 100 % de CPU sin progreso?  →  vuelve al 1
 4. Responde pero mal
      └─ chat-check.py  (¿basura?)      tools-check.py  (¿herramientas?)
 5. Responde pero lento
      └─ bench.py y compara con: Router 78, Gemma 44, Complejo 100 tok/s a 1 cliente
         ¿VRAM al límite tras dar carga?  →  7.9
```

## 16. Reset completo del stack

```powershell
.\scripts\Stop-Stack.ps1 -ReleaseWsl     # para modelos y pasarela, libera la GPU y la RAM de WSL2
wsl --shutdown                           # solo si CUDA está roto
.\scripts\Start-Stack.ps1 -Profile B     # A, B, complex-solo o none
```

Las cachés de compilación (`~/.cache/vllm`, `~/.cache/flashinfer` en WSL2) **no se borran** salvo sospecha fundada: la primera vez cuestan 2-5 minutos de arranque por modelo y no se ha visto ninguna corrupta. La imagen queda fijada por digest en `llm-stack/scripts/vllm-image.lock`.

## 17. Referencias

| Recurso | Dónde |
|:---|:---|
| Todo lo medido y decidido, con su bitácora | `11-mejoras-y-decisiones.md` |
| Scripts y las lecciones que costó aprender | `llm-stack/scripts/README.md` |
| La pasarela | `llm-stack/gateway/README.md` |
