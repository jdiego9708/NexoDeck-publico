#!/bin/bash
# Muestra la ayuda de `vllm serve` para uno o varios flags, con su descripcion y sus valores
# validos, tal como los conoce la imagen local. Es la fuente fiable: buscar en el codigo con grep
# falla porque los registros cambian de forma de una version a otra.
#
# Uso:  bash vllm-help.sh <flag> [flag ...]
# Ej.:  bash vllm-help.sh --tool-call-parser --reasoning-parser --default-chat-template-kwargs
set -uo pipefail

[ $# -ge 1 ] || { echo "Uso: $0 <flag> [flag ...]" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="$(cat "$SCRIPT_DIR/vllm-image.local")"

# Con --gpus all: sin GPU, `vllm serve --help` muere con "Failed to infer device type" (construye
# los argumentos a partir de la configuracion del dispositivo) y no imprime nada.
help_text="$(docker run --rm --gpus all --entrypoint vllm "$IMAGE" serve --help=all 2>/dev/null)"

for flag in "$@"; do
  echo "== $flag"
  # Desde la linea del flag hasta el siguiente flag (una linea que empieza por espacios y '-').
  awk -v flag="$flag" '
    index($0, flag) && /^ +-/ { printing = 1; print; next }
    printing && /^ +-/ { printing = 0 }
    printing { print }
  ' <<<"$help_text" | head -n 40
  echo
done
