import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/domain/action_param.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/actions/domain/macro_plan.dart';
import 'package:nexodeck/features/actions/domain/macro_step.dart';

/// Tests de la parte pura del motor de macros: que se ejecuta, en que
/// orden, y que se le pregunta al usuario antes. Sin Drift ni bridge de por
/// medio -- por eso `planMacro`/`promptParametersFor` son funciones libres
/// y no metodos del repositorio.
void main() {
  group('planMacro', () {
    test('resuelve los pasos en orden de orderIndex, no de insercion', () {
      final abrir = _action(id: 'abrir', name: 'Abrir OBS');
      final saludar = _action(id: 'saludar', name: 'Saludar');
      final grabar = _action(id: 'grabar', name: 'Grabar');

      final macro = _action(
        id: 'macro',
        name: 'Arrancar stream',
        type: ActionType.macro,
        // A proposito desordenados: la lista puede llegar en cualquier
        // orden desde la query.
        steps: [
          _step('s3', 'grabar', order: 2),
          _step('s1', 'abrir', order: 0),
          _step('s2', 'saludar', order: 1),
        ],
      );

      final plan = planMacro(macro, [macro, abrir, saludar, grabar]);

      expect(plan.map((s) => s.action.id), ['abrir', 'saludar', 'grabar']);
    });

    test('conserva el delay de cada paso', () {
      final uno = _action(id: 'uno', name: 'Uno');
      final macro = _action(
        id: 'macro',
        name: 'M',
        type: ActionType.macro,
        steps: [_step('s1', 'uno', order: 0, delayMs: 1500)],
      );

      final plan = planMacro(macro, [macro, uno]);

      expect(plan.single.delayAfter, const Duration(milliseconds: 1500));
    });

    test('descarta un paso que apunta a otra macro', () {
      // Camino real: se crea la macro con un paso normal y DESPUES se edita
      // esa accion para convertirla en macro. La validacion del repositorio
      // no puede atrapar eso, asi que el plan tiene que filtrarlo o la
      // ejecucion recursa para siempre.
      final anidada = _action(
        id: 'anidada',
        name: 'Otra macro',
        type: ActionType.macro,
      );
      final normal = _action(id: 'normal', name: 'Normal');
      final macro = _action(
        id: 'macro',
        name: 'M',
        type: ActionType.macro,
        steps: [
          _step('s1', 'anidada', order: 0),
          _step('s2', 'normal', order: 1),
        ],
      );

      final plan = planMacro(macro, [macro, anidada, normal]);

      expect(plan.map((s) => s.action.id), ['normal']);
    });

    test('descarta un paso cuya accion ya no existe', () {
      final normal = _action(id: 'normal', name: 'Normal');
      final macro = _action(
        id: 'macro',
        name: 'M',
        type: ActionType.macro,
        steps: [
          _step('s1', 'borrada', order: 0),
          _step('s2', 'normal', order: 1),
        ],
      );

      final plan = planMacro(macro, [macro, normal]);

      expect(plan.map((s) => s.action.id), ['normal']);
    });
  });

  group('promptParametersFor', () {
    test('una accion simple pide sus propios parametros', () {
      final accion = _action(
        id: 'a',
        name: 'A',
        params: [_param('rama', 'Rama')],
      );

      final prompt = promptParametersFor(accion, [accion]);

      expect(prompt.map((p) => p.key), ['rama']);
    });

    test('una macro pide la union de los parametros de sus pasos', () {
      final checkout = _action(
        id: 'checkout',
        name: 'Checkout',
        params: [_param('rama', 'Rama')],
      );
      final desplegar = _action(
        id: 'desplegar',
        name: 'Desplegar',
        params: [_param('entorno', 'Entorno')],
      );
      final macro = _action(
        id: 'macro',
        name: 'Deploy',
        type: ActionType.macro,
        steps: [
          _step('s1', 'checkout', order: 0),
          _step('s2', 'desplegar', order: 1),
        ],
      );

      final prompt = promptParametersFor(macro, [macro, checkout, desplegar]);

      expect(prompt.map((p) => p.key), ['rama', 'entorno']);
    });

    test(
      'deduplica por key: la misma variable en tres pasos se pregunta una vez',
      () {
        // Este es el punto entero del diseno: sin dedupe, una macro de 3
        // pasos que comparten `{{rama}}` abriria 3 dialogos seguidos
        // pidiendo lo mismo.
        final uno = _action(
          id: 'uno',
          name: 'Uno',
          params: [_param('rama', 'Rama')],
        );
        final dos = _action(
          id: 'dos',
          name: 'Dos',
          params: [_param('rama', 'Rama otra vez'), _param('tag', 'Tag')],
        );
        final tres = _action(
          id: 'tres',
          name: 'Tres',
          params: [_param('rama', 'Rama de nuevo')],
        );
        final macro = _action(
          id: 'macro',
          name: 'M',
          type: ActionType.macro,
          steps: [
            _step('s1', 'uno', order: 0),
            _step('s2', 'dos', order: 1),
            _step('s3', 'tres', order: 2),
          ],
        );

        final prompt = promptParametersFor(macro, [macro, uno, dos, tres]);

        expect(prompt.map((p) => p.key), ['rama', 'tag']);
        // Gana la primera aparicion, que es la que el usuario ve primero al
        // leer la macro de arriba abajo.
        expect(prompt.first.label, 'Rama');
      },
    );

    test('una macro sin pasos no pide nada', () {
      final macro = _action(id: 'macro', name: 'M', type: ActionType.macro);

      expect(promptParametersFor(macro, [macro]), isEmpty);
    });
  });

  group('renderCommand', () {
    test('un parametro ausente cae al valor por defecto', () {
      final accion = _action(
        id: 'a',
        name: 'A',
        command: 'git checkout {{rama}}',
        params: [_param('rama', 'Rama', defaultValue: 'main')],
      );

      expect(accion.renderCommand({}), 'git checkout main');
    });

    test('un valor vacio explicito NO cae al valor por defecto', () {
      // Distincion que el protocolo tambien respeta (ver el round-trip de
      // `ExecuteAction` con un valor vacio): borrar el campo a proposito es
      // una eleccion del usuario, no una ausencia.
      final accion = _action(
        id: 'a',
        name: 'A',
        command: 'echo "{{mensaje}}"',
        params: [_param('mensaje', 'Mensaje', defaultValue: 'hola')],
      );

      expect(accion.renderCommand({'mensaje': ''}), 'echo ""');
    });

    test('el mismo placeholder se reemplaza todas las veces que aparece', () {
      final accion = _action(
        id: 'a',
        name: 'A',
        command: 'mkdir {{n}} && cd {{n}}',
        params: [_param('n', 'Nombre')],
      );

      expect(accion.renderCommand({'n': 'demo'}), 'mkdir demo && cd demo');
    });
  });
}

DeckAction _action({
  required String id,
  required String name,
  ActionType type = ActionType.terminal,
  String? command,
  List<ActionParam> params = const [],
  List<DeckMacroStep> steps = const [],
}) => DeckAction(
  id: id,
  name: name,
  description: null,
  icon: 'bolt',
  colorHex: '#6366F1',
  actionType: type,
  commandTemplate: command,
  requiresAdmin: false,
  terminalType: null,
  isFavorite: false,
  parameters: params,
  macroSteps: steps,
);

ActionParam _param(String key, String label, {String? defaultValue}) =>
    ActionParam(
      id: 'param-$key',
      key: key,
      label: label,
      inputType: ParamInputType.text,
      defaultValue: defaultValue,
      options: const [],
      orderIndex: 0,
    );

DeckMacroStep _step(
  String id,
  String stepActionId, {
  required int order,
  int delayMs = 0,
}) => DeckMacroStep(
  id: id,
  stepActionId: stepActionId,
  orderIndex: order,
  delayMsAfter: delayMs,
);
