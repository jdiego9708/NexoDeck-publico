"""Imprime los modelos de models.json como lineas `repo<TAB>dir`, para que los scripts de shell
no tengan que parsear JSON.

Uso: python3 list-models.py [--alternatives] [rol ...]
Sin roles se listan todos los del manifiesto.
"""
import json
import os
import sys


def main():
    arguments = sys.argv[1:]
    use_alternatives = "--alternatives" in arguments
    roles = [argument for argument in arguments if not argument.startswith("--")]

    manifest_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models.json")
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)

    entries = manifest["alternatives" if use_alternatives else "models"]
    known_roles = {entry["role"] for entry in entries}
    unknown = [role for role in roles if role not in known_roles]
    if unknown:
        sys.exit(f"Rol desconocido: {', '.join(unknown)}. Disponibles: {', '.join(sorted(known_roles))}")

    for entry in entries:
        if not roles or entry["role"] in roles:
            print(f"{entry['repo']}\t{entry['dir']}")


if __name__ == "__main__":
    main()
