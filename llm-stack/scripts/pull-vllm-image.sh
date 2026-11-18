#!/bin/bash
# Descarga la imagen de vLLM y guarda su digest en vllm-image.lock, junto a este script (doc 11 §3:
# los pines de b12x y cutlass-dsl solo son reproducibles si la imagen esta fijada, no con :latest).
#
# Uso:  bash pull-vllm-image.sh [etiqueta]        (por defecto: latest)
#
# El lock guarda `repositorio@sha256:...`. Los scripts de arranque deben usar ESA referencia, y
# solo se cambia el lock deliberadamente, tras pasar el benchmark con la imagen nueva.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="vllm/vllm-openai"
TAG="${1:-latest}"
LOCK_FILE="$SCRIPT_DIR/vllm-image.lock"

echo "== $(date +%T) Descargando $REPOSITORY:$TAG =="
docker pull "$REPOSITORY:$TAG"

digest="$(docker image inspect "$REPOSITORY:$TAG" --format '{{index .RepoDigests 0}}')"
size="$(docker image inspect "$REPOSITORY:$TAG" --format '{{.Size}}')"
created="$(docker image inspect "$REPOSITORY:$TAG" --format '{{.Created}}')"

{
  echo "# Imagen de vLLM fijada. Generado por pull-vllm-image.sh el $(date +%F)."
  echo "image=$digest"
  echo "tag=$TAG"
  echo "size_bytes=$size"
  echo "created=$created"
} > "$LOCK_FILE"

echo "== Fijada: $digest =="
cat "$LOCK_FILE"
