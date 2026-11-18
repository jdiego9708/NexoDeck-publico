// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'window_layouts_dao.dart';

// ignore_for_file: type=lint
mixin _$WindowLayoutsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $WindowLayoutsTable get windowLayouts => attachedDatabase.windowLayouts;
  WindowLayoutsDaoManager get managers => WindowLayoutsDaoManager(this);
}

class WindowLayoutsDaoManager {
  final _$WindowLayoutsDaoMixin _db;
  WindowLayoutsDaoManager(this._db);
  $$WindowLayoutsTableTableManager get windowLayouts =>
      $$WindowLayoutsTableTableManager(_db.attachedDatabase, _db.windowLayouts);
}
