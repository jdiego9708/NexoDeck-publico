import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/ai_assistant/application/ai_live_runner.dart';
import 'package:nexodeck/features/ai_assistant/domain/action_draft.dart';

/// Tests de las funciones puras del ejecutor en vivo: que parametros pide y
/// como sustituye `{{variables}}`. **No se cubre** `runDraftLive` completo
/// (necesita `BuildContext`, `WidgetRef` y el bridge de Rust) — mismo
/// criterio que `ai_draft_test.dart` con `applyDraft`.

DraftParam _param(String key, {String? defaultValue}) => DraftParam(
  key: key,
  label: key,
  inputType: ParamInputType.text,
  defaultValue: defaultValue,
);

DraftStep _step({
  String name = 'Paso',
  String resolvedCommand = 'echo hola',
  List<DraftParam> parameters = const [],
  int delayMsAfter = 0,
  bool requiresAdmin = false,
}) => DraftStep(
  name: name,
  actionType: ActionType.terminal,
  command: resolvedCommand,
  resolvedCommand: resolvedCommand,
  terminalType: TerminalType.powershell,
  requiresAdmin: requiresAdmin,
  showTerminalWindow: false,
  parameters: parameters,
  delayMsAfter: delayMsAfter,
);

ActionDraft _draft({required List<DraftStep> steps, DraftRisk risk = DraftRisk.safe}) =>
    ActionDraft(
      name: 'Borrador de prueba',
      icon: 'terminal',
      colorHex: '#6366F1',
      summary: '',
      steps: steps,
      risk: risk,
    );

void main() {
  group('paramsForLiveDraft', () {
    test('sin parametros en ningun paso, no pide nada', () {
      expect(paramsForLiveDraft(_draft(steps: [_step()])), isEmpty);
    });

    /// El caso real del brief: dos pasos que comparten `{{letra}}` se
    /// preguntan una sola vez, no dos.
    test('deduplica por key entre pasos que comparten una variable', () {
      final draft = _draft(
        steps: [
          _step(name: 'Paso 1', parameters: [_param('letra')]),
          _step(name: 'Paso 2', parameters: [_param('letra'), _param('modo')]),
        ],
      );

      final params = paramsForLiveDraft(draft);

      expect(params.map((p) => p.key), ['letra', 'modo']);
    });

    test('mantiene el orden de primera aparicion', () {
      final draft = _draft(
        steps: [
          _step(name: 'Paso 1', parameters: [_param('b'), _param('a')]),
          _step(name: 'Paso 2', parameters: [_param('a'), _param('c')]),
        ],
      );

      expect(paramsForLiveDraft(draft).map((p) => p.key), ['b', 'a', 'c']);
    });
  });

  group('renderLiveCommand', () {
    test('sustituye la variable con el valor provisto', () {
      final step = _step(resolvedCommand: 'git checkout {{rama}}', parameters: [_param('rama')]);

      expect(renderLiveCommand(step, {'rama': 'main'}), 'git checkout main');
    });

    /// Un valor ausente (el usuario dejo el campo vacio, o el dialogo nunca
    /// pregunto porque no hacia falta) cae al default del parametro, nunca a
    /// una llave vacia -- mismo criterio que `DeckAction.renderCommand`.
    test('sin valor provisto, cae al default del parametro', () {
      final step = _step(
        resolvedCommand: 'echo {{modo}}',
        parameters: [_param('modo', defaultValue: 'rapido')],
      );

      expect(renderLiveCommand(step, const {}), 'echo rapido');
    });

    test('sin parametros, el comando resuelto queda igual', () {
      final step = _step(resolvedCommand: 'flutter analyze');

      expect(renderLiveCommand(step, const {}), 'flutter analyze');
    });
  });

  group('buildSummaryPrompt', () {
    /// El caso real que motivo esto: el mensaje final del chat solo repetia
    /// lo que el modelo escribio ANTES de correr ("el boton ejecutara git
    /// status"), nunca la salida real. El prompt tiene que llevar esa salida
    /// de verdad, no un resumen inventado por Dart.
    test('lleva la salida real de un solo paso', () {
      final draft = _draft(steps: [_step(name: 'Git Status')]);
      final results = [
        const LiveStepResult(
          stepName: 'Git Status',
          ok: true,
          outputTail: 'modified: CLAUDE.md\nno changes added to commit',
        ),
      ];

      final prompt = buildSummaryPrompt(draft, results);

      expect(prompt, contains('modified: CLAUDE.md'));
      expect(prompt, contains('no changes added to commit'));
      expect(prompt, contains('Git Status'));
      expect(prompt, contains('OK'));
    });

    test('un paso fallido lleva el motivo, no la salida', () {
      final draft = _draft(steps: [_step(name: 'Build')]);
      final results = [
        const LiveStepResult(
          stepName: 'Build',
          ok: false,
          errorMessage: 'El comando de "Build" fallo (codigo 1)',
        ),
      ];

      final prompt = buildSummaryPrompt(draft, results);

      expect(prompt, contains('FALLO'));
      expect(prompt, contains('El comando de "Build" fallo (codigo 1)'));
    });

    test('un macro de dos pasos lleva la salida de cada uno por separado', () {
      final draft = _draft(steps: [_step(name: 'Paso A'), _step(name: 'Paso B')]);
      final results = [
        const LiveStepResult(stepName: 'Paso A', ok: true, outputTail: 'salida de A'),
        const LiveStepResult(stepName: 'Paso B', ok: true, outputTail: 'salida de B'),
      ];

      final prompt = buildSummaryPrompt(draft, results);

      expect(prompt, contains('Paso A'));
      expect(prompt, contains('salida de A'));
      expect(prompt, contains('Paso B'));
      expect(prompt, contains('salida de B'));
    });

    test('sin salida real, lo dice en vez de dejar un bloque vacio', () {
      final draft = _draft(steps: [_step(name: 'Copiar')]);
      final results = [const LiveStepResult(stepName: 'Copiar', ok: true)];

      expect(buildSummaryPrompt(draft, results), contains('sin salida'));
    });
  });
}
