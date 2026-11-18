import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';
import 'package:nexodeck/src/rust/api/hub.dart' as bridge;
import 'package:uuid/uuid.dart';

/// Wrapper sobre las dos DAOs + el bridge. El id de la fila (un UUID
/// generado aca) es TAMBIEN el id que usa Rust para la conexion -- Rust no
/// genera uno propio (ver `nexodeck-hub/src/lib.rs`), asi que un
/// `MessageReceived` que llega por `watchHubEvents()` siempre coincide con
/// una fila que ya existe.
class HubSubscriptionsRepository {
  HubSubscriptionsRepository(this._subscriptionsDao, this._messagesDao);

  /// Eventos de todas las conexiones vivas. Pasa por el repositorio (y no
  /// directo al bridge) para que `HostRuntime` se pueda probar sin FFI.
  Stream<bridge.HubSubscriptionEvent> watchEvents() => bridge.watchHubEvents();

  final HubSubscriptionsDao _subscriptionsDao;
  final HubMessagesDao _messagesDao;

  Stream<List<HubSubscription>> watchAll() => _subscriptionsDao.watchAll();

  Stream<List<HubMessage>> watchMessages(String subscriptionId) =>
      _messagesDao.watchFor(subscriptionId);

  /// Crea la fila y arranca la conexion SignalR. `invokeArgs` son los
  /// valores crudos (sin comillas de JSON) -- `"job-123"`, no `'"job-123"'`.
  Future<String> createSignalR({
    required String name,
    required String baseUrl,
    required String hubPath,
    required String invokeMethod,
    required List<String> invokeArgs,
    bool allowInvalidCert = false,
  }) async {
    const uuid = Uuid();
    final id = uuid.v4();
    await _subscriptionsDao.create(
      HubSubscriptionsCompanion.insert(
        id: Value(id),
        name: name,
        kind: HubSubscriptionKind.signalR,
        baseUrl: baseUrl,
        hubPath: Value(hubPath),
        invokeMethod: Value(invokeMethod),
        invokeArgsJson: Value(jsonEncode(invokeArgs)),
        allowInvalidCert: Value(allowInvalidCert),
        status: const Value(HubSubscriptionStatus.active),
      ),
    );
    await bridge.startHubSubscription(
      subscriptionId: id,
      baseUrl: baseUrl,
      kind: bridge.HubSubscriptionKind.signalR(
        hubPath: hubPath,
        invokeMethod: invokeMethod,
        invokeArgsJson: invokeArgs.map(jsonEncode).toList(),
      ),
      allowInvalidCert: allowInvalidCert,
    );
    return id;
  }

  /// Crea la fila y arranca un WebSocket crudo (sin protocolo SignalR
  /// encima). `wsUrl` es la URL `ws(s)://` completa.
  Future<String> createRawWebSocket({
    required String name,
    required String wsUrl,
    bool allowInvalidCert = false,
  }) async {
    const uuid = Uuid();
    final id = uuid.v4();
    await _subscriptionsDao.create(
      HubSubscriptionsCompanion.insert(
        id: Value(id),
        name: name,
        kind: HubSubscriptionKind.rawWebSocket,
        baseUrl: wsUrl,
        allowInvalidCert: Value(allowInvalidCert),
        status: const Value(HubSubscriptionStatus.active),
      ),
    );
    await bridge.startHubSubscription(
      subscriptionId: id,
      baseUrl: wsUrl,
      kind: const bridge.HubSubscriptionKind.rawWebSocket(),
      allowInvalidCert: allowInvalidCert,
    );
    return id;
  }

  Future<void> stop(String id) async {
    await bridge.stopHubSubscription(subscriptionId: id);
    await _subscriptionsDao.updateStatus(id, HubSubscriptionStatus.stopped);
  }

  /// Repite el flujo de conexion entero con la MISMA configuracion que ya
  /// esta guardada -- no hace falta que el usuario vuelva a escribir nada.
  /// El hueco mientras la app estuvo cerrada (o la suscripcion detenida) es
  /// real: lo que se emitio en ese tiempo no se recupera, esto solo retoma
  /// desde ahora.
  Future<void> restart(HubSubscription subscription) async {
    await bridge.startHubSubscription(
      subscriptionId: subscription.id,
      baseUrl: subscription.baseUrl,
      kind: subscription.kind == HubSubscriptionKind.signalR
          ? bridge.HubSubscriptionKind.signalR(
              hubPath: subscription.hubPath ?? '',
              invokeMethod: subscription.invokeMethod ?? '',
              invokeArgsJson:
                  (jsonDecode(subscription.invokeArgsJson ?? '[]') as List)
                      .map((arg) => jsonEncode(arg))
                      .toList(),
            )
          : const bridge.HubSubscriptionKind.rawWebSocket(),
      allowInvalidCert: subscription.allowInvalidCert,
    );
    await _subscriptionsDao.updateStatus(
      subscription.id,
      HubSubscriptionStatus.active,
    );
  }

  Future<void> delete(String id) async {
    await bridge.removeHubSubscription(subscriptionId: id);
    await _subscriptionsDao.deleteSubscription(id);
  }

  /// Escribe un mensaje recibido y actualiza el estado/`lastEventAt` de la
  /// fila. Lo llama el listener global (`HostRuntime`) por cada
  /// `MessageReceived` que llega del bridge -- Rust nunca toca SQLite.
  Future<void> recordMessage({
    required String subscriptionId,
    required String eventName,
    required String payloadJson,
  }) async {
    final now = DateTime.now();
    await _messagesDao.insert(
      HubMessagesCompanion.insert(
        subscriptionId: subscriptionId,
        eventName: eventName,
        payloadJson: payloadJson,
        receivedAt: Value(now),
      ),
    );
    await _subscriptionsDao.updateStatus(
      subscriptionId,
      HubSubscriptionStatus.active,
      lastEventAt: now,
      lastEventSummary: _summarize(eventName, payloadJson),
    );
  }

  /// `'eventName: payload recortado'`, para el panel remoto de Android
  /// (`HubSubscriptionSummary.lastEventSummary`) -- ese cable manda un
  /// resumen, nunca el JSON completo.
  static String _summarize(String eventName, String payloadJson) {
    const maxPayloadChars = 60;
    final payload = payloadJson.length > maxPayloadChars
        ? '${payloadJson.substring(0, maxPayloadChars)}…'
        : payloadJson;
    return '$eventName: $payload';
  }

  Future<void> markDisconnected(String subscriptionId) =>
      _subscriptionsDao.updateStatus(subscriptionId, HubSubscriptionStatus.failed);

  Future<void> markStopped(String subscriptionId) =>
      _subscriptionsDao.updateStatus(subscriptionId, HubSubscriptionStatus.stopped);

  Future<void> markFailed(String subscriptionId) =>
      _subscriptionsDao.updateStatus(subscriptionId, HubSubscriptionStatus.failed);

  Future<void> markConnected(String subscriptionId) =>
      _subscriptionsDao.updateStatus(subscriptionId, HubSubscriptionStatus.active);
}
