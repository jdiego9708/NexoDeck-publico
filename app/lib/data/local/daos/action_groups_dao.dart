import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/action_groups_table.dart';

part 'action_groups_dao.g.dart';

@DriftAccessor(tables: [ActionGroups])
class ActionGroupsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ActionGroupsDaoMixin {
  ActionGroupsDao(super.db);

  Stream<List<ActionGroup>> watchAll() => (select(
    actionGroups,
  )..orderBy([(g) => OrderingTerm.asc(g.orderIndex)])).watch();

  Future<String> createGroup(ActionGroupsCompanion entry) async {
    await into(actionGroups).insert(entry);
    return entry.id.value;
  }

  Future<bool> updateGroup(ActionGroupsCompanion entry) =>
      update(actionGroups).replace(entry);

  Future<int> deleteGroup(String id) =>
      (delete(actionGroups)..where((g) => g.id.equals(id))).go();
}
