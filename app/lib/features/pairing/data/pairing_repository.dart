import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

/// Envuelve las funciones del bridge relacionadas con el flujo de pairing
/// (ambos roles: host en desktop, cliente en Android). Wrapper delgado a
/// proposito -- toda la logica real vive en `nexodeck-transport` (Rust).
class PairingRepository {
  const PairingRepository();

  Stream<bridge.PairingEvent> watchPairingEvents() =>
      bridge.watchPairingEvents();

  /// Rol PC.
  Future<void> startTransportHost(String deviceName) =>
      bridge.startTransportHost(deviceName: deviceName);

  Future<String> armPairing() => bridge.armPairing();

  Future<void> disarmPairing() => bridge.disarmPairing();

  Future<void> confirmPairing(bool accept) =>
      bridge.confirmPairing(accept: accept);

  Future<String> getServerCertFingerprint() =>
      bridge.getServerCertFingerprint();

  /// Rol Android.
  Stream<bridge.DiscoveredHost> discoverHosts() => bridge.discoverHosts();

  Future<void> connectToHost({
    required String host,
    required int port,
    required String deviceName,
  }) => bridge.connectToHost(host: host, port: port, deviceName: deviceName);

  Future<void> reconnectToHost({
    required String deviceId,
    required String host,
    required int port,
    required String pinnedFingerprint,
  }) => bridge.reconnectToHost(
    deviceId: deviceId,
    host: host,
    port: port,
    pinnedFingerprint: pinnedFingerprint,
  );

  Future<void> sendPairConfirm() => bridge.sendPairConfirm();
}
