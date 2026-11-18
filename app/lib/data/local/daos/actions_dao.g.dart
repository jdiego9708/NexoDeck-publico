// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'actions_dao.dart';

// ignore_for_file: type=lint
mixin _$ActionsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ActionGroupsTable get actionGroups => attachedDatabase.actionGroups;
  $ActionsTableTable get actionsTable => attachedDatabase.actionsTable;
  ActionsDaoManager get managers => ActionsDaoManager(this);
}

class ActionsDaoManager {
  final _$ActionsDaoMixin _db;
  ActionsDaoManager(this._db);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db.attachedDatabase, _db.actionGroups);
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db.attachedDatabase, _db.actionsTable);
}
