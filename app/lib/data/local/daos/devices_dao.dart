import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/devices_table.dart';

part 'devices_dao.g.dart';

@DriftAccessor(tables: [Devices])
class DevicesDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$DevicesDaoMixin {
  DevicesDao(super.db);

  Stream<List<Device>> watchAll() =>
      (select(devices)
            ..orderBy([(d) => OrderingTerm.desc(d.lastConnectedAt)]))
          .watch();

  Future<Device?> getByCertFingerprint(String fingerprint) =>
      (select(
        devices,
      )..where((d) => d.certFingerprint.equals(fingerprint))).getSingleOrNull();

  Future<String> pairDevice(DevicesCompanion entry) async {
    await into(devices).insert(entry);
    return entry.id.value;
  }

  /// Actualizacion parcial (solo `isAuthorized`) -- a proposito NO usa
  /// `.replace()`, que resetearia a null/default cualquier columna ausente
  /// del companion.
  Future<int> setAuthorized(String id, bool isAuthorized) =>
      (update(devices)..where((d) => d.id.equals(id))).write(
        DevicesCompanion(isAuthorized: Value(isAuthorized)),
      );

  /// Direccion fija para alcanzar la PC fuera de la LAN. `null` en las dos
  /// la borra (se vuelve a depender solo de mDNS).
  ///
  /// Update parcial por el mismo motivo que `setAuthorized`: `.replace()`
  /// resetearia a null/default toda columna ausente del companion.
  Future<int> setManualAddress(String id, String? host, int? port) =>
      (update(devices)..where((d) => d.id.equals(id))).write(
        DevicesCompanion(
          manualHost: Value(host),
          manualPort: Value(port),
        ),
      );

  /// Oferta del tunel por relay, escrita al recibir
  /// `ConnectionEvent.relayOfferReceived` -- los tres en `null` la borra
  /// (la PC apago el tunel). Update parcial, mismo motivo que
  /// `setAuthorized`.
  Future<int> setRelayOffer(
    String id, {
    String? host,
    int? port,
    String? tokenHex,
  }) => (update(devices)..where((d) => d.id.equals(id))).write(
    DevicesCompanion(
      relayHost: Value(host),
      relayPort: Value(port),
      relayTokenHex: Value(tokenHex),
    ),
  );

  Future<int> deleteDevice(String id) =>
      (delete(devices)..where((d) => d.id.equals(id))).go();
}
