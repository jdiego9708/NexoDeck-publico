import 'package:nexodeck/src/rust/api/relay.dart' as bridge;

/// Envuelve las funciones del bridge del tunel por relay (`api/relay.rs`).
/// Wrapper delgado, mismo patron que `ConnectionRepository`/
/// `PairingRepository` -- toda la logica real vive en `nexodeck-transport`.
class RelayRepository {
  const RelayRepository();

  /// Rol PC: genera el secreto del tunel (32 bytes en hex). No lo persiste
  /// por si solo -- quien llama decide si lo guarda.
  Future<String> generateToken() => bridge.generateRelayToken();

  /// Rol PC: enciende el tunel. No reemplaza la LAN, agrega un camino mas.
  Future<void> startTunnel({
    required String host,
    required int port,
    required String tokenHex,
  }) => bridge.startRelayTunnel(host: host, port: port, tokenHex: tokenHex);

  /// Rol PC: apaga el tunel. La LAN sigue funcionando igual.
  Future<void> stopTunnel() => bridge.stopRelayTunnel();

  /// Rol PC: en que anda el tunel ahora mismo (Parked/Matched/Failed/Stopped).
  Stream<bridge.RelayStatus> watchStatus() => bridge.watchRelayStatus();

  /// Rol Android: reconexion a traves del tunel -- ultimo recurso, despues
  /// de que mDNS y la direccion manual fallen (ver `_maybeReconnect` en
  /// `connected_device_screen.dart`).
  Future<void> reconnectViaRelay({
    required String deviceId,
    required String host,
    required int port,
    required String tokenHex,
    required String pinnedFingerprint,
  }) => bridge.reconnectViaRelay(
    deviceId: deviceId,
    host: host,
    port: port,
    tokenHex: tokenHex,
    pinnedFingerprint: pinnedFingerprint,
  );
}
