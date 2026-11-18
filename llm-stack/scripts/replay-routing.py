"""Simulador de reproduccion de politicas de enrutado, sin gastar GPU (la idea de Dream-RSI a escala
pequena): con los resultados YA medidos de HumanEval para dos modelos, evalua politicas alternativas
de "que problemas van al modelo ligero" leyendo los resultados guardados en vez de volver a generar.

Solo tiene sentido porque cada decision tiene un RESULTADO VERIFICABLE (el problema pasa o no sus
tests en el evaluador aislado). Sin eso, "reproducir" no mide nada.

Uso: python3 replay-routing.py [--eval-dir ~/eval] [--bootstrap 2000]

Lee `results-complex-*.jsonl` y `results-router-*.jsonl` (los de 164 problemas) y HumanEval.jsonl.
Con varias pasadas por modelo usa la tasa de acierto por problema (0, 0.5, 1...), que absorbe parte
del ruido de la temperatura 0 bajo carga (doc 11, 7.23).

Cuidado con lo que NO dice: son 164 problemas de un benchmark conocido, con 2 pasadas por modelo. Un
umbral "que va bien" aqui puede ser ruido; por eso cada politica se compara con el AZAR al mismo
reparto y se da un intervalo de confianza por remuestreo. Si el intervalo incluye el 0, la
politica NO es mejor que repartir al azar.
"""
import argparse
import glob
import json
import os
import random
import statistics


def load_runs(eval_dir, model):
    """Una lista de {task_id: passed} por cada fichero de resultados completo del modelo."""
    runs = []
    for path in sorted(glob.glob(os.path.join(eval_dir, f"results-{model}-*.jsonl"))):
        with open(path, encoding="utf-8") as handle:
            rows = [json.loads(line) for line in handle if line.strip()]
        if len(rows) == 164:  # se ignoran las pruebas parciales (--limit)
            runs.append({row["task_id"]: bool(row["passed"]) for row in rows})
    return runs


def pass_rates(runs):
    return {task: statistics.mean(run[task] for run in runs) for task in runs[0]}


def evaluate(policy_to_router, rate_router, rate_complex, tasks):
    """Acierto esperado de una politica: la tasa del modelo al que manda cada problema."""
    chosen = [rate_router[t] if policy_to_router[t] else rate_complex[t] for t in tasks]
    return statistics.mean(chosen)


def lift_over_random(policy_to_router, rate_router, rate_complex, tasks):
    """Acierto de la politica menos el de un reparto al azar con la misma proporcion al ligero."""
    share = sum(policy_to_router[t] for t in tasks) / len(tasks)
    baseline = share * statistics.mean(rate_router[t] for t in tasks) + \
        (1 - share) * statistics.mean(rate_complex[t] for t in tasks)
    return evaluate(policy_to_router, rate_router, rate_complex, tasks) - baseline


def bootstrap_interval(policy_to_router, rate_router, rate_complex, tasks, resamples, seed=7):
    generator = random.Random(seed)
    lifts = []
    for _ in range(resamples):
        sample = [generator.choice(tasks) for _ in tasks]
        share = sum(policy_to_router[t] for t in sample) / len(sample)
        baseline = share * statistics.mean(rate_router[t] for t in sample) + \
            (1 - share) * statistics.mean(rate_complex[t] for t in sample)
        lifts.append(statistics.mean(
            rate_router[t] if policy_to_router[t] else rate_complex[t] for t in sample) - baseline)
    lifts.sort()
    return lifts[int(0.025 * resamples)], lifts[int(0.975 * resamples)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--eval-dir", default=os.path.expanduser("~/eval"))
    parser.add_argument("--bootstrap", type=int, default=2000)
    args = parser.parse_args()

    complex_runs, router_runs = load_runs(args.eval_dir, "complex"), load_runs(args.eval_dir, "router")
    if not complex_runs or not router_runs:
        raise SystemExit("Faltan resultados completos de 'complex' y 'router' (eval-humaneval.py).")
    rate_complex, rate_router = pass_rates(complex_runs), pass_rates(router_runs)

    with open(os.path.join(args.eval_dir, "HumanEval.jsonl"), encoding="utf-8") as handle:
        problems = {p["task_id"]: p for p in map(json.loads, filter(str.strip, handle))}
    tasks = sorted(rate_complex, key=lambda t: int(t.split("/")[1]))
    length = {t: len(problems[t]["prompt"]) for t in tasks}

    print(f"pasadas: complex={len(complex_runs)} router={len(router_runs)}   problemas={len(tasks)}")
    print(f"acierto medio: complex={statistics.mean(rate_complex.values()):.3f}  "
          f"router={statistics.mean(rate_router.values()):.3f}")

    router_always = [t for t in tasks if rate_router[t] == 1.0]
    both = [t for t in router_always if rate_complex[t] == 1.0]
    print(f"el router acierta SIEMPRE (en todas las pasadas) {len(router_always)} problemas "
          f"({100 * len(router_always) / len(tasks):.0f} %); en {len(both)} de ellos tambien el complejo")

    # Techo teorico: si se supiera de antemano quien acierta. No es una politica realizable.
    oracle = {t: rate_router[t] >= rate_complex[t] for t in tasks}
    print(f"\nTECHO (oraculo, no realizable): {evaluate(oracle, rate_router, rate_complex, tasks):.3f} "
          f"mandando {100 * sum(oracle.values()) / len(tasks):.0f} % al router")

    # Cascada con verificador: primero el router; si su respuesta NO pasa los tests, se escala al
    # complejo. Es realizable siempre que exista algo que compruebe la respuesta (aqui, los tests
    # del problema). Se empareja la pasada k de un modelo con la pasada k del otro.
    print("\nCASCADA con verificador (router primero, escala al complejo si no pasa los tests):")
    for k in range(min(len(complex_runs), len(router_runs))):
        solved, escalated = 0, 0
        for t in tasks:
            if router_runs[k][t]:
                solved += 1
            else:
                escalated += 1
                solved += complex_runs[k][t]
        alone = sum(complex_runs[k][t] for t in tasks)
        print(f"  pasada {k + 1}: cascada {solved}/{len(tasks)} = {100 * solved / len(tasks):.1f} %   "
              f"(complejo solo: {alone}/{len(tasks)} = {100 * alone / len(tasks):.1f} %)   "
              f"escala al complejo el {100 * escalated / len(tasks):.0f} % de los problemas")

    # Politica del modelo `auto` actual aplicada a estos prompts: casi todo va al trabajador porque
    # un enunciado de HumanEval (firma + docstring) supera con creces los 150 caracteres.
    auto_share = sum(length[t] < 150 for t in tasks) / len(tasks)
    print(f"`auto` actual (simple < 150 caracteres): mandaria {100 * auto_share:.0f} % de estos problemas al router")

    # Politicas de umbral de longitud: "los N % de enunciados mas cortos van al router".
    order = sorted(tasks, key=lambda t: length[t])
    print("\nPolitica 'los enunciados mas cortos al router'  (lift = acierto - reparto al azar con la misma proporcion)")
    print(f"  {'% al router':>11} {'acierto':>8} {'azar':>7} {'lift':>7}   IC95% del lift")
    for percent in (10, 20, 30, 40, 50, 60, 70):
        cutoff = order[: int(len(order) * percent / 100)]
        policy = {t: (t in cutoff) for t in tasks}
        result = evaluate(policy, rate_router, rate_complex, tasks)
        lift = lift_over_random(policy, rate_router, rate_complex, tasks)
        low, high = bootstrap_interval(policy, rate_router, rate_complex, tasks, args.bootstrap)
        verdict = "mejor que el azar" if low > 0 else ("PEOR que el azar" if high < 0 else "indistinguible del azar")
        print(f"  {percent:>10}% {result:>8.3f} {result - lift:>7.3f} {lift:>+7.3f}   [{low:+.3f}, {high:+.3f}]  {verdict}")

    # Cuanto pierde mandar TODO al complejo frente al router en los "faciles" (los que el router
    # acierta siempre): es el ahorro potencial si se pudiera identificarlos.
    print(f"\nAhorro potencial: {len(router_always)} problemas ({100 * len(router_always) / len(tasks):.0f} %) "
          "los resuelve el router sin fallar nunca; el reto es reconocerlos ANTES de generar.")


if __name__ == "__main__":
    main()
