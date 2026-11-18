"""Comprueba el tool calling de un modelo, con la forma de peticion que usa el agente de NexoDeck
(`nexodeck-ai`: campo `tools` + `tool_choice: auto`). Va por la pasarela, no directo a vLLM.

Uso: python3 tools-check.py --model complex --key ndk_...   (o la variable NEXODECK_LLM_KEY)
     python3 tools-check.py --model router --url http://127.0.0.1:8888

Mira tres cosas, de menos a mas exigente:
  1. que el servidor ACEPTE `tools` (sin `--enable-auto-tool-choice` vLLM contesta 400);
  2. que el modelo LLAME a la herramienta cuando la pregunta la necesita;
  3. que los argumentos lleguen como JSON valido con lo que se pidio.
Sale con codigo 1 si falla cualquiera. Ademas informa de si el modelo "razona en voz alta":
NexoDeck no manda `enable_thinking: false` a los servicios remotos.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

TOOLS = [{
    "type": "function",
    "function": {
        "name": "get_disk_usage",
        "description": "Devuelve el espacio usado de un disco de la maquina, en GB.",
        "parameters": {
            "type": "object",
            "properties": {"drive": {"type": "string", "description": "Letra de la unidad, p. ej. D"}},
            "required": ["drive"],
        },
    },
}]


def post(url, key, body):
    request = urllib.request.Request(
        f"{url}/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, {"raw": error.read().decode()[:300]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--url", default="http://127.0.0.1:8888")
    parser.add_argument("--key", default=os.environ.get("NEXODECK_LLM_KEY", ""))
    args = parser.parse_args()
    if not args.key:
        sys.exit("Falta la clave: --key o la variable NEXODECK_LLM_KEY.")

    ok = True
    status, data = post(args.url, args.key, {
        "model": args.model, "max_tokens": 200, "temperature": 0,
        "tools": TOOLS, "tool_choice": "auto",
        "messages": [{"role": "user", "content": "Cuanto espacio usa el disco D? Usa la herramienta."}],
    })
    print(f"== {args.model}: peticion con `tools` -> HTTP {status}")
    if status != 200:
        print(f"   NO ACEPTA tools: {json.dumps(data)[:260]}")
        sys.exit(1)

    message = data["choices"][0]["message"]
    calls = message.get("tool_calls") or []
    print(f"   llamadas a herramientas: {len(calls)}")
    if not calls:
        print(f"   NO LLAMO a la herramienta. Contenido: {(message.get('content') or '')[:160]!r}")
        ok = False
    else:
        call = calls[0]["function"]
        try:
            arguments = json.loads(call["arguments"])
            valid = call["name"] == "get_disk_usage" and str(arguments.get("drive", "")).strip(": \\/").upper() == "D"
        except (ValueError, KeyError):
            arguments, valid = call.get("arguments"), False
        print(f"   {call['name']}({call.get('arguments')})  ->  {'OK' if valid else 'ARGUMENTOS MAL'}")
        ok &= valid

    reasoning = message.get("reasoning_content") or message.get("reasoning") or ""
    content = message.get("content") or ""
    print(f"   razonamiento en voz alta: {'SI (' + str(len(reasoning)) + ' car.)' if reasoning else 'no'}"
          f"{'  <think> en el contenido' if '<think>' in content else ''}")

    # NexoDeck pide SIEMPRE streaming (`stream_chat`, SSE): las llamadas a herramientas llegan
    # troceadas en `delta.tool_calls` y el cliente tiene que recomponerlas. Se comprueba aparte.
    print(f"== {args.model}: la misma peticion con `stream: true`")
    streamed_ok = check_streaming(args)
    ok &= streamed_ok
    print("RESULTADO:", "OK" if ok else "FALLA")
    sys.exit(0 if ok else 1)


def check_streaming(args):
    body = {
        "model": args.model, "max_tokens": 200, "temperature": 0, "stream": True,
        "tools": TOOLS, "tool_choice": "auto",
        "messages": [{"role": "user", "content": "Cuanto espacio usa el disco D? Usa la herramienta."}],
    }
    request = urllib.request.Request(
        f"{args.url}/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {args.key}"})
    name, arguments, chunks, done = "", "", 0, False
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            for raw in response:
                line = raw.decode().strip()
                if not line.startswith("data: "):
                    continue
                payload = line[len("data: "):]
                if payload == "[DONE]":
                    done = True
                    break
                chunks += 1
                for call in (json.loads(payload)["choices"][0].get("delta", {}).get("tool_calls") or []):
                    function = call.get("function") or {}
                    name += function.get("name") or ""
                    arguments += function.get("arguments") or ""
    except urllib.error.HTTPError as error:
        print(f"   HTTP {error.code}: {error.read().decode()[:200]}")
        return False

    try:
        valid = name == "get_disk_usage" and json.loads(arguments).get("drive", "").strip(": \\/").upper() == "D"
    except ValueError:
        valid = False
    print(f"   {chunks} trozos SSE, [DONE]={done}, llamada recompuesta: {name}({arguments})  ->  {'OK' if valid else 'MAL'}")
    return valid and done


if __name__ == "__main__":
    main()
