import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge;

import '../../../core/di/provider_reader.dart';
import '../../actions/data/actions_repository.dart'
    show CommandCancelledException, CommandFailedException;
import '../../actions/domain/action_param.dart';
import '../../actions/domain/auto_subscribe.dart';
import '../../actions/presentation/widgets/parameter_prompt_dialog.dart';
import '../../hub_subscriptions/application/hub_subscriptions_provider.dart';
import '../../run_center/application/run_center_controller.dart';
import '../../run_center/domain/command_run.dart';
import '../domain/action_draft.dart';
import '../domain/chat_entry.dart';
import '../domain/draft_to_editor.dart' show autoSubscribeConfigFor;
import '../presentation/widgets/confirm_dangerous_run_dialog.dart';

/// Lo que dejo un paso ejecutado en vivo, para poder pedirle al modelo un
/// resumen DE VERDAD despues (ver `buildSummaryPrompt`) — sin esto, lo unico
/// que el chat tiene para "explicar" el comando es lo que el modelo escribio
/// ANTES de correrlo, cuando solo estaba proponiendo el boton y no podia
/// saber que iba a pasar.
class LiveStepResult {
  const LiveStepResult({
    required this.stepName,
    required this.ok,
    this.outputTail = '',
    this.errorMessage,
  });

  final String stepName;
  final bool ok;

  /// Vacio para portapapeles (no produce salida) y para un paso que abrio
  /// una ventana aparte (no se captura).
  final String outputTail;

  /// Solo si `!ok`: por que fallo, en texto legible.
  final String? errorMessage;
}

/// Ejecuta un borrador propuesto por el asistente EN VIVO, sin pasar por
/// Drift. Misma responsabilidad que `runDeckAction`
/// (`features/actions/presentation/run_action.dart`) — pedir parametros,
/// correr, reportar — pero opera directo sobre `draft.steps`: un borrador de
/// la IA nunca se guarda a menos que el usuario elija "Guardar como boton"
/// (`applyDraft`, sin relacion con esta funcion).
///
/// `onEntry` agrega una fila a la conversacion por cada paso que arranca (o
/// termina sin runner), para que el progreso se vea ahi ademas del Panel de
/// Ejecuciones — que lo recibe gratis via `RunCenterController.declareOrigin`,
/// el mismo mecanismo que ya usa `main.dart` para las ejecuciones remotas.
///
/// Devuelve la lista de resultados reales (vacia si no llego a correr nada:
/// el usuario cancelo la confirmacion extra o el dialogo de parametros) para
/// que quien llama pueda pedirle al modelo que los resuma.
Future<List<LiveStepResult>> runDraftLive(
  BuildContext context,
  WidgetRef ref,
  ActionDraft draft, {
  required void Function(LiveRunEntry entry) onEntry,
}) async {
  final needsExtraConfirm =
      draft.risk == DraftRisk.dangerous ||
      draft.steps.any((step) => step.requiresAdmin);
  if (needsExtraConfirm) {
    if (!context.mounted) return const [];
    final confirmed = await showConfirmDangerousRunDialog(context, draft);
    if (!confirmed) return const [];
  }
  if (!context.mounted) return const [];

  final values = await _promptParameters(context, draft);
  if (values == null) return const []; // el usuario cancelo el dialogo de parametros
  if (!context.mounted) return const [];

  final messenger = ScaffoldMessenger.of(context);
  final results = <LiveStepResult>[];

  for (var index = 0; index < draft.steps.length; index++) {
    final step = draft.steps[index];
    final command = renderLiveCommand(step, values);

    try {
      results.add(await _runStep(ref, step: step, command: command, onEntry: onEntry));
    } on CommandCancelledException {
      // El usuario la corto desde el Panel de Ejecuciones: ya sabe lo que
      // hizo, un SnackBar de error arriba seria reprocharle una decision
      // suya (mismo criterio que `run_action.dart`).
      return results;
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Se detuvo en el paso ${index + 1} de ${draft.steps.length} '
              '("${step.name}"): $error',
            ),
          ),
        );
      }
      results.add(LiveStepResult(stepName: step.name, ok: false, errorMessage: '$error'));
      return results;
    }

    // La pausa del ultimo paso se omite: nadie esta esperando nada despues
    // (mismo criterio que `ActionsRepository._executeMacro`).
    if (index < draft.steps.length - 1 && step.delayMsAfter > 0) {
      await Future<void>.delayed(Duration(milliseconds: step.delayMsAfter));
    }
  }

  return results;
}

/// Corre un borrador EN VIVO sin `BuildContext` -- la mitad de
/// [runDraftLive] que usa el camino remoto
/// (`ConnectionEvent.AiRunDraftRequested`, ver `main.dart`).
///
/// El borrador que llega aca ya tiene los `{{parametros}}` resueltos: el
/// telefono los junto con el mismo dialogo que usa este archivo, de su
/// lado, antes de mandarlo. Por eso no hay nada que preguntar ni ninguna
/// confirmacion extra que mostrar -- quien inicio el pedido ya lo hizo,
/// mismo modelo de confianza que `ExecuteAction`.
///
/// `onRunStarted` avisa el `runId` de cada paso capturado apenas arranca,
/// para que quien llama pueda reenviarlo al dispositivo que lo pidio con el
/// mismo mecanismo que ya usa una accion remota comun (`ActionRunUpdate`).
/// No se llama para un paso de portapapeles: no genera ningun run que
/// seguir.
Future<List<LiveStepResult>> runDraftLiveHeadless(
  ProviderReader read,
  ActionDraft draft, {
  required void Function(String stepName, String runId) onRunStarted,
}) async {
  final results = <LiveStepResult>[];

  for (var index = 0; index < draft.steps.length; index++) {
    final step = draft.steps[index];

    try {
      results.add(await _runStepHeadless(read, step: step, onRunStarted: onRunStarted));
    } on CommandCancelledException {
      return results;
    } catch (error) {
      results.add(LiveStepResult(stepName: step.name, ok: false, errorMessage: '$error'));
      return results;
    }

    // La pausa del ultimo paso se omite: nadie esta esperando nada despues
    // (mismo criterio que `runDraftLive`/`ActionsRepository._executeMacro`).
    if (index < draft.steps.length - 1 && step.delayMsAfter > 0) {
      await Future<void>.delayed(Duration(milliseconds: step.delayMsAfter));
    }
  }

  return results;
}

Future<LiveStepResult> _runStepHeadless(
  ProviderReader read, {
  required DraftStep step,
  required void Function(String stepName, String runId) onRunStarted,
}) async {
  switch (step.actionType) {
    case ActionType.clipboard:
      await bridge.executeClipboardAction(
        text: step.resolvedCommand,
        pasteIntoActiveWindow: false,
      );
      return LiveStepResult(stepName: step.name, ok: true);

    case ActionType.terminal:
      return _runCapturedHeadless(read, step: step, onRunStarted: onRunStarted);

    case ActionType.macro:
      // Inalcanzable: ver el mismo caso en `_runStep`.
      throw StateError('un paso del borrador no puede ser una macro');
  }
}

Future<LiveStepResult> _runCapturedHeadless(
  ProviderReader read, {
  required DraftStep step,
  required void Function(String stepName, String runId) onRunStarted,
}) async {
  final runId = await bridge.startCapturedCommand(
    label: step.name,
    command: step.resolvedCommand,
    terminalType: _toBridgeTerminalType(step.terminalType),
    requiresAdmin: step.requiresAdmin,
  );
  // `remote`, no `local`: este run lo pidio el telefono, y el Panel de
  // Ejecuciones de la PC ya sabe distinguir el origen (ver
  // `ActionExecutionRequested` en `HostRuntime`).
  read(runCenterProvider.notifier).declareOrigin(runId, RunOrigin.remote);
  onRunStarted(step.name, runId);

  final outcome = await bridge.awaitCommandRun(runId: runId);
  if (outcome.ok) {
    final config = autoSubscribeConfigFor(step);
    if (config != null) {
      unawaited(
        tryAutoSubscribe(
          hubSubscriptions: read(hubSubscriptionsRepositoryProvider),
          label: step.name,
          config: config,
          outputTail: outcome.outputTail,
        ),
      );
    }
    return LiveStepResult(stepName: step.name, ok: true, outputTail: outcome.outputTail);
  }

  if (outcome.status == bridge.CommandRunStatus.cancelled) {
    throw CommandCancelledException(step.name);
  }
  throw CommandFailedException(
    actionName: step.name,
    exitCode: outcome.exitCode,
    outputTail: outcome.outputTail,
  );
}

Future<LiveStepResult> _runStep(
  WidgetRef ref, {
  required DraftStep step,
  required String command,
  required void Function(LiveRunEntry entry) onEntry,
}) async {
  switch (step.actionType) {
    case ActionType.clipboard:
      await bridge.executeClipboardAction(
        text: command,
        pasteIntoActiveWindow: false,
      );
      onEntry(LiveRunEntry.clipboard(stepName: step.name));
      return LiveStepResult(stepName: step.name, ok: true);

    case ActionType.terminal:
      // A diferencia de un boton guardado, `show_terminal_window` del
      // borrador NO se respeta aca. El modelo lo pone en `true` cada vez
      // que interpreta "quiero ver la salida" -- que es exactamente lo que
      // el usuario pidio con "corre git status"-- porque para un boton
      // GUARDADO esa es la unica forma de conseguirlo. En modo en vivo no:
      // capturado YA muestra la salida (en el chat y en el Panel de
      // Ejecuciones), sin la ventana aparte que rompe la promesa de "todo
      // pasa aca". La excepcion real (un comando de verdad interactivo,
      // tipo `ssh` o `npm init`) queda fuera de alcance de este modo a
      // proposito: capturado se colgaria esperando un input que nadie puede
      // escribir, y ese caso ya tiene su via -- "Guardar como boton", que
      // si respeta la eleccion del modelo.
      return _runCaptured(ref, step: step, command: command, onEntry: onEntry);

    case ActionType.macro:
      // Inalcanzable: un borrador de la IA nunca declara un paso de tipo
      // macro (`draft::validate` del lado Rust ya lo rechazaria antes de
      // que `propose_action` lo acepte).
      throw StateError('un paso del borrador no puede ser una macro');
  }
}

Future<LiveStepResult> _runCaptured(
  WidgetRef ref, {
  required DraftStep step,
  required String command,
  required void Function(LiveRunEntry entry) onEntry,
}) async {
  final runId = await bridge.startCapturedCommand(
    label: step.name,
    command: command,
    terminalType: _toBridgeTerminalType(step.terminalType),
    requiresAdmin: step.requiresAdmin,
  );
  ref.read(runCenterProvider.notifier).declareOrigin(runId, RunOrigin.local);
  onEntry(LiveRunEntry.captured(stepName: step.name, runId: runId));

  final outcome = await bridge.awaitCommandRun(runId: runId);
  if (outcome.ok) {
    final config = autoSubscribeConfigFor(step);
    if (config != null) {
      // Sin `await`: el paso ya termino bien, y esperar a que la
      // suscripcion conecte solo demoraria el resto de la cadena por algo
      // que no es parte de lo que el paso prometio hacer (mismo criterio
      // que `ActionsRepository._executeCaptured`).
      unawaited(
        tryAutoSubscribe(
          hubSubscriptions: ref.read(hubSubscriptionsRepositoryProvider),
          label: step.name,
          config: config,
          outputTail: outcome.outputTail,
        ),
      );
    }
    // Incluye `detached`: el proceso se lanzo y basta.
    return LiveStepResult(stepName: step.name, ok: true, outputTail: outcome.outputTail);
  }

  if (outcome.status == bridge.CommandRunStatus.cancelled) {
    throw CommandCancelledException(step.name);
  }
  throw CommandFailedException(
    actionName: step.name,
    exitCode: outcome.exitCode,
    outputTail: outcome.outputTail,
  );
}

Future<Map<String, String>?> _promptParameters(
  BuildContext context,
  ActionDraft draft,
) async {
  final params = paramsForLiveDraft(draft);
  if (params.isEmpty) return const {};
  if (!context.mounted) return null;

  return showParameterPromptDialog(context, title: draft.name, parameters: params);
}

/// Junta los `{{parametros}}` de TODOS los pasos de una sola vez,
/// deduplicados por `key` (orden de primera aparicion) — mismo criterio que
/// `promptParametersFor` (`features/actions/domain/macro_plan.dart`) usa
/// para macros guardadas: se pregunta la union, no paso por paso. Separada
/// de `_promptParameters` (que necesita `BuildContext`) para poder
/// testearla sola.
List<ActionParam> paramsForLiveDraft(ActionDraft draft) {
  final seen = <String>{};
  final params = <ActionParam>[];
  for (final step in draft.steps) {
    for (final param in step.parameters) {
      if (seen.add(param.key)) {
        params.add(
          ActionParam(
            id: param.key,
            key: param.key,
            label: param.label,
            inputType: param.inputType,
            defaultValue: param.defaultValue,
            options: param.options,
            orderIndex: params.length,
          ),
        );
      }
    }
  }
  return params;
}

/// Mismo reemplazo que `DeckAction.renderCommand`
/// (`features/actions/domain/deck_action.dart`): un valor ausente cae al
/// default del parametro, nunca a una llave vacia.
String renderLiveCommand(DraftStep step, Map<String, String> values) {
  var result = step.resolvedCommand;
  for (final param in step.parameters) {
    final value = values[param.key] ?? param.defaultValue ?? '';
    result = result.replaceAll('{{${param.key}}}', value);
  }
  return result;
}

/// Arma el pedido de resumen que se le manda al modelo despues de una
/// corrida en vivo.
///
/// Bug real: sin esto, lo unico que el chat mostraba como "explicacion" era
/// la frase que el modelo escribio ANTES de correr el comando (cuando
/// todavia no sabia que iba a pasar) — "el boton ejecutara X", nunca "el
/// comando dijo Y". Se le manda la salida real (`outputTail`, ya acotada del
/// lado Rust) y se le pide que la lea, no que la adivine.
///
/// Es un mensaje mas del usuario (`sendMessage`), no un evento nuevo del
/// protocolo: reusa el mismo turno de siempre, con las mismas herramientas y
/// el mismo gate — nada nuevo del lado Rust. Quien llama decide si mostrarlo
/// como burbuja o mandarlo "de una" (`ai_chat_view.dart` hace lo segundo: el
/// usuario nunca escribio esto, mostrarlo como si lo hubiera hecho seria
/// mentirle).
String buildSummaryPrompt(ActionDraft draft, List<LiveStepResult> results) {
  final buffer = StringBuffer()
    ..writeln(
      results.length == 1
          ? 'Termino de correr el boton "${draft.name}". Esta es la salida real:'
          : 'Termino de correr el boton "${draft.name}" (${results.length} pasos). '
                'Esta es la salida real de cada uno:',
    );

  for (final result in results) {
    buffer.writeln();
    buffer.writeln('### ${result.stepName} — ${result.ok ? "OK" : "FALLO"}');
    if (!result.ok && result.errorMessage != null) {
      buffer.writeln(result.errorMessage);
    } else if (result.outputTail.trim().isNotEmpty) {
      buffer
        ..writeln('```')
        ..writeln(result.outputTail.trim())
        ..writeln('```');
    } else {
      buffer.writeln('(sin salida)');
    }
  }

  buffer.writeln();
  buffer.writeln(
    // Bug real: "resumime en un par de oraciones" terminaba en "el comando '
    // se ejecuto correctamente" — verdadero, pero cero informacion. La
    // longitud no es lo que hay que pedir, es CONTENIDO: si la salida trae
    // una lista, cuenta y algunos ejemplos concretos (nombres, rutas,
    // numeros) sacados de ESA salida, no una categoria generica.
    'Contame que dice esta salida, con la informacion concreta que trae — '
    'nombres de archivo, rutas, cantidades, codigos de error, lo que '
    'corresponda. Si hay una lista larga, no hace falta copiarla entera: '
    'decime cuantos items hay y algunos ejemplos reales. "se ejecuto '
    'correctamente" sin mas NO sirve si la salida tiene algo que contar — '
    'para eso ya esta el icono de check. No repitas la descripcion de antes '
    'de correrlo, y no inventes nada que no este en la salida de arriba.',
  );
  return buffer.toString();
}

bridge.TerminalType _toBridgeTerminalType(TerminalType type) => switch (type) {
  TerminalType.defaultShell => bridge.TerminalType.defaultShell,
  TerminalType.powershell => bridge.TerminalType.powerShell,
  TerminalType.bash => bridge.TerminalType.bash,
  TerminalType.cmd => bridge.TerminalType.cmd,
};
