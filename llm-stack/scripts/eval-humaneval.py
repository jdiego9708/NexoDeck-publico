"""Evalua un modelo del stack con HumanEval (164 problemas de Python, pass@1 con temperatura 0).

Uso (dentro de WSL2, con los servidores vLLM levantados):
    python3 eval-humaneval.py --model complex --port 8000
    python3 eval-humaneval.py --model router  --port 8002 --limit 20

Va DIRECTO a vLLM (no por la pasarela): para medir la calidad del modelo no hace falta clave. Pide
la funcion completa en un bloque ```python, extrae el codigo y lo ejecuta con los tests del
problema.

**El codigo generado por el modelo se ejecuta en un contenedor aislado**, nunca en la maquina:
sin red (`--network none`), sin capacidades, sistema de ficheros de solo lectura, sin usuario
privilegiado, con limites de memoria, CPU y procesos, y con un `timeout` dentro y otro fuera. Usa
la imagen local de vLLM porque ya esta descargada y trae Python.

Limites de lo que mide, para no leerlo de mas: HumanEval son funciones cortas y autocontenidas, y
es un benchmark conocido (puede estar en los datos de entrenamiento). Sirve para comparar modelos
entre si y para descartar problemas graves, no como garantia de calidad sobre codigo real del
proyecto.
"""
import argparse
import collections
import concurrent.futures
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

DATASET_URL = "https://raw.githubusercontent.com/openai/human-eval/master/data/HumanEval.jsonl.gz"
EXPECTED_PROBLEMS = 164

INSTRUCTION = (
    "Complete the following Python function. Reply with ONLY the complete function (its signature "
    "and body, plus any import it needs) in a single ```python code block, with no explanation.\n\n"
    "```python\n{prompt}\n```"
)


def load_problems(cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, "HumanEval.jsonl")
    if not os.path.exists(path):
        print(f"Descargando el dataset de {DATASET_URL}")
        with urllib.request.urlopen(DATASET_URL, timeout=60) as response:
            data = gzip.decompress(response.read())
        with open(path, "wb") as handle:
            handle.write(data)
    with open(path, encoding="utf-8") as handle:
        problems = [json.loads(line) for line in handle if line.strip()]
    if len(problems) != EXPECTED_PROBLEMS:
        sys.exit(f"El dataset tiene {len(problems)} problemas y deberian ser {EXPECTED_PROBLEMS}: {path}")
    return problems


def generate(base_url, model, prompt, max_tokens):
    body = json.dumps({
        "model": model, "max_tokens": max_tokens, "temperature": 0,
        "messages": [{"role": "user", "content": INSTRUCTION.format(prompt=prompt)}],
    }).encode()
    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions", data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        data = json.load(response)
    return data["choices"][0]["message"]["content"] or "", data["usage"]["completion_tokens"]


def extract_code(reply, entry_point):
    """El bloque ```python que define la funcion pedida; si no hay bloques, la respuesta entera."""
    blocks = re.findall(r"```(?:python|py)?\s*\n(.*?)```", reply, flags=re.DOTALL)
    for block in blocks:
        if re.search(rf"def\s+{re.escape(entry_point)}\s*\(", block):
            return block
    return blocks[0] if blocks else reply


def build_program(problem, code):
    """Prompt (imports y funciones auxiliares) + codigo del modelo + tests. El codigo del modelo
    redefine la funcion del prompt, que solo trae la firma y el docstring."""
    return f"{problem['prompt']}\n\n{code}\n\n{problem['test']}\n\ncheck({problem['entry_point']})\n"


def run_sandbox(image, program, limit_seconds=10):
    """Ejecuta el programa en un contenedor sin red ni privilegios. Devuelve (ok, categoria)."""
    directory = tempfile.mkdtemp(prefix="humaneval-")
    path = os.path.join(directory, "program.py")
    name = f"humaneval-{uuid.uuid4().hex[:12]}"
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(program)
        os.chmod(path, 0o644)
        command = [
            "docker", "run", "--rm", "--name", name,
            "--network", "none", "--memory", "512m", "--cpus", "1", "--pids-limit", "64",
            "--read-only", "--tmpfs", "/tmp:size=32m", "--user", "65534:65534",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
            "-v", f"{path}:/work/program.py:ro",
            "--entrypoint", "timeout", image, str(limit_seconds), "python3", "/work/program.py",
        ]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=limit_seconds + 25)
        except subprocess.TimeoutExpired:
            subprocess.run(["docker", "rm", "-f", name], capture_output=True)
            return False, "timeout"
        if result.returncode == 0:
            return True, "ok"
        if result.returncode == 124:
            return False, "timeout"
        error = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "sin salida"
        category = error.split(":")[0].strip() or "error"
        return False, category[:40]
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def evaluate_one(args, image, problem):
    started = time.perf_counter()
    try:
        reply, tokens = generate(args.base, args.model, problem["prompt"], args.max_tokens)
    except Exception as error:  # el servidor puede fallar a mitad: se anota y se sigue
        return {"task_id": problem["task_id"], "passed": False, "category": f"generacion: {type(error).__name__}",
                "tokens": 0, "seconds": time.perf_counter() - started}
    code = extract_code(reply, problem["entry_point"])
    passed, category = run_sandbox(image, build_program(problem, code))
    result = {"task_id": problem["task_id"], "passed": passed, "category": category, "tokens": tokens,
              "seconds": time.perf_counter() - started}
    if not passed:
        # Solo de los fallos, para poder distinguir un fallo del modelo de un fallo de la extraccion
        # del codigo (p. ej. un bloque cortado por max_tokens) sin volver a lanzar todo.
        result["reply"] = reply
    return result


def selftest(image, problems):
    """Comprueba el PROPIO evaluador: un evaluador que nunca falla, o cuyo aislamiento no aisla,
    no vale. Devuelve True si todo se comporta como debe."""
    problem = problems[0]
    canonical = build_program(problem, problem["prompt"] + problem["canonical_solution"])
    wrong = build_program(problem, f"def {problem['entry_point']}(*args, **kwargs):\n    return None\n")
    loop = f"{problem['prompt']}\n\nwhile True:\n    pass\n"
    network = "import socket\nsocket.create_connection(('1.1.1.1', 53), timeout=3)\n"
    disk = "open('/work/escritura.txt', 'w').write('x')\n"
    root_disk = "open('/escritura.txt', 'w').write('x')\n"
    who = "import os\nassert os.getuid() != 0, 'corre como root'\n"

    cases = [
        ("la solucion canonica pasa", canonical, True),
        ("una solucion incorrecta falla", wrong, False),
        ("un bucle infinito se corta por tiempo", loop, False),
        ("sin red: no puede abrir una conexion", network, False),
        ("no puede escribir en el directorio montado", disk, False),
        ("no puede escribir en la raiz del contenedor", root_disk, False),
        ("no corre como root", who, True),
    ]
    healthy = True
    for label, program, expect_pass in cases:
        passed, category = run_sandbox(image, program, limit_seconds=3)
        ok = passed == expect_pass
        healthy &= ok
        print(f"  {'OK   ' if ok else 'MAL  '} {label:<48} -> {'pasa' if passed else 'falla'} ({category})")
    print("AUTOTEST:", "el evaluador se comporta como debe" if healthy else "EL EVALUADOR ESTA MAL, no te fies de sus cifras")
    return healthy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true", help="comprueba el evaluador y su aislamiento")
    parser.add_argument("--model")
    parser.add_argument("--port", type=int)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--limit", type=int, default=0, help="0 = los 164 problemas")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--max-tokens", type=int, default=1024)
    parser.add_argument("--out", default=os.path.expanduser("~/eval"))
    args = parser.parse_args()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(script_dir, "vllm-image.local"), encoding="utf-8") as handle:
        image = handle.read().strip()

    problems = load_problems(args.out)
    if args.selftest:
        sys.exit(0 if selftest(image, problems) else 1)
    if not args.model or not args.port:
        parser.error("--model y --port son obligatorios (salvo con --selftest)")
    args.base = f"http://{args.host}:{args.port}"
    if args.limit:
        problems = problems[: args.limit]
    print(f"modelo={args.model} problemas={len(problems)} trabajadores={args.workers} imagen={image}")

    started = time.perf_counter()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(evaluate_one, args, image, problem) for problem in problems]
        for done, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            results.append(future.result())
            if done % 20 == 0 or done == len(problems):
                passed = sum(r["passed"] for r in results)
                print(f"  {done}/{len(problems)}  acertados {passed}  ({time.perf_counter() - started:.0f} s)")
    results.sort(key=lambda r: int(r["task_id"].split("/")[1]))

    passed = sum(r["passed"] for r in results)
    total_tokens = sum(r["tokens"] for r in results)
    failures = collections.Counter(r["category"] for r in results if not r["passed"])
    out_path = os.path.join(args.out, f"results-{args.model}-{time.strftime('%Y%m%d-%H%M%S')}.jsonl")
    with open(out_path, "w", encoding="utf-8") as handle:
        for result in results:
            handle.write(json.dumps(result) + "\n")

    print(f"\nRESULTADO {args.model}: pass@1 = {passed}/{len(results)} = {100 * passed / len(results):.1f} %")
    print(f"tokens generados por problema (media): {total_tokens / len(results):.0f}   tiempo total: {time.perf_counter() - started:.0f} s")
    print("fallos por categoria:", dict(failures.most_common(8)) or "ninguno")
    print(f"detalle: {out_path}")


if __name__ == "__main__":
    main()
