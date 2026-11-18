"""Prepara una muestra ESTRATIFICADA de MMLU (57 materias, opcion multiple) para eval-mmlu.py.

Necesita pyarrow para leer el parquet, que no esta en el Python del sistema; se lanza con uv:

    ~/.local/bin/uv run --no-project --with pyarrow python3 prepare-mmlu.py [--per-subject 10]

Descarga el conjunto de prueba de `cais/mmlu` (configuracion `all`, licencia MIT), elige
`--per-subject` preguntas por materia con una semilla fija (la misma muestra siempre) y las guarda en
~/eval/mmlu-sample.jsonl. Con 57 materias x 10 son 570 preguntas: suficiente para comparar dos
modelos por categoria, no para clasificar materias sueltas (10 preguntas dan un error enorme).
"""
import argparse
import io
import json
import os
import random
import urllib.request

import pyarrow.parquet as pq

URL = "https://huggingface.co/datasets/cais/mmlu/resolve/main/all/test-00000-of-00001.parquet"
LETTERS = "ABCD"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-subject", type=int, default=10)
    parser.add_argument("--seed", type=int, default=20260919)
    parser.add_argument("--out", default=os.path.expanduser("~/eval/mmlu-sample.jsonl"))
    args = parser.parse_args()

    print(f"Descargando {URL}")
    with urllib.request.urlopen(URL, timeout=120) as response:
        table = pq.read_table(io.BytesIO(response.read()))
    rows = table.to_pylist()
    print(f"{len(rows)} preguntas en el conjunto de prueba")

    by_subject = {}
    for index, row in enumerate(rows):
        by_subject.setdefault(row["subject"], []).append((index, row))

    generator = random.Random(args.seed)
    sample = []
    for subject in sorted(by_subject):
        items = by_subject[subject]
        for index, row in generator.sample(items, min(args.per_subject, len(items))):
            sample.append({
                "id": index,
                "subject": subject,
                "question": row["question"],
                "choices": list(row["choices"]),
                "answer": LETTERS[int(row["answer"])],
            })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        for item in sample:
            handle.write(json.dumps(item, ensure_ascii=False) + "\n")
    print(f"{len(sample)} preguntas de {len(by_subject)} materias -> {args.out}")


if __name__ == "__main__":
    main()
