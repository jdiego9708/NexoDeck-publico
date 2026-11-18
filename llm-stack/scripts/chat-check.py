"""Comprueba que cada servidor vLLM responde de forma COHERENTE, no solo que responda rapido.

El benchmark (bench.py) mide tokens por segundo y no mira que dicen: un modelo corrupto tras
recargar pesos (Sleep Mode nivel 2, doc 11 §7.17) rindio 93 tok/s generando basura. Aqui se hacen
preguntas con respuesta verificable, con temperatura 0, y se compara con lo esperado.

Uso: python3 chat-check.py [--ports 8002 8000] [--models router complex]
Sin argumentos revisa los tres puertos del stack (8000 complex, 8001 fast, 8002 router) y omite
los que no esten levantados. Sale con codigo 1 solo si algun modelo genera BASURA (modelo
corrupto); una respuesta incorrecta se muestra pero no cuenta como fallo tecnico.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.request

ROLES = {"complex": 8000, "fast": 8001, "router": 8002}

# (pregunta, patron que DEBE aparecer en una respuesta sana)
CHECKS = [
    ("Cuanto es 17 + 25? Responde solo con el numero.", r"\b42\b"),
    ("Cual es la capital de Francia? Responde con una palabra.", r"Par[ií]s"),
    ("Cuenta del 1 al 5 separando con comas.", r"1\D+2\D+3\D+4\D+5"),
]


def ask(port, model, question):
    body = json.dumps({
        "model": model, "max_tokens": 64, "temperature": 0,
        # Qwen3.5 razona por defecto; se desactiva para que la respuesta corta llegue en el contenido.
        "chat_template_kwargs": {"enable_thinking": False},
        "messages": [{"role": "user", "content": question}],
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)["choices"][0]["message"]["content"] or ""


def is_degenerate(text):
    """Salida basura tipica: un caracter repetido muchas veces ('1112222222...')."""
    return re.search(r"(.)\1{9,}", text) is not None


def check_role(role, port):
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=3)
    except (urllib.error.URLError, OSError):
        print(f"-- {role} (:{port}): no levantado, se omite")
        return True

    print(f"== {role} (:{port})")
    healthy = True
    for question, pattern in CHECKS:
        answer = ask(port, role, question)
        # Dos fallos distintos: basura (modelo corrupto, p. ej. tras recargar pesos) y respuesta
        # simplemente incorrecta (calidad del modelo). Solo la basura indica un problema tecnico.
        if is_degenerate(answer):
            verdict = "BASURA"
            healthy = False
        elif re.search(pattern, answer) is None:
            verdict = "incorrecta"
        else:
            verdict = "OK"
        print(f"   {verdict:<10} {question[:46]:<46} -> {answer.strip()[:60]!r}")
    return healthy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--roles", nargs="+", default=list(ROLES), choices=list(ROLES))
    args = parser.parse_args()

    results = [check_role(role, ROLES[role]) for role in args.roles]
    print("RESULTADO:", "todos coherentes" if all(results) else "HAY MODELOS QUE RESPONDEN MAL")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
