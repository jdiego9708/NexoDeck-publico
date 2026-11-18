import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/actions_table.dart';

part 'actions_dao.g.dart';

@DriftAccessor(tables: [ActionsTable])
class ActionsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ActionsDaoMixin {
  ActionsDao(super.db);

  Stream<List<ActionsTableData>> watchAll() =>
      (select(actionsTable)..orderBy([(a) => OrderingTerm.asc(a.name)]))
          .watch();

  Future<ActionsTableData?> getById(String id) =>
      (select(actionsTable)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<String> createAction(ActionsTableCompanion entry) async {
    await into(actionsTable).insert(entry);
    return entry.id.value;
  }

  Future<bool> updateAction(ActionsTableCompanion entry) =>
      update(actionsTable).replace(entry);

  Future<int> deleteAction(String id) =>
      (delete(actionsTable)..where((a) => a.id.equals(id))).go();
}
