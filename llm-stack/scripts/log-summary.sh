#!/bin/bash
# Resume el registro de un servidor vLLM sin volcar el fichero entero (un arranque genera cientos de
# lineas y casi todas son ruido). Muestra los kernels y backends elegidos, la memoria medida y
# las excepciones. Se ejecuta como el usuario de Ubuntu.
#
# Uso:  bash log-summary.sh <router|fast|complex> [lineas-de-contexto-tras-el-primer-error]
set -euo pipefail

ROLE="${1:?Uso: $0 <router|fast|complex> [contexto]}"
CONTEXT="${2:-0}"
LOG="$HOME/vllm-stack/logs/vllm-$ROLE.log"

# Si el contenedor sigue existiendo, se refresca el fichero desde el.
if docker ps -a --format '{{.Names}}' | grep -qx "vllm-$ROLE"; then
  docker logs "vllm-$ROLE" > "$LOG" 2>&1 || true
fi
[ -f "$LOG" ] || { echo "No hay registro de $ROLE en $LOG" >&2; exit 1; }

echo "== Kernels y backends elegidos =="
grep -E "\] Using .*(Kernel|kernel|backend|Backend)" "$LOG" | sed 's/^.*\] //' | sort -u | head -n 20

echo "== Memoria =="
grep -E "Model loading took|Available KV|GPU KV cache size|Actual usage|reserved .* for KV|CUDA graph pool" "$LOG" | sed 's/^.*\] //' | head -n 10

echo "== Excepciones (la causa esta en la primera) =="
grep -n -E "(Error|Exception):|out of memory" "$LOG" | sed 's/^\([0-9]*\):.*\] /\1: /' | awk '!seen[$0]++' | head -n 8

if [ "$CONTEXT" -gt 0 ]; then
  first="$(grep -n -E "ERROR .*Traceback" "$LOG" | head -n 1 | cut -d: -f1 || true)"
  if [ -n "$first" ]; then
    echo "== Traceback (desde la linea $first) =="
    sed -n "${first},$((first + CONTEXT))p" "$LOG" | sed 's/^.*core.py:[0-9]*\] //'
  fi
fi
