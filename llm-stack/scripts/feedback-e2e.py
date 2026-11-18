"""Extremo a extremo de los resultados verificados: preguntas MMLU por la pasarela con `auto`, cada
respuesta se verifica contra la letra correcta y el resultado se informa con POST /v1/feedback.

Genera datos REALES para decisions.jsonl: el modelo que eligio `auto` y si su respuesta paso la
verificacion. Despues, `summarize-decisions.py` los une.

Uso (desde Windows, donde escucha la pasarela; la muestra vive en WSL2):
    $env:NEXODECK_LLM_KEY = "ndk_..."
    python feedback-e2e.py --sample "\\\\wsl.localhost\\Ubuntu\\home\\<usuario>\\eval\\mmlu-sample.jsonl" --n 60

Por que MMLU: cada pregunta tiene una respuesta correcta conocida, asi que hay un VERIFICADOR real.
Es tambien una prueba honesta de las reglas de `auto`: mandan a estas preguntas al «trabajador»
(el Complejo en el perfil B), que en MMLU rinde peor que el Router (doc 11, 7.25); los datos
registrados deben reflejarlo.
"""
import argparse
import json
import os
import random
import re
import urllib.error
import urllib.request

PROMPT = (
    "The following is a multiple choice question about {subject}. "
    "Answer with ONLY the letter (A, B, C or D) of the correct option, and nothing else.\n\n"
    "{question}\nA. {a}\nB. {b}\nC. {c}\nD. {d}\nAnswer:"
)


def post(url, key, body):
    request = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return response.status, dict(response.headers), json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), {"error": error.read().decode()[:200]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", required=True, help="mmlu-sample.jsonl (prepare-mmlu.py)")
    parser.add_argument("--gateway", default="http://127.0.0.1:8888")
    parser.add_argument("--key", default=os.environ.get("NEXODECK_LLM_KEY", ""))
    parser.add_argument("--n", type=int, default=60)
    parser.add_argument("--seed", type=int, default=3)
    args = parser.parse_args()
    if not args.key:
        raise SystemExit("Falta la clave: --key o la variable NEXODECK_LLM_KEY.")

    with open(args.sample, encoding="utf-8") as handle:
        items = [json.loads(line) for line in handle if line.strip()]
    random.Random(args.seed).shuffle(items)
    items = items[: args.n]

    reported, failed_feedback, no_id = 0, 0, 0
    for item in items:
        prompt = PROMPT.format(subject=item["subject"].replace("_", " "), question=item["question"],
                               a=item["choices"][0], b=item["choices"][1], c=item["choices"][2], d=item["choices"][3])
        status, headers, data = post(f"{args.gateway}/v1/chat/completions", args.key, {
            "model": "auto", "max_tokens": 8, "temperature": 0,
            "messages": [{"role": "user", "content": prompt}]})
        if status != 200:
            print(f"  la peticion fallo: HTTP {status} {data}")
            continue
        headers = {name.lower(): value for name, value in headers.items()}
        request_id = headers.get("x-nexodeck-request-id")
        if not request_id:
            no_id += 1
            continue
        reply = data["choices"][0]["message"]["content"] or ""
        match = re.search(r"\b([ABCD])\b", reply.upper())
        verified = bool(match) and match.group(1) == item["answer"]
        status, _, data = post(f"{args.gateway}/v1/feedback", args.key, {
            "request_id": request_id, "verified": verified, "verifier": "mmlu-letter"})
        if status == 200:
            reported += 1
        else:
            failed_feedback += 1
            print(f"  el feedback fallo: HTTP {status} {data}")

    print(f"preguntas: {len(items)}   resultados informados: {reported}   feedback fallido: {failed_feedback}"
          f"   sin request-id: {no_id}")


if __name__ == "__main__":
    main()
