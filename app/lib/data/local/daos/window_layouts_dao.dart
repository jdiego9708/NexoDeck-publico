import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/window_layouts_table.dart';

part 'window_layouts_dao.g.dart';

@DriftAccessor(tables: [WindowLayouts])
class WindowLayoutsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$WindowLayoutsDaoMixin {
  WindowLayoutsDao(super.db);

  Future<WindowLayout?> getForMode(WindowMode mode) =>
      (select(
        windowLayouts,
      )..where((w) => w.mode.equalsValue(mode))).getSingleOrNull();

  Future<void> saveLayout(WindowLayoutsCompanion entry) =>
      into(windowLayouts).insertOnConflictUpdate(entry);
}
