#!/bin/bash
# Comprueba que CUDA funciona dentro de un contenedor de vLLM, con un limite de tiempo. Se ejecuta
# como el usuario de Ubuntu, sin ningun servidor vLLM levantado (para que no compitan).
#
# Uso:  bash check-cuda.sh [segundos-de-limite]      (por defecto 90)
#
# Si termina con "CUDA OK", el fallo de un arranque colgado esta en vLLM o en su configuracion.
# Si se queda parado o falla, la GPU o el controlador de WSL2 estan en mal estado: prueba
# `wsl --shutdown` desde Windows (y vuelve a lanzar Start-WslKeepAlive.ps1).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="$(cat "$SCRIPT_DIR/vllm-image.local")"
LIMIT="${1:-90}"

timeout "$LIMIT" docker run --rm --gpus all --ipc=host --entrypoint python3 \
  -v "$SCRIPT_DIR:/scripts:ro" "$IMAGE" /scripts/cuda-smoke.py 2>&1 | grep -v -E "^(INFO|WARNING) "
status=${PIPESTATUS[0]}

if [ "$status" -eq 124 ]; then
  echo "== SIN RESPUESTA en ${LIMIT} s: CUDA se ha quedado parado. Probable estado roto de la GPU/WSL2 =="
  exit 124
fi
exit "$status"
