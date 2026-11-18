import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as remote_bridge;

/// Borrador propuesto por el asistente, **en tipos del dominio**.
///
/// Igual que `HardwareSnapshot.fromBridge` en el dashboard: el DTO del bridge se
/// convierte apenas llega y de ahi para adentro nadie mas toca
/// `package:nexodeck/src/rust`. Eso es lo que deja que `draft_to_editor.dart` y
/// `draft_validation.dart` sean funciones puras testeables sin FFI.
///
/// Dos bridges distintos convergen en este UNICO tipo de dominio:
/// `bridge` (`api/ai.dart`, el borrador tal como lo arma el motor LOCAL) y
/// `remote_bridge` (`api/connection.dart`, el mismo borrador cruzando el
/// cable hacia o desde un telefono). `fromBridge`/`fromRemote` entran por
/// cualquiera de los dos; `toRemote()` sale solo hacia el cable -- nunca
/// hace falta un `toBridge()` porque el motor local nunca recibe un
/// borrador de vuelta, solo los propone.
enum DraftRisk { safe, caution, dangerous }

DraftRisk _riskFromBridge(bridge.AiRiskLevel level) => switch (level) {
  bridge.AiRiskLevel.safe => DraftRisk.safe,
  bridge.AiRiskLevel.caution => DraftRisk.caution,
  bridge.AiRiskLevel.dangerous => DraftRisk.dangerous,
};

DraftRisk _riskFromRemote(remote_bridge.AiRemoteRisk level) => switch (level) {
  remote_bridge.AiRemoteRisk.safe => DraftRisk.safe,
  remote_bridge.AiRemoteRisk.caution => DraftRisk.caution,
  remote_bridge.AiRemoteRisk.dangerous => DraftRisk.dangerous,
};

remote_bridge.AiRemoteRisk _riskToRemote(DraftRisk risk) => switch (risk) {
  DraftRisk.safe => remote_bridge.AiRemoteRisk.safe,
  DraftRisk.caution => remote_bridge.AiRemoteRisk.caution,
  DraftRisk.dangerous => remote_bridge.AiRemoteRisk.dangerous,
};

ActionType _actionTypeFromBridge(bridge.AiDraftActionType kind) => switch (kind) {
  bridge.AiDraftActionType.clipboard => ActionType.clipboard,
  bridge.AiDraftActionType.terminal => ActionType.terminal,
};

ActionType _actionTypeFromRemote(remote_bridge.RemoteActionKind kind) => switch (kind) {
  remote_bridge.RemoteActionKind.clipboard => ActionType.clipboard,
  remote_bridge.RemoteActionKind.terminal => ActionType.terminal,
  // Un paso de borrador nunca es una macro -- `draft::validate` del lado
  // Rust ya lo rechaza antes de que `propose_action` lo acepte. Inalcanzable
  // en la practica, pero el switch tiene que ser exhaustivo igual.
  remote_bridge.RemoteActionKind.macro => ActionType.terminal,
};

remote_bridge.RemoteActionKind _actionTypeToRemote(ActionType type) => switch (type) {
  ActionType.clipboard => remote_bridge.RemoteActionKind.clipboard,
  ActionType.terminal => remote_bridge.RemoteActionKind.terminal,
  ActionType.macro => remote_bridge.RemoteActionKind.macro, // inalcanzable, ver arriba
};

TerminalType _terminalFromBridge(bridge.AiTerminalType kind) => switch (kind) {
  bridge.AiTerminalType.defaultShell => TerminalType.defaultShell,
  bridge.AiTerminalType.powerShell => TerminalType.powershell,
  bridge.AiTerminalType.bash => TerminalType.bash,
  bridge.AiTerminalType.cmd => TerminalType.cmd,
};

TerminalType _terminalFromRemote(remote_bridge.AiRemoteTerminal kind) => switch (kind) {
  remote_bridge.AiRemoteTerminal.defaultShell => TerminalType.defaultShell,
  remote_bridge.AiRemoteTerminal.powerShell => TerminalType.powershell,
  remote_bridge.AiRemoteTerminal.bash => TerminalType.bash,
  remote_bridge.AiRemoteTerminal.cmd => TerminalType.cmd,
};

remote_bridge.AiRemoteTerminal _terminalToRemote(TerminalType type) => switch (type) {
  TerminalType.defaultShell => remote_bridge.AiRemoteTerminal.defaultShell,
  TerminalType.powershell => remote_bridge.AiRemoteTerminal.powerShell,
  TerminalType.bash => remote_bridge.AiRemoteTerminal.bash,
  TerminalType.cmd => remote_bridge.AiRemoteTerminal.cmd,
};

ParamInputType _paramKindFromBridge(bridge.AiParamInputType kind) => switch (kind) {
  bridge.AiParamInputType.text => ParamInputType.text,
  bridge.AiParamInputType.number => ParamInputType.number,
  bridge.AiParamInputType.select => ParamInputType.select,
};

ParamInputType _paramKindFromRemote(remote_bridge.RemoteParamKind kind) => switch (kind) {
  remote_bridge.RemoteParamKind.text => ParamInputType.text,
  remote_bridge.RemoteParamKind.number => ParamInputType.number,
  remote_bridge.RemoteParamKind.select => ParamInputType.select,
};

remote_bridge.RemoteParamKind _paramKindToRemote(ParamInputType kind) => switch (kind) {
  ParamInputType.text => remote_bridge.RemoteParamKind.text,
  ParamInputType.number => remote_bridge.RemoteParamKind.number,
  ParamInputType.select => remote_bridge.RemoteParamKind.select,
};

class DraftParam {
  const DraftParam({
    required this.key,
    required this.label,
    required this.inputType,
    this.defaultValue,
    this.options = const [],
  });

  factory DraftParam.fromBridge(bridge.AiDraftParam param) => DraftParam(
    key: param.key,
    label: param.label,
    inputType: _paramKindFromBridge(param.kind),
    defaultValue: param.defaultValue,
    options: List.unmodifiable(param.options),
  );

  factory DraftParam.fromRemote(remote_bridge.RemoteActionParam param) => DraftParam(
    key: param.key,
    label: param.label,
    inputType: _paramKindFromRemote(param.kind),
    defaultValue: param.defaultValue,
    options: List.unmodifiable(param.options),
  );

  remote_bridge.RemoteActionParam toRemote() => remote_bridge.RemoteActionParam(
    key: key,
    label: label,
    kind: _paramKindToRemote(inputType),
    defaultValue: defaultValue,
    options: options,
  );

  final String key;
  final String label;
  final ParamInputType inputType;
  final String? defaultValue;
  final List<String> options;
}

/// Espejo de `AutoSubscribeConfig` (`features/actions/domain/deck_action.dart`)
/// del lado del borrador: mismos 5 campos, para que `draft_to_editor.dart`
/// pueda construir uno desde el otro sin perder nada.
class DraftAutoSubscribe {
  const DraftAutoSubscribe({
    required this.baseUrl,
    required this.hubPath,
    required this.invokeMethod,
    required this.jsonField,
    this.allowInvalidCert = false,
  });

  factory DraftAutoSubscribe.fromBridge(bridge.AiDraftAutoSubscribe config) =>
      DraftAutoSubscribe(
        baseUrl: config.baseUrl,
        hubPath: config.hubPath,
        invokeMethod: config.invokeMethod,
        jsonField: config.jsonField,
        allowInvalidCert: config.allowInvalidCert,
      );

  factory DraftAutoSubscribe.fromRemote(remote_bridge.AiRemoteAutoSubscribe config) =>
      DraftAutoSubscribe(
        baseUrl: config.baseUrl,
        hubPath: config.hubPath,
        invokeMethod: config.invokeMethod,
        jsonField: config.jsonField,
        allowInvalidCert: config.allowInvalidCert,
      );

  remote_bridge.AiRemoteAutoSubscribe toRemote() => remote_bridge.AiRemoteAutoSubscribe(
    baseUrl: baseUrl,
    hubPath: hubPath,
    invokeMethod: invokeMethod,
    jsonField: jsonField,
    allowInvalidCert: allowInvalidCert,
  );

  final String baseUrl;
  final String hubPath;
  final String invokeMethod;
  final String jsonField;
  final bool allowInvalidCert;
}

class DraftStep {
  const DraftStep({
    required this.name,
    this.description,
    required this.actionType,
    required this.command,
    required this.resolvedCommand,
    required this.terminalType,
    required this.requiresAdmin,
    required this.showTerminalWindow,
    this.workingDirectory,
    this.parameters = const [],
    this.delayMsAfter = 0,
    this.risk = DraftRisk.safe,
    this.riskNotes = const [],
    this.autoSubscribe,
  });

  factory DraftStep.fromBridge(bridge.AiDraftStep step) => DraftStep(
    name: step.name,
    description: step.description,
    actionType: _actionTypeFromBridge(step.actionType),
    command: step.command,
    resolvedCommand: step.resolvedCommand,
    terminalType: _terminalFromBridge(step.terminal),
    requiresAdmin: step.requiresAdmin,
    showTerminalWindow: step.showTerminalWindow,
    workingDirectory: step.workingDirectory,
    parameters: step.parameters.map(DraftParam.fromBridge).toList(growable: false),
    delayMsAfter: step.delayMsAfter,
    risk: _riskFromBridge(step.risk),
    riskNotes: List.unmodifiable(step.riskNotes),
    autoSubscribe: step.autoSubscribe != null
        ? DraftAutoSubscribe.fromBridge(step.autoSubscribe!)
        : null,
  );

  factory DraftStep.fromRemote(remote_bridge.AiRemoteDraftStep step) => DraftStep(
    name: step.name,
    description: step.description,
    actionType: _actionTypeFromRemote(step.actionType),
    command: step.command,
    resolvedCommand: step.resolvedCommand,
    terminalType: _terminalFromRemote(step.terminal),
    requiresAdmin: step.requiresAdmin,
    showTerminalWindow: step.showTerminalWindow,
    workingDirectory: step.workingDirectory,
    parameters: step.parameters.map(DraftParam.fromRemote).toList(growable: false),
    delayMsAfter: step.delayMsAfter,
    risk: _riskFromRemote(step.risk),
    riskNotes: List.unmodifiable(step.riskNotes),
    autoSubscribe: step.autoSubscribe != null
        ? DraftAutoSubscribe.fromRemote(step.autoSubscribe!)
        : null,
  );

  remote_bridge.AiRemoteDraftStep toRemote() => remote_bridge.AiRemoteDraftStep(
    name: name,
    description: description,
    actionType: _actionTypeToRemote(actionType),
    command: command,
    resolvedCommand: resolvedCommand,
    terminal: _terminalToRemote(terminalType),
    requiresAdmin: requiresAdmin,
    showTerminalWindow: showTerminalWindow,
    workingDirectory: workingDirectory,
    parameters: parameters.map((p) => p.toRemote()).toList(growable: false),
    delayMsAfter: delayMsAfter,
    risk: _riskToRemote(risk),
    riskNotes: riskNotes,
    autoSubscribe: autoSubscribe?.toRemote(),
  );

  final String name;
  final String? description;
  final ActionType actionType;

  /// Como lo escribio el modelo. Es lo que se muestra en la vista previa
  /// porque es lo mas legible.
  final String command;

  /// Lo que realmente se guarda y ejecuta: el comando con el
  /// `working_directory` ya plegado adentro con la sintaxis del shell que
  /// corresponda. Lo calcula Rust (`draft::fold_working_directory`) para que
  /// no haya dos implementaciones del mismo plegado.
  final String resolvedCommand;

  final TerminalType terminalType;
  final bool requiresAdmin;
  final bool showTerminalWindow;
  final String? workingDirectory;
  final List<DraftParam> parameters;
  final int delayMsAfter;
  final DraftRisk risk;
  final List<String> riskNotes;
  final DraftAutoSubscribe? autoSubscribe;
}

class ActionDraft {
  const ActionDraft({
    required this.name,
    this.description,
    required this.icon,
    required this.colorHex,
    required this.summary,
    required this.steps,
    required this.risk,
  });

  factory ActionDraft.fromBridge(bridge.AiActionDraft draft) => ActionDraft(
    name: draft.name,
    description: draft.description,
    icon: draft.icon,
    colorHex: draft.colorHex,
    summary: draft.summary,
    steps: draft.steps.map(DraftStep.fromBridge).toList(growable: false),
    risk: _riskFromBridge(draft.risk),
  );

  factory ActionDraft.fromRemote(remote_bridge.AiRemoteDraft draft) => ActionDraft(
    name: draft.name,
    description: draft.description,
    icon: draft.icon,
    colorHex: draft.colorHex,
    summary: draft.summary,
    steps: draft.steps.map(DraftStep.fromRemote).toList(growable: false),
    risk: _riskFromRemote(draft.risk),
  );

  /// Para mandarlo por el cable (`AiApplyDraft`/`AiRunDraft` desde el
  /// telefono, o el eco de `DraftReady` desde la PC) -- ver el comentario de
  /// arriba sobre por que no hace falta un `toBridge()`.
  remote_bridge.AiRemoteDraft toRemote() => remote_bridge.AiRemoteDraft(
    name: name,
    description: description,
    icon: icon,
    colorHex: colorHex,
    summary: summary,
    steps: steps.map((s) => s.toRemote()).toList(growable: false),
    isMacro: isMacro,
    risk: _riskToRemote(risk),
  );

  final String name;
  final String? description;
  final String icon;
  final String colorHex;

  /// Por que el comando quedo asi, escrito por el modelo. Es lo que el usuario
  /// lee para aprobar con criterio en vez de a ciegas.
  final String summary;

  final List<DraftStep> steps;
  final DraftRisk risk;

  /// Mas de un paso significa hojas + macro.
  bool get isMacro => steps.length > 1;
}

/// Traduce un evento del stream LOCAL del asistente al que cruza el cable
/// hacia el telefono -- ver `ai_chat_view.dart`.
///
/// Cubre solo los 6 casos que se reenvian 1:1 (`AssistantMessage`,
/// `ToolStarted`, `ToolFinished`, `DraftReady`, `TurnDone`, `Failed`).
/// `AssistantToken` y `Thinking` **nunca entran aca**: se resumen en un solo
/// `AiRemoteChatEvent.typing()` debounced, calculado del lado de quien llama
/// -- mandar cada token por WiFi es exactamente lo que este protocolo evita
/// a proposito (ver el comentario de `MessageV1::AiChatEvent`).
remote_bridge.AiRemoteChatEvent aiChatEventToRemote(bridge.AiChatEvent event) => switch (event) {
  bridge.AiChatEvent_AssistantMessage(:final text) => remote_bridge.AiRemoteChatEvent.assistantMessage(
    text: text,
  ),
  bridge.AiChatEvent_ToolStarted(:final name, :final summary) =>
    remote_bridge.AiRemoteChatEvent.toolStarted(name: name, summary: summary),
  bridge.AiChatEvent_ToolFinished(:final name, :final ok, :final summary) =>
    remote_bridge.AiRemoteChatEvent.toolFinished(name: name, ok: ok, summary: summary),
  bridge.AiChatEvent_DraftReady(:final draft) => remote_bridge.AiRemoteChatEvent.draftReady(
    draft: ActionDraft.fromBridge(draft).toRemote(),
  ),
  bridge.AiChatEvent_TurnDone() => const remote_bridge.AiRemoteChatEvent.turnDone(),
  bridge.AiChatEvent_Failed(:final detail) => remote_bridge.AiRemoteChatEvent.failed(detail: detail),
  bridge.AiChatEvent_AssistantToken() || bridge.AiChatEvent_Thinking() => throw ArgumentError(
    'AssistantToken/Thinking no se traducen 1:1 -- son el debounce de Typing, ver ai_chat_view.dart',
  ),
};
