// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_groups_dao.dart';

// ignore_for_file: type=lint
mixin _$ActionGroupsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ActionGroupsTable get actionGroups => attachedDatabase.actionGroups;
  ActionGroupsDaoManager get managers => ActionGroupsDaoManager(this);
}

class ActionGroupsDaoManager {
  final _$ActionGroupsDaoMixin _db;
  ActionGroupsDaoManager(this._db);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db.attachedDatabase, _db.actionGroups);
}
