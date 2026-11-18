#!/bin/bash
# Inspecciona una imagen de vLLM: versiones, GPU visible, arquitecturas, cuantizaciones, kernels
# b12x y cuales de los flags que usa la receta existen de verdad. No arranca ningun modelo.
# Se ejecuta como el usuario de Ubuntu.
#
# Uso:  bash inspect-vllm-image.sh [imagen]
# Sin argumento usa la fijada en vllm-image.lock; con `local` usa la derivada de
# build-vllm-image.sh (vllm-image.local).
#
# Sirve para contrastar la receta (docs 02 y 04) con la imagen real ANTES de escribir comandos
# de arranque: la receta cita flags de una version concreta y pueden haber cambiado de nombre.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-lock}" in
  lock) IMAGE="$(grep '^image=' "$SCRIPT_DIR/vllm-image.lock" | cut -d= -f2-)" ;;
  local) IMAGE="$(cat "$SCRIPT_DIR/vllm-image.local")" ;;
  *) IMAGE="$1" ;;
esac
echo "Imagen: $IMAGE"

run_in_image() {
  docker run --rm --gpus all --entrypoint "$1" -v "$SCRIPT_DIR:/scripts:ro" "$IMAGE" "${@:2}"
}

echo "== vllm --version =="
run_in_image vllm --version 2>&1 | tail -n 1

echo "== Contenido de la imagen (python) =="
run_in_image python3 /scripts/inspect-vllm.py 2>&1 | grep -v -E "^(INFO|WARNING) " || true

echo "== Flags de 'vllm serve' que usa la receta =="
help_text="$(run_in_image vllm serve --help=all 2>&1 || true)"
for flag in --linear-backend --moe-backend --enable-sleep-mode --cpu-offload-gb --kv-cache-dtype \
            --enable-prefix-caching --enable-chunked-prefill --max-num-seqs --gpu-memory-utilization \
            --enforce-eager --language-model-only --limit-mm-per-prompt --tool-call-parser \
            --speculative-config --kv-offloading-size --api-key --max-model-len --quantization; do
  if grep -q -- "$flag" <<<"$help_text"; then echo "   existe   $flag"; else echo "   FALTA    $flag"; fi
done
