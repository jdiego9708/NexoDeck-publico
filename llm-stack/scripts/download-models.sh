#!/bin/bash
# Descarga los modelos de models.json a ~/models (doc 03). Se ejecuta como el usuario de Ubuntu,
# NO como root: los ficheros y la cache de HuggingFace tienen que quedar a su nombre.
#
# Uso:  bash download-models.sh [--alternatives] [rol ...]
#       bash download-models.sh                 # los tres modelos de la receta
#       bash download-models.sh router          # solo el router
#
# Velocidad: se usa el backend Xet de alto rendimiento (HF_XET_HIGH_PERFORMANCE) y se sube la
# concurrencia de ficheros (--max-workers, 16 en vez del 8 por defecto). Xet ya trocea y baja en
# paralelo un mismo fichero grande, asi que la concurrencia de ficheros solo importa en repos con
# muchos shards; el techo real es la linea y el CDN de HuggingFace, no estos numeros.
#
# Variables opcionales:
#   MODELS_DIR     destino (por defecto ~/models; mantenlo en el sistema de ficheros de WSL2,
#                  /mnt/d/ es varias veces mas lento al cargar)
#   HF_TOKEN       token de HuggingFace (no hace falta: los repos son publicos)
#   HF_MAX_WORKERS ficheros en paralelo para `hf download` (por defecto 16; el CLI usa 8)
#
# Cambios respecto al doc 03: la CLI actual se llama `hf` (no `huggingface-cli`), y
# --local-dir-use-symlinks esta obsoleto porque --local-dir ya copia los ficheros.
# Es reanudable: si se corta, volver a lanzarlo continua donde se quedo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"

if [ "$(id -u)" -eq 0 ]; then
  echo "No lo ejecutes como root: los modelos quedarian a nombre de root." >&2
  exit 1
fi

export PATH="$HOME/.local/bin:$PATH"
export HF_HOME="$MODELS_DIR/.cache"
export HF_XET_HIGH_PERFORMANCE=1
MAX_WORKERS="${HF_MAX_WORKERS:-16}"

if ! command -v uv >/dev/null 2>&1; then
  echo "== Instalando uv =="
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if ! command -v hf >/dev/null 2>&1; then
  echo "== Instalando la CLI hf =="
  uv tool install --force "huggingface_hub[cli]"
fi

# `HF_XET_HIGH_PERFORMANCE` solo hace algo si hf_xet esta instalado: si falta, se ignora en
# silencio y la descarga cae a HTTP normal, mucho mas lenta. Se comprueba y se instala, en vez
# de suponerlo.
if ! python3 -c 'import hf_xet' >/dev/null 2>&1; then
  echo "== hf_xet ausente: se instala (sin el, la transferencia de alto rendimiento se ignora) =="
  uv tool install --force --with hf_xet "huggingface_hub[cli]"
fi

mkdir -p "$MODELS_DIR"

while IFS=$'\t' read -r repo dir; do
  echo "== $(date +%T) Descargando $repo -> $MODELS_DIR/$dir =="
  hf download "$repo" --local-dir "$MODELS_DIR/$dir" --max-workers "$MAX_WORKERS"
  du -sh "$MODELS_DIR/$dir"
done < <(python3 "$SCRIPT_DIR/list-models.py" "$@")

echo "== $(date +%T) TERMINADO =="
du -sh "$MODELS_DIR"/*/
df -h "$MODELS_DIR"
