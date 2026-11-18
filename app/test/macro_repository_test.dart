import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/action_parameters_dao.dart';
import 'package:nexodeck/data/local/daos/actions_dao.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/daos/macro_steps_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/data/actions_repository.dart';
import 'package:nexodeck/features/actions/domain/macro_plan.dart';
import 'package:nexodeck/features/hub_subscriptions/data/hub_subscriptions_repository.dart';

/// Persistencia de macros contra SQLite real (en memoria). No cubre
/// `execute()`: eso llama al bridge de Rust, que no existe en un test de
/// Dart puro -- la logica de "que se ejecuta y en que orden" vive aparte,
/// en funciones puras, y se prueba en `macro_plan_test.dart`.
void main() {
  late NexoDeckDatabase db;
  late ActionsRepository repository;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    repository = ActionsRepository(
      db,
      ActionsDao(db),
      ActionParametersDao(db),
      MacroStepsDao(db),
      HubSubscriptionsRepository(HubSubscriptionsDao(db), HubMessagesDao(db)),
    );
  });

  tearDown(() => db.close());

  Future<String> crearAccionSimple(String name) => repository.createAction(
    name: name,
    icon: 'bolt',
    colorHex: '#6366F1',
    actionType: ActionType.terminal,
    commandTemplate: 'echo $name',
  );

  test('una macro guarda sus pasos en orden y los devuelve ordenados', () async {
    final uno = await crearAccionSimple('Uno');
    final dos = await crearAccionSimple('Dos');
    final tres = await crearAccionSimple('Tres');

    final macroId = await repository.createAction(
      name: 'Mi macro',
      icon: 'playlist_play',
      colorHex: '#EF4444',
      actionType: ActionType.macro,
      macroSteps: [
        MacroStepDraft(stepActionId: uno, delayMsAfter: 250),
        MacroStepDraft(stepActionId: dos),
        MacroStepDraft(stepActionId: tres, delayMsAfter: 1000),
      ],
    );

    final actions = await repository.watchAll().first;
    final macro = actions.firstWhere((a) => a.id == macroId);

    expect(macro.macroSteps.map((s) => s.stepActionId), [uno, dos, tres]);
    expect(macro.macroSteps.map((s) => s.orderIndex), [0, 1, 2]);
    expect(macro.macroSteps.map((s) => s.delayMsAfter), [250, 0, 1000]);

    // Y el plan resuelto contra las acciones reales conserva ese orden.
    final plan = planMacro(macro, actions);
    expect(plan.map((s) => s.action.name), ['Uno', 'Dos', 'Tres']);
  });

  test('guardar de nuevo reemplaza los pasos, no los acumula', () async {
    final uno = await crearAccionSimple('Uno');
    final dos = await crearAccionSimple('Dos');

    final macroId = await repository.createAction(
      name: 'Mi macro',
      icon: 'playlist_play',
      colorHex: '#EF4444',
      actionType: ActionType.macro,
      macroSteps: [MacroStepDraft(stepActionId: uno)],
    );

    var macro = (await repository.watchAll().first).firstWhere(
      (a) => a.id == macroId,
    );
    await repository.updateAction(
      macro,
      name: 'Mi macro',
      icon: 'playlist_play',
      colorHex: '#EF4444',
      actionType: ActionType.macro,
      macroSteps: [MacroStepDraft(stepActionId: dos)],
    );

    macro = (await repository.watchAll().first).firstWhere(
      (a) => a.id == macroId,
    );
    expect(macro.macroSteps, hasLength(1));
    expect(macro.macroSteps.single.stepActionId, dos);
  });

  test('rechaza una macro cuyo paso apunta a otra macro', () async {
    final hoja = await crearAccionSimple('Hoja');
    final anidada = await repository.createAction(
      name: 'Macro interna',
      icon: 'playlist_play',
      colorHex: '#EF4444',
      actionType: ActionType.macro,
      macroSteps: [MacroStepDraft(stepActionId: hoja)],
    );

    expect(
      () => repository.createAction(
        name: 'Macro externa',
        icon: 'playlist_play',
        colorHex: '#EF4444',
        actionType: ActionType.macro,
        macroSteps: [MacroStepDraft(stepActionId: anidada)],
      ),
      throwsA(isA<NestedMacroException>()),
    );
  });

  test('borrar una accion se lleva los pasos que la referenciaban', () async {
    // `onDelete: cascade` en `macro_steps.step_action_id`. Si esto dejara
    // de valer, una macro quedaria con un paso colgado apuntando a nada.
    final uno = await crearAccionSimple('Uno');
    final dos = await crearAccionSimple('Dos');
    final macroId = await repository.createAction(
      name: 'Mi macro',
      icon: 'playlist_play',
      colorHex: '#EF4444',
      actionType: ActionType.macro,
      macroSteps: [
        MacroStepDraft(stepActionId: uno),
        MacroStepDraft(stepActionId: dos),
      ],
    );

    await repository.deleteAction(uno);

    final macro = (await repository.watchAll().first).firstWhere(
      (a) => a.id == macroId,
    );
    expect(macro.macroSteps, hasLength(1));
    expect(macro.macroSteps.single.stepActionId, dos);
  });

  test(
    'el join con parametros y pasos no duplica ninguno de los dos',
    () async {
      // El `watchAll` hace DOS leftOuterJoin, asi que una accion con N
      // parametros y M pasos vuelve en N*M filas. Sin deduplicar por id,
      // los parametros aparecerian repetidos tantas veces como pasos haya.
      // Se fuerza el caso escribiendo ambas cosas sobre la misma fila.
      final hoja = await crearAccionSimple('Hoja');
      final otra = await crearAccionSimple('Otra');

      final id = await repository.createAction(
        name: 'Mixta',
        icon: 'bolt',
        colorHex: '#6366F1',
        actionType: ActionType.macro,
        parameters: const [
          ActionParamDraft(
            key: 'rama',
            label: 'Rama',
            inputType: ParamInputType.text,
          ),
          ActionParamDraft(
            key: 'tag',
            label: 'Tag',
            inputType: ParamInputType.text,
          ),
        ],
        macroSteps: [
          MacroStepDraft(stepActionId: hoja),
          MacroStepDraft(stepActionId: otra),
        ],
      );

      final action = (await repository.watchAll().first).firstWhere(
        (a) => a.id == id,
      );
      expect(action.parameters.map((p) => p.key), ['rama', 'tag']);
      expect(action.macroSteps, hasLength(2));
    },
  );

  test('las opciones de un parametro select sobreviven el round-trip', () async {
    final id = await repository.createAction(
      name: 'Deploy',
      icon: 'bolt',
      colorHex: '#6366F1',
      actionType: ActionType.terminal,
      commandTemplate: 'deploy {{entorno}}',
      parameters: const [
        ActionParamDraft(
          key: 'entorno',
          label: 'Entorno',
          inputType: ParamInputType.select,
          defaultValue: 'staging',
          options: ['staging', 'producción'],
        ),
      ],
    );

    final action = (await repository.watchAll().first).firstWhere(
      (a) => a.id == id,
    );
    final param = action.parameters.single;
    expect(param.options, ['staging', 'producción']);
    expect(param.defaultValue, 'staging');
    expect(action.renderCommand({}), 'deploy staging');
  });
}
