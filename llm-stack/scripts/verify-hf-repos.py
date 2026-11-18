"""Paso 0 del plan de medicion (doc 11): comprueba por la API de HuggingFace, en solo lectura, que
los repos de models.json existen y son lo que dicen ser. No descarga pesos.

Uso: python3 verify-hf-repos.py [--alternatives]

Conviene lanzarlo ANTES de download-models.sh: unos minutos evitan bajar 10 GB para descubrir que
un repo desaparecio, cambio de formato o exige codigo remoto.
"""
import json
import os
import sys
import urllib.error
import urllib.request

WEIGHT_SUFFIXES = (".safetensors", ".bin", ".gguf", ".pt")


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "nexodeck-verify/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def gib(size):
    return f"{size / 1024 ** 3:.2f} GiB"


def check(entry):
    repo = entry["repo"]
    print(f"== {entry['role']}: {repo}")
    try:
        info = get_json(f"https://huggingface.co/api/models/{repo}?blobs=true")
    except urllib.error.HTTPError as error:
        print(f"   NO DISPONIBLE: HTTP {error.code}")
        return False
    except Exception as error:  # red caida, DNS, etc.
        print(f"   ERROR: {error}")
        return False

    files = info.get("siblings", [])
    weights = [f for f in files if f["rfilename"].endswith(WEIGHT_SUFFIXES)]
    total = sum(f.get("size") or 0 for f in weights)
    formats = sorted({f["rfilename"].rsplit(".", 1)[-1] for f in weights})
    print(f"   gated={info.get('gated')} privado={info.get('private')} descargas={info.get('downloads')}")
    print(f"   modificado={info.get('lastModified')} licencia={info.get('cardData', {}).get('license')}")
    print(f"   pesos: {len(weights)} ficheros, {gib(total)}, formatos={formats}")
    print(f"   tags: {', '.join(info.get('tags', [])[:12])}")
    has_pickle = any(f["rfilename"].endswith((".bin", ".pt")) for f in files)
    has_code = any(f["rfilename"].endswith(".py") for f in files)
    print(f"   riesgo: pesos pickle={has_pickle}, codigo remoto (.py)={has_code}")

    healthy = not info.get("gated") and not has_pickle and not has_code
    try:
        config = get_json(f"https://huggingface.co/{repo}/raw/main/config.json")
        quant = config.get("quantization_config", {})
        print(f"   config: model_type={config.get('model_type')} quant_method={quant.get('quant_method')} "
              f"bits={quant.get('bits')} group={quant.get('group_size')}")
        remote_code = "auto_map" in config
        print(f"   auto_map (codigo remoto)={remote_code}")
        healthy = healthy and not remote_code
    except Exception as error:
        print(f"   config.json no legible: {error}")
        healthy = False
    return healthy


def main():
    key = "alternatives" if "--alternatives" in sys.argv[1:] else "models"
    manifest_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models.json")
    with open(manifest_path, encoding="utf-8") as handle:
        entries = json.load(handle)[key]

    results = [check(entry) for entry in entries]
    print()
    print("RESULTADO:", "todos los repos existen y no traen riesgos evidentes" if all(results)
          else "hay repos con problemas, revisa las lineas anteriores")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
