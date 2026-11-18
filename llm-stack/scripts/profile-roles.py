"""Lee `profiles.json` y contesta que rol local de vLLM sirve cada slot de un perfil.

Lo usa `serve-profile.sh` para no tener el mapeo perfil->roles escrito a mano en el shell: la
fuente de verdad es `profiles.json`, que a su vez escribe NexoDeck desde su pantalla de perfiles.

Uso:
    python3 profile-roles.py <A|B|C> router      # imprime el rol del slot router, o nada
    python3 profile-roles.py <A|B|C> thinking    # imprime el rol del slot pensamiento, o nada

Un slot con `source` distinto de `stack` (llamacpp, ollama, remote, claudecode) no lo sirve el
stack: en ese caso no imprime nada y `serve-profile.sh` simplemente no lo arranca. Si no existe
`profiles.json` (o el perfil o el slot), imprime el mapeo historico para no romper una instalacion
que todavia no tiene el manifiesto.
"""
import json
import os
import sys

DEFAULT_PROFILES = {
    "A": {"router": "router", "thinking": "fast"},
    "B": {"router": "router", "thinking": "complex"},
    # C es de un solo modelo: el writer ocupa los dos slots (el pipeline de la busqueda usa un
    # unico modelo; la extraccion JSON la hace el mismo).
    "C": {"router": "writer", "thinking": "writer"},
}


def main():
    if len(sys.argv) != 3:
        sys.exit("Uso: profile-roles.py <A|B|C> <router|thinking>")

    profile = sys.argv[1].upper()
    slot = sys.argv[2].lower()
    if slot not in ("router", "thinking"):
        sys.exit(f"Slot desconocido: {slot} (router o thinking)")

    manifest_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profiles.json")
    role = None
    try:
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        entry = manifest["profiles"][profile][slot]
        if entry.get("source") == "stack":
            role = entry.get("model")
    except (OSError, KeyError):
        # Sin manifiesto se usa el mapeo historico. Es lo que permite que una instalacion vieja
        # siga arrancando despues de actualizar los scripts.
        role = DEFAULT_PROFILES.get(profile, {}).get(slot)

    if role:
        print(role)


if __name__ == "__main__":
    main()
