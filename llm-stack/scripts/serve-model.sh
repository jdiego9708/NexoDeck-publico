#!/bin/bash
# Arranca UN modelo de la receta en un contenedor vLLM y espera a que responda. Se ejecuta como
# el usuario de Ubuntu.
#
# Uso:  bash serve-model.sh <router|fast|complex|writer> [-- args extra de vllm serve]
#
# Variables opcionales:
#   GPU_UTIL   fraccion de la VRAM TOTAL que se reserva (sobrescribe la del rol)
#   WAIT_S     segundos maximos esperando al servidor (por defecto 900: la primera vez con NVFP4
#              hay compilacion JIT de 2-5 minutos y la GPU parece parada)
#
# Decisiones (doc 11):
#   - Puerto atado a 127.0.0.1: nunca se expone fuera de esta maquina.
#   - Imagen derivada con b12x (vllm-image.local, construida por build-vllm-image.sh).
#   - Los modelos se montan en solo lectura y HF_HUB_OFFLINE=1: el servidor nunca va a la red.
#   - Cache de JIT (~/.cache/vllm y ~/.cache/flashinfer) montada, para no recompilar en cada arranque.
#   - Arrancar de UNO en UNO: el perfilado de memoria de dos instancias a la vez no es fiable.
#   - --gpu-memory-utilization es fraccion de la VRAM TOTAL (15.93 GiB), y vLLM se niega a arrancar
#     si no hay libre esa cantidad: Windows ya ocupa 1-2.4 GiB. Por eso los valores son bajos.
#   - VLLM_WSL2_ENABLE_PIN_MEMORY=1: en WSL2 vLLM desactiva la memoria fijada por defecto (aviso
#     "pin_memory=False as WSL is detected") y sin ella el ejecutor v2 de 0.29 falla al arrancar con
#     "RuntimeError: UVA is not available". Tambien la necesita el offload a CPU (--cpu-offload-gb).
#     Lo dice el propio codigo de vLLM (envs.py): soportada con kernel >= 4.19.121, aqui es 6.18.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
WAIT_S="${WAIT_S:-900}"

ROLE="${1:-}"
[ -n "$ROLE" ] || { echo "Uso: $0 <router|fast|complex> [-- args extra]" >&2; exit 1; }
shift
[ "${1:-}" = "--" ] && shift
EXTRA_ARGS=("$@")

case "$ROLE" in
  router)
    PORT=8002
    MODEL_DIR="qwen3.5-4b-nvfp4"
    # Medido el 18-sep-2026: pesos+no-torch 3.44 GiB, activaciones 0.13 GiB (con batched-tokens 2048),
    # grafos CUDA 0.01 GiB. Con 0.27 (4.3 GiB) quedan ~0.7 GiB de KV (~19 000 tokens); con 0.34,
    # 1.84 GiB (49 152 tokens). Sin acotar --max-num-batched-tokens el pico de activaciones se
    # comia ~1.3 GiB y 0.28 daba "No available memory for the cache blocks".
    UTIL="0.27"
    KV_BYTES=697932185  # 0.65 GiB: cabe 1 peticion de 16 384 tokens (~40 KiB/token)
    # Tool calling: el agente de NexoDeck manda `tools` + `tool_choice: auto`, y sin
    # --enable-auto-tool-choice y un parser vLLM contesta 400 (doc 11 §7.21). Qwen3.5 usa el
    # parser qwen3_coder. Como NexoDeck NUNCA manda `enable_thinking: false` a los servicios
    # remotos, el razonamiento se apaga aqui por defecto; --reasoning-parser qwen3 separa el
    # razonamiento en `reasoning_content` para el cliente que lo pida.
    ROLE_ARGS=(--max-model-len 16384 --max-num-seqs 8 --max-num-batched-tokens 2048
               --linear-backend b12x --language-model-only --enable-prefix-caching
               --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3
               --default-chat-template-kwargs '{"enable_thinking": false}')
    ;;
  fast)
    PORT=8001
    MODEL_DIR="gemma-4-12b-awq"
    # Medido solo (0.68): pesos 8.02 GiB + activaciones 0.24 GiB, KV 2.57 GiB = 23 189 tokens.
    # El KV de Gemma tiene un SUELO de ~1.6 GiB (capas de ventana deslizante) y crece poco con el
    # contexto: una peticion completa necesita 1.69 GiB a 8 192 tokens y 1.75 GiB a 12 288
    # (~15 KiB/token). Con menos KV que eso vLLM se niega a arrancar. De ahi 1.75 GiB y ctx 8 192.
    UTIL="0.55"
    KV_BYTES=1879048192  # 1.75 GiB
    # Tool calling con el parser `gemma4` (existe en vLLM 0.29.0). Sin el, una peticion con `tools`
    # contesta 400 (medido el 19-sep-2026, igual que le paso al Router y al Complejo, 7.21).
    ROLE_ARGS=(--max-model-len 8192 --max-num-seqs 8 --max-num-batched-tokens 2048
               --language-model-only --enable-prefix-caching
               --enable-auto-tool-choice --tool-call-parser gemma4)
    ;;
  complex)
    PORT=8000
    MODEL_DIR="qwen3-coder-30b-reap50-nvfp4"
    # Medido el 18-sep-2026 (doc 11 §7.11): con --moe-backend b12x los grafos CUDA fallan con
    # "illegal memory access" (y con --enforce-eager va a 7 tok/s, inutilizable). Con
    # flashinfer_cutlass y grafos da ~100 tok/s con 1 cliente y ~258 con 4. Coste: el pico de
    # activaciones sube a 1.08 GiB con --max-num-batched-tokens 2048, de ahi el 1024.
    # Pesos 9.33 GiB (+0.17 no-torch); el KV va en FP8 (viene asi en el modelo): ~47 KiB/token.
    UTIL="0.75"
    KV_BYTES=912680550  # 0.85 GiB: una peticion de 16 384 tokens (~0.75 GiB)
    # Tool calling con el parser de Qwen3-Coder (el que ya citaba la receta, doc 04 §5.2).
    ROLE_ARGS=(--max-model-len 16384 --max-num-seqs 4 --max-num-batched-tokens 1024
               --linear-backend b12x --moe-backend flashinfer_cutlass --enable-prefix-caching
               --enable-auto-tool-choice --tool-call-parser qwen3_coder)
    ;;
  writer)
    PORT=8003
    MODEL_DIR="qwen3.5-9b-awq"
    # Trabajador de texto del perfil C (Texto). Qwen3.5-9B en AWQ: el repo cuantiza solo el MLP
    # (`modules_to_not_convert` incluye `linear_attn`/`self_attn`), asi que la atencion va en BF16 y
    # NO se pasa `--linear-backend b12x`: con AWQ/Marlin no hay JIT (doc 00). Los pesos son ~11.5 GiB,
    # asi que **corre SOLO**: es el unico modelo del perfil C y se lleva la GPU entera. `--language-
    # model-only` salta la torre de vision y baja la VRAM. El contexto es largo (32k): la atencion
    # hibrida (lineal 3 de cada 4 capas) deja el KV pequeno (~32 KiB/token en las capas completas).
    UTIL="0.7"
    KV_BYTES=2147483648  # 2 GiB: sobra para 32 768 tokens (a medir con `serve-model.sh writer`)
    ROLE_ARGS=(--max-model-len 32768 --max-num-seqs 8 --max-num-batched-tokens 2048
               --language-model-only --enable-prefix-caching
               --reasoning-parser qwen3
               --default-chat-template-kwargs '{"enable_thinking": false}')
    ;;
  *) echo "Rol desconocido: $ROLE (router, fast, complex o writer)" >&2; exit 1 ;;
esac

# Un modelo sin descargar no se puede servir, y arrancar el contenedor igual cuesta 2-6 min de
# espera para morir con un `HFValidationError: Repo id must be in the form ...` criptico (vLLM trata
# la ruta inexistente como un repo de Hugging Face). Se comprueba ANTES de tocar Docker y se dice
# que falta y como bajarlo. Mismo criterio que un `0` de temperatura: un fallo mudo es peor.
MODEL_PATH="$MODELS_DIR/$MODEL_DIR"
if [ ! -d "$MODEL_PATH" ] || [ -z "$(ls -A "$MODEL_PATH" 2>/dev/null)" ]; then
  echo "Falta descargar el modelo del rol '$ROLE': no existe $MODEL_PATH (o esta vacio)." >&2
  echo "  Desde NexoDeck: Configura tus perfiles -> toca el modelo -> «Descargar»." >&2
  echo "  A mano:         bash $SCRIPT_DIR/download-models.sh $ROLE" >&2
  exit 1
fi

# Con dos instancias en la misma GPU, la aritmetica por fracciones de vLLM no es fiable (Gemma
# fallo a 0.55 junto al Router aunque sola necesita ~8.3 GiB). Por defecto se fija el KV en bytes
# (--kv-cache-memory), que vLLM sugiere en su propio registro; GPU_UTIL fuerza el modo fraccion.
KV_BYTES="${KV_BYTES:-}"
if [ -n "${GPU_UTIL:-}" ] || [ -z "$KV_BYTES" ]; then
  MEMORY_ARGS=(--gpu-memory-utilization "${GPU_UTIL:-$UTIL}")
else
  # Con --kv-cache-memory vLLM SIGUE comprobando en el arranque que haya libre la fraccion por
  # defecto (0.92 = 14.65 GiB) y falla con "Free memory ... is less than desired GPU memory
  # utilization" en cuanto Windows ocupa mas de ~1.3 GiB. La fraccion no se usa para nada mas en
  # este modo, asi que se baja para que el chequeo no dependa de lo que este haciendo el escritorio.
  MEMORY_ARGS=(--kv-cache-memory "$KV_BYTES" --gpu-memory-utilization 0.5)
fi

IMAGE="$(cat "$SCRIPT_DIR/vllm-image.local")"
NAME="vllm-$ROLE"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Ya existe el contenedor $NAME; lo elimino para volver a arrancarlo."
  docker rm -f "$NAME" >/dev/null
fi

mkdir -p "$HOME/.cache/vllm" "$HOME/.cache/flashinfer"

# SLEEP_MODE=1 activa /sleep y /wake_up (doc 04). Exige VLLM_SERVER_DEV_MODE=1, que ademas abre
# endpoints de administracion peligrosos (p. ej. /collective_rpc): por eso el puerto va SOLO en
# 127.0.0.1 y nunca se debe publicar fuera sin una pasarela que filtre rutas (doc 11 §3).
SLEEP_ENV=()
if [ "${SLEEP_MODE:-0}" = "1" ]; then
  SLEEP_ENV=(-e VLLM_SERVER_DEV_MODE=1)
  EXTRA_ARGS+=(--enable-sleep-mode)
fi

echo "== $(date +%T) Arrancando $ROLE ($MODEL_DIR) en 127.0.0.1:$PORT, memoria: ${MEMORY_ARGS[*]} =="

# Reinicio acotado y healthcheck por contenedor (doc 11 apartado 3, punto 5). Tres reinicios y se
# rinde: un arranque en falso cuesta 2-6 min de JIT y un reinicio sin tope seria un bucle comiendose
# la GPU. La politica solo reacciona a que el PROCESO salga, asi que la regla de limpieza sigue
# valiendo: `docker rm -f` (stop-models.sh) borra el contenedor y no dispara reinicio. Ojo: Docker
# NO reinicia por healthcheck, solo lo expone; un contenedor "vivo pero insano" lo ve el vigilante.
# El healthcheck corre DENTRO del contenedor: usa python3 (vLLM lo trae) y no curl, que la imagen no
# garantiza. `--health-start-period` cubre el peor arranque medido con la cache en frio (Router 151 s).
docker run -d --name "$NAME" --gpus all --ipc=host \
  --label nexodeck.stack=1 --label "nexodeck.role=$ROLE" \
  --restart on-failure:3 \
  --health-cmd "python3 -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=4).status==200 else 1)\"" \
  --health-interval 30s --health-timeout 5s --health-retries 3 --health-start-period 360s \
  -p "127.0.0.1:$PORT:8000" \
  -v "$MODELS_DIR:/models:ro" \
  -v "$HOME/.cache/vllm:/root/.cache/vllm" \
  -v "$HOME/.cache/flashinfer:/root/.cache/flashinfer" \
  -e HF_HUB_OFFLINE=1 \
  -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 \
  "${SLEEP_ENV[@]}" \
  --entrypoint vllm "$IMAGE" \
  serve "/models/$MODEL_DIR" --served-model-name "$ROLE" --host 0.0.0.0 --port 8000 \
  "${MEMORY_ARGS[@]}" "${ROLE_ARGS[@]}" "${EXTRA_ARGS[@]}" >/dev/null

LOG_FILE="$HOME/vllm-stack/logs/$NAME.log"

# El traceback final de vLLM es siempre el mismo ("Engine core initialization failed"); la causa
# real esta varias lineas antes. Se guarda el registro entero y se extraen las lineas de excepcion.
report_failure() {
  docker logs "$NAME" > "$LOG_FILE" 2>&1 || true
  echo "== Registro completo en $LOG_FILE. Causa probable: =="
  grep -E "(Error|Exception):|out of memory|Not enough|No available memory" "$LOG_FILE" | sort -u | tail -n 8
  # Falta de VRAM por otro modelo del MISMO perfil. Bajo WSL2 vLLM no ve la memoria de las otras
  # instancias (doc 11 §7.12), asi que el reparto hay que dimensionarlo a mano: este es el fallo
  # del perfil que pide dos modelos que no caben juntos (p. ej. C = router + writer).
  if grep -q "less than desired GPU memory utilization" "$LOG_FILE" 2>/dev/null; then
    echo "== FALTA VRAM: otro modelo del perfil ya tiene la GPU y vLLM no lo ve (WSL2)."
    echo "   Revisa que el perfil no pida dos modelos que no caben juntos. =="
  fi
}

started=$SECONDS
while true; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "== EL CONTENEDOR SE HA PARADO tras $((SECONDS - started)) s =="
    report_failure
    exit 1
  fi
  if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "== $(date +%T) $ROLE listo en $((SECONDS - started)) s =="
    break
  fi
  if [ $((SECONDS - started)) -ge "$WAIT_S" ]; then
    echo "== Sin respuesta tras $WAIT_S s =="
    report_failure
    exit 1
  fi
  sleep 5
done

nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
docker logs "$NAME" 2>&1 | grep -i -E "model loading took|KV cache|maximum concurrency|backend|kernel|offload" | tail -n 12 || true
