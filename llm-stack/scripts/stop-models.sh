#!/bin/bash
# Para y elimina los contenedores vLLM del stack. Se ejecuta como el usuario de Ubuntu.
#
# Uso:  bash stop-models.sh [router|fast|complex|writer ...]     (sin argumentos: todos)
set -euo pipefail

roles=("$@")
if [ ${#roles[@]} -eq 0 ]; then roles=(router fast complex writer); fi

for role in "${roles[@]}"; do
  name="vllm-$role"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker rm -f "$name" >/dev/null && echo "parado: $name"
  else
    echo "no existe: $name"
  fi
done

nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
