// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_parameters_dao.dart';

// ignore_for_file: type=lint
mixin _$ActionParametersDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ActionGroupsTable get actionGroups => attachedDatabase.actionGroups;
  $ActionsTableTable get actionsTable => attachedDatabase.actionsTable;
  $ActionParametersTable get actionParameters =>
      attachedDatabase.actionParameters;
  ActionParametersDaoManager get managers => ActionParametersDaoManager(this);
}

class ActionParametersDaoManager {
  final _$ActionParametersDaoMixin _db;
  ActionParametersDaoManager(this._db);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db.attachedDatabase, _db.actionGroups);
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db.attachedDatabase, _db.actionsTable);
  $$ActionParametersTableTableManager get actionParameters =>
      $$ActionParametersTableTableManager(
        _db.attachedDatabase,
        _db.actionParameters,
      );
}
