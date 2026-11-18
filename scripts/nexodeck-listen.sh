#!/bin/bash
# Escucha el buzon de salida de NexoDeck: emite una linea por cada mensaje que
# el usuario mande desde el chat de la app hacia ESTA sesion de Claude Code.
#
# Pensado para lanzarse con la herramienta Monitor, NO con Bash en segundo
# plano. Es la misma leccion que ya costo tres preguntas sin contestar el
# 24-ago con `puente-cc.sh`: `run_in_background` avisa UNA vez, cuando el
# comando termina, y un bucle infinito no termina nunca. Monitor convierte cada
# linea de stdout en una notificacion mientras el script sigue vivo, que es
# exactamente lo que hace falta. Por eso el bucle es infinito a proposito.
#
#   bash scripts/nexodeck-listen.sh
#   bash scripts/nexodeck-listen.sh --name "ODM"
#
# LA IDENTIDAD LA PONE ESTE SCRIPT, no Claude Code. No hace falta ninguna
# bandera suya: quien lo lanza sabe donde esta, asi que se deduce el nombre de
# la carpeta y la rama de git ("NexoDeck en main"). Con `--name` se pisa. El
# identificador es el pid, unico en la maquina mientras el vigilante viva; si
# hay dos sesiones en el mismo repositorio, el nombre se repite y el pid las
# desempata.
#
# El token sale de NEXODECK_CONTROL_TOKEN o, si no esta, del fichero que escribe
# NexoDeck en el directorio de datos del usuario.
#
# LA MARCA DE AGUA SOLO AVANZA DESPUES DE EMITIR. Si esto muere a mitad, la
# vuelta siguiente repite en vez de saltarse: repetir molesta, perder no se
# arregla. Es la regla de `vigilar-cc.sh` y vale igual aqui.
#
# LA CAIDA DEL CANAL EMITE LINEA. El silencio de un oyente muerto es identico al
# de "no hay mensajes", y esa es la peor forma de fallar.
set -u

PORT="${NEXODECK_CONTROL_PORT:-58646}"
BASE="http://127.0.0.1:${PORT}"
FAILURES=0
DOWN=0
NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME="${2:-}"; shift 2 ;;
        --help|-h)
            echo "uso: nexodeck-listen.sh [--name <nombre de esta sesion>]"
            exit 0
            ;;
        *) echo "argumento desconocido: $1"; exit 2 ;;
    esac
done

# --- Quien soy ------------------------------------------------------

SESSION="$$"
CWD="$(pwd)"

if [ -z "$NAME" ]; then
    FOLDER="$(basename "$CWD")"
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ]; then
        NAME="$FOLDER en $BRANCH"
    else
        NAME="$FOLDER"
    fi
fi

# La marca de agua es POR SESION: dos vigilantes en la misma maquina no pueden
# compartir fichero o cada uno se saltaria los mensajes del otro.
MARK_FILE="${NEXODECK_LISTEN_MARK:-${TMPDIR:-/tmp}/nexodeck-listen-${SESSION}.txt}"

# --- El token -------------------------------------------------------

TOKEN="${NEXODECK_CONTROL_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    # Mismo sitio en el que lo escribe `nexodeck-control::ensure_token`.
    KEY_FILE="${APPDATA:-$HOME/.local/share}/nexodeck/NexoDeck/data/control_token.txt"
    [ -f "$KEY_FILE" ] && TOKEN=$(tr -d '\r\n' < "$KEY_FILE")
fi
if [ -z "$TOKEN" ]; then
    echo "CANAL CAIDO · no hay token: define NEXODECK_CONTROL_TOKEN o abre NexoDeck una vez"
    exit 1
fi

# --- Dependencias ---------------------------------------------------
#
# NO basta con `command -v`: en Windows, `python3` resuelve al señuelo de la
# Microsoft Store (`WindowsApps/python3`), que existe, esta en el PATH, imprime
# "Python was not found" y sale con codigo != 0. Verificado en vivo el
# 9-sep-2026: el oyente decia "CANAL CAIDO" en bucle con el servidor
# perfectamente vivo. Por eso cada candidato se PRUEBA de verdad.
PY=""
for candidate in python3 python py; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if [ "$("$candidate" -c 'print(1)' 2>/dev/null)" = "1" ]; then
        PY="$candidate"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "CANAL CAIDO · hace falta python para leer la respuesta del buzon"
    exit 1
fi

[ -s "$MARK_FILE" ] || echo 0 > "$MARK_FILE"

# Se emite el nombre para que la sesion sepa como se llama: es lo que tiene que
# pasar en `from` cuando use la herramienta `post_message`, porque NexoDeck no
# puede saberlo por su cuenta.
echo "Escuchando a NexoDeck como \"${NAME}\" (sesion ${SESSION}). Usa ese nombre en 'from' si escribes con post_message."

# Se codifican para la URL con el mismo interprete: un nombre de rama con `/`
# o una carpeta con espacios romperian la consulta.
ENC=$("$PY" -c '
import sys, urllib.parse
print("&".join("%s=%s" % (k, urllib.parse.quote(v, safe=""))
               for k, v in zip(("session", "label", "cwd"), sys.argv[1:])))
' "$SESSION" "$NAME" "$CWD")

while true; do
    MARK=$(cat "$MARK_FILE" 2>/dev/null || echo 0)

    # `confirm` va con la marca YA emitida, nunca con la que se va a emitir:
    # es lo que le dice a NexoDeck que el mensaje llego a una sesion viva.
    RESPONSE=$(curl -s --max-time 40 \
        -H "Authorization: Bearer ${TOKEN}" \
        "${BASE}/outbox?since=${MARK}&confirm=${MARK}&${ENC}" 2>/dev/null) || RESPONSE=""

    if [ -z "$RESPONSE" ]; then
        FAILURES=$((FAILURES + 1))
        # Un fallo suelto es normal (la app se reinicio, el turno tardo). Varios
        # seguidos significan que no hay nadie al otro lado.
        if [ "$FAILURES" -ge 3 ] && [ "$DOWN" -eq 0 ]; then
            DOWN=1
            echo "CANAL CAIDO · NexoDeck no responde en ${BASE}. Comprueba que este abierto y con el servidor de control encendido."
        fi
        sleep 5
        continue
    fi

    if [ "$DOWN" -eq 1 ]; then
        DOWN=0
        echo "CANAL RECUPERADO · NexoDeck vuelve a responder"
    fi
    FAILURES=0

    # Una linea por mensaje, con el id delante: ese numero es lo que hay que
    # pasarle a la herramienta `reply`. Los saltos de linea del texto se
    # aplanan porque Monitor entrega UNA notificacion por linea de stdout, y un
    # mensaje de tres lineas llegaria partido en tres.
    OUTPUT=$(printf '%s' "$RESPONSE" | "$PY" -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(3)
last = 0
for m in data.get("messages", []):
    text = " / ".join(line.strip() for line in m["text"].splitlines() if line.strip())
    marca = "PREGUNTA" if m.get("expects_reply") else "AVISO"
    # Un mensaje sin destinatario fue para todas las sesiones: se dice, porque
    # contestar algo que tambien le llego a otro es distinto.
    para = "" if m.get("target") else " (a todas las sesiones)"
    print("NEXODECK #%d %s%s: %s" % (m["seq"], marca, para, text))
    last = max(last, m["seq"])
print("__MARK__%d" % last, file=sys.stderr)
' 2>"${MARK_FILE}.new") || {
        echo "CANAL CAIDO · la respuesta del buzon no se pudo leer"
        sleep 5
        continue
    }

    # Primero se emite...
    [ -n "$OUTPUT" ] && echo "$OUTPUT"

    # ...y solo despues avanza la marca. Este orden es la regla entera.
    NEW=$(sed -n 's/^__MARK__//p' "${MARK_FILE}.new" 2>/dev/null | tail -1)
    rm -f "${MARK_FILE}.new"
    if [ -n "$NEW" ] && [ "$NEW" != "0" ]; then
        echo "$NEW" > "$MARK_FILE"
    fi
done
