#!/bin/bash
# Construye la imagen local `nexodeck-vllm:<version>-b12x` a partir de la fijada en vllm-image.lock
# (Dockerfile.vllm). Se ejecuta como el usuario de Ubuntu.
#
# Uso:  bash build-vllm-image.sh
#
# La version de vLLM se lee de la propia imagen base, para que el extra [b12x] coincida con ella.
# Si cambias vllm-image.lock, vuelve a construir y a pasar el benchmark antes de fiarte.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_IMAGE="$(grep '^image=' "$SCRIPT_DIR/vllm-image.lock" | cut -d= -f2-)"

# La version se lee de los metadatos del paquete, no de `vllm --version`: este ultimo mezcla avisos
# (Triton, WSL...) con la version y sin GPU la ultima linea ya no es la version.
VLLM_VERSION="$(docker run --rm --entrypoint python3 "$BASE_IMAGE" -m pip show vllm | sed -n 's/^Version: //p')"
if [ -z "$VLLM_VERSION" ]; then
  echo "No he podido leer la version de vLLM de la imagen base." >&2
  exit 1
fi
TAG="nexodeck-vllm:${VLLM_VERSION}-b12x"

echo "Base:    $BASE_IMAGE"
echo "vLLM:    $VLLM_VERSION"
echo "Destino: $TAG"

docker build \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "VLLM_VERSION=$VLLM_VERSION" \
  -t "$TAG" \
  -f "$SCRIPT_DIR/Dockerfile.vllm" \
  "$SCRIPT_DIR"

echo "== Construida: $TAG =="
docker image ls "nexodeck-vllm" --format '{{.Repository}}:{{.Tag}}  {{.Size}}  {{.ID}}'
echo "$TAG" > "$SCRIPT_DIR/vllm-image.local"
