"""Prueba el Sleep Mode de un servidor vLLM arrancado con SLEEP_MODE=1 (serve-model.sh).

Mide, para un nivel de sueno, cuanta VRAM libera, cuanta RAM ocupa el sistema, cuanto tarda en
dormir y en despertar, y comprueba que el modelo responde bien y rinde igual despues.

Uso: python3 test-sleep-mode.py --port 8000 --model complex --level 1
     python3 test-sleep-mode.py --port 8000 --model complex --level 2

Nivel 1: los pesos pasan a RAM y el KV se descarta. Despertar es copiar de vuelta.
Nivel 2: los pesos se DESCARTAN tambien; al despertar hay que recargarlos desde disco (la receta,
         doc 04, cita /reload_weights; aqui se prueban las variantes y se informa de cual va).
"""
import argparse
import json
import subprocess
import time
import urllib.error
import urllib.request


def gpu_used_mib():
    output = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
        capture_output=True, text=True, check=True).stdout
    return int(output.strip().splitlines()[0])


def ram_used_mib():
    values = {}
    with open("/proc/meminfo", encoding="utf-8") as handle:
        for line in handle:
            key, rest = line.split(":", 1)
            values[key] = int(rest.split()[0])
    return (values["MemTotal"] - values["MemAvailable"]) // 1024


def http(port, method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}", data=data, method=method,
        headers={"Content-Type": "application/json"})
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            text = response.read().decode()
            return response.status, time.perf_counter() - started, text
    except urllib.error.HTTPError as error:
        return error.code, time.perf_counter() - started, error.read().decode()[:200]


def generate(port, model, tokens=128):
    status, elapsed, text = http(port, "POST", "/v1/chat/completions", {
        "model": model, "max_tokens": tokens, "temperature": 0,
        "messages": [{"role": "user", "content": "Cuenta del 1 al 20 separando con comas."}]})
    if status != 200:
        return None, None, f"HTTP {status}: {text[:120]}"
    data = json.loads(text)
    reply = data["choices"][0]["message"]["content"] or ""
    return data["usage"]["completion_tokens"] / elapsed, reply, None


def snapshot(label):
    print(f"   [{label}] VRAM usada={gpu_used_mib()} MiB  RAM usada={ram_used_mib()} MiB")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--level", type=int, choices=[1, 2], default=1)
    args = parser.parse_args()
    port = args.port

    generate(port, args.model, 8)  # calentamiento
    rate, reply, error = generate(port, args.model)
    print(f"== Antes de dormir: {rate:.1f} tok/s  respuesta: {reply[:60]!r}")
    snapshot("despierto")

    status, elapsed, text = http(port, "POST", f"/sleep?level={args.level}")
    print(f"== POST /sleep?level={args.level}: HTTP {status} en {elapsed:.2f} s  {text[:80]}")
    if status != 200:
        print("   El servidor no admite Sleep Mode (lo arrancaste con SLEEP_MODE=1?).")
        return
    time.sleep(2)
    snapshot("dormido")
    print("   is_sleeping:", http(port, "GET", "/is_sleeping")[2].strip())

    wake_started = time.perf_counter()
    if args.level == 1:
        status, elapsed, text = http(port, "POST", "/wake_up")
        print(f"== POST /wake_up: HTTP {status} en {elapsed:.2f} s  {text[:80]}")
    else:
        # Nivel 2: primero los pesos, luego recargarlos, luego el KV (procedimiento de vLLM);
        # si esas rutas no existen se cae a las que cita la receta.
        for path, body in [("/wake_up?tags=weights", None),
                           ("/collective_rpc", {"method": "reload_weights"}),
                           ("/wake_up?tags=kv_cache", None)]:
            status, elapsed, text = http(port, "POST", path, body)
            print(f"== POST {path}: HTTP {status} en {elapsed:.2f} s  {text[:80]}")
            if status == 404 and path == "/collective_rpc":
                status, elapsed, text = http(port, "POST", "/reload_weights")
                print(f"== POST /reload_weights (receta): HTTP {status} en {elapsed:.2f} s  {text[:80]}")
    print(f"== Tiempo total de despertar: {time.perf_counter() - wake_started:.2f} s")
    http(port, "POST", "/reset_prefix_cache")
    snapshot("despierto de nuevo")
    print("   is_sleeping:", http(port, "GET", "/is_sleeping")[2].strip())

    rate, reply, error = generate(port, args.model)
    if error:
        print(f"== Despues de despertar: FALLA {error}")
        return
    print(f"== Despues de despertar: {rate:.1f} tok/s  respuesta: {reply[:60]!r}")


if __name__ == "__main__":
    main()
