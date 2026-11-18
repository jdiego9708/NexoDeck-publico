import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/action_groups_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/data/action_groups_repository.dart';

void main() {
  late NexoDeckDatabase db;
  late ActionGroupsRepository repository;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    repository = ActionGroupsRepository(ActionGroupsDao(db));
  });

  tearDown(() => db.close());

  // Nota: `NexoDeckDatabase.forTesting` corre el mismo `onCreate` que la
  // app real, que siembra 2 grupos de ejemplo ("Desarrollo"/"Streaming",
  // ver `_seedDefaults` en `database.dart`). Por eso estos tests buscan
  // el grupo por `id`/nombre en vez de asumir que la lista arranca vacia.

  test('createGroup y watchAll devuelve el grupo creado', () async {
    final id = await repository.createGroup(
      name: 'Juegos',
      colorHex: '#6366F1',
    );

    final groups = await repository.watchAll().first;
    final created = groups.where((g) => g.id == id);
    expect(created, hasLength(1));
    expect(created.single.name, 'Juegos');
  });

  test('renameGroup actualiza nombre y color sin duplicar filas', () async {
    final id = await repository.createGroup(name: 'Juegos');
    final group = (await repository.watchAll().first).firstWhere(
      (g) => g.id == id,
    );

    await repository.renameGroup(
      group,
      name: 'Entretenimiento',
      icon: group.icon,
      colorHex: '#EF4444',
    );

    final groups = await repository.watchAll().first;
    final renamed = groups.where((g) => g.id == id);
    expect(renamed, hasLength(1));
    expect(renamed.single.name, 'Entretenimiento');
    expect(renamed.single.colorHex, '#EF4444');
  });

  test(
    'deleteGroup deja las acciones asociadas sin grupo (setNull), no las borra',
    () async {
      final groupId = await repository.createGroup(name: 'Juegos');

      const actionId = 'action-1';
      await db
          .into(db.actionsTable)
          .insert(
            ActionsTableCompanion.insert(
              id: const Value(actionId),
              name: 'Git status',
              actionType: ActionType.terminal,
              groupId: Value(groupId),
            ),
          );

      await repository.deleteGroup(groupId);

      final action = await (db.select(
        db.actionsTable,
      )..where((a) => a.id.equals(actionId))).getSingle();
      expect(action.groupId, isNull);

      final groups = await repository.watchAll().first;
      expect(groups.where((g) => g.id == groupId), isEmpty);
    },
  );
}
