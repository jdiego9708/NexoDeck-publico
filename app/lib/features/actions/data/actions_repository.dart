import 'dart:async';

import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/action_parameters_dao.dart';
import 'package:nexodeck/data/local/daos/actions_dao.dart';
import 'package:nexodeck/data/local/daos/macro_steps_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/hub_subscriptions/data/hub_subscriptions_repository.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge;
import 'package:uuid/uuid.dart';

import '../domain/action_param.dart';
import '../domain/auto_subscribe.dart';
import '../domain/deck_action.dart';
import '../domain/macro_plan.dart';
import '../domain/macro_step.dart';

/// Un parametro tal como lo produce el editor, antes de tener un id de
/// fila asignado (se genera al guardar).
class ActionParamDraft {
  const ActionParamDraft({
    required this.key,
    required this.label,
    required this.inputType,
    this.defaultValue,
    this.options = const [],
  });

  final String key;
  final String label;
  final ParamInputType inputType;
  final String? defaultValue;

  /// Opciones del desplegable, solo para `inputType = select`. Se serializan
  /// a JSON recien al escribir la fila (`ActionParam.encodeOptions`) --
  /// dentro de la app siempre son una lista.
  final List<String> options;
}

/// Un paso de macro tal como lo produce el editor, antes de guardarse.
class MacroStepDraft {
  const MacroStepDraft({required this.stepActionId, this.delayMsAfter = 0});

  final String stepActionId;
  final int delayMsAfter;
}

/// Un comando capturado termino mal. Lleva el codigo de salida y el final de
/// la salida real, que es lo unico que le sirve al usuario para entender que
/// paso -- antes de la ejecucion capturada esto no existia: un comando que
/// fallaba reportaba exito.
class CommandFailedException implements Exception {
  const CommandFailedException({
    required this.actionName,
    required this.exitCode,
    required this.outputTail,
  });

  final String actionName;
  final int? exitCode;
  final String outputTail;

  @override
  String toString() {
    final code = exitCode != null ? ' (codigo $exitCode)' : '';
    final tail = outputTail.trim();
    return 'El comando de "$actionName" fallo$code'
        '${tail.isEmpty ? '' : ':\n$tail'}';
  }
}

/// El usuario cancelo la ejecucion desde la notificacion. Es una excepcion
/// para que corte una macro igual que un fallo, pero la UI **no** la reporta
/// como error: el usuario ya sabe lo que hizo.
class CommandCancelledException implements Exception {
  const CommandCancelledException(this.actionName);

  final String actionName;

  @override
  String toString() => 'Se cancelo "$actionName"';
}

/// Se intento guardar una macro con un paso que apunta a otra macro. No hay
/// macros anidadas: es la regla que el esquema deja explicitamente en manos
/// de esta capa (ver el comentario de `MacroSteps` en Drift).
class NestedMacroException implements Exception {
  const NestedMacroException(this.stepName);

  final String stepName;

  @override
  String toString() =>
      'Una macro no puede contener otra macro (paso: "$stepName")';
}

class ActionsRepository {
  ActionsRepository(
    this._db,
    this._actionsDao,
    this._parametersDao,
    this._macroStepsDao,
    this._hubSubscriptions,
  );

  final NexoDeckDatabase _db;
  final ActionsDao _actionsDao;
  final ActionParametersDao _parametersDao;
  final MacroStepsDao _macroStepsDao;

  /// Para la auto-suscripcion al terminar un comando capturado -- ver
  /// `_executeCaptured` y el comentario de `AutoSubscribeConfig`.
  final HubSubscriptionsRepository _hubSubscriptions;

  /// Une `actionsTable` con `actionParameters` y `macroSteps` en una sola
  /// query reactiva -- se re-emite si cambia una accion, sus parametros o
  /// los pasos de una macro, sin combinar streams a mano.
  ///
  /// **Los dos `leftOuterJoin` producen un producto cartesiano**: una
  /// accion con 2 parametros y 3 pasos vuelve en 6 filas, con cada
  /// parametro y cada paso repetidos. Por eso se deduplica por id en vez de
  /// acumular a ciegas. En la practica el producto casi nunca se da (una
  /// macro no tiene `commandTemplate` propio, asi que no tiene parametros
  /// propios), pero deduplicar es correcto en todos los casos y cuesta un
  /// `Map`.
  Stream<List<DeckAction>> watchAll() {
    final query = _db.select(_db.actionsTable).join([
      leftOuterJoin(
        _db.actionParameters,
        _db.actionParameters.actionId.equalsExp(_db.actionsTable.id),
      ),
      leftOuterJoin(
        _db.macroSteps,
        _db.macroSteps.macroActionId.equalsExp(_db.actionsTable.id),
      ),
    ]);

    return query.watch().map((rows) {
      final grouped = <String, List<TypedResult>>{};
      for (final row in rows) {
        final actionId = row.readTable(_db.actionsTable).id;
        grouped.putIfAbsent(actionId, () => []).add(row);
      }

      final actions = grouped.values.map((rowsForAction) {
        final actionRow = rowsForAction.first.readTable(_db.actionsTable);

        final parametersById = <String, ActionParam>{};
        final stepsById = <String, DeckMacroStep>{};
        for (final row in rowsForAction) {
          final parameter = row.readTableOrNull(_db.actionParameters);
          if (parameter != null) {
            parametersById[parameter.id] = ActionParam.fromRow(parameter);
          }
          final step = row.readTableOrNull(_db.macroSteps);
          if (step != null) {
            stepsById[step.id] = DeckMacroStep.fromRow(step);
          }
        }

        final parameters = parametersById.values.toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        final steps = stepsById.values.toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

        return DeckAction.fromRow(
          actionRow,
          parameters: parameters,
          macroSteps: steps,
        );
      }).toList();

      actions.sort((a, b) => a.name.compareTo(b.name));
      return actions;
    });
  }

  /// Espera a que termine una ejecucion capturada. Pasa por el repositorio
  /// (y no directo al bridge) para que quien sigue un run remoto se pueda
  /// probar sin FFI -- ver `HostRuntime`.
  Future<bridge.CommandRunOutcome> awaitCommandRun(String runId) =>
      bridge.awaitCommandRun(runId: runId);

  Future<String> createAction({
    required String name,
    String? description,
    required String icon,
    required String colorHex,
    required ActionType actionType,
    String? commandTemplate,
    bool requiresAdmin = false,
    TerminalType? terminalType,
    bool showTerminalWindow = true,
    bool pasteToActiveWindow = false,
    String? groupId,
    AutoSubscribeConfig? autoSubscribe,
    List<ActionParamDraft> parameters = const [],
    List<MacroStepDraft> macroSteps = const [],
  }) async {
    await _assertNoNestedMacros(macroSteps);
    const uuid = Uuid();
    final id = uuid.v4();
    await _actionsDao.createAction(
      ActionsTableCompanion.insert(
        id: Value(id),
        name: name,
        description: Value(description),
        icon: Value(icon),
        colorHex: Value(colorHex),
        actionType: actionType,
        commandTemplate: Value(commandTemplate),
        requiresAdmin: Value(requiresAdmin),
        terminalType: Value(terminalType),
        showTerminalWindow: Value(showTerminalWindow),
        pasteToActiveWindow: Value(pasteToActiveWindow),
        groupId: Value(groupId),
        autoSubscribeBaseUrl: Value(autoSubscribe?.baseUrl),
        autoSubscribeHubPath: Value(autoSubscribe?.hubPath),
        autoSubscribeInvokeMethod: Value(autoSubscribe?.invokeMethod),
        autoSubscribeJsonField: Value(autoSubscribe?.jsonField),
        autoSubscribeAllowInvalidCert: Value(
          autoSubscribe?.allowInvalidCert ?? false,
        ),
      ),
    );
    await _saveParameters(id, parameters);
    await _saveMacroSteps(id, macroSteps);
    return id;
  }

  Future<void> updateAction(
    DeckAction existing, {
    required String name,
    String? description,
    required String icon,
    required String colorHex,
    required ActionType actionType,
    String? commandTemplate,
    bool requiresAdmin = false,
    TerminalType? terminalType,
    bool showTerminalWindow = true,
    bool pasteToActiveWindow = false,
    String? groupId,
    AutoSubscribeConfig? autoSubscribe,
    List<ActionParamDraft> parameters = const [],
    List<MacroStepDraft> macroSteps = const [],
  }) async {
    await _assertNoNestedMacros(macroSteps);
    await _actionsDao.updateAction(
      ActionsTableCompanion(
        id: Value(existing.id),
        name: Value(name),
        description: Value(description),
        icon: Value(icon),
        colorHex: Value(colorHex),
        actionType: Value(actionType),
        commandTemplate: Value(commandTemplate),
        requiresAdmin: Value(requiresAdmin),
        terminalType: Value(terminalType),
        showTerminalWindow: Value(showTerminalWindow),
        pasteToActiveWindow: Value(pasteToActiveWindow),
        groupId: Value(groupId),
        isFavorite: Value(existing.isFavorite),
        updatedAt: Value(DateTime.now()),
        autoSubscribeBaseUrl: Value(autoSubscribe?.baseUrl),
        autoSubscribeHubPath: Value(autoSubscribe?.hubPath),
        autoSubscribeInvokeMethod: Value(autoSubscribe?.invokeMethod),
        autoSubscribeJsonField: Value(autoSubscribe?.jsonField),
        autoSubscribeAllowInvalidCert: Value(
          autoSubscribe?.allowInvalidCert ?? false,
        ),
      ),
    );
    await _saveParameters(existing.id, parameters);
    await _saveMacroSteps(existing.id, macroSteps);
  }

  Future<void> deleteAction(String id) => _actionsDao.deleteAction(id);

  /// Reemplaza los pasos de una macro ya existente, sin tocar el resto de
  /// sus campos. Lo usa la importacion de decks, que crea primero todas las
  /// acciones (para tener el mapa de ids) y recien despues resuelve los
  /// pasos.
  Future<void> replaceMacroSteps(
    String macroActionId,
    List<MacroStepDraft> steps,
  ) async {
    await _assertNoNestedMacros(steps);
    await _saveMacroSteps(macroActionId, steps);
  }

  Future<void> _saveParameters(
    String actionId,
    List<ActionParamDraft> parameters,
  ) async {
    const uuid = Uuid();
    final companions = <ActionParametersCompanion>[
      for (var i = 0; i < parameters.length; i++)
        ActionParametersCompanion.insert(
          id: Value(uuid.v4()),
          actionId: actionId,
          key: parameters[i].key,
          label: parameters[i].label,
          inputType: Value(parameters[i].inputType),
          defaultValue: Value(parameters[i].defaultValue),
          optionsJson: Value(ActionParam.encodeOptions(parameters[i].options)),
          orderIndex: Value(i),
        ),
    ];
    await _parametersDao.replaceForAction(actionId, companions);
  }

  Future<void> _saveMacroSteps(
    String macroActionId,
    List<MacroStepDraft> steps,
  ) async {
    const uuid = Uuid();
    final companions = <MacroStepsCompanion>[
      for (var i = 0; i < steps.length; i++)
        MacroStepsCompanion.insert(
          id: Value(uuid.v4()),
          macroActionId: macroActionId,
          stepActionId: steps[i].stepActionId,
          orderIndex: i,
          delayMsAfter: Value(steps[i].delayMsAfter),
        ),
    ];
    await _macroStepsDao.replaceSteps(macroActionId, companions);
  }

  /// Rechaza guardar una macro cuyos pasos apunten a otra macro.
  ///
  /// El esquema deja esta regla explicitamente en manos de esta capa (ver
  /// el comentario de `MacroSteps`). Se comprueba contra la base y no
  /// contra lo que el editor cree saber, porque el editor puede tener una
  /// lista de acciones desactualizada.
  Future<void> _assertNoNestedMacros(List<MacroStepDraft> steps) async {
    if (steps.isEmpty) return;
    final ids = steps.map((s) => s.stepActionId).toSet();
    final rows = await (_db.select(
      _db.actionsTable,
    )..where((a) => a.id.isIn(ids))).get();
    for (final row in rows) {
      if (row.actionType == ActionType.macro) {
        throw NestedMacroException(row.name);
      }
    }
  }

  /// Ejecuta la accion: rellena el `commandTemplate` con [paramValues] y la
  /// dispara del lado Rust (portapapeles o terminal nueva).
  ///
  /// Si es una macro, corre sus pasos en orden, esperando el `delayMsAfter`
  /// de cada uno. [onStep] se llama antes de cada paso (indice base 0) para
  /// que la UI pueda mostrar el progreso: una macro con pausas tarda
  /// segundos, y sin feedback parece que no paso nada.
  ///
  /// **Un paso que falla aborta el resto**, envuelto en
  /// [MacroStepException]. Es lo correcto para el caso de uso real (una
  /// macro es una secuencia, no una bolsa de acciones sueltas: seguir
  /// despues de que fallo "abrir la app" solo produce mas errores), y
  /// ademas deja claro cual paso rompio.
  /// [waitForCompletion] decide si una accion de terminal capturada se espera
  /// hasta que el proceso realmente termine.
  ///
  /// El deck local espera (`true`): es lo que permite que una macro secuencie
  /// de verdad y que un comando fallido corte la macro. El camino **remoto**
  /// pasa `false`: el ack que espera el telefono significa "arranco", igual
  /// que antes de la ejecucion capturada, y bloquearlo 30 segundos por un
  /// `flutter analyze` dejaria al celular con un spinner que parece colgado.
  ///
  /// [onRunStarted] recibe el id de cada ejecucion capturada apenas arranca,
  /// para que quien dispara pueda anotarla (por ejemplo, marcar que vino del
  /// telefono).
  Future<void> execute(
    DeckAction action, {
    Map<String, String> paramValues = const {},
    void Function(int index, int total, DeckAction step)? onStep,
    bool waitForCompletion = true,
    void Function(String runId)? onRunStarted,
  }) async {
    if (action.actionType == ActionType.macro) {
      return _executeMacro(
        action,
        paramValues: paramValues,
        onStep: onStep,
        waitForCompletion: waitForCompletion,
        onRunStarted: onRunStarted,
      );
    }
    await _executeLeaf(
      action,
      paramValues,
      waitForCompletion: waitForCompletion,
      onRunStarted: onRunStarted,
    );
  }

  Future<void> _executeMacro(
    DeckAction macro, {
    required Map<String, String> paramValues,
    void Function(int index, int total, DeckAction step)? onStep,
    bool waitForCompletion = true,
    void Function(String runId)? onRunStarted,
  }) async {
    // Se relee la lista completa (y no se confia en un snapshot del
    // provider) por el mismo motivo documentado en `main.dart`: los
    // providers son autoDispose y pueden no tener valor cuando nadie los
    // observa. Aca ademas hace falta la lista entera para RESOLVER los ids
    // de los pasos, no solo la macro.
    final all = await watchAll().first;
    final plan = planMacro(macro, all);

    for (var i = 0; i < plan.length; i++) {
      final step = plan[i];
      onStep?.call(i, plan.length, step.action);
      try {
        await _executeLeaf(
          step.action,
          paramValues,
          waitForCompletion: waitForCompletion,
          onRunStarted: onRunStarted,
        );
      } catch (e) {
        throw MacroStepException(
          stepIndex: i,
          totalSteps: plan.length,
          stepName: step.action.name,
          cause: e,
        );
      }
      // La pausa del ultimo paso se omite: nadie esta esperando nada
      // despues, y hace que la macro "termine" varios segundos tarde.
      if (i < plan.length - 1 && step.delayAfter > Duration.zero) {
        await Future<void>.delayed(step.delayAfter);
      }
    }
  }

  /// Ejecuta una accion que NO es macro. Separado de [execute] para que el
  /// motor de macros no pueda recursar por accidente.
  Future<void> _executeLeaf(
    DeckAction action,
    Map<String, String> paramValues, {
    bool waitForCompletion = true,
    void Function(String runId)? onRunStarted,
  }) async {
    final command = action.renderCommand(paramValues);
    switch (action.actionType) {
      case ActionType.clipboard:
        await bridge.executeClipboardAction(
          text: command,
          // Con esto prendido el texto no solo se copia: Rust le devuelve el
          // foco a la ventana que lo tenia antes del clic y le manda Ctrl+V.
          // Sin eso, disparar la accion con el mouse deja el texto en el
          // portapapeles pero nunca lo pega -- el propio clic robo el foco.
          pasteIntoActiveWindow: action.pasteToActiveWindow,
        );
      case ActionType.terminal:
        // `showTerminalWindow` decide entre los dos modos. En `true` se abre
        // una consola real y no se captura nada: es la via para comandos
        // interactivos (ssh, npm init), que capturados se colgarian esperando
        // un input que nadie puede escribir. En `false` -- el caso normal --
        // el comando corre adentro de la app y su salida vuelve como eventos.
        if (action.showTerminalWindow) {
          await bridge.executeTerminalAction(
            command: command,
            terminalType: _toBridgeTerminalType(
              action.terminalType ?? TerminalType.defaultShell,
            ),
            requiresAdmin: action.requiresAdmin,
            showWindow: true,
          );
          return;
        }
        await _executeCaptured(
          action,
          command,
          waitForCompletion: waitForCompletion,
          onRunStarted: onRunStarted,
        );
      case ActionType.macro:
        // Inalcanzable: `planMacro` ya filtra los pasos que apuntan a una
        // macro. Explicito para que el `switch` sea exhaustivo sin un
        // `default` que se trague un tipo nuevo en el futuro.
        throw const NestedMacroException('paso anidado');
    }
  }

  /// Corre un comando capturado. El progreso y la salida los publica el
  /// runner de Rust por su propio stream (lo escucha `RunCenterController`);
  /// aca solo importa **esperar el resultado** y convertirlo en excepcion si
  /// hace falta.
  Future<void> _executeCaptured(
    DeckAction action,
    String command, {
    required bool waitForCompletion,
    void Function(String runId)? onRunStarted,
  }) async {
    final runId = await bridge.startCapturedCommand(
      label: action.name,
      command: command,
      terminalType: _toBridgeTerminalType(
        action.terminalType ?? TerminalType.defaultShell,
      ),
      requiresAdmin: action.requiresAdmin,
    );
    onRunStarted?.call(runId);
    if (!waitForCompletion) return;

    final outcome = await bridge.awaitCommandRun(runId: runId);
    if (outcome.ok) {
      final autoSubscribe = action.autoSubscribe;
      if (autoSubscribe != null) {
        // Sin `await`: no hay ninguna razon para que quien disparo la
        // accion espere a que la suscripcion termine de conectar, y un
        // fallo de auto-suscripcion (JSON sin el campo esperado, hub
        // caido) no es un fallo de LA ACCION -- el curl ya termino bien.
        unawaited(
          tryAutoSubscribe(
            hubSubscriptions: _hubSubscriptions,
            label: action.name,
            config: autoSubscribe,
            outputTail: outcome.outputTail,
          ),
        );
      }
      return; // incluye `detached`: la app se lanzo y basta
    }

    if (outcome.status == bridge.CommandRunStatus.cancelled) {
      throw CommandCancelledException(action.name);
    }
    throw CommandFailedException(
      actionName: action.name,
      exitCode: outcome.exitCode,
      outputTail: outcome.outputTail,
    );
  }

  bridge.TerminalType _toBridgeTerminalType(TerminalType type) =>
      switch (type) {
        TerminalType.defaultShell => bridge.TerminalType.defaultShell,
        TerminalType.powershell => bridge.TerminalType.powerShell,
        TerminalType.bash => bridge.TerminalType.bash,
        TerminalType.cmd => bridge.TerminalType.cmd,
      };
}
