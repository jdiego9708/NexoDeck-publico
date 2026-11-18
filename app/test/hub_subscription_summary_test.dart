import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';
import 'package:nexodeck/features/hub_subscriptions/domain/hub_subscription_summary.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

HubSubscription _subscription({
  HubSubscriptionKind kind = HubSubscriptionKind.signalR,
  String baseUrl = 'https://api.example.local:5242',
  String? hubPath = '/hubs/plant-training-progress',
  HubSubscriptionStatus status = HubSubscriptionStatus.active,
  String? lastEventSummary,
  DateTime? lastEventAt,
}) => HubSubscription(
  id: 'sub-1',
  name: 'Entrenamiento IA',
  kind: kind,
  baseUrl: baseUrl,
  allowInvalidCert: false,
  status: status,
  createdAt: DateTime.utc(2026, 1, 1),
  lastEventSummary: lastEventSummary,
  lastEventAt: lastEventAt,
  hubPath: hubPath,
);

void main() {
  group('hubSubscriptionTarget', () {
    test('SignalR concatena baseUrl y hubPath', () {
      final subscription = _subscription(
        kind: HubSubscriptionKind.signalR,
        baseUrl: 'https://api.example.local:5242',
        hubPath: '/hubs/plant-training-progress',
      );
      expect(
        hubSubscriptionTarget(subscription),
        'https://api.example.local:5242/hubs/plant-training-progress',
      );
    });

    test('WebSocket crudo usa baseUrl entero, sin hubPath', () {
      final subscription = _subscription(
        kind: HubSubscriptionKind.rawWebSocket,
        baseUrl: 'wss://example.com/stream',
        hubPath: null,
      );
      expect(hubSubscriptionTarget(subscription), 'wss://example.com/stream');
    });
  });

  group('hubSubscriptionSummaryOf', () {
    test('mapea id/name/target y deja lastEventSummary/lastEventAt en null', () {
      final subscription = _subscription();
      final summary = hubSubscriptionSummaryOf(subscription);

      expect(summary.id, 'sub-1');
      expect(summary.name, 'Entrenamiento IA');
      expect(
        summary.target,
        'https://api.example.local:5242/hubs/plant-training-progress',
      );
      expect(summary.lastEventSummary, isNull);
      expect(summary.lastEventAt, isNull);
    });

    test('convierte lastEventAt a segundos Unix', () {
      final subscription = _subscription(
        lastEventSummary: 'ReceiveProgress: {"pct":50}',
        lastEventAt: DateTime.fromMillisecondsSinceEpoch(1_800_000_000 * 1000),
      );
      final summary = hubSubscriptionSummaryOf(subscription);

      expect(summary.lastEventSummary, 'ReceiveProgress: {"pct":50}');
      expect(summary.lastEventAt, 1_800_000_000);
    });

    for (final entry in {
      HubSubscriptionStatus.active: bridge.HubSubscriptionSummaryStatus.active,
      HubSubscriptionStatus.stopped:
          bridge.HubSubscriptionSummaryStatus.stopped,
      HubSubscriptionStatus.failed: bridge.HubSubscriptionSummaryStatus.failed,
    }.entries) {
      test('mapea el estado ${entry.key} a ${entry.value}', () {
        final subscription = _subscription(status: entry.key);
        expect(hubSubscriptionSummaryOf(subscription).status, entry.value);
      });
    }
  });
}
