"""Paso 7 del doc 03, sin dependencias: valida las cabeceras de los safetensors descargados
(estructura y desplazamientos frente al tamano real del fichero) y resume tipos de tensor y
cuantizacion, para confirmar que cada modelo es del formato que dice su repo.

Uso: python3 verify-models.py [--alternatives]
Variable opcional: MODELS_DIR (por defecto ~/models).

Un `model.safetensors` truncado tiene la cabecera bien pero los datos cortos: por eso se compara
el final del ultimo tensor con el tamano del fichero, no solo se lee el JSON.
"""
import collections
import glob
import json
import os
import struct
import sys

# Tipos de tensor que delatan cada cuantizacion en los checkpoints de esta receta.
QUANT_SIGNATURES = {
    "nvfp4": {"U8", "F8_E4M3"},  # pesos FP4 empaquetados en bytes + escalas FP8
    "awq": {"I32"},  # pesos de 4 bits empaquetados en enteros de 32 bits
}


def read_header(path):
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        (header_length,) = struct.unpack("<Q", handle.read(8))
        header = json.loads(handle.read(header_length))
    header.pop("__metadata__", None)
    end_of_data = max((t["data_offsets"][1] for t in header.values()), default=0)
    complete = 8 + header_length + end_of_data == size
    return header, complete


def verify_model(entry, models_dir):
    folder = os.path.join(models_dir, entry["dir"])
    print(f"== {entry['role']}: {entry['dir']}")
    files = sorted(glob.glob(os.path.join(folder, "*.safetensors")))
    if not files:
        print("   NO ENCONTRADO: no hay ficheros .safetensors")
        return False

    dtypes = collections.Counter()
    names = []
    all_complete = True
    for path in files:
        header, complete = read_header(path)
        all_complete &= complete
        names.extend(header)
        dtypes.update(t["dtype"] for t in header.values())
        print(f"   {os.path.basename(path)}: {len(header)} tensores, completo={complete}")

    with open(os.path.join(folder, "config.json"), encoding="utf-8") as handle:
        config = json.load(handle)
    quant = config.get("quantization_config", {})
    text = config.get("text_config", config)
    visual = sum(1 for name in names if "visual" in name or "vision" in name)

    print(f"   tipos: {dict(dtypes)}")
    print(f"   model_type={config.get('model_type')} architectures={config.get('architectures')}")
    print(f"   capas={text.get('num_hidden_layers')} expertos={text.get('num_experts')} "
          f"activos={text.get('num_experts_per_tok')} contexto={text.get('max_position_embeddings')}")
    print(f"   quantization_config: quant_method={quant.get('quant_method')} algo={quant.get('quant_algo')} "
          f"bits={quant.get('bits')} group={quant.get('group_size')}")
    print(f"   tensores de la parte visual: {visual} de {len(names)}")

    signature = QUANT_SIGNATURES.get(entry["expected_quant"], set())
    matches = signature.issubset(dtypes)
    print(f"   cuantizacion esperada '{entry['expected_quant']}': {'OK' if matches else 'NO COINCIDE con los tipos de tensor'}")
    return all_complete and matches


def main():
    key = "alternatives" if "--alternatives" in sys.argv[1:] else "models"
    models_dir = os.path.expanduser(os.environ.get("MODELS_DIR", "~/models"))
    manifest_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models.json")
    with open(manifest_path, encoding="utf-8") as handle:
        entries = json.load(handle)[key]

    results = [verify_model(entry, models_dir) for entry in entries]
    print()
    print("RESULTADO:", "todos los modelos estan completos y en el formato esperado" if all(results)
          else "hay modelos incompletos o en otro formato, revisa las lineas anteriores")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
