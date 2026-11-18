import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/macro_steps_table.dart';

part 'macro_steps_dao.g.dart';

@DriftAccessor(tables: [MacroSteps])
class MacroStepsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$MacroStepsDaoMixin {
  MacroStepsDao(super.db);

  Stream<List<MacroStep>> watchStepsForMacro(String macroActionId) =>
      (select(macroSteps)
            ..where((s) => s.macroActionId.equals(macroActionId))
            ..orderBy([(s) => OrderingTerm.asc(s.orderIndex)]))
          .watch();

  Future<void> replaceSteps(
    String macroActionId,
    List<MacroStepsCompanion> steps,
  ) async {
    await transaction(() async {
      await (delete(
        macroSteps,
      )..where((s) => s.macroActionId.equals(macroActionId))).go();
      for (final step in steps) {
        await into(macroSteps).insert(step);
      }
    });
  }
}
