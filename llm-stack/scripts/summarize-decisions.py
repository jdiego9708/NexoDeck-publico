"""Resume `decisions.jsonl` de la pasarela uniendo cada decision con su resultado verificado.

Uso: python summarize-decisions.py [ruta/decisions.jsonl]
Sin argumento lee %LOCALAPPDATA%\\nexodeck\\LlmGateway\\data\\decisions.jsonl (o NEXODECK_GATEWAY_DIR).

El fichero tiene dos tipos de linea unidos por `id`: `decision` (lo que decidio `auto`) y `outcome`
(el resultado verificado que informo quien comprobo la respuesta, con POST /v1/feedback). Las
lineas antiguas sin `type` se tratan como decisiones.

Sirve para lo que la receta llamaba Router Replay: ver, por decision y modelo, cuantas peticiones
tienen resultado y que fraccion paso la verificacion. Con pocos resultados no se puede concluir nada:
por eso siempre se imprime el `n`.
"""
import collections
import json
import os
import sys


def default_path():
    directory = os.environ.get("NEXODECK_GATEWAY_DIR")
    if not directory:
        directory = os.path.join(os.environ.get("LOCALAPPDATA", ""), "nexodeck", "LlmGateway", "data")
    return os.path.join(directory, "decisions.jsonl")


def load(path):
    decisions, outcomes, skipped = {}, {}, 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except ValueError:
                skipped += 1
                continue
            identifier = row.get("id")
            if row.get("type") == "outcome":
                if identifier:
                    outcomes[identifier] = row
            else:
                # Una decision anterior a los ids no se puede unir con ningun resultado.
                decisions[identifier or f"sin-id-{len(decisions)}"] = row
    return decisions, outcomes, skipped


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else default_path()
    if not os.path.exists(path):
        sys.exit(f"No existe {path}")
    decisions, outcomes, skipped = load(path)

    orphans = [i for i in outcomes if i not in decisions]
    with_outcome = [i for i in decisions if i in outcomes]
    verified = sum(bool(outcomes[i]["verified"]) for i in with_outcome)
    print(f"fichero: {path}")
    print(f"decisiones: {len(decisions)}   con resultado: {len(with_outcome)} "
          f"({100 * len(with_outcome) / max(len(decisions), 1):.0f} %)   "
          f"verificadas: {verified}/{len(with_outcome)}"
          + (f"   resultados sin decision en el fichero: {len(orphans)}" if orphans else "")
          + (f"   lineas ilegibles: {skipped}" if skipped else ""))

    groups = collections.defaultdict(lambda: {"n": 0, "with_outcome": 0, "verified": 0, "fallback": 0})
    for identifier, decision in decisions.items():
        group = groups[(decision.get("decision", "?"), decision.get("model", "?"))]
        group["n"] += 1
        group["fallback"] += bool(decision.get("fallback"))
        if identifier in outcomes:
            group["with_outcome"] += 1
            group["verified"] += bool(outcomes[identifier]["verified"])

    print(f"\n{'decision':<18} {'modelo':<10} {'n':>5} {'con resultado':>14} {'verificadas':>12} {'tasa':>7} {'conmutadas':>11}")
    for (name, model), group in sorted(groups.items()):
        rate = f"{100 * group['verified'] / group['with_outcome']:.0f} %" if group["with_outcome"] else "-"
        print(f"{name:<18} {model:<10} {group['n']:>5} {group['with_outcome']:>14} {group['verified']:>12} {rate:>7} {group['fallback']:>11}")

    by_verifier = collections.Counter(str(outcomes[i].get("verifier")) for i in with_outcome)
    if by_verifier:
        print("\nresultados por verificador:", dict(by_verifier))
    if len(with_outcome) < 30:
        print("\nCuidado: con menos de ~30 resultados, ninguna tasa de esta tabla es concluyente.")


if __name__ == "__main__":
    main()
