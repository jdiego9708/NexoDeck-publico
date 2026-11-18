#!/bin/bash
# Arranca un PERFIL completo del stack (los modelos que el manifiesto diga). Se ejecuta como el
# usuario de Ubuntu, y con `Start-WslKeepAlive.ps1` ya lanzado desde Windows: sin esa sesion abierta
# WSL2 apaga la distro y los servidores mueren solos.
#
# Uso:  bash serve-profile.sh <A|B|C|complex-solo>
#
# Que roles sirve cada perfil NO esta escrito aca: lo dice `profiles.json`, que escribe NexoDeck
# desde su pantalla de perfiles y del que se leen los slots `router` y `thinking` con
# `profile-roles.py`. Un slot con `source` distinto de `stack` (llamacpp, ollama, remote, claudecode)
# no lo sirve vLLM. Si no existe `profiles.json`, `profile-roles.py` devuelve el mapeo historico
# (A: router+fast, B: router+complex), asi que una instalacion vieja sigue arrancando igual.
#
# Perfiles (doc 11, apartados 7.10, 7.11 y 7.14; margen medido con Windows incluido):
#   A             Router (ctx 16 384) + Rapido/Gemma (ctx 8 192).            15.5 de 16.3 GiB
#   B             Router (ctx 8 192)  + Complejo/Qwen3-Coder (ctx 8 192).    14.9 de 16.3 GiB
#   C             Writer/Qwen3.5-9B solo (ctx 32 768): ~12 de 16.3 GiB
#   complex-solo  Complejo con todo el contexto (16 384) y sin Router.       ~13 de 16.3 GiB
#
# El Rapido y el Complejo NO conviven (decision del usuario y, ademas, no caben). Cambiar de
# perfil para todos los contenedores y los arranca de nuevo: no es una conmutacion en caliente.
#
# Por que estos valores (no los cambies sin medir):
#   - El KV se fija en bytes: bajo WSL2 cada instancia ve la GPU casi libre y vLLM no detecta el
#     desbordamiento entre instancias (doc 11 §7.12).
#   - --max-num-batched-tokens 256 en el Complejo cuesta ~25 % de rendimiento; 512 no (§7.14).
#   - --cpu-offload-gb en el Router lo deja a 3 tok/s (§7.13): no se usa.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:?Uso: $0 <A|B|complex-solo>}"
PROFILE_UPPER="$(printf '%s' "$PROFILE" | tr '[:lower:]' '[:upper:]')"

serve() { bash "$SCRIPT_DIR/serve-model.sh" "$@"; }

# Rol local de un slot del perfil segun `profiles.json`. Vacio si ese slot no lo sirve vLLM.
role_for() {
  python3 "$SCRIPT_DIR/profile-roles.py" "$PROFILE_UPPER" "$1"
}

bash "$SCRIPT_DIR/stop-models.sh"

case "$PROFILE_UPPER" in
  COMPLEX-SOLO)
    serve complex
    ;;
  A|B|C)
    thinking="$(role_for thinking)"
    router="$(role_for router)"

    # A stdout, NO a stderr: es un aviso, no un fallo. `Start-Stack.ps1` corre con
    # `$ErrorActionPreference='Stop'` y `2>&1`, asi que una linea de stderr lo abortaba y un
    # perfil todo-remoto (DeepSeek, Claude Code) parecia fallar cuando no hay nada que arrancar.
    if [ -z "$thinking" ] && [ -z "$router" ]; then
      echo "== El perfil $PROFILE_UPPER no tiene ningun modelo local (todo remoto o Claude Code):"
      echo "   no hay nada que arrancar en vLLM. La pasarela sigue disponible para el resto. =="
    fi

    # El trabajador primero cuando es el grande: es el que mas VRAM pide y conviene perfilarlo solo.
    if [ "$thinking" = "complex" ]; then
      serve complex -- --max-model-len 8192 --max-num-batched-tokens 512 --kv-cache-memory 483183820
    elif [ -n "$thinking" ]; then
      serve "$thinking"
    fi

    if [ -n "$router" ] && [ "$router" != "$thinking" ]; then
      # Con el Complejo cargado (o en el perfil B) el Router va con contexto y KV reducidos.
      if [ "$PROFILE_UPPER" = "B" ] || [ "$thinking" = "complex" ]; then
        serve router -- --max-model-len 8192 --max-num-batched-tokens 512 --kv-cache-memory 429496730
      else
        serve router
      fi
    fi
    ;;
  *)
    echo "Perfil desconocido: $PROFILE (A, B, C o complex-solo)" >&2
    exit 1
    ;;
esac

echo "== Perfil $PROFILE listo =="
docker ps --format '{{.Names}}  {{.Status}}'
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
