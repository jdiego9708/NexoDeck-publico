#!/bin/bash
# Guarda una nota en la boveda de NexoDeck desde cualquier agente o script, por
# HTTP, sin necesitar un cliente MCP.
#
# Es la misma herramienta `save_note` que usa Claude Code por MCP; lo unico que
# cambia es que aqui la peticion se manda a mano. Sirve para un agente que no
# habla MCP, un script de una cadena larga, o para probar sin abrir una sesion.
#
#   bash scripts/nexodeck-save-note.sh "Lo que sea que haya que guardar"
#   comando_largo | bash scripts/nexodeck-save-note.sh --title "Resultado de la tanda"
#   bash scripts/nexodeck-save-note.sh --path temas/malla.md --title "Apunte" "texto"
#
# EL TEXTO VIAJA POR STDIN O COMO UN ARGUMENTO ENTERO, nunca interpolado en una
# linea de shell. Es la misma regla que ya sigue `nexodeck-notify`: un resumen
# lleva comillas, backticks y saltos de linea, y montarlo dentro de un comando
# es exactamente como se corrompe.
#
# SOLO FUNCIONA EN LA MAQUINA DE NEXODECK. El servidor de control escucha en
# 127.0.0.1 a proposito (ver la seccion "Servidor de control" de CLAUDE.md): un
# agente en otra maquina no lo alcanza, y abrirlo a la red seria dejar una
# puerta de escritura en la boveda del usuario.
#
# EL FORMATO LO ARREGLA NEXODECK. Manda markdown normal: no hace falta envolver
# nada en una cerca de codigo ni poner frontmatter (el que mandes se descarta).
# Sin --path la nota cae en `inbox/` con la fecha; con un --path que ya existe
# se AÑADE al final, nunca se pisa.
set -u

PORT="${NEXODECK_CONTROL_PORT:-58646}"
URL="http://127.0.0.1:${PORT}/mcp"
TITLE=""
NOTE_PATH=""
FROM=""
TEXT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --title) TITLE="${2:-}"; shift 2 ;;
        --path) NOTE_PATH="${2:-}"; shift 2 ;;
        --from) FROM="${2:-}"; shift 2 ;;
        --help|-h)
            echo "uso: nexodeck-save-note.sh [--title T] [--path ruta.md] [--from sesion] [texto]"
            echo "     sin texto, se lee de stdin"
            exit 0
            ;;
        *) TEXT="$1"; shift ;;
    esac
done

# Sin texto en la linea de ordenes se lee todo stdin: es el caso de una tuberia.
if [ -z "$TEXT" ]; then
    TEXT=$(cat)
fi
if [ -z "${TEXT//[$' \t\n\r']/}" ]; then
    echo "no hay nada que guardar: pasa el texto como argumento o por stdin" >&2
    exit 1
fi

TOKEN="${NEXODECK_CONTROL_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    # Mismo sitio en el que lo escribe `nexodeck-control::ensure_token`.
    KEY_FILE="${APPDATA:-$HOME/.local/share}/nexodeck/NexoDeck/data/control_token.txt"
    [ -f "$KEY_FILE" ] && TOKEN=$(tr -d '\r\n' < "$KEY_FILE")
fi
if [ -z "$TOKEN" ]; then
    echo "no hay token: define NEXODECK_CONTROL_TOKEN o abre NexoDeck una vez" >&2
    exit 1
fi

# Sin identidad, la nota no dice de donde salio. Se deduce igual que en
# `nexodeck-listen.sh`: la carpeta y la rama de quien lanza esto.
if [ -z "$FROM" ]; then
    FOLDER=$(basename "$(pwd)")
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    FROM="$FOLDER${BRANCH:+ en $BRANCH}"
fi

# El JSON se construye con python, no con `printf`: el texto lleva comillas y
# saltos de linea, y escaparlos a mano en shell es como se rompe esto.
PAYLOAD=$(TEXT="$TEXT" TITLE="$TITLE" NOTE_PATH="$NOTE_PATH" FROM="$FROM" python -c '
import json, os
args = {"text": os.environ["TEXT"], "from": os.environ["FROM"]}
for key, env in (("title", "TITLE"), ("path", "NOTE_PATH")):
    value = os.environ.get(env, "").strip()
    if value:
        args[key] = value
print(json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {"name": "save_note", "arguments": args},
}))
') || { echo "no se pudo preparar la peticion (¿falta python?)" >&2; exit 1; }

RESPONSE=$(curl -s -S --max-time 30 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URL") || { echo "no se pudo hablar con NexoDeck: ¿esta abierto?" >&2; exit 1; }

# Un fallo NO puede parecerse a un exito: es la regla de todo el servidor de
# control. Se distingue por `isError` y se sale con codigo distinto de cero.
echo "$RESPONSE" | RESP="$RESPONSE" python -c '
import json, os, sys
try:
    body = json.loads(os.environ["RESP"])
except json.JSONDecodeError:
    print("respuesta ilegible de NexoDeck:", os.environ["RESP"][:200], file=sys.stderr)
    sys.exit(1)
if "error" in body:
    print("NexoDeck rechazo la peticion:", body["error"].get("message", body["error"]), file=sys.stderr)
    sys.exit(1)
result = body.get("result", {})
text = (result.get("content") or [{}])[0].get("text", "")
print(text)
sys.exit(1 if result.get("isError") else 0)
'
