"""Compara dos resultados de eval-humaneval.py: cuantos problemas resuelve cada modelo, cuales solo
uno de los dos, y de que tipo son los fallos (con un vistazo a los de sintaxis, que pueden ser un
fallo de la extraccion del codigo y no del modelo).

Uso: python3 analyze-eval.py results-complex-....jsonl results-router-....jsonl [--syntax N]
"""
import argparse
import json


def load(path):
    with open(path, encoding="utf-8") as handle:
        return {row["task_id"]: row for row in map(json.loads, filter(str.strip, handle))}


def looks_truncated(reply):
    """Un bloque ```python sin cerrar suele ser una respuesta cortada por max_tokens."""
    return reply.count("```") % 2 == 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("strong")
    parser.add_argument("light")
    parser.add_argument("--syntax", type=int, default=3, help="cuantos SyntaxError mostrar")
    args = parser.parse_args()

    strong, light = load(args.strong), load(args.light)
    ids = sorted(strong, key=lambda task: int(task.split("/")[1]))
    both = [t for t in ids if strong[t]["passed"] and light[t]["passed"]]
    only_strong = [t for t in ids if strong[t]["passed"] and not light[t]["passed"]]
    only_light = [t for t in ids if light[t]["passed"] and not strong[t]["passed"]]
    neither = [t for t in ids if not strong[t]["passed"] and not light[t]["passed"]]

    print(f"resuelven los dos: {len(both)}   solo el fuerte: {len(only_strong)}   "
          f"solo el ligero: {len(only_light)}   ninguno: {len(neither)}   (de {len(ids)})")
    print(f"solo el fuerte: {', '.join(t.split('/')[1] for t in only_strong)}")
    print(f"solo el ligero: {', '.join(t.split('/')[1] for t in only_light) or '-'}")
    print(f"ninguno:        {', '.join(t.split('/')[1] for t in neither)}")

    for label, rows in (("fuerte", strong), ("ligero", light)):
        syntax = [t for t in ids if rows[t]["category"] == "SyntaxError"]
        truncated = [t for t in syntax if looks_truncated(rows[t].get("reply", ""))]
        print(f"\n[{label}] SyntaxError: {len(syntax)}  de ellos con bloque sin cerrar (cortados): {len(truncated)}")
        for task in syntax[: args.syntax]:
            reply = rows[task].get("reply", "(sin respuesta guardada)")
            print(f"  -- {task}  ({rows[task]['tokens']} tokens)  ...{reply[-260:]!r}")


if __name__ == "__main__":
    main()
