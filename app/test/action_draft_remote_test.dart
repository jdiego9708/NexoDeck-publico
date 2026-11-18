import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/ai_assistant/domain/action_draft.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as remote_bridge;

/// Tests de las conversiones entre el borrador de dominio (`ActionDraft`) y
/// su forma sobre el cable (`AiRemoteDraft`, `api/connection.dart`) -- el
/// camino que usa el chat remoto (`remote_ai_chat_screen.dart`) para mostrar
/// un borrador que llego por WiFi y para mandarlo de vuelta
/// (`AiApplyDraft`/`AiRunDraft`).

DraftStep _step({
  String name = 'Analizar',
  String command = 'flutter analyze',
  List<DraftParam> parameters = const [],
  DraftAutoSubscribe? autoSubscribe,
  DraftRisk risk = DraftRisk.safe,
  List<String> riskNotes = const [],
}) => DraftStep(
  name: name,
  actionType: ActionType.terminal,
  command: command,
  resolvedCommand: command,
  terminalType: TerminalType.powershell,
  requiresAdmin: false,
  showTerminalWindow: false,
  parameters: parameters,
  risk: risk,
  riskNotes: riskNotes,
  autoSubscribe: autoSubscribe,
);

ActionDraft _draft({
  String name = 'Borrador de prueba',
  List<DraftStep>? steps,
  DraftRisk risk = DraftRisk.safe,
}) => ActionDraft(
  name: name,
  icon: 'terminal',
  colorHex: '#6366F1',
  summary: 'porque si',
  steps: steps ?? [_step()],
  risk: risk,
);

void main() {
  group('DraftParam <-> RemoteActionParam', () {
    test('sobrevive el viaje de ida y vuelta', () {
      const param = DraftParam(
        key: 'rama',
        label: 'Rama',
        inputType: ParamInputType.select,
        defaultValue: 'main',
        options: ['main', 'dev'],
      );

      final roundTripped = DraftParam.fromRemote(param.toRemote());

      expect(roundTripped.key, 'rama');
      expect(roundTripped.label, 'Rama');
      expect(roundTripped.inputType, ParamInputType.select);
      expect(roundTripped.defaultValue, 'main');
      expect(roundTripped.options, ['main', 'dev']);
    });
  });

  group('DraftStep <-> AiRemoteDraftStep', () {
    test('sobrevive el viaje de ida y vuelta, con auto_subscribe', () {
      final step = _step(
        parameters: const [
          DraftParam(key: 'rama', label: 'Rama', inputType: ParamInputType.text),
        ],
        autoSubscribe: const DraftAutoSubscribe(
          baseUrl: 'https://api.example.com',
          hubPath: '/trainingHub',
          invokeMethod: 'SubscribeToJob',
          jsonField: 'run_id',
        ),
        risk: DraftRisk.caution,
        riskNotes: const ['toca la red'],
      );

      final roundTripped = DraftStep.fromRemote(step.toRemote());

      expect(roundTripped.name, step.name);
      expect(roundTripped.resolvedCommand, step.resolvedCommand);
      expect(roundTripped.terminalType, TerminalType.powershell);
      expect(roundTripped.parameters, hasLength(1));
      expect(roundTripped.parameters.single.key, 'rama');
      expect(roundTripped.risk, DraftRisk.caution);
      expect(roundTripped.riskNotes, ['toca la red']);
      expect(roundTripped.autoSubscribe?.hubPath, '/trainingHub');
      expect(roundTripped.autoSubscribe?.jsonField, 'run_id');
    });

    test('sin auto_subscribe, sigue siendo null del otro lado', () {
      final roundTripped = DraftStep.fromRemote(_step().toRemote());
      expect(roundTripped.autoSubscribe, isNull);
    });
  });

  group('ActionDraft <-> AiRemoteDraft', () {
    test('sobrevive el viaje de ida y vuelta con varios pasos', () {
      final draft = _draft(
        steps: [_step(name: 'Uno'), _step(name: 'Dos')],
        risk: DraftRisk.dangerous,
      );

      final roundTripped = ActionDraft.fromRemote(draft.toRemote());

      expect(roundTripped.name, draft.name);
      expect(roundTripped.icon, draft.icon);
      expect(roundTripped.colorHex, draft.colorHex);
      expect(roundTripped.risk, DraftRisk.dangerous);
      expect(roundTripped.steps.map((s) => s.name), ['Uno', 'Dos']);
      expect(roundTripped.isMacro, isTrue);
    });
  });

  group('aiChatEventToRemote', () {
    test('AssistantMessage se traduce 1:1', () {
      final remote = aiChatEventToRemote(
        const bridge.AiChatEvent.assistantMessage(text: 'listo'),
      );
      expect(remote, isA<remote_bridge.AiRemoteChatEvent_AssistantMessage>());
      expect(
        (remote as remote_bridge.AiRemoteChatEvent_AssistantMessage).text,
        'listo',
      );
    });

    test('ToolStarted y ToolFinished se traducen 1:1', () {
      final started = aiChatEventToRemote(
        const bridge.AiChatEvent.toolStarted(name: 'find_project', summary: 'Buscando'),
      );
      expect(started, isA<remote_bridge.AiRemoteChatEvent_ToolStarted>());

      final finished = aiChatEventToRemote(
        const bridge.AiChatEvent.toolFinished(name: 'find_project', ok: true, summary: '11 resultados'),
      );
      expect(finished, isA<remote_bridge.AiRemoteChatEvent_ToolFinished>());
    });

    test('DraftReady convierte el borrador entero', () {
      final draft = bridge.AiActionDraft(
        name: 'Git status',
        icon: 'terminal',
        colorHex: '#6366F1',
        summary: 'porque si',
        steps: const [],
        isMacro: false,
        risk: bridge.AiRiskLevel.safe,
      );

      final remote = aiChatEventToRemote(bridge.AiChatEvent.draftReady(draft: draft));

      expect(remote, isA<remote_bridge.AiRemoteChatEvent_DraftReady>());
      expect(
        (remote as remote_bridge.AiRemoteChatEvent_DraftReady).draft.name,
        'Git status',
      );
    });

    test('TurnDone y Failed se traducen 1:1', () {
      expect(
        aiChatEventToRemote(const bridge.AiChatEvent.turnDone()),
        isA<remote_bridge.AiRemoteChatEvent_TurnDone>(),
      );
      final failed = aiChatEventToRemote(
        const bridge.AiChatEvent.failed(detail: 'error hablando con el modelo'),
      );
      expect(failed, isA<remote_bridge.AiRemoteChatEvent_Failed>());
      expect((failed as remote_bridge.AiRemoteChatEvent_Failed).detail, 'error hablando con el modelo');
    });

    /// Contrato explicito de la funcion: estos dos casos NUNCA cruzan el
    /// cable 1:1 -- se resumen en un `Typing` debounced calculado por quien
    /// llama (`ai_chat_view.dart`). Llamarla con estos casos es un error de
    /// uso, no algo que la funcion tenga que resolver en silencio.
    test('AssistantToken y Thinking no se traducen -- lanzan', () {
      expect(
        () => aiChatEventToRemote(const bridge.AiChatEvent.assistantToken(delta: 'x')),
        throwsArgumentError,
      );
      expect(
        () => aiChatEventToRemote(const bridge.AiChatEvent.thinking()),
        throwsArgumentError,
      );
    });
  });
}
