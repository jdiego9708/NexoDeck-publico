import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/hub_subscriptions_table.dart';

part 'hub_subscriptions_dao.g.dart';

@DriftAccessor(tables: [HubSubscriptions])
class HubSubscriptionsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$HubSubscriptionsDaoMixin {
  HubSubscriptionsDao(super.db);

  Stream<List<HubSubscription>> watchAll() => (select(
    hubSubscriptions,
  )..orderBy([(s) => OrderingTerm.desc(s.createdAt)])).watch();

  Future<HubSubscription?> getById(String id) =>
      (select(hubSubscriptions)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  Future<String> create(HubSubscriptionsCompanion entry) async {
    await into(hubSubscriptions).insert(entry);
    return entry.id.value;
  }

  Future<void> updateStatus(
    String id,
    HubSubscriptionStatus status, {
    DateTime? lastEventAt,
    String? lastEventSummary,
  }) => (update(hubSubscriptions)..where((s) => s.id.equals(id))).write(
    HubSubscriptionsCompanion(
      status: Value(status),
      lastEventAt: lastEventAt == null ? const Value.absent() : Value(lastEventAt),
      lastEventSummary: lastEventSummary == null
          ? const Value.absent()
          : Value(lastEventSummary),
    ),
  );

  /// Borra la suscripcion y, por el `onDelete: cascade` de `HubMessages`,
  /// todo su historial.
  Future<int> deleteSubscription(String id) =>
      (delete(hubSubscriptions)..where((s) => s.id.equals(id))).go();
}
