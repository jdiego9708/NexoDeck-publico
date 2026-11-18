import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/alert_rules_table.dart';

part 'alert_rules_dao.g.dart';

@DriftAccessor(tables: [AlertRules])
class AlertRulesDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$AlertRulesDaoMixin {
  AlertRulesDao(super.db);

  Stream<List<AlertRule>> watchAll() => select(alertRules).watch();

  Stream<List<AlertRule>> watchEnabled() =>
      (select(alertRules)..where((r) => r.isEnabled.equals(true))).watch();

  Future<String> createRule(AlertRulesCompanion entry) async {
    await into(alertRules).insert(entry);
    return entry.id.value;
  }

  Future<bool> updateRule(AlertRulesCompanion entry) =>
      update(alertRules).replace(entry);

  Future<int> deleteRule(String id) =>
      (delete(alertRules)..where((r) => r.id.equals(id))).go();
}
