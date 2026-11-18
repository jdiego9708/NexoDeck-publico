"""Valida el detector de codigo del modelo `auto` contra HumanEval (todo es codigo) y MMLU (casi nada).

Uso (en Windows, desde la carpeta gateway/ ya compilada, con los datasets de ~/eval copiados):
    python check-code-detector.py --humaneval HumanEval.jsonl --mmlu mmlu-sample.jsonl

El detector es el de verdad: se invoca `cargo run --example classify`, que lee los prompts por stdin.
Se mide con el mismo texto que envian los evaluadores (`eval-humaneval.py`, `eval-mmlu.py`).

Que se espera:
  - HumanEval: 100 % detectado (son 164 problemas de codigo). Lo que falle es un codigo que iria al
    generalista, que en codigo saca 75-79 % frente al 89-90 % del Complejo.
  - MMLU: solo deben salir las materias de programacion. Cada pregunta de otra materia detectada es
    un falso positivo: acabaria en el Complejo, que ahi saca 37 %.
Con `--show` se listan los fallos, para ajustar `code_markers`.
"""
import argparse
import collections
import json
import subprocess
import sys

MMLU_PROMPT = (
    "The following is a multiple choice question about {subject}. "
    "Answer with ONLY the letter (A, B, C or D) of the correct option, and nothing else.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nAnswer:"
)

MMLU_PROMPT_ES = (
    "La siguiente es una pregunta de opción múltiple sobre {subject}. "
    "Responde SOLO con la letra (A, B, C o D) de la opción correcta, y nada más.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nRespuesta:"
)

CODE_SUBJECTS = {"college computer science", "high school computer science", "machine learning",
                 "computer security", "electrical engineering"}


def load(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def classify(texts, gateway_dir):
    payload = "\n".join(json.dumps({"text": text}) for text in texts) + "\n"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--release", "--example", "classify"],
        input=payload, capture_output=True, text=True, encoding="utf-8", cwd=gateway_dir, check=True)
    flags = [line == "1" for line in result.stdout.split()]
    assert len(flags) == len(texts), f"{len(flags)} salidas para {len(texts)} entradas"
    return flags


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--humaneval", required=True)
    parser.add_argument("--mmlu", required=True)
    parser.add_argument("--mmlu-es", help="mmlu-es-sample.jsonl (prepare-mmlu-es.py): falsos positivos en espanol")
    parser.add_argument("--code-es", help="data/code-prompts-es.jsonl: recall en espanol")
    parser.add_argument("--gateway-dir", default="../gateway")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()

    if args.code_es:
        prompts = load(args.code_es)
        flags = classify([p["text"] for p in prompts], args.gateway_dir)
        print(f"Codigo en espanol (escrito a mano): {sum(flags)}/{len(flags)} detectados ({100 * sum(flags) / len(flags):.1f} %)")
        for prompt, hit in zip(prompts, flags):
            if not hit:
                print("  no detectado:", prompt["text"][:110].replace("\n", " "))
    if args.mmlu_es:
        items = load(args.mmlu_es)
        texts = [MMLU_PROMPT_ES.format(subject=i["subject"].replace("_", " "), question=i["question"],
                                       a=i["choices"][0], b=i["choices"][1], c=i["choices"][2], d=i["choices"][3])
                 for i in items]
        flags = classify(texts, args.gateway_dir)
        detected = collections.Counter(i["subject"].replace("_", " ") for i, hit in zip(items, flags) if hit)
        outside = {s: n for s, n in detected.items() if s not in CODE_SUBJECTS}
        print(f"MMLU en espanol: {sum(flags)}/{len(flags)} detectados; "
              f"FALSOS POSITIVOS (fuera de materias de programacion) {sum(outside.values())}")
        for subject, count in sorted(outside.items(), key=lambda kv: -kv[1]):
            print(f"  {subject}: {count}")
        if args.show:
            for item, hit in zip(items, flags):
                if hit and item["subject"].replace("_", " ") not in CODE_SUBJECTS:
                    print("  ---", item["subject"], "|", item["question"][:160].replace("\n", " "))

    problems = load(args.humaneval)
    flags = classify([p["prompt"] for p in problems], args.gateway_dir)
    missed = [p["task_id"] for p, hit in zip(problems, flags) if not hit]
    print(f"HumanEval: {sum(flags)}/{len(flags)} detectados como codigo ({100 * sum(flags) / len(flags):.1f} %)")
    if args.show:
        for task in missed:
            print("  no detectado:", task)

    items = load(args.mmlu)
    texts = [MMLU_PROMPT.format(subject=i["subject"].replace("_", " "), question=i["question"],
                                a=i["choices"][0], b=i["choices"][1], c=i["choices"][2], d=i["choices"][3])
             for i in items]
    flags = classify(texts, args.gateway_dir)
    by_subject = collections.Counter(i["subject"].replace("_", " ") for i, hit in zip(items, flags) if hit)
    outside = {s: n for s, n in by_subject.items() if s not in CODE_SUBJECTS}
    print(f"MMLU: {sum(flags)}/{len(flags)} detectados; en materias de programacion "
          f"{sum(n for s, n in by_subject.items() if s in CODE_SUBJECTS)}, "
          f"FALSOS POSITIVOS {sum(outside.values())}")
    for subject, count in sorted(outside.items(), key=lambda kv: -kv[1]):
        print(f"  {subject}: {count}")
    if args.show:
        for item, text, hit in zip(items, texts, flags):
            if hit and item["subject"].replace("_", " ") not in CODE_SUBJECTS:
                print("  ---", item["subject"], "|", item["question"][:160].replace("\n", " "))
    return 0


if __name__ == "__main__":
    sys.exit(main())
