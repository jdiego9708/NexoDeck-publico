"""Evalua el CONOCIMIENTO GENERAL de un modelo del stack con una muestra estratificada de MMLU.

Uso (dentro de WSL2, con los servidores vLLM levantados y tras prepare-mmlu.py):
    python3 eval-mmlu.py --model complex --port 8000
    python3 eval-mmlu.py --model router  --port 8002 --limit 60

Pregunta de opcion multiple, cero ejemplos, temperatura 0; se pide SOLO la letra y se toma la primera
A-D suelta de la respuesta. Va directo a vLLM (no por la pasarela).

Sirve para una decision concreta: si el enrutado del modelo `auto` deberia ser por DOMINIO (codigo o
no) y no por longitud del enunciado (doc 11, 7.24). Un modelo de codigo podado y cuantizado (el
Complejo) podria ser peor en conocimiento general que uno generalista pequeno (el Router); esto lo
mide en vez de suponerlo.

Limites: MMLU esta en ingles y es un benchmark conocido; 10 preguntas por materia no permiten juzgar
materias sueltas, solo categorias; y, como en HumanEval, temperatura 0 no es determinista bajo carga
concurrente: se dan rangos, no una cifra.
"""
import argparse
import collections
import concurrent.futures
import json
import os
import re
import time
import urllib.request

PROMPT = (
    "The following is a multiple choice question about {subject}. "
    "Answer with ONLY the letter (A, B, C or D) of the correct option, and nothing else.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nAnswer:"
)


REASON_PROMPT = (
    "The following is a multiple choice question about {subject}. Think through it step by step, "
    "briefly, and then finish with a final line of the exact form `Answer: X` where X is A, B, C or D.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}"
)


def ask(base_url, model, item, reason=False):
    """Con reason=False se pide SOLO la letra; con reason=True se deja razonar antes (max_tokens
    mayor): sirve para separar un fallo de FORMATO (un modelo que no responde bien sin pensar) de un
    fallo de CONOCIMIENTO."""
    template = REASON_PROMPT if reason else PROMPT
    body = json.dumps({
        "model": model, "max_tokens": 512 if reason else 8, "temperature": 0,
        "messages": [{"role": "user", "content": template.format(
            subject=item["subject"].replace("_", " "), question=item["question"],
            a=item["choices"][0], b=item["choices"][1], c=item["choices"][2], d=item["choices"][3])}],
    }).encode()
    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions", data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as response:
        data = json.load(response)
    return data["choices"][0]["message"]["content"] or ""


def parse_letter(reply, reason=False):
    if reason:
        # La ULTIMA linea `Answer: X` (puede llevar asteriscos de markdown); el razonamiento previo
        # menciona letras sueltas y no debe confundirse con la respuesta.
        matches = re.findall(r"answer\s*[:：]\s*\**\s*\(?([ABCD])\b", reply, flags=re.IGNORECASE)
        return matches[-1].upper() if matches else None
    match = re.search(r"\b([ABCD])\b", reply.upper())
    return match.group(1) if match else None


def evaluate_one(base_url, model, item, reason=False):
    try:
        reply = ask(base_url, model, item, reason)
    except Exception as error:  # el servidor puede fallar a mitad: se anota y se sigue
        return {"id": item["id"], "subject": item["subject"], "correct": False, "letter": None,
                "error": f"{type(error).__name__}"}
    letter = parse_letter(reply, reason)
    # Se guarda SIEMPRE la respuesta cruda (recortada): asi se puede comprobar que el numero no sea
    # un artefacto del analisis de la letra, que es exactamente lo que hay que descartar.
    return {"id": item["id"], "subject": item["subject"], "correct": letter == item["answer"],
            "letter": letter, "expected": item["answer"], "reply": reply[-80:] if reason else reply[:80]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--limit", type=int, default=0, help="0 = toda la muestra")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--dir", default=os.path.expanduser("~/eval"))
    parser.add_argument("--reason", action="store_true",
                        help="deja razonar antes de responder (max_tokens 512) en vez de pedir solo la letra")
    args = parser.parse_args()
    base_url = f"http://{args.host}:{args.port}"

    with open(os.path.join(args.dir, "mmlu-sample.jsonl"), encoding="utf-8") as handle:
        items = [json.loads(line) for line in handle if line.strip()]
    if args.limit:
        items = items[: args.limit]
    print(f"modelo={args.model} preguntas={len(items)} trabajadores={args.workers}")

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda item: evaluate_one(base_url, args.model, item, args.reason), items))

    correct = sum(r["correct"] for r in results)
    unparsed = sum(r["letter"] is None and "error" not in r for r in results)
    errors = sum("error" in r for r in results)
    # Los resultados con razonamiento van a otro nombre: analyze-mmlu.py solo lee `mmlu-<modelo>-*`,
    # y mezclar las dos formas de preguntar falsearia la comparacion.
    prefix = "mmlureason" if args.reason else "mmlu"
    out_path = os.path.join(args.dir, f"{prefix}-{args.model}-{time.strftime('%Y%m%d-%H%M%S')}.jsonl")
    with open(out_path, "w", encoding="utf-8") as handle:
        for result in results:
            handle.write(json.dumps(result, ensure_ascii=False) + "\n")

    # Reparto de letras: un modelo que responde casi siempre la misma esta adivinando (o el analisis
    # esta mal); una distribucion cercana a la real (~25 % cada una) es una respuesta de verdad.
    letters = collections.Counter(r["letter"] or "-" for r in results)
    print("letras respondidas:", dict(sorted(letters.items())), " respuestas reales:",
          dict(sorted(collections.Counter(item["answer"] for item in items).items())))
    print("primeras respuestas crudas:", [(r.get("reply"), r.get("expected")) for r in results[:6]])
    print(f"RESULTADO {args.model}: {correct}/{len(results)} = {100 * correct / len(results):.1f} %   "
          f"sin letra legible: {unparsed}   errores de servidor: {errors}   ({time.perf_counter() - started:.0f} s)")
    if unparsed:
        sample = [r for r in results if r["letter"] is None and "error" not in r][:3]
        print("ejemplos sin letra:", [r.get("reply") for r in sample])
    print(f"detalle: {out_path}")


if __name__ == "__main__":
    main()
