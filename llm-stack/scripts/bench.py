"""Benchmark minimo de un servidor vLLM (API OpenAI), sin dependencias: lanza N clientes a la vez,
cada uno con varias peticiones, y mide latencia y tokens por segundo (por cliente y agregados).

Uso: python3 bench.py --port 8002 --model router --clients 1 4 8 --requests 3 --max-tokens 128

Cada cliente manda un prompt distinto (para no medir solo la cache de prefijos, que se mide con
--shared-prefix). Los tokens generados salen del campo `usage` de la respuesta, no de contar
palabras. Es un benchmark de decodificacion; para carga realista usar tambien `vllm bench serve`.
"""
import argparse
import json
import statistics
import threading
import time
import urllib.request

TOPICS = [
    "el ciclo del agua", "la fotosintesis", "el protocolo TCP", "una lista enlazada",
    "la tabla periodica", "el teorema de Pitagoras", "un compilador", "la memoria virtual",
    "el efecto invernadero", "un algoritmo de ordenacion", "la lectura de un mapa", "la fusion nuclear",
]
SHARED_PREFIX = "Eres un asistente tecnico preciso y conciso. " * 40


def chat(port, model, prompt, max_tokens):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=600) as response:
        data = json.load(response)
    elapsed = time.perf_counter() - started
    return data["usage"]["completion_tokens"], elapsed


def run_level(args, clients):
    results = []
    lock = threading.Lock()

    def worker(index):
        for request_number in range(args.requests):
            topic = TOPICS[(index * args.requests + request_number) % len(TOPICS)]
            prompt = f"Explica en detalle {topic}."
            if args.shared_prefix:
                prompt = SHARED_PREFIX + prompt
            tokens, elapsed = chat(args.port, args.model, prompt, args.max_tokens)
            with lock:
                results.append((tokens, elapsed))

    started = time.perf_counter()
    threads = [threading.Thread(target=worker, args=(i,)) for i in range(clients)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    wall = time.perf_counter() - started

    total_tokens = sum(tokens for tokens, _ in results)
    per_request = [tokens / elapsed for tokens, elapsed in results if elapsed > 0]
    latencies = sorted(elapsed for _, elapsed in results)
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))]
    print(f"clientes={clients:<2} peticiones={len(results):<3} tokens={total_tokens:<6} "
          f"agregado={total_tokens / wall:7.1f} tok/s  por cliente={statistics.mean(per_request):6.1f} tok/s  "
          f"latencia media={statistics.mean(latencies):5.1f}s p95={p95:5.1f}s")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--clients", type=int, nargs="+", default=[1, 4, 8])
    parser.add_argument("--requests", type=int, default=3, help="peticiones por cliente")
    parser.add_argument("--max-tokens", type=int, default=128)
    parser.add_argument("--shared-prefix", action="store_true", help="prefijo comun largo en todos los prompts")
    args = parser.parse_args()

    print(f"modelo={args.model} puerto={args.port} max_tokens={args.max_tokens} "
          f"prefijo_comun={args.shared_prefix}")
    chat(args.port, args.model, "Hola", 8)  # calentamiento: la primera peticion paga inicializaciones
    for clients in args.clients:
        run_level(args, clients)


if __name__ == "__main__":
    main()
