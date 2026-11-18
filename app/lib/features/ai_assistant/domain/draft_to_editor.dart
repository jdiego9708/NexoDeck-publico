import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../../actions/data/actions_repository.dart';
import '../../actions/domain/deck_action.dart';
import '../../actions/presentation/action_editor_sheet.dart';
import 'action_draft.dart';

/// Traduce el borrador de la IA a lo que entiende el editor de acciones.
///
/// Funciones **puras**: no tocan Drift ni el bridge. Lo que si hace falta
/// persistir (las hojas de una macro) lo resuelve `AiDraftApplier` del lado de
/// la aplicacion, usando estas piezas.

/// Semilla para una accion de un solo paso.
ActionEditorSeed seedForSingleStep(ActionDraft draft) {
  assert(draft.steps.isNotEmpty, 'un borrador sin pasos no llega hasta aca');
  final step = draft.steps.first;

  return ActionEditorSeed(
    name: draft.name,
    description: draft.description ?? step.description,
    icon: draft.icon,
    colorHex: draft.colorHex,
    actionType: step.actionType,
    // El comando **resuelto**: el que ya tiene el `cd` plegado adentro. El
    // esquema de acciones no tiene columna para carpeta de trabajo, asi que si
    // se guardara el original el boton correria desde donde estuviera parada la
    // consola y "no haria nada" sin ningun error.
    commandTemplate: step.resolvedCommand,
    requiresAdmin: step.requiresAdmin,
    terminalType: step.actionType == ActionType.terminal ? step.terminalType : null,
    showTerminalWindow: step.showTerminalWindow,
    parameters: paramDraftsFor(step),
    autoSubscribe: autoSubscribeConfigFor(step),
  );
}

/// Semilla para una de las **hojas** de una cadena.
///
/// El nombre lo toma del paso, no del borrador: en el deck van a convivir con
/// la macro y llamarlas todas igual las volveria indistinguibles.
ActionEditorSeed seedForStep(ActionDraft draft, int index) {
  final step = draft.steps[index];

  return ActionEditorSeed(
    name: step.name,
    description: step.description,
    icon: draft.icon,
    colorHex: draft.colorHex,
    actionType: step.actionType,
    commandTemplate: step.resolvedCommand,
    requiresAdmin: step.requiresAdmin,
    terminalType: step.actionType == ActionType.terminal ? step.terminalType : null,
    showTerminalWindow: step.showTerminalWindow,
    parameters: paramDraftsFor(step),
    autoSubscribe: autoSubscribeConfigFor(step),
  );
}

/// Semilla de la macro que encadena hojas **ya creadas**.
///
/// Una macro no declara parametros propios: se le preguntan los de sus pasos,
/// deduplicados por clave (ver `promptParametersFor` en `macro_plan.dart`).
ActionEditorSeed seedForMacro(ActionDraft draft, List<String> leafActionIds) {
  assert(
    leafActionIds.length == draft.steps.length,
    'hace falta un id por paso: ${leafActionIds.length} vs ${draft.steps.length}',
  );

  return ActionEditorSeed(
    name: draft.name,
    description: draft.description,
    icon: draft.icon,
    colorHex: draft.colorHex,
    actionType: ActionType.macro,
    macroSteps: [
      for (var index = 0; index < leafActionIds.length; index++)
        MacroStepDraft(
          stepActionId: leafActionIds[index],
          // La pausa del ultimo paso no se aplica (no hay nada despues), asi
          // que se manda en cero para que el editor no muestre un campo que no
          // hace nada. Mismo criterio que `ActionsRepository._executeMacro`.
          delayMsAfter: index == leafActionIds.length - 1
              ? 0
              : draft.steps[index].delayMsAfter,
        ),
    ],
  );
}

/// La suscripcion de un paso, en el tipo que consume el editor/repositorio.
/// `null` si el paso no la declara.
AutoSubscribeConfig? autoSubscribeConfigFor(DraftStep step) {
  final config = step.autoSubscribe;
  if (config == null) return null;
  return AutoSubscribeConfig(
    baseUrl: config.baseUrl,
    hubPath: config.hubPath,
    invokeMethod: config.invokeMethod,
    jsonField: config.jsonField,
    allowInvalidCert: config.allowInvalidCert,
  );
}

/// Parametros de un paso, en el tipo que consume el repositorio.
List<ActionParamDraft> paramDraftsFor(DraftStep step) => [
  for (final param in step.parameters)
    if (param.key.trim().isNotEmpty)
      ActionParamDraft(
        key: param.key.trim(),
        label: param.label.trim().isEmpty ? param.key.trim() : param.label.trim(),
        inputType: param.inputType,
        defaultValue: (param.defaultValue?.trim().isEmpty ?? true)
            ? null
            : param.defaultValue!.trim(),
        options: param.options,
      ),
];
