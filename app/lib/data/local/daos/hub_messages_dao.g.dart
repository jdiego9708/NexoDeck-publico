// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hub_messages_dao.dart';

// ignore_for_file: type=lint
mixin _$HubMessagesDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $HubSubscriptionsTable get hubSubscriptions =>
      attachedDatabase.hubSubscriptions;
  $HubMessagesTable get hubMessages => attachedDatabase.hubMessages;
  HubMessagesDaoManager get managers => HubMessagesDaoManager(this);
}

class HubMessagesDaoManager {
  final _$HubMessagesDaoMixin _db;
  HubMessagesDaoManager(this._db);
  $$HubSubscriptionsTableTableManager get hubSubscriptions =>
      $$HubSubscriptionsTableTableManager(
        _db.attachedDatabase,
        _db.hubSubscriptions,
      );
  $$HubMessagesTableTableManager get hubMessages =>
      $$HubMessagesTableTableManager(_db.attachedDatabase, _db.hubMessages);
}
