import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/hub_messages_table.dart';

part 'hub_messages_dao.g.dart';

@DriftAccessor(tables: [HubMessages])
class HubMessagesDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$HubMessagesDaoMixin {
  HubMessagesDao(super.db);

  /// Mas nuevo primero -- el panel lo dibuja con `reverse: true`, igual que
  /// `RunPanel`.
  Stream<List<HubMessage>> watchFor(String subscriptionId) => (select(
    hubMessages,
  )..where((m) => m.subscriptionId.equals(subscriptionId))
        ..orderBy([(m) => OrderingTerm.desc(m.receivedAt)]))
      .watch();

  Future<void> insert(HubMessagesCompanion entry) =>
      into(hubMessages).insert(entry);
}
