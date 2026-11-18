import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/action_groups_dao.dart';
import 'package:nexodeck/data/local/daos/action_parameters_dao.dart';
import 'package:nexodeck/data/local/daos/actions_dao.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/daos/macro_steps_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/data/action_groups_repository.dart';
import 'package:nexodeck/features/actions/data/actions_repository.dart';
import 'package:nexodeck/features/actions/data/deck_transfer_repository.dart';
import 'package:nexodeck/features/actions/domain/deck_export.dart';
import 'package:nexodeck/features/actions/domain/macro_plan.dart';
import 'package:nexodeck/features/hub_subscriptions/data/hub_subscriptions_repository.dart';

/// `ActionsRepository` necesita un `HubSubscriptionsRepository` para la
/// auto-suscripcion al terminar un comando capturado (ver
/// `actions_repository.dart`). Ninguno de estos tests dispara esa via, asi
/// que alcanza con uno real sobre la misma base en memoria.
HubSubscriptionsRepository _hubRepoFor(NexoDeckDatabase db) =>
    HubSubscriptionsRepository(HubSubscriptionsDao(db), HubMessagesDao(db));

void main() {
  late NexoDeckDatabase db;
  late ActionsRepository actions;
  late ActionGroupsRepository groups;
  late DeckTransferRepository transfer;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    actions = ActionsRepository(
      db,
      ActionsDao(db),
      ActionParametersDao(db),
      MacroStepsDao(db),
      _hubRepoFor(db),
    );
    groups = ActionGroupsRepository(ActionGroupsDao(db));
    transfer = DeckTransferRepository(actions, groups);
  });

  tearDown(() => db.close());

  test('el round-trip conserva una macro con sus pasos EN ORDEN', () async {
    // Es la razón de ser de estos tests: los pasos referencian acciones por
    // id, y al importar todo entra con ids NUEVOS. Si el remapeo falla, la
    // macro se importa "bien" pero apuntando a nada, y el síntoma recién
    // aparece al ejecutarla.
    final uno = await actions.createAction(
      name: 'Uno',
      icon: 'bolt',
      colorHex: '#111111',
      actionType: ActionType.terminal,
      commandTemplate: 'echo uno',
    );
    final dos = await actions.createAction(
      name: 'Dos',
      icon: 'bolt',
      colorHex: '#222222',
      actionType: ActionType.clipboard,
      commandTemplate: 'dos',
    );
    await actions.createAction(
      name: 'Mi macro',
      icon: 'playlist_play',
      colorHex: '#333333',
      actionType: ActionType.macro,
      macroSteps: [
        MacroStepDraft(stepActionId: dos, delayMsAfter: 700),
        MacroStepDraft(stepActionId: uno),
      ],
    );

    final json = await transfer.exportToJson();

    // Se importa sobre una base VACÍA para que los ids nuevos no puedan
    // coincidir por casualidad con los del origen.
    final db2 = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    final actions2 = ActionsRepository(
      db2,
      ActionsDao(db2),
      ActionParametersDao(db2),
      MacroStepsDao(db2),
      _hubRepoFor(db2),
    );
    final transfer2 = DeckTransferRepository(
      actions2,
      ActionGroupsRepository(ActionGroupsDao(db2)),
    );
    addTearDown(db2.close);

    // Ojo: `forTesting` corre el mismo `onCreate` que la app real, que
    // siembra acciones de ejemplo -- el export las incluye. Por eso se
    // afirma sobre la macro concreta y no sobre el total.
    final result = await transfer2.importFromJson(json);
    expect(result.actions, greaterThanOrEqualTo(3));
    expect(result.droppedSteps, 0);

    final all = await actions2.watchAll().first;
    final macro = all.firstWhere((a) => a.name == 'Mi macro');
    final plan = planMacro(macro, all);

    expect(plan.map((s) => s.action.name), ['Dos', 'Uno']);
    expect(plan.first.delayAfter, const Duration(milliseconds: 700));
    // Los ids son nuevos, no los del archivo.
    expect(macro.macroSteps.first.stepActionId, isNot(dos));
  });

  test('el round-trip conserva parámetros, opciones y grupo', () async {
    final groupId = await groups.createGroup(name: 'Dev', colorHex: '#ABCDEF');
    await actions.createAction(
      name: 'Deploy',
      description: 'Despliega',
      icon: 'rocket',
      colorHex: '#6366F1',
      actionType: ActionType.terminal,
      commandTemplate: 'deploy {{entorno}}',
      requiresAdmin: true,
      terminalType: TerminalType.powershell,
      showTerminalWindow: false,
      groupId: groupId,
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

    final json = await transfer.exportToJson();

    final db2 = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    final actions2 = ActionsRepository(
      db2,
      ActionsDao(db2),
      ActionParametersDao(db2),
      MacroStepsDao(db2),
      _hubRepoFor(db2),
    );
    final groups2 = ActionGroupsRepository(ActionGroupsDao(db2));
    addTearDown(db2.close);

    await DeckTransferRepository(actions2, groups2).importFromJson(json);

    final imported = (await actions2.watchAll().first).firstWhere(
      (a) => a.name == 'Deploy',
    );
    expect(imported.description, 'Despliega');
    expect(imported.requiresAdmin, isTrue);
    expect(imported.terminalType, TerminalType.powershell);
    expect(imported.showTerminalWindow, isFalse);

    final param = imported.parameters.single;
    expect(param.key, 'entorno');
    expect(param.options, ['staging', 'producción']);
    expect(param.defaultValue, 'staging');

    // El grupo se recrea con id nuevo, y la acción queda apuntando a ESE.
    final importedGroups = await groups2.watchAll().first;
    final dev = importedGroups.firstWhere((g) => g.name == 'Dev');
    expect(imported.groupId, dev.id);
    expect(imported.groupId, isNot(groupId));
  });

  test('importar dos veces agrega, no pisa', () async {
    // Regla explícita: abrir un deck compartido no puede borrar el propio.
    await actions.createAction(
      name: 'Sola',
      icon: 'bolt',
      colorHex: '#111111',
      actionType: ActionType.clipboard,
      commandTemplate: 'x',
    );
    final json = await transfer.exportToJson();

    await transfer.importFromJson(json);
    await transfer.importFromJson(json);

    final all = await actions.watchAll().first;
    expect(all.where((a) => a.name == 'Sola'), hasLength(3));
  });

  test('un paso que apunta a una acción ausente se descarta y se cuenta', () async {
    // Archivo editado a mano o exportado parcialmente. La macro entra igual
    // (más corta), pero el resultado lo dice: perder pasos en silencio es
    // peor que no importar.
    final json = jsonEncode({
      'version': 1,
      'actions': [
        {
          'id': 'a-macro',
          'name': 'Macro rota',
          'icon': 'bolt',
          'colorHex': '#111111',
          'actionType': 'macro',
          'macroSteps': [
            {'stepActionId': 'no-existe', 'delayMsAfter': 0},
            {'stepActionId': 'a-hoja', 'delayMsAfter': 0},
          ],
        },
        {
          'id': 'a-hoja',
          'name': 'Hoja',
          'icon': 'bolt',
          'colorHex': '#222222',
          'actionType': 'clipboard',
          'commandTemplate': 'hola',
        },
      ],
    });

    final result = await transfer.importFromJson(json);

    expect(result.droppedSteps, 1);
    final all = await actions.watchAll().first;
    final macro = all.firstWhere((a) => a.name == 'Macro rota');
    expect(planMacro(macro, all).map((s) => s.action.name), ['Hoja']);
  });

  test('una macro dentro de otra se descarta en vez de romper todo', () async {
    final json = jsonEncode({
      'version': 1,
      'actions': [
        {
          'id': 'externa',
          'name': 'Externa',
          'icon': 'bolt',
          'colorHex': '#111111',
          'actionType': 'macro',
          'macroSteps': [
            {'stepActionId': 'interna', 'delayMsAfter': 0},
          ],
        },
        {
          'id': 'interna',
          'name': 'Interna',
          'icon': 'bolt',
          'colorHex': '#222222',
          'actionType': 'macro',
          'macroSteps': <Map<String, Object?>>[],
        },
      ],
    });

    final result = await transfer.importFromJson(json);

    expect(result.actions, 2);
    expect(result.droppedSteps, 1);
  });

  group('parseDeckExport rechaza archivos que no son decks', () {
    test('JSON inválido', () {
      expect(
        () => parseDeckExport('esto no es json'),
        throwsA(isA<DeckImportException>()),
      );
    });

    test('JSON válido pero sin "version"', () {
      expect(
        () => parseDeckExport('{"actions": []}'),
        throwsA(isA<DeckImportException>()),
      );
    });

    test('una versión más nueva se rechaza con un motivo claro', () {
      // Mejor negarse que importar a medias un formato que no se entiende.
      expect(
        () => parseDeckExport('{"version": 999, "actions": []}'),
        throwsA(
          isA<DeckImportException>().having(
            (e) => e.message,
            'message',
            contains('más nueva'),
          ),
        ),
      );
    });

    test('sin acciones válidas', () {
      expect(
        () => parseDeckExport('{"version": 1, "actions": []}'),
        throwsA(isA<DeckImportException>()),
      );
    });

    test('un actionType desconocido cae al default en vez de tumbar todo', () {
      final parsed = parseDeckExport(
        jsonEncode({
          'version': 1,
          'actions': [
            {
              'id': 'x',
              'name': 'Rara',
              'actionType': 'teletransporte',
            },
          ],
        }),
      );
      expect(parsed.actions.single.actionType, ActionType.clipboard);
    });
  });
}
