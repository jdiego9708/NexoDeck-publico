---
date: 2026-09-17
---
# 01-TOOLS.md

Configuración del Entorno Base

Documentación completa para preparar el entorno de ejecución del stack vLLM multiagente sobre Windows 11 + WSL2 + Docker Engine, con acceso completo a la GPU Blackwell RTX 5060 Ti (SM120).

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Arquitectura del Entorno](#2-arquitectura-del-entorno)
3. [Paso 1 — Configurar `.wslconfig` en Windows](#3-paso-1--configurar-wslconfig-en-windows)
4. [Paso 2 — Instalar Docker Engine dentro de Ubuntu (WSL2)](#4-paso-2--instalar-docker-engine-dentro-de-ubuntu-wsl2)
5. [Paso 3 — Instalar NVIDIA Container Toolkit en Ubuntu](#5-paso-3--instalar-nvidia-container-toolkit-en-ubuntu)
6. [Paso 4 — Verificación Completa del Entorno](#6-paso-4--verificación-completa-del-entorno)
7. [Paso 5 — Preparar Directorios de Trabajo](#7-paso-5--preparar-directorios-de-trabajo)
8. [Checklist Final](#8-checklist-final)
9. [Advertencias Críticas](#9-advertencias-críticas)
10. [Referencias](#10-referencias)

---

## 1. Contexto y Objetivos

Este documento prepara la **capa base de infraestructura** sobre la cual se construirá el resto del stack:

- **Windows 11 Pro** como sistema operativo anfitrión.
- **WSL2 con Ubuntu** como entorno Linux de ejecución.
- **Docker Engine nativo** (no Docker Desktop) para contenedores.
- **NVIDIA Container Toolkit** para passthrough de GPU a contenedores.
- **systemd habilitado** en WSL2 para gestión de servicios.

El objetivo es tener un entorno **reproducible, autocontenido y libre de dependencias de aplicaciones Windows**, salvo el driver NVIDIA (que debe permanecer en Windows) y el túnel Cloudflare (que se configura en fases posteriores y sí corre en Windows).

### Hardware objetivo

| Componente | Valor |
|:---|:---|
| **GPU** | NVIDIA RTX 5060 Ti 16 GB (Blackwell, compute_cap **12.0** / SM120) |
| **CPU** | AMD Ryzen 7 5700X (8c/16t) |
| **RAM** | 32 GB DDR4 |
| **Driver NVIDIA** | 591.86 / CUDA 13.1 |
| **OS** | Windows 11 Pro (Build 26200) |
| **WSL2** | v2.7.13 o superior |
| **Docker Engine** | 29.x o superior (dentro de Ubuntu) |

---

## 2. Arquitectura del Entorno
┌──────────────────────────────────────────────────────────┐
│ WINDOWS 11 PRO (host) │
│ ├─ Driver NVIDIA 591.86 (indispensable en Windows) │
│ ├─ WSL2 v2.7.13 (backend de virtualización ligera) │
│ └─ Túnel Cloudflare (corre aquí, fases posteriores) │
└──────────────────────┬───────────────────────────────────┘
│ WSL2
▼
┌──────────────────────────────────────────────────────────┐
│ UBUNTU (distro WSL2) │
│ ├─ systemd habilitado │
│ ├─ Docker Engine 29.x (nativo, sin Docker Desktop) │
│ ├─ containerd.io │
│ ├─ NVIDIA Container Toolkit │
│ └─ Directorios de trabajo (/home/usuario/vllm-stack) │
└──────────────────────┬───────────────────────────────────┘
│ GPU passthrough
▼
┌──────────────────────────────────────────────────────────┐
│ CONTENEDORES DOCKER (fases posteriores) │
│ ├─ vLLM con b12x kernels │
│ ├─ Modelos NVFP4 y AWQ │
│ └─ Router semántico vLLM-SR │
└──────────────────────────────────────────────────────────┘

### Decisiones arquitectónicas y justificación

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Docker Engine nativo en WSL2** | Docker Desktop | Elimina capa de indirección, consume menos RAM, control total del daemon, y es lo que vLLM recomienda oficialmente |
| **systemd habilitado en WSL2** | Arranque manual de servicios | Permite `systemctl enable docker`, arranque automático, y comportamiento equivalente a un servidor Linux real |
| **NVIDIA Container Toolkit dentro de WSL2** | Toolkit en Windows | El driver NVIDIA debe permanecer en Windows, pero el runtime de contenedores debe estar dentro de WSL2 |
| **WSL2 con 28 GB de RAM asignados** | 16 GB por defecto | Con 3 modelos y JIT compilation de NVFP4, se necesita más memoria para Sleep Mode y compilación |
| **8 GB de swap** | 2 GB por defecto | Margen para picos de compilación JIT de kernels b12x |

---

## 3. Paso 1 — Configurar `.wslconfig` en Windows

### 3.1 ¿Qué es `.wslconfig`?

Es un archivo de configuración global que controla cómo se comporta WSL2 en el sistema. Se ubica en el perfil del usuario de Windows.

### 3.2 ¿Por qué es crítico?

WSL2 asigna por defecto **solo el 50% de la RAM del sistema** (~16 GB de tus 32 GB). Con 3 modelos vLLM y compilación JIT de kernels NVFP4, necesitas más memoria para:

- Mantener el modelo inactivo en RAM durante Sleep Mode.
- Compilar kernels b12x en el primer arranque.
- Soportar el caché KV de múltiples agentes concurrentes.

### 3.3 Procedimiento

Abrir **PowerShell** (no requiere administrador):
notepad $env:USERPROFILE\.wslconfig

Si el archivo no existe, notepad preguntará si deseas crearlo. Aceptar.

3.4 Contenido completo
ini
[wsl2]
memory=28GB
processors=12
swap=8GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
3.5 Explicación de cada parámetro
Parámetro	Valor	Razón
memory=28GB	28 GB	Deja ~4 GB para Windows (navegadores, VS Code, terminal). Evita que el host se congele.
processors=12	12 hilos	Deja 4 hilos para Windows. El Ryzen 7 5700X tiene 16 hilos totales.
swap=8GB	8 GB	Margen para picos de compilación JIT de kernels NVFP4.
localhostForwarding=true	Activado	Permite que localhost en Windows llegue a servicios en WSL2 (necesario para el túnel Cloudflare).
autoMemoryReclaim=gradual	Gradual	Devuelve RAM no usada de WSL2 a Windows automáticamente.
sparseVhd=true	Activado	Reduce el tamaño del disco virtual de WSL2 (importante con modelos grandes).
Advertencia: autoMemoryReclaim debe estar en [experimental], no en [wsl2]. Si lo pones en [wsl2], WSL mostrará wsl: Clave 'wsl2.autoMemoryReclaim' desconocida.

3.6 Aplicar cambios
powershell
wsl --shutdown
Esperar 10 segundos y luego abrir Ubuntu:

powershell
wsl -d Ubuntu
3.7 Verificar
Dentro de Ubuntu:

bash
free -h
Salida esperada: Mem: 28Gi total (o similar).

bash
nproc
Salida esperada: 12.

4. Paso 2 — Instalar Docker Engine dentro de Ubuntu (WSL2)
4.1 ¿Por qué NO usar Docker Desktop?
Docker Desktop añade una capa de indirección (daemon en Windows + CLI vía socket), consume ~1-2 GB extra de RAM en procesos Windows, y su integración con WSL2 puede fallar en el passthrough de GPU. Además, su licencia requiere pago para empresas con >250 empleados o >$10M de ingresos anuales.

vLLM recomienda oficialmente Docker Engine nativo dentro de WSL2. Esto:

Elimina la dependencia de la GUI.

Da control total del daemon.

Hace el passthrough de GPU más limpio y predecible.

Reduce el consumo de RAM.

4.2 Comparativa
Aspecto	Docker Desktop	Docker Engine en WSL2
Instalación	App Windows + backend WSL2	apt install docker-ce en Ubuntu
Licencia	Comercial (con restricciones)	Apache 2.0 (libre)
RAM extra	~1-2 GB en Windows	~100 MB (solo dockerd)
GPU passthrough	Depende de integración WSL	Directo con NVIDIA Container Toolkit
Control del daemon	Limitado por GUI	Total
Arranque automático	Se inicia con Windows	Vía systemd en WSL2
Compatibilidad vLLM	Funciona	Recomendado oficialmente
4.3 Eliminar Docker Desktop previo (si aplica)
Si ya activaste la integración de Docker Desktop con Ubuntu:

Docker Desktop → Settings → Resources → WSL Integration → Desactivar toggle de Ubuntu.

Cerrar Docker Desktop.

En Ubuntu, eliminar rastros:

bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo rm -rf /var/lib/docker /var/lib/containerd
Si nunca activaste la integración, salta directamente a 4.4.

4.4 Instalar Docker Engine
Abrir Ubuntu desde PowerShell:

powershell
wsl -d Ubuntu
Ejecutar dentro de Ubuntu:

bash
# 1. Actualizar índices de paquetes
sudo apt-get update

# 2. Instalar dependencias
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# 3. Crear directorio de claves
sudo mkdir -p /etc/apt/keyrings

# 4. Añadir clave GPG oficial de Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 5. Permisos de lectura para la clave
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 6. Añadir repositorio de Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 7. Actualizar índices con el nuevo repositorio
sudo apt-get update

# 8. Instalar Docker Engine
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
4.5 Verificar la instalación
bash
sudo docker --version
Salida esperada: Docker version 29.x.x, build xxxxx.

bash
sudo systemctl --no-pager status containerd
Debería mostrar Active: active (running).

4.6 Habilitar systemd en WSL2
WSL2 no usa systemd por defecto. Sin esto, Docker no arranca automáticamente al iniciar WSL.

Crear /etc/wsl.conf:

bash
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true
EOF
Reiniciar WSL desde PowerShell:

powershell
wsl --shutdown
wsl -d Ubuntu
Verificar systemd dentro de Ubuntu:

bash
systemctl --version
Salida esperada: systemd 255 (o superior).

bash
ps -p 1 -o comm=
Salida esperada: systemd.

4.7 Habilitar Docker como servicio
bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
sudo systemctl start docker
sudo systemctl status docker
Salida esperada: Active: active (running) en verde.

Alternativa sin systemd: si prefieres no habilitar systemd, inicia Docker manualmente en cada sesión con sudo service docker start. Menos elegante, pero funcional.

4.8 Habilitar Docker sin sudo
bash
sudo usermod -aG docker $USER
newgrp docker
Cierra y reabre la sesión de Ubuntu (o el terminal) para que el grupo se aplique.

Verificar:

bash
docker --version
docker run --rm hello-world
Salida esperada: mensaje Hello from Docker!.

4.9 Verificación de la sección
bash
docker info | grep -E "Server Version|Storage Driver|Cgroup"
Salida esperada:

text
Server Version: 29.x.x
Storage Driver: overlay2
Cgroup Driver: systemd
Cgroup Version: 2
Si todo funciona sin sudo y los datos anteriores aparecen, la instalación de Docker Engine está completa.

5. Paso 3 — Instalar NVIDIA Container Toolkit en Ubuntu
5.1 ¿Qué es?
Es el runtime que permite a los contenedores Docker acceder a la GPU del host. Sin él, un contenedor con --gpus all no verá la RTX 5060 Ti.

5.2 ¿Por qué dentro de WSL2 y no en Windows?
El driver NVIDIA debe permanecer en Windows (es el que da acceso a la GPU a WSL2). Pero el runtime de contenedores (que traduce las llamadas de Docker a CUDA) debe estar dentro de WSL2 porque es ahí donde corren los contenedores.

NO instales drivers NVIDIA ni CUDA Toolkit dentro de WSL2. Los drivers de Windows son los que dan acceso a la GPU. Los contenedores Docker ya incluyen su propio CUDA. Instalarlos dentro de WSL causará conflictos.

5.3 Instalación
Todos los comandos dentro de Ubuntu (WSL2):

bash
# 1. Eliminar repositorios previos que puedan causar conflictos
sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 2. Añadir clave GPG oficial de NVIDIA
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# 3. Añadir repositorio
echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] \
  https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 4. Actualizar índices
sudo apt-get update

# 5. Instalar el toolkit
sudo apt-get install -y nvidia-container-toolkit

# 6. Configurar runtime Docker
sudo nvidia-ctk runtime configure --runtime=docker

# 7. Reiniciar Docker para aplicar
sudo systemctl restart docker
5.4 Verificar la configuración
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
Si daemon.json no contiene el runtime nvidia, la configuración falló. Repite el paso 5.3 desde el comando 6.

6. Paso 4 — Verificación Completa del Entorno
Esta sección consolida todas las verificaciones. Ejecutar en orden.

6.1 Verificar GPU desde Windows
En PowerShell:

powershell
nvidia-smi
Salida esperada: información de la RTX 5060 Ti, driver 591.86, CUDA 13.1.

6.2 Verificar GPU desde WSL2
En PowerShell:

powershell
wsl -d Ubuntu -e bash -c "nvidia-smi"
Salida esperada: idéntica a la del paso 6.1.

6.3 Verificar Compute Capability
Dentro de Ubuntu:

bash
nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv
Salida esperada:

text
name, compute_cap, driver_version
NVIDIA GeForce RTX 5060 Ti, 12.0, 591.86
Si compute_cap no es 12.0, detente aquí. Los kernels b12x y NVFP4 no funcionarán.

6.4 Verificar Docker sin sudo
Dentro de Ubuntu:

bash
docker --version
docker run --rm hello-world
Salida esperada: mensaje Hello from Docker!.

6.5 Verificar GPU desde contenedor Docker (prueba definitiva)
Dentro de Ubuntu:

bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
Salida esperada: la misma información de la RTX 5060 Ti que en 6.1.

Si este comando falla, la instalación del NVIDIA Container Toolkit está incompleta o mal configurada.

6.6 Verificar memoria y CPU asignados a WSL2
Dentro de Ubuntu:

bash
free -h
nproc
Salida esperada:

free -h → Mem: 28Gi total

nproc → 12

6.7 Verificar systemd
Dentro de Ubuntu:

bash
systemctl --version
systemctl is-system-running
Salida esperada:

systemd 255 (o superior)

running o degraded (ambos aceptables; degraded no es un error crítico en WSL2)

7. Paso 5 — Preparar Directorios de Trabajo
Estructura de directorios para el stack completo. No se crean contenedores ni se descargan modelos aquí; solo la organización de carpetas.

7.1 Crear estructura base
Dentro de Ubuntu:

bash
# Directorio raíz del stack
mkdir -p ~/vllm-stack

# Subdirectorios
mkdir -p ~/vllm-stack/logs
mkdir -p ~/vllm-stack/router
mkdir -p ~/vllm-stack/replay
mkdir -p ~/vllm-stack/RSIAgent

# Directorio de modelos
mkdir -p ~/models

# Directorio de memoria persistente para RSIAgent
mkdir -p ~/.rsiaagent/memory
7.2 Verificar estructura
bash
tree -L 2 ~/vllm-stack
Salida esperada:

text
/home/juan/vllm-stack
├── RSIAgent
├── logs
├── replay
└── router
Si tree no está instalado:

bash
sudo apt-get install -y tree
7.3 Verificar espacio en disco
bash
df -h ~
Necesitas: al menos 35 GB libres en el sistema de archivos de Ubuntu.

Si el disco está ajustado, mover los modelos a /mnt/d/ (disco D: de Windows montado en WSL2):

bash
mkdir -p /mnt/d/vllm-models
Y configurar la variable de entorno para que Hugging Face use ese directorio:

bash
echo 'export HF_HOME=/mnt/d/vllm-models' >> ~/.bashrc
source ~/.bashrc
8. Checklist Final
Antes de pasar a la Fase 2 (instalación de vLLM), verificar todos los puntos:

Windows
□ .wslconfig creado con memory=28GB, processors=12, swap=8GB
□ autoMemoryReclaim=gradual en [experimental]
□ nvidia-smi funciona en PowerShell
□ Driver NVIDIA 591.86 (o superior) instalado
WSL2
□ WSL2 v2.7.13 (o superior)
□ Ubuntu distro disponible
□ free -h muestra ~28 GB de RAM
□ nproc muestra 12
□ nvidia-smi funciona dentro de Ubuntu
Docker
□ Docker Engine 29.x instalado (no Docker Desktop)
□ docker --version funciona sin sudo
□ docker run --rm hello-world funciona
□ docker info muestra Cgroup Version: 2
□ systemctl is-system-running responde
NVIDIA Container Toolkit
□ Toolkit instalado
□ /etc/docker/daemon.json incluye runtime nvidia
□ docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi funciona
Directorios
□ ~/vllm-stack/ con subdirectorios logs, router, replay, RSIAgent
□ ~/models/ creado
□ ~/.rsiaagent/memory/ creado
□ Al menos 35 GB libres en disco
Compute Capability
□ compute_cap reportado como 12.0
9. Advertencias Críticas
9.1 NO instalar drivers NVIDIA dentro de WSL2
Los drivers deben permanecer solo en Windows. WSL2 usa el driver del host para acceder a la GPU. Instalar un driver dentro de WSL2 puede romper el passthrough.

9.2 NO instalar CUDA Toolkit en WSL2 (para este stack)
Los contenedores Docker de vLLM ya incluyen su propio CUDA. Instalar CUDA Toolkit en WSL2 puede causar conflictos de versiones con los contenedores.

9.3 autoMemoryReclaim va en [experimental], NO en [wsl2]
Si se coloca en [wsl2], WSL muestra wsl: Clave 'wsl2.autoMemoryReclaim' desconocida y la opción se ignora.

9.4 Docker Desktop debe desactivarse si estaba activo
Si activaste la integración WSL de Docker Desktop previamente, desactívala antes de instalar Docker Engine nativo. Tener ambos activos causa conflictos de socket.

9.5 systemd=true requiere WSL2 v0.67.6 o superior
Si tu WSL2 es anterior, actualiza con:

powershell
wsl --update
9.6 El túnel Cloudflare NO va en WSL2
El túnel se ejecuta en Windows (fases posteriores) y se comunica con WSL2 vía localhostForwarding=true. No lo instales dentro de Ubuntu.

9.7 Los 28 GB de RAM son para WSL2, no para un contenedor
WSL2 asigna esa RAM a la VM Linux completa. Dentro, Docker y los contenedores comparten ese presupuesto. Si corres 3 modelos simultáneos, no todos cabrán en RAM; de ahí la necesidad de Sleep Mode.

10. Referencias
Recurso	URL
Documentación oficial de WSL2	https://learn.microsoft.com/en-us/windows/wsl/
Configuración avanzada de WSL2	https://learn.microsoft.com/en-us/windows/wsl/wsl-config
Docker Engine en Ubuntu	https://docs.docker.com/engine/install/ubuntu/
Docker post-install (sin sudo)	https://docs.docker.com/engine/install/linux-postinstall/
NVIDIA Container Toolkit	https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/
systemd en WSL2	https://devblogs.microsoft.com/commandline/systemd-support-is-now-available-in-wsl/
vLLM Docs (referencia general)	https://docs.vllm.ai
Próximos pasos
Una vez completado el checklist final de este documento, el entorno está listo para la Fase 2: Instalación de vLLM con kernels b12x.

El siguiente archivo de documentación (02-vLLM-Installation.md) asume:

Docker Engine funcionando con GPU passthrough verificado.

systemd activo.

Directorios creados.

Compute capability 12.0 confirmada.
