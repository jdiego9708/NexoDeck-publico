import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as connection_bridge;

import '../../../core/di/database_provider.dart';
import '../data/hub_subscriptions_repository.dart';

final hubSubscriptionsRepositoryProvider = Provider<HubSubscriptionsRepository>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return HubSubscriptionsRepository(HubSubscriptionsDao(db), HubMessagesDao(db));
});

final hubSubscriptionsListProvider =
    StreamProvider.autoDispose<List<HubSubscription>>((ref) {
      return ref.watch(hubSubscriptionsRepositoryProvider).watchAll();
    });

final hubMessagesProvider = StreamProvider.autoDispose
    .family<List<HubMessage>, String>((ref, subscriptionId) {
      return ref
          .watch(hubSubscriptionsRepositoryProvider)
          .watchMessages(subscriptionId);
    });

/// Rol Android: ultimo snapshot de las suscripciones de la PC, recibido por
/// `ConnectionEvent.hubSubscriptionsSnapshotReceived` -- ver
/// `connected_device_screen.dart`. `null` hasta que llega el primero (recien
/// conectado, o la PC no tiene ninguna suscripcion). Mismo patron que
/// `remoteTopProcessesProvider` (`features/processes/application/process_providers.dart`).
final remoteHubSubscriptionsProvider =
    StateProvider<List<connection_bridge.HubSubscriptionSummary>?>(
      (ref) => null,
    );
