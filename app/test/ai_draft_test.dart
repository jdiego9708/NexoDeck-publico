import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/ai_assistant/domain/action_draft.dart';
import 'package:nexodeck/features/ai_assistant/domain/draft_to_editor.dart';
import 'package:nexodeck/features/ai_assistant/domain/draft_validation.dart';

const _autoSubscribe = DraftAutoSubscribe(
  baseUrl: 'https://api.example.com',
  hubPath: '/jobsHub',
  invokeMethod: 'SubscribeToJob',
  jsonField: 'job_id',
);

/// Tests de las funciones puras que traducen el borrador de la IA a lo que
/// entiende el editor de acciones.
///
/// **No se cubre** `applyDraft` (`ai_draft_applier.dart`): necesita un
/// `BuildContext` y escribe en Drift. Lo que si esta cubierto es la parte que
/// decide *que* se escribe, que es donde puede haber un error silencioso — una
/// acción guardada con el comando sin el `cd`, o una macro cuyos pasos no
/// coinciden con las hojas.

DraftStep _step({
  String name = 'Analizar',
  String command = 'flutter analyze',
  String? resolvedCommand,
  String? workingDirectory,
  ActionType actionType = ActionType.terminal,
  TerminalType terminalType = TerminalType.powershell,
  List<DraftParam> parameters = const [],
  int delayMsAfter = 0,
  DraftRisk risk = DraftRisk.safe,
  List<String> riskNotes = const [],
  DraftAutoSubscribe? autoSubscribe,
}) => DraftStep(
  name: name,
  actionType: actionType,
  command: command,
  resolvedCommand: resolvedCommand ?? command,
  terminalType: terminalType,
  requiresAdmin: false,
  showTerminalWindow: true,
  workingDirectory: workingDirectory,
  parameters: parameters,
  delayMsAfter: delayMsAfter,
  risk: risk,
  riskNotes: riskNotes,
  autoSubscribe: autoSubscribe,
);

ActionDraft _draft({
  String name = 'Analizar ExampleApp',
  String icon = 'code',
  String colorHex = '#6366F1',
  required List<DraftStep> steps,
  DraftRisk risk = DraftRisk.safe,
}) => ActionDraft(
  name: name,
  icon: icon,
  colorHex: colorHex,
  summary: 'porque si',
  steps: steps,
  risk: risk,
);

void main() {
  group('seedForSingleStep', () {
    test('usa el comando RESUELTO, no el que escribio el modelo', () {
      final draft = _draft(
        steps: [
          _step(
            command: 'flutter analyze',
            resolvedCommand: 'cd /d "E:\\Proyectos\\App"\r\nflutter analyze',
            workingDirectory: r'E:\Proyectos\App',
          ),
        ],
      );

      final seed = seedForSingleStep(draft);

      // Si se guardara el original, el boton correria desde donde estuviera
      // parada la consola y "no haria nada" sin ningun error.
      expect(seed.commandTemplate, contains('cd /d'));
      expect(seed.commandTemplate, contains('flutter analyze'));
    });

    test('no manda terminalType cuando la accion es de portapapeles', () {
      final seed = seedForSingleStep(
        _draft(
          steps: [_step(actionType: ActionType.clipboard, command: 'texto')],
        ),
      );

      expect(seed.actionType, ActionType.clipboard);
      expect(seed.terminalType, isNull);
    });

    test('traslada los parametros con la etiqueta cayendo a la clave', () {
      final seed = seedForSingleStep(
        _draft(
          steps: [
            _step(
              command: 'git checkout {{rama}}',
              parameters: const [
                DraftParam(key: 'rama', label: '', inputType: ParamInputType.text),
              ],
            ),
          ],
        ),
      );

      expect(seed.parameters, hasLength(1));
      expect(seed.parameters.first.key, 'rama');
      expect(seed.parameters.first.label, 'rama');
    });

    test('descarta parametros sin clave', () {
      final seed = seedForSingleStep(
        _draft(
          steps: [
            _step(
              parameters: const [
                DraftParam(key: '  ', label: 'vacio', inputType: ParamInputType.text),
              ],
            ),
          ],
        ),
      );

      expect(seed.parameters, isEmpty);
    });
  });

  group('autoSubscribeConfigFor', () {
    test('un paso sin suscripcion no arma nada', () {
      expect(autoSubscribeConfigFor(_step()), isNull);
    });

    test('traslada los 5 campos del paso al tipo del editor', () {
      final config = autoSubscribeConfigFor(_step(autoSubscribe: _autoSubscribe));

      expect(config, isNotNull);
      expect(config!.baseUrl, _autoSubscribe.baseUrl);
      expect(config.hubPath, _autoSubscribe.hubPath);
      expect(config.invokeMethod, _autoSubscribe.invokeMethod);
      expect(config.jsonField, _autoSubscribe.jsonField);
      expect(config.allowInvalidCert, isFalse);
    });

    /// El editor abre con el toggle ya prendido y los 4 campos llenos: el
    /// usuario revisa y confirma como con cualquier otro dato del borrador,
    /// nada nuevo se guarda sin pasar por ahi.
    test('seedForSingleStep lo pasa a la semilla del editor', () {
      final seed = seedForSingleStep(
        _draft(steps: [_step(autoSubscribe: _autoSubscribe)]),
      );

      expect(seed.autoSubscribe?.hubPath, '/jobsHub');
    });
  });

  group('cadenas', () {
    test('cada hoja toma su propio nombre, no el del borrador', () {
      final draft = _draft(
        name: 'Ciclo de desarrollo',
        steps: [_step(name: 'Analizar'), _step(name: 'Correr en el telefono')],
      );

      expect(seedForStep(draft, 0).name, 'Analizar');
      expect(seedForStep(draft, 1).name, 'Correr en el telefono');
      // Si todas se llamaran igual que la macro, en el deck serian
      // indistinguibles.
      expect(seedForStep(draft, 0).name, isNot(draft.name));
    });

    test('las hojas heredan el icono y el color del borrador', () {
      final draft = _draft(
        icon: 'terminal',
        colorHex: '#22C55E',
        steps: [_step(), _step()],
      );

      expect(seedForStep(draft, 0).icon, 'terminal');
      expect(seedForStep(draft, 1).colorHex, '#22C55E');
    });

    test('la macro encadena los ids en orden', () {
      final draft = _draft(
        steps: [_step(name: 'Uno'), _step(name: 'Dos'), _step(name: 'Tres')],
      );

      final seed = seedForMacro(draft, ['id-1', 'id-2', 'id-3']);

      expect(seed.actionType, ActionType.macro);
      expect(
        seed.macroSteps.map((s) => s.stepActionId),
        ['id-1', 'id-2', 'id-3'],
      );
      // Una macro no declara parametros propios: se le preguntan los de sus
      // pasos, deduplicados por clave.
      expect(seed.parameters, isEmpty);
    });

    test('la pausa del ultimo paso se descarta', () {
      final draft = _draft(
        steps: [
          _step(delayMsAfter: 500),
          _step(delayMsAfter: 800),
          _step(delayMsAfter: 999),
        ],
      );

      final seed = seedForMacro(draft, ['a', 'b', 'c']);

      // No hay nada despues del ultimo paso: la pausa solo haria que la macro
      // "termine" segundos tarde. Mismo criterio que el motor de macros.
      expect(seed.macroSteps.map((s) => s.delayMsAfter), [500, 800, 0]);
    });

    test('un solo paso no es macro', () {
      expect(_draft(steps: [_step()]).isMacro, isFalse);
      expect(_draft(steps: [_step(), _step()]).isMacro, isTrue);
    });
  });

  group('validateDraft', () {
    test('un borrador correcto no tiene problemas', () {
      expect(validateDraft(_draft(steps: [_step()])), isEmpty);
    });

    test('rechaza un icono que no existe en el set del editor', () {
      final issues = validateDraft(_draft(icon: 'cohete', steps: [_step()]));

      expect(issues.map((i) => i.field), contains('icon'));
    });

    test('rechaza un color fuera de la paleta, sin importar mayusculas', () {
      expect(
        validateDraft(_draft(colorHex: '#123456', steps: [_step()])),
        isNotEmpty,
      );
      expect(
        validateDraft(_draft(colorHex: '#6366f1', steps: [_step()])),
        isEmpty,
      );
    });

    test('rechaza un nombre mas largo que el limite de la columna', () {
      final largo = 'a' * (kMaxActionNameLength + 1);

      expect(
        validateDraft(_draft(name: largo, steps: [_step()])).map((i) => i.field),
        contains('name'),
      );
      expect(
        validateDraft(
          _draft(name: 'a' * kMaxActionNameLength, steps: [_step()]),
        ),
        isEmpty,
      );
    });

    test('detecta una variable usada pero no declarada', () {
      final issues = validateDraft(
        _draft(steps: [_step(command: 'git checkout {{rama}}')]),
      );

      expect(issues, hasLength(1));
      expect(issues.first.message, contains('rama'));
      expect(issues.first.stepIndex, 0);
    });

    test('una variable declarada no da problema', () {
      final issues = validateDraft(
        _draft(
          steps: [
            _step(
              command: 'git checkout {{rama}}',
              parameters: const [
                DraftParam(key: 'rama', label: 'Rama', inputType: ParamInputType.text),
              ],
            ),
          ],
        ),
      );

      expect(issues, isEmpty);
    });

    /// El comando resuelto puede traer una variable que el original no tenia
    /// (por ejemplo en el `working_directory`): se valida contra el resuelto.
    test('valida contra el comando resuelto, no contra el original', () {
      final issues = validateDraft(
        _draft(
          steps: [
            _step(
              command: 'flutter analyze',
              resolvedCommand: 'cd /d "E:\\{{proyecto}}"\r\nflutter analyze',
            ),
          ],
        ),
      );

      expect(issues.map((i) => i.message).join(), contains('proyecto'));
    });

    test('detecta claves repetidas dentro del mismo paso', () {
      final issues = validateDraft(
        _draft(
          steps: [
            _step(
              command: 'echo {{a}}',
              parameters: const [
                DraftParam(key: 'a', label: 'A', inputType: ParamInputType.text),
                DraftParam(key: 'a', label: 'A otra vez', inputType: ParamInputType.text),
              ],
            ),
          ],
        ),
      );

      expect(issues.map((i) => i.message).join(), contains('repetida'));
    });

    test('un borrador sin pasos se rechaza', () {
      expect(validateDraft(_draft(steps: const [])), isNotEmpty);
    });

    test('el problema de un paso indica de que paso se trata', () {
      final issues = validateDraft(
        _draft(steps: [_step(), _step(command: 'echo {{x}}')]),
      );

      expect(issues.single.stepIndex, 1);
      expect(issues.single.toString(), startsWith('Paso 2:'));
    });
  });
}
