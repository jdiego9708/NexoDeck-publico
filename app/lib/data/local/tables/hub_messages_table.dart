import 'package:drift/drift.dart';

import 'hub_subscriptions_table.dart';

/// Un mensaje recibido de una suscripcion, ya persistido. Se escribe uno
/// por cada `HubEvent::MessageReceived` que llega del lado Rust -- el
/// repositorio (`hub_subscriptions_repository.dart`) es quien hace esa
/// escritura, nunca Rust: la base solo la toca Dart.
@TableIndex(
  name: 'idx_hub_messages_subscription_received',
  columns: {#subscriptionId, #receivedAt},
)
class HubMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get subscriptionId =>
      text().references(HubSubscriptions, #id, onDelete: KeyAction.cascade)();

  /// El `target` invocado (SignalR, ej. `ReceivePlantTrainingProgress`) o
  /// `"message"`/`"binary"` (WebSocket crudo).
  TextColumn get eventName => text()();

  /// JSON tal cual vino del lado Rust -- siempre JSON valido, listo para
  /// mostrar formateado sin que la UI tenga que adivinar el formato.
  TextColumn get payloadJson => text()();

  DateTimeColumn get receivedAt =>
      dateTime().clientDefault(() => DateTime.now())();
}
