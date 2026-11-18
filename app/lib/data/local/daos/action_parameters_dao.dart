import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/action_parameters_table.dart';

part 'action_parameters_dao.g.dart';

@DriftAccessor(tables: [ActionParameters])
class ActionParametersDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ActionParametersDaoMixin {
  ActionParametersDao(super.db);

  Stream<List<ActionParameter>> watchForAction(String actionId) =>
      (select(actionParameters)
            ..where((p) => p.actionId.equals(actionId))
            ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]))
          .watch();

  Future<void> replaceForAction(
    String actionId,
    List<ActionParametersCompanion> parameters,
  ) async {
    await transaction(() async {
      await (delete(
        actionParameters,
      )..where((p) => p.actionId.equals(actionId))).go();
      for (final parameter in parameters) {
        await into(actionParameters).insert(parameter);
      }
    });
  }
}
