import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/devices_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/devices_table.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

import '../domain/manual_host.dart';
import '../domain/paired_device.dart';

/// Convierte el `DevicePlatform` del bridge (Rust) al enum equivalente que
/// ya vive en el esquema de Drift -- son dos tipos con la misma forma pero
/// paquetes distintos, no se puede compartir uno solo entre Rust y Dart.
DevicePlatform devicePlatformFromBridge(bridge.DevicePlatform platform) =>
    switch (platform) {
      bridge.DevicePlatform.android => DevicePlatform.android,
      bridge.DevicePlatform.ios => DevicePlatform.ios,
      bridge.DevicePlatform.windows => DevicePlatform.windows,
      bridge.DevicePlatform.linux => DevicePlatform.linux,
    };

class DevicesRepository {
  DevicesRepository(this._dao);

  final DevicesDao _dao;

  Stream<List<PairedDevice>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(PairedDevice.fromRow).toList());

  /// El `id` viene de Rust (resultado del handshake de pairing), no se
  /// genera del lado Dart -- ver `PairingEvent.pairingSucceeded`.
  Future<void> pairDevice({
    required String id,
    required String name,
    required DevicePlatform platform,
    required String certFingerprint,
    ManualHost? manualAddress,
  }) => _dao.pairDevice(
    DevicesCompanion.insert(
      id: Value(id),
      name: name,
      platform: platform,
      certFingerprint: certFingerprint,
      lastTransportUsed: const Value(TransportType.wifi),
      lastConnectedAt: Value(DateTime.now()),
      // Se guarda ya desde el pairing cuando el emparejamiento se hizo
      // contra una direccion escrita a mano: es el caso de emparejar fuera
      // de la LAN, donde mDNS nunca va a encontrar nada y sin esto la
      // reconexion no tendria a donde ir.
      manualHost: Value(manualAddress?.host),
      manualPort: Value(manualAddress?.port),
    ),
  );

  /// Fija (o borra, con `null`) la direccion manual de una PC ya
  /// emparejada.
  Future<void> setManualAddress(String id, ManualHost? address) =>
      _dao.setManualAddress(id, address?.host, address?.port);

  Future<void> setAuthorized(String id, bool isAuthorized) =>
      _dao.setAuthorized(id, isAuthorized);

  /// Persiste (o borra, con `null`) la oferta del tunel por relay --
  /// llamado desde el manejador de `ConnectionEvent.relayOfferReceived`
  /// (`connected_device_screen.dart`), nunca desde un dialogo del usuario.
  Future<void> setRelayOffer(String id, RelayEndpoint? endpoint) =>
      _dao.setRelayOffer(
        id,
        host: endpoint?.host,
        port: endpoint?.port,
        tokenHex: endpoint?.tokenHex,
      );

  Future<void> deleteDevice(String id) => _dao.deleteDevice(id);
}
