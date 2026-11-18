import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';

/// Cubre la capa de persistencia (tablas + DAOs) sin tocar el bridge de
/// Rust: crear/detener/reiniciar de verdad necesita el cliente SignalR
/// nativo, que no esta disponible bajo `flutter test`. Lo que si se puede
/// (y vale la pena) verificar aca: el esquema, el cascade de borrado y las
/// consultas de las dos DAOs nuevas.
void main() {
  late NexoDeckDatabase db;
  late HubSubscriptionsDao subscriptionsDao;
  late HubMessagesDao messagesDao;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    subscriptionsDao = HubSubscriptionsDao(db);
    messagesDao = HubMessagesDao(db);
  });

  tearDown(() => db.close());

  HubSubscriptionsCompanion signalRSubscription(String id, {DateTime? createdAt}) =>
      HubSubscriptionsCompanion.insert(
        id: Value(id),
        name: 'Entrenamiento IA',
        kind: HubSubscriptionKind.signalR,
        baseUrl: 'http://localhost:5242',
        hubPath: const Value('/hubs/plant-training-progress'),
        invokeMethod: const Value('SubscribeToJob'),
        invokeArgsJson: const Value('["job-1"]'),
        status: const Value(HubSubscriptionStatus.active),
        createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
      );

  test('la suscripcion nueva arranca activa y sin ultimo evento', () async {
    await subscriptionsDao.create(signalRSubscription('sub-1'));

    final subscription = await subscriptionsDao.getById('sub-1');
    expect(subscription, isNotNull);
    expect(subscription!.status, HubSubscriptionStatus.active);
    expect(subscription.lastEventAt, isNull);
  });

  test('watchAll trae la mas reciente primero', () async {
    // `DateTimeColumn` guarda con resolucion de segundos -- fechas
    // explicitas y bien separadas, no un delay real, es lo que hace el test
    // determinista.
    await subscriptionsDao.create(
      signalRSubscription('sub-old', createdAt: DateTime(2026, 1, 1, 10, 0, 0)),
    );
    await subscriptionsDao.create(
      signalRSubscription('sub-new', createdAt: DateTime(2026, 1, 1, 10, 0, 5)),
    );

    final list = await subscriptionsDao.watchAll().first;
    expect(list.map((s) => s.id).toList(), ['sub-new', 'sub-old']);
  });

  test('updateStatus actualiza el estado y el ultimo evento', () async {
    await subscriptionsDao.create(signalRSubscription('sub-1'));
    // Truncado a segundos: es la resolucion real que guarda la columna.
    final now = DateTime.fromMillisecondsSinceEpoch(
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    );

    await subscriptionsDao.updateStatus(
      'sub-1',
      HubSubscriptionStatus.failed,
      lastEventAt: now,
    );

    final subscription = await subscriptionsDao.getById('sub-1');
    expect(subscription!.status, HubSubscriptionStatus.failed);
    expect(subscription.lastEventAt, now);
  });

  test(
    'borrar la suscripcion se lleva su historial (cascade), no las de otras',
    () async {
      await subscriptionsDao.create(signalRSubscription('sub-1'));
      await subscriptionsDao.create(signalRSubscription('sub-2'));
      await messagesDao.insert(
        HubMessagesCompanion.insert(
          subscriptionId: 'sub-1',
          eventName: 'ReceivePlantTrainingProgress',
          payloadJson: '[{"pct":10}]',
        ),
      );
      await messagesDao.insert(
        HubMessagesCompanion.insert(
          subscriptionId: 'sub-2',
          eventName: 'ReceivePlantTrainingProgress',
          payloadJson: '[{"pct":20}]',
        ),
      );

      await subscriptionsDao.deleteSubscription('sub-1');

      expect(await messagesDao.watchFor('sub-1').first, isEmpty);
      expect(await messagesDao.watchFor('sub-2').first, hasLength(1));
      expect(await subscriptionsDao.getById('sub-1'), isNull);
    },
  );

  test('watchFor devuelve los mensajes del mas nuevo al mas viejo', () async {
    await subscriptionsDao.create(signalRSubscription('sub-1'));
    await messagesDao.insert(
      HubMessagesCompanion.insert(
        subscriptionId: 'sub-1',
        eventName: 'ReceivePlantTrainingProgress',
        payloadJson: '[{"pct":10}]',
        receivedAt: Value(DateTime(2026, 1, 1, 10, 0, 0)),
      ),
    );
    await messagesDao.insert(
      HubMessagesCompanion.insert(
        subscriptionId: 'sub-1',
        eventName: 'ReceivePlantTrainingProgress',
        payloadJson: '[{"pct":20}]',
        receivedAt: Value(DateTime(2026, 1, 1, 10, 0, 5)),
      ),
    );

    final messages = await messagesDao.watchFor('sub-1').first;
    expect(messages.map((m) => m.payloadJson).toList(), [
      '[{"pct":20}]',
      '[{"pct":10}]',
    ]);
  });
}
