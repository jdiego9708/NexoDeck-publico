#!/bin/bash
# Se ejecuta DENTRO del contenedor de vLLM (lo lanza build-vllm-image.sh --probe). Muestra, sin
# instalar nada, que versiones de b12x y nvidia-cutlass-dsl traeria el extra `vllm[b12x]`.
#
# Sirve para decidir los pines con datos: la receta (doc 02) fija cutlass-dsl a 4.4.2 por un fallo
# de la 4.5.0 en una version anterior de vLLM, pero la imagen 0.29.0 ya trae la 4.6.2.
set -uo pipefail

# `import vllm` imprime avisos por stdout (p. ej. el de WSL y pin_memory), asi que la version se
# lee de los metadatos del paquete y no de una importacion.
version="$(python3 -m pip show vllm | sed -n 's/^Version: //p')"
echo "vllm instalado: $version"

if command -v uv >/dev/null 2>&1; then
  echo "== uv pip install --dry-run 'vllm[b12x]==$version' =="
  uv pip install --system --dry-run "vllm[b12x]==$version" 2>&1 | tail -n 25
else
  echo "== pip install --dry-run 'vllm[b12x]==$version' =="
  python3 -m pip install --dry-run "vllm[b12x]==$version" 2>&1 | tail -n 25
fi

echo "== Paquetes actuales relacionados =="
python3 -m pip list 2>/dev/null | grep -i -E "cutlass|b12x|flashinfer|^torch |^vllm " || true
