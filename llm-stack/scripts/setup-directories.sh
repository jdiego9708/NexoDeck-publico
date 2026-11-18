#!/bin/bash
# Crea la estructura de directorios del stack (doc 01, paso 5) y comprueba que el usuario puede
# usar docker sin sudo. Se ejecuta como el usuario de Ubuntu, no como root.
#
# Usa $HOME en vez de `/home/juan`: los docs 03-10 llevan esa ruta del autor original y en esta
# maquina el usuario es otro.
set -euo pipefail

mkdir -p "$HOME/vllm-stack/logs" "$HOME/vllm-stack/router" "$HOME/vllm-stack/replay" "$HOME/vllm-stack/RSIAgent"
mkdir -p "$HOME/models" "$HOME/.rsiaagent/memory"

echo "HOME=$HOME"
ls -d "$HOME"/vllm-stack/* "$HOME/models" "$HOME/.rsiaagent/memory"
echo "grupos: $(id -nG)"

if docker ps >/dev/null 2>&1; then
  echo "docker sin sudo: OK"
else
  echo "docker sin sudo: FALLA. Cierra la sesion de WSL (wsl --terminate <distro>) y vuelve a entrar."
  exit 1
fi

df -h "$HOME" | tail -1
