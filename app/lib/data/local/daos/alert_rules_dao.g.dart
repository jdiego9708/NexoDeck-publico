// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_rules_dao.dart';

// ignore_for_file: type=lint
mixin _$AlertRulesDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $AlertRulesTable get alertRules => attachedDatabase.alertRules;
  AlertRulesDaoManager get managers => AlertRulesDaoManager(this);
}

class AlertRulesDaoManager {
  final _$AlertRulesDaoMixin _db;
  AlertRulesDaoManager(this._db);
  $$AlertRulesTableTableManager get alertRules =>
      $$AlertRulesTableTableManager(_db.attachedDatabase, _db.alertRules);
}
