#!/bin/bash
# Instala Docker Engine y NVIDIA Container Toolkit dentro de Ubuntu (WSL2), segun el doc 01,
# secciones 4.4-4.8 y 5.3. Se ejecuta como ROOT, asi que no lleva sudo:
#
#   wsl -d Ubuntu -u root -e bash /mnt/d/Repositorios/NexoDeck/llm-stack/scripts/install-docker-engine.sh [usuario]
#
# El usuario que entra en el grupo `docker` es el argumento, o la variable TARGET_USER, o el
# primer usuario normal de la distro (uid 1000). Docker Desktop tiene que estar desinstalado:
# con los dos activos chocan los sockets (doc 01 §9.4).
#
# Es idempotente: se puede relanzar. OJO: reinicia el servicio docker al final, asi que corta
# cualquier `docker pull` o contenedor en marcha.
#
# Notas de la primera ejecucion (18-sep-2026, Ubuntu 26.04 "resolute"): Docker publica paquetes
# para esta version, el toolkit de NVIDIA tambien, y `docker info` da Storage Driver `overlayfs`
# (snapshotter de containerd) en vez del `overlay2` que cita el doc.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ejecutalo como root: wsl -d Ubuntu -u root -e bash <este script>" >&2
  exit 1
fi

TARGET_USER="${1:-${TARGET_USER:-$(getent passwd 1000 | cut -d: -f1)}}"
if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "No encuentro el usuario '$TARGET_USER'. Pasalo como argumento." >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
arch="$(dpkg --print-architecture)"
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"

echo "== 0. Comprobando que los repositorios publican paquetes para '$codename' =="
docker_status="$(curl -s -o /dev/null -w '%{http_code}' "https://download.docker.com/linux/ubuntu/dists/${codename}/stable/binary-${arch}/Packages")"
nvidia_status="$(curl -s -o /dev/null -w '%{http_code}' "https://nvidia.github.io/libnvidia-container/stable/deb/${arch}/Packages")"
echo "docker: $docker_status  nvidia-container-toolkit: $nvidia_status"
if [ "$docker_status" != "200" ] || [ "$nvidia_status" != "200" ]; then
  echo "Un repositorio no responde 200 para esta distro; revisa antes de seguir." >&2
  exit 1
fi

echo "== 1. Dependencias =="
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

echo "== 2. Repositorio de Docker =="
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y

echo "== 3. Docker Engine =="
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "== 4. NVIDIA Container Toolkit =="
rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/${arch} /" \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker

echo "== 5. Servicios y usuario =="
systemctl enable docker.service containerd.service
systemctl restart docker
usermod -aG docker "$TARGET_USER"

echo "== 6. Verificacion =="
docker --version
docker info | grep -E "Server Version|Storage Driver|Cgroup"
cat /etc/docker/daemon.json
docker run --rm hello-world | head -3
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader
echo "== LISTO. '$TARGET_USER' debe reabrir su sesion (wsl --terminate <distro>) para usar docker sin sudo =="
