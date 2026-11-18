// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'macro_steps_dao.dart';

// ignore_for_file: type=lint
mixin _$MacroStepsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ActionGroupsTable get actionGroups => attachedDatabase.actionGroups;
  $ActionsTableTable get actionsTable => attachedDatabase.actionsTable;
  $MacroStepsTable get macroSteps => attachedDatabase.macroSteps;
  MacroStepsDaoManager get managers => MacroStepsDaoManager(this);
}

class MacroStepsDaoManager {
  final _$MacroStepsDaoMixin _db;
  MacroStepsDaoManager(this._db);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db.attachedDatabase, _db.actionGroups);
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db.attachedDatabase, _db.actionsTable);
  $$MacroStepsTableTableManager get macroSteps =>
      $$MacroStepsTableTableManager(_db.attachedDatabase, _db.macroSteps);
}
