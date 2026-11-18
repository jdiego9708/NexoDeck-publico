#!/bin/bash
# Autocomprobacion de esta carpeta, sin tocar el sistema: sintaxis de los scripts de shell y de
# Python, finales de linea y que el manifiesto de modelos se lea bien.
#
# Uso:  bash check-scripts.sh
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
failures=0

for script in *.sh; do
  if bash -n "$script"; then echo "sintaxis OK: $script"; else echo "SINTAXIS MAL: $script"; failures=$((failures + 1)); fi
done

for script in *.py; do
  if python3 -m py_compile "$script"; then echo "python OK: $script"; else echo "PYTHON MAL: $script"; failures=$((failures + 1)); fi
done
rm -rf __pycache__

if grep -lU $'\r' ./*.sh ./*.py ./*.json 2>/dev/null; then
  echo "HAY FINALES DE LINEA CRLF en los ficheros de arriba (bash fallaria); revisa .gitattributes"
  failures=$((failures + 1))
else
  echo "finales de linea OK (sin CRLF)"
fi

echo "-- modelos de la receta:"
python3 list-models.py || failures=$((failures + 1))

echo "-- un rol inventado tiene que fallar con un mensaje claro:"
if python3 list-models.py rol-inventado; then
  echo "DEBERIA HABER FALLADO"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then echo "TODO OK"; else echo "$failures problema(s)"; exit 1; fi
