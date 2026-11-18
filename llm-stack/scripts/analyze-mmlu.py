"""Compara los resultados de MMLU de dos modelos por CATEGORIA y evalua un enrutado por dominio.

Uso: python3 analyze-mmlu.py [--eval-dir ~/eval] [--bootstrap 2000]

Lee `mmlu-complex-*.jsonl` y `mmlu-router-*.jsonl` (solo las pasadas completas, 570 preguntas). Con
varias pasadas por modelo usa la tasa de acierto por pregunta.

Para cada categoria da la precision de cada modelo y la DIFERENCIA (complejo - router) con un
intervalo de confianza del 95 % por remuestreo de preguntas. Si el intervalo incluye el 0, no se
puede afirmar que uno sea mejor que otro en esa categoria.

Despues evalua politicas de enrutado POR DOMINIO reproduciendo los resultados ya medidos (sin GPU):
"lo que esta en la categoria X va al complejo, lo demas al router", frente a mandarlo todo a un solo
modelo y frente al oraculo (techo no realizable).

Ojo con lo que NO dice: son preguntas de opcion multiple en ingles de un benchmark conocido, y elegir
la mejor politica mirando estos mismos datos la sobreajusta a ellos.
"""
import argparse
import glob
import json
import os
import random
import statistics

CATEGORIES = {
    "STEM": [
        "abstract_algebra", "astronomy", "college_biology", "college_chemistry", "college_computer_science",
        "college_mathematics", "college_physics", "computer_security", "conceptual_physics",
        "electrical_engineering", "elementary_mathematics", "high_school_biology", "high_school_chemistry",
        "high_school_computer_science", "high_school_mathematics", "high_school_physics",
        "high_school_statistics", "machine_learning",
    ],
    "humanidades": [
        "formal_logic", "high_school_european_history", "high_school_us_history", "high_school_world_history",
        "international_law", "jurisprudence", "logical_fallacies", "moral_disputes", "moral_scenarios",
        "philosophy", "prehistory", "professional_law", "world_religions",
    ],
    "ciencias sociales": [
        "econometrics", "high_school_geography", "high_school_government_and_politics",
        "high_school_macroeconomics", "high_school_microeconomics", "high_school_psychology",
        "human_sexuality", "professional_psychology", "public_relations", "security_studies", "sociology",
        "us_foreign_policy",
    ],
    "otras (salud, negocios, general)": [
        "anatomy", "business_ethics", "clinical_knowledge", "college_medicine", "global_facts", "human_aging",
        "management", "marketing", "medical_genetics", "miscellaneous", "nutrition", "professional_accounting",
        "professional_medicine", "virology",
    ],
}
# Las materias mas cercanas al codigo: donde un modelo de codigo deberia lucirse.
CODE_ADJACENT = {"college_computer_science", "high_school_computer_science", "computer_security", "machine_learning"}
CATEGORY_OF = {subject: category for category, subjects in CATEGORIES.items() for subject in subjects}


def load_runs(eval_dir, model, expected):
    runs = []
    for path in sorted(glob.glob(os.path.join(eval_dir, f"mmlu-{model}-*.jsonl"))):
        with open(path, encoding="utf-8") as handle:
            rows = [json.loads(line) for line in handle if line.strip()]
        if len(rows) == expected:
            runs.append({row["id"]: bool(row["correct"]) for row in rows})
    return runs


def rates(runs):
    return {question: statistics.mean(run[question] for run in runs) for question in runs[0]}


def bootstrap(values_by_question, questions, statistic, resamples, seed=11):
    generator = random.Random(seed)
    samples = []
    for _ in range(resamples):
        chosen = [generator.choice(questions) for _ in questions]
        samples.append(statistic(chosen))
    samples.sort()
    return samples[int(0.025 * resamples)], samples[int(0.975 * resamples)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--eval-dir", default=os.path.expanduser("~/eval"))
    parser.add_argument("--bootstrap", type=int, default=2000)
    args = parser.parse_args()

    with open(os.path.join(args.eval_dir, "mmlu-sample.jsonl"), encoding="utf-8") as handle:
        sample = {row["id"]: row for row in map(json.loads, filter(str.strip, handle))}
    expected = len(sample)
    complex_runs = load_runs(args.eval_dir, "complex", expected)
    router_runs = load_runs(args.eval_dir, "router", expected)
    if not complex_runs or not router_runs:
        raise SystemExit(f"Faltan pasadas completas ({expected} preguntas) de 'complex' y 'router': eval-mmlu.py.")
    rate_c, rate_r = rates(complex_runs), rates(router_runs)
    questions = sorted(sample)

    def accuracy(rate, chosen):
        return statistics.mean(rate[q] for q in chosen)

    def difference(chosen):
        return accuracy(rate_c, chosen) - accuracy(rate_r, chosen)

    print(f"pasadas: complex={len(complex_runs)} router={len(router_runs)}   preguntas={expected}")
    per_run = lambda runs: ", ".join(f"{100 * sum(r.values()) / len(r):.1f}" for r in runs)
    print(f"precision por pasada (%): complex [{per_run(complex_runs)}]   router [{per_run(router_runs)}]")

    groups = {"TODO": questions, "materias de codigo (CS, seguridad, ML)": [q for q in questions if sample[q]["subject"] in CODE_ADJACENT]}
    for category in CATEGORIES:
        groups[category] = [q for q in questions if CATEGORY_OF.get(sample[q]["subject"]) == category]

    print(f"\n{'categoria':<42} {'n':>4} {'complejo':>9} {'router':>8} {'dif. (C-R)':>11}  IC95% de la diferencia")
    for label, chosen in groups.items():
        if not chosen:
            continue
        low, high = bootstrap(None, chosen, difference, args.bootstrap)
        verdict = "complejo mejor" if low > 0 else ("ROUTER mejor" if high < 0 else "sin diferencia clara")
        print(f"{label:<42} {len(chosen):>4} {100 * accuracy(rate_c, chosen):>8.1f}% {100 * accuracy(rate_r, chosen):>7.1f}% "
              f"{100 * difference(chosen):>+10.1f}  [{100 * low:+.1f}, {100 * high:+.1f}]  {verdict}")

    # Politicas de enrutado por dominio: el complejo para las categorias elegidas, el router para el resto.
    def policy_accuracy(complex_categories, chosen=questions):
        return statistics.mean(
            rate_c[q] if CATEGORY_OF.get(sample[q]["subject"]) in complex_categories else rate_r[q] for q in chosen)

    print("\nENRUTADO POR DOMINIO (precision esperada, reproduciendo lo medido):")
    always_complex, always_router = accuracy(rate_c, questions), accuracy(rate_r, questions)
    oracle = statistics.mean(max(rate_c[q], rate_r[q]) for q in questions)
    print(f"  todo al complejo:            {100 * always_complex:.1f} %")
    print(f"  todo al router:              {100 * always_router:.1f} %")
    print(f"  oraculo (no realizable):     {100 * oracle:.1f} %")
    for label, complex_categories in (
        ("STEM al complejo, el resto al router", {"STEM"}),
        ("solo lo que NO es STEM al complejo", set(CATEGORIES) - {"STEM"}),
    ):
        value = policy_accuracy(complex_categories)
        share = sum(CATEGORY_OF.get(sample[q]["subject"]) in complex_categories for q in questions) / len(questions)
        print(f"  {label:<36} {100 * value:.1f} %  (complejo recibe el {100 * share:.0f} %)")

    print("\nPor materia, las mayores diferencias (10 preguntas cada una: ORIENTATIVO, no concluyente):")
    by_subject = {}
    for q in questions:
        by_subject.setdefault(sample[q]["subject"], []).append(q)
    ranked = sorted(by_subject, key=lambda s: accuracy(rate_c, by_subject[s]) - accuracy(rate_r, by_subject[s]))
    for subject in ranked[:4] + ranked[-4:]:
        chosen = by_subject[subject]
        print(f"  {subject:<34} complejo {100 * accuracy(rate_c, chosen):>5.1f}%   router {100 * accuracy(rate_r, chosen):>5.1f}%")


if __name__ == "__main__":
    main()
