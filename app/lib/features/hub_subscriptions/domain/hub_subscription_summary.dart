import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as connection_bridge;

/// Origen ya resuelto de una suscripcion: `baseUrl` + `hubPath` para
/// SignalR, o `baseUrl` entero para WebSocket crudo (que ya trae la URL
/// `ws(s)://` completa). Unica definicion -- antes vivia duplicada en
/// `_SubscriptionRow` y en `HubSubscriptionDetailScreen`.
String hubSubscriptionTarget(HubSubscription subscription) =>
    subscription.kind == HubSubscriptionKind.signalR
    ? '${subscription.baseUrl}${subscription.hubPath ?? ''}'
    : subscription.baseUrl;

/// Arma el DTO que viaja por la red hacia el panel de solo lectura de
/// Android (`ConnectionEvent::HubSubscriptionsSnapshotReceived`) a partir de
/// la fila de Drift. `lastEventAt` se manda en segundos Unix -- asi lo
/// espera `nexodeck_protocol::HubSubscriptionWire.last_event_at` (`i64`).
connection_bridge.HubSubscriptionSummary hubSubscriptionSummaryOf(
  HubSubscription subscription,
) => connection_bridge.HubSubscriptionSummary(
  id: subscription.id,
  name: subscription.name,
  target: hubSubscriptionTarget(subscription),
  status: _toBridgeStatus(subscription.status),
  lastEventSummary: subscription.lastEventSummary,
  lastEventAt: subscription.lastEventAt == null
      ? null
      : subscription.lastEventAt!.millisecondsSinceEpoch ~/ 1000,
);

connection_bridge.HubSubscriptionSummaryStatus _toBridgeStatus(
  HubSubscriptionStatus status,
) => switch (status) {
  HubSubscriptionStatus.active =>
    connection_bridge.HubSubscriptionSummaryStatus.active,
  HubSubscriptionStatus.stopped =>
    connection_bridge.HubSubscriptionSummaryStatus.stopped,
  HubSubscriptionStatus.failed =>
    connection_bridge.HubSubscriptionSummaryStatus.failed,
};
