"""Prueba de extremo a extremo del enrutado por dominio de `auto` con los modelos REALES (perfil B).

Uso (Windows, con el perfil B y la pasarela levantados; clave en NEXODECK_LLM_KEY):
    python eval-auto-mixed.py --mmlu-es mmlu-es-sample.jsonl --mmlu mmlu-sample.jsonl \
        --humaneval HumanEval.jsonl --code-es data/code-prompts-es.jsonl --n 60

Que hace, todo por la pasarela (nunca directo a vLLM):
  1. Preguntas de MMLU en ESPANOL y en INGLES por `auto`: cada respuesta se verifica contra la letra
     correcta y se informa con POST /v1/feedback. Se espera que casi todo vaya al Router (`not_code`).
  2. Las mismas preguntas en espanol con el modelo EXPLICITO (`router` y `complex`), sin feedback: da la
     precision de cada modelo en espanol, que no estaba medida.
  3. Prompts de codigo (HumanEval en ingles, los escritos a mano en espanol) por `auto`: solo se cuenta
     a que modelo va cada uno. No se verifica la calidad del codigo aqui (eso lo hace eval-humaneval.py
     en su sandbox); se espera que casi todo vaya al Complejo (`code`/`complex_keywords`/`complex`).

Los prompts de codigo se mandan con max_tokens pequeno: solo interesa el enrutado, no la respuesta.
"""
import argparse
import collections
import concurrent.futures
import json
import os
import random
import re
import urllib.error
import urllib.request

PROMPT_EN = (
    "The following is a multiple choice question about {subject}. "
    "Answer with ONLY the letter (A, B, C or D) of the correct option, and nothing else.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nAnswer:"
)
PROMPT_ES = (
    "La siguiente es una pregunta de opción múltiple sobre {subject}. "
    "Responde SOLO con la letra (A, B, C o D) de la opción correcta, y nada más.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nRespuesta:"
)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def post(gateway, key, path, body):
    request = urllib.request.Request(
        f"{gateway}{path}", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return response.status, {k.lower(): v for k, v in response.headers.items()}, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, {k.lower(): v for k, v in error.headers.items()}, {"error": error.read().decode()[:200]}


def mmlu_prompt(template, item):
    c = item["choices"]
    return template.format(subject=item["subject"].replace("_", " "), question=item["question"],
                           a=c[0], b=c[1], c=c[2], d=c[3])


def letter_ok(data, item):
    reply = (data.get("choices") or [{}])[0].get("message", {}).get("content") or ""
    match = re.search(r"\b([ABCD])\b", reply.upper())
    return bool(match) and match.group(1) == item["answer"]


def run_mmlu_auto(args, label, items, template):
    """Por `auto`, con verificacion y feedback. Devuelve {(decision, modelo): [aciertos]}."""
    def one(item):
        status, headers, data = post(args.gateway, args.key, "/v1/chat/completions", {
            "model": "auto", "max_tokens": 8, "temperature": 0,
            "messages": [{"role": "user", "content": mmlu_prompt(template, item)}]})
        if status != 200:
            return None
        ok = letter_ok(data, item)
        request_id = headers.get("x-nexodeck-request-id")
        if request_id:
            post(args.gateway, args.key, "/v1/feedback",
                 {"request_id": request_id, "verified": ok, "verifier": "mmlu-letter"})
        return headers.get("x-nexodeck-decision"), headers.get("x-nexodeck-model"), ok

    groups = collections.defaultdict(list)
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        for result in pool.map(one, items):
            if result is None:
                failed += 1
            else:
                groups[(result[0], result[1])].append(result[2])
    print(f"\n[{label}] por `auto` ({len(items)} preguntas, {failed} fallidas)")
    for (decision, model), oks in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print(f"  {decision:<10} -> {model:<8} {len(oks):>3} preguntas, {100 * sum(oks) / len(oks):5.1f} % correctas")


def run_mmlu_explicit(args, label, items, template, model):
    def one(item):
        status, _, data = post(args.gateway, args.key, "/v1/chat/completions", {
            "model": model, "max_tokens": 8, "temperature": 0,
            "messages": [{"role": "user", "content": mmlu_prompt(template, item)}]})
        return letter_ok(data, item) if status == 200 else None

    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        results = [r for r in pool.map(one, items) if r is not None]
    print(f"[{label}] `{model}` explicito: {100 * sum(results) / len(results):5.1f} % correctas ({len(results)} preguntas)")


def run_routing_only(args, label, prompts):
    def one(text):
        status, headers, _ = post(args.gateway, args.key, "/v1/chat/completions", {
            "model": "auto", "max_tokens": 4, "temperature": 0,
            "messages": [{"role": "user", "content": text}]})
        return (headers.get("x-nexodeck-decision"), headers.get("x-nexodeck-model")) if status == 200 else None

    groups = collections.Counter()
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        for result in pool.map(one, prompts):
            groups[result] += 1
    print(f"\n[{label}] enrutado de {len(prompts)} prompts de codigo (sin verificar la respuesta)")
    for (decision, model), count in groups.most_common():
        print(f"  {decision:<17} -> {model:<8} {count:>3}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mmlu-es", required=True)
    parser.add_argument("--mmlu", required=True)
    parser.add_argument("--humaneval", required=True)
    parser.add_argument("--code-es", required=True)
    parser.add_argument("--gateway", default="http://127.0.0.1:8888")
    parser.add_argument("--key", default=os.environ.get("NEXODECK_LLM_KEY", ""))
    parser.add_argument("--n", type=int, default=60, help="preguntas de MMLU por idioma")
    parser.add_argument("--n-code", type=int, default=30, help="prompts de HumanEval")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--explicit", default="router,complex",
                        help="modelos que se miden por nombre, separados por comas (perfil A: router,fast)")
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()
    if not args.key:
        raise SystemExit("Falta la clave: --key o la variable NEXODECK_LLM_KEY.")

    generator = random.Random(args.seed)
    es = load(args.mmlu_es)
    en = load(args.mmlu)
    generator.shuffle(es)
    generator.shuffle(en)
    es, en = es[: args.n], en[: args.n]

    run_mmlu_auto(args, "MMLU espanol", es, PROMPT_ES)
    run_mmlu_auto(args, "MMLU ingles", en, PROMPT_EN)
    print()
    for model in args.explicit.split(","):
        run_mmlu_explicit(args, "MMLU espanol", es, PROMPT_ES, model)
        run_mmlu_explicit(args, "MMLU ingles", en, PROMPT_EN, model)

    humaneval = load(args.humaneval)
    generator.shuffle(humaneval)
    run_routing_only(args, "HumanEval ingles", [p["prompt"] for p in humaneval[: args.n_code]])
    run_routing_only(args, "codigo espanol", [p["text"] for p in load(args.code_es)])


if __name__ == "__main__":
    main()
