// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_actions_dao.dart';

// ignore_for_file: type=lint
mixin _$ProfileActionsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $ActionGroupsTable get actionGroups => attachedDatabase.actionGroups;
  $ActionsTableTable get actionsTable => attachedDatabase.actionsTable;
  $ProfileActionsTable get profileActions => attachedDatabase.profileActions;
  ProfileActionsDaoManager get managers => ProfileActionsDaoManager(this);
}

class ProfileActionsDaoManager {
  final _$ProfileActionsDaoMixin _db;
  ProfileActionsDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$ActionGroupsTableTableManager get actionGroups =>
      $$ActionGroupsTableTableManager(_db.attachedDatabase, _db.actionGroups);
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db.attachedDatabase, _db.actionsTable);
  $$ProfileActionsTableTableManager get profileActions =>
      $$ProfileActionsTableTableManager(
        _db.attachedDatabase,
        _db.profileActions,
      );
}
