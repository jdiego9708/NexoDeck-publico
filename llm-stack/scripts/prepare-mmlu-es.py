"""Prepara una muestra ESTRATIFICADA de MMLU EN ESPANOL (MMMLU, traduccion al espanol latino).

Uso (en Windows o en WSL2, solo biblioteca estandar):
    python prepare-mmlu-es.py --out mmlu-es-sample.jsonl [--per-subject 10]

Descarga `openai/MMMLU` (`test/mmlu_ES-LA.csv`, licencia MIT): las mismas preguntas de MMLU traducidas por
personas. Misma semilla y mismo formato que `prepare-mmlu.py` (id, subject, question, choices, answer),
asi que `check-code-detector.py`, `eval-auto-mixed.py` y `eval-mmlu.py` la leen igual.

Por que existe: el detector de codigo de `auto` se ajusto con prompts en ingles. Esto mide sus falsos
positivos en espanol, que es lo que escribe el usuario en NexoDeck.
"""
import argparse
import csv
import io
import json
import random
import urllib.request

URL = "https://huggingface.co/datasets/openai/MMMLU/resolve/main/test/mmlu_ES-LA.csv"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-subject", type=int, default=10)
    parser.add_argument("--seed", type=int, default=20260919)
    parser.add_argument("--out", default="mmlu-es-sample.jsonl")
    args = parser.parse_args()

    print(f"Descargando {URL}")
    with urllib.request.urlopen(URL, timeout=180) as response:
        text = response.read().decode("utf-8")
    rows = list(csv.DictReader(io.StringIO(text)))
    print(f"{len(rows)} preguntas")

    by_subject = {}
    for index, row in enumerate(rows):
        by_subject.setdefault(row["Subject"], []).append((index, row))

    generator = random.Random(args.seed)
    count = 0
    with open(args.out, "w", encoding="utf-8") as handle:
        for subject in sorted(by_subject):
            items = by_subject[subject]
            for index, row in generator.sample(items, min(args.per_subject, len(items))):
                handle.write(json.dumps({
                    "id": index, "subject": subject, "question": row["Question"],
                    "choices": [row["A"], row["B"], row["C"], row["D"]], "answer": row["Answer"],
                }, ensure_ascii=False) + "\n")
                count += 1
    print(f"{count} preguntas de {len(by_subject)} materias -> {args.out}")


if __name__ == "__main__":
    main()
