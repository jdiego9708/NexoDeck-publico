import 'package:nexodeck/data/local/tables/actions_table.dart';

import 'action_param.dart';
import 'deck_action.dart';

/// Un paso de macro ya resuelto contra la lista real de acciones: la accion
/// concreta a ejecutar y cuanto esperar despues.
class MacroRunStep {
  const MacroRunStep({required this.action, required this.delayAfter});

  final DeckAction action;
  final Duration delayAfter;
}

/// Resuelve los pasos de [macro] contra [all], en orden.
///
/// Funcion pura a proposito: es toda la logica de "que se ejecuta y en que
/// orden" sin tocar Drift ni el bridge, asi que se puede testear sin base
/// ni FFI (ver `test/macro_plan_test.dart`).
///
/// Descarta dos clases de paso, en ambos casos en silencio porque no son
/// errores del usuario sino estados imposibles de sostener:
///
/// - **Pasos cuya accion ya no existe.** En la practica no deberian llegar
///   nunca: `macro_steps.step_action_id` tiene `onDelete: cascade`, asi que
///   borrar la accion borra el paso. Queda como defensa por si alguna vez
///   se carga un plan desde una fuente sin esa garantia (un import de deck,
///   Fase 9).
/// - **Pasos que apuntan a otra macro.** No hay macros anidadas. El
///   repositorio ya lo rechaza al guardar, pero hay un camino que se le
///   escapa: crear la macro M con el paso A, y despues EDITAR A para
///   convertirla en macro. Filtrarlo tambien aca es lo que evita que ese
///   caso termine en una recursion infinita en tiempo de ejecucion.
List<MacroRunStep> planMacro(DeckAction macro, List<DeckAction> all) {
  final byId = {for (final action in all) action.id: action};
  final steps = [...macro.macroSteps]
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  final plan = <MacroRunStep>[];
  for (final step in steps) {
    final action = byId[step.stepActionId];
    if (action == null) continue;
    if (action.actionType == ActionType.macro) continue;
    plan.add(MacroRunStep(action: action, delayAfter: step.delayAfter));
  }
  return plan;
}

/// Los parametros que hay que pedirle al usuario ANTES de ejecutar
/// [action].
///
/// Para una accion simple son sus propios parametros. Para una macro son
/// los de todos sus pasos, deduplicados por `key`: si tres pasos usan
/// `{{rama}}`, se pregunta una sola vez y el valor se aplica a los tres.
/// Preguntar por paso convertiria una macro de 5 pasos en 5 dialogos
/// seguidos, que es exactamente lo que la macro venia a evitar.
///
/// El orden es el de primera aparicion (paso 1 antes que paso 2), que es el
/// orden en que el usuario piensa la macro.
List<ActionParam> promptParametersFor(DeckAction action, List<DeckAction> all) {
  if (action.actionType != ActionType.macro) return action.parameters;

  final seen = <String>{};
  final result = <ActionParam>[];
  for (final step in planMacro(action, all)) {
    for (final param in step.action.parameters) {
      if (seen.add(param.key)) result.add(param);
    }
  }
  return result;
}

/// Falla de un paso concreto de una macro. Envuelve el error original para
/// que el dialogo de error pueda decir *cual* paso fallo -- con el error
/// pelado, "no se pudo abrir la aplicacion" en una macro de 6 pasos no le
/// dice a nadie donde mirar.
class MacroStepException implements Exception {
  const MacroStepException({
    required this.stepIndex,
    required this.totalSteps,
    required this.stepName,
    required this.cause,
  });

  /// Base 0 -- para mostrar se usa `stepIndex + 1`.
  final int stepIndex;
  final int totalSteps;
  final String stepName;
  final Object cause;

  @override
  String toString() =>
      'Paso ${stepIndex + 1} de $totalSteps ("$stepName") fallo: $cause';
}
