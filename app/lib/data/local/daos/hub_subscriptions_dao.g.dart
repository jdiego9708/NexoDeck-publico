// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hub_subscriptions_dao.dart';

// ignore_for_file: type=lint
mixin _$HubSubscriptionsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $HubSubscriptionsTable get hubSubscriptions =>
      attachedDatabase.hubSubscriptions;
  HubSubscriptionsDaoManager get managers => HubSubscriptionsDaoManager(this);
}

class HubSubscriptionsDaoManager {
  final _$HubSubscriptionsDaoMixin _db;
  HubSubscriptionsDaoManager(this._db);
  $$HubSubscriptionsTableTableManager get hubSubscriptions =>
      $$HubSubscriptionsTableTableManager(
        _db.attachedDatabase,
        _db.hubSubscriptions,
      );
}
