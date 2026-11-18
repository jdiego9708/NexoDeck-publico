"""Mide el efecto de la cache de prefijos y del offload del KV a RAM (--kv-offloading-size).

Manda N prompts largos y DISTINTOS entre si, uno detras de otro, y repite la tanda varias veces.
Si el KV de todos a la vez no cabe en la GPU, sin offload la segunda ronda tiene que recalcular
(prefill) porque la ronda anterior desalojo lo de cada prompt; con offload deberia recuperarlo de
RAM. Se pide poca salida (--max-tokens 8) para que casi todo el tiempo sea prefill.

Uso: python3 bench-prefix-reuse.py --port 8000 --model complex --prompts 6 --words 2200 --rounds 3

Muestra por ronda la latencia media y los tokens de prompt que vinieron de la cache
(`usage.prompt_tokens_details.cached_tokens`), que es la medida directa de si el prefijo se reutilizo.
Ajusta --words para que el prompt quepa en el contexto del servidor y N x prompt supere su KV.
"""
import argparse
import json
import random
import statistics
import time
import urllib.request

VOCABULARY = (
    "rio montana ciudad codigo servidor mensaje sistema grafo mapa palma lote vuelo imagen "
    "modelo tarea agente memoria cache token kernel tensor matriz nodo arbol ruta zona campo "
    "sensor motor batch cola hilo proceso disco fichero carpeta registro consulta indice clave "
    "valor version cambio prueba error fallo causa efecto medida limite margen presupuesto"
).split()


def build_prompt(seed, words):
    """Texto pseudoaleatorio reproducible; cada semilla da un texto sin prefijo comun con las demas."""
    generator = random.Random(seed)
    body = " ".join(generator.choice(VOCABULARY) for _ in range(words))
    return f"[documento {seed}] {body}\n\nResume en una frase el documento anterior."


def chat(port, model, prompt, max_tokens):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=900) as response:
        data = json.load(response)
    elapsed = time.perf_counter() - started
    usage = data["usage"]
    cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens") or 0
    return usage["prompt_tokens"], cached, elapsed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompts", type=int, default=6)
    parser.add_argument("--words", type=int, default=2200)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--max-tokens", type=int, default=8)
    args = parser.parse_args()

    prompts = [build_prompt(seed, args.words) for seed in range(args.prompts)]
    chat(args.port, args.model, "Hola", 4)  # calentamiento

    print(f"modelo={args.model} puerto={args.port} prompts={args.prompts} palabras={args.words}")
    for round_number in range(1, args.rounds + 1):
        results = [chat(args.port, args.model, prompt, args.max_tokens) for prompt in prompts]
        prompt_tokens = sum(r[0] for r in results)
        cached = sum(r[1] for r in results)
        latencies = [r[2] for r in results]
        print(f"ronda {round_number}: prompt={prompt_tokens // len(results)} tok/peticion  "
              f"desde cache={100 * cached / prompt_tokens:5.1f} %  "
              f"latencia media={statistics.mean(latencies):5.2f}s  max={max(latencies):5.2f}s  "
              f"total={sum(latencies):6.2f}s")


if __name__ == "__main__":
    main()
