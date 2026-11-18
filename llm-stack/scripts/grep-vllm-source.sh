#!/bin/bash
# Busca un patron en el codigo de vLLM DENTRO de la imagen local, sin arrancar ningun modelo.
# Sirve para entender un fallo concreto cuando el mensaje del motor no dice mas (p. ej.
# "UVA is not available") y para descubrir variables de entorno o flags que la documentacion no cita.
#
# Uso:  bash grep-vllm-source.sh <patron-regex> [ruta-relativa-dentro-de-vllm]
# Ej.:  bash grep-vllm-source.sh 'def is_uva_available' utils
#       bash grep-vllm-source.sh 'MODEL_RUNNER' envs.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="$(cat "$SCRIPT_DIR/vllm-image.local")"
PATTERN="${1:?Falta el patron}"
WHERE="${2:-.}"

docker run --rm --entrypoint grep "$IMAGE" -rn -E "$PATTERN" \
  "/usr/local/lib/python3.12/dist-packages/vllm/$WHERE" --include='*.py' | head -n 40
