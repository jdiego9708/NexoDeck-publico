import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import 'action_param.dart';
import 'macro_step.dart';

/// Configuracion de auto-suscripcion (ver el comentario largo en
/// `actions_table.dart`): cuando un comando capturado termina bien, se lee
/// [jsonField] de su salida (interpretada como JSON) y se arranca una
/// suscripcion SignalR con ese valor.
class AutoSubscribeConfig {
  const AutoSubscribeConfig({
    required this.baseUrl,
    required this.hubPath,
    required this.invokeMethod,
    required this.jsonField,
    this.allowInvalidCert = false,
  });

  final String baseUrl;
  final String hubPath;
  final String invokeMethod;

  /// Campo de nivel superior de la respuesta JSON (ej. `job_id`). Sin
  /// soporte de rutas anidadas por ahora -- las respuestas de ExampleApi
  /// que motivaron esto lo traen siempre al tope.
  final String jsonField;
  final bool allowInvalidCert;
}

/// Entidad pura de dominio -- sin dependencias de Flutter ni de Drift mas
/// alla de los enums compartidos (`ActionType`/`TerminalType`), que son
/// vocabulario del dominio, no detalle de persistencia.
class DeckAction {
  const DeckAction({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.colorHex,
    required this.actionType,
    required this.commandTemplate,
    required this.requiresAdmin,
    required this.terminalType,
    required this.isFavorite,
    required this.parameters,
    this.macroSteps = const [],
    this.showTerminalWindow = true,
    this.pasteToActiveWindow = false,
    this.groupId,
    this.autoSubscribe,
  });

  factory DeckAction.fromRow(
    ActionsTableData row, {
    List<ActionParam> parameters = const [],
    List<DeckMacroStep> macroSteps = const [],
  }) => DeckAction(
    id: row.id,
    name: row.name,
    description: row.description,
    icon: row.icon,
    colorHex: row.colorHex,
    actionType: row.actionType,
    commandTemplate: row.commandTemplate,
    requiresAdmin: row.requiresAdmin,
    terminalType: row.terminalType,
    isFavorite: row.isFavorite,
    parameters: parameters,
    macroSteps: macroSteps,
    showTerminalWindow: row.showTerminalWindow,
    pasteToActiveWindow: row.pasteToActiveWindow,
    groupId: row.groupId,
    autoSubscribe:
        row.autoSubscribeBaseUrl != null &&
            row.autoSubscribeHubPath != null &&
            row.autoSubscribeInvokeMethod != null &&
            row.autoSubscribeJsonField != null
        ? AutoSubscribeConfig(
            baseUrl: row.autoSubscribeBaseUrl!,
            hubPath: row.autoSubscribeHubPath!,
            invokeMethod: row.autoSubscribeInvokeMethod!,
            jsonField: row.autoSubscribeJsonField!,
            allowInvalidCert: row.autoSubscribeAllowInvalidCert,
          )
        : null,
  );

  final String id;
  final String name;
  final String? description;
  final String icon;
  final String colorHex;
  final ActionType actionType;
  final String? commandTemplate;
  final bool requiresAdmin;
  final TerminalType? terminalType;
  final bool isFavorite;
  final List<ActionParam> parameters;

  /// Pasos de la macro, ya ordenados por `orderIndex`. Vacio para
  /// cualquier `actionType` que no sea `macro`. Ver `planMacro`
  /// (`macro_plan.dart`), que los resuelve contra las acciones reales.
  final List<DeckMacroStep> macroSteps;

  /// Solo aplica a `actionType = terminal` -- ver el comentario en la
  /// columna de Drift (`actions_table.dart`).
  final bool showTerminalWindow;

  /// Solo aplica a `actionType = clipboard`: ademas de copiar, devolverle el
  /// foco a la ventana anterior y mandarle Ctrl+V -- ver la columna de Drift.
  final bool pasteToActiveWindow;
  final String? groupId;

  /// `null` = no se suscribe sola. Solo tiene efecto en modo capturado
  /// (`showTerminalWindow = false`) -- ver `ActionsRepository._executeCaptured`.
  final AutoSubscribeConfig? autoSubscribe;

  /// Reemplaza cada `{{key}}` en [commandTemplate] por el valor provisto en
  /// [values] (keyed por `ActionParam.key`). Placeholders sin valor
  /// provisto se dejan tal cual -- error de captura, no de ejecucion.
  String renderCommand(Map<String, String> values) {
    var result = commandTemplate ?? '';
    for (final param in parameters) {
      final value = values[param.key] ?? param.defaultValue ?? '';
      result = result.replaceAll('{{${param.key}}}', value);
    }
    return result;
  }
}
