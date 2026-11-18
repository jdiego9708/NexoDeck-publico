import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/devices_table.dart';

import 'manual_host.dart';

/// Entidad de dominio para un dispositivo emparejado -- mismo patron que
/// `DeckAction.fromRow`: envuelve la fila de Drift sin arrastrar detalles
/// de persistencia hacia la UI.
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.certFingerprint,
    required this.lastTransportUsed,
    required this.lastConnectedAt,
    required this.isAuthorized,
    required this.pairedAt,
    required this.manualAddress,
    required this.relayEndpoint,
  });

  factory PairedDevice.fromRow(Device row) => PairedDevice(
    id: row.id,
    name: row.name,
    platform: row.platform,
    certFingerprint: row.certFingerprint,
    lastTransportUsed: row.lastTransportUsed,
    lastConnectedAt: row.lastConnectedAt,
    isAuthorized: row.isAuthorized,
    pairedAt: row.pairedAt,
    // El puerto puede faltar aunque la direccion este: se guardan juntos,
    // pero una fila vieja o editada a mano no tiene por que cumplirlo, y
    // caer al puerto por defecto es lo que el usuario espera.
    manualAddress: row.manualHost == null
        ? null
        : ManualHost(
            host: row.manualHost!,
            port: row.manualPort ?? kDefaultTransportPort,
          ),
    // Los tres llegan juntos (`setRelayOffer` los escribe de a uno), asi
    // que si falta el host no hay tunel que ofrecer.
    relayEndpoint: row.relayHost == null || row.relayTokenHex == null
        ? null
        : (
            host: row.relayHost!,
            port: row.relayPort ?? 58644,
            tokenHex: row.relayTokenHex!,
          ),
  );

  final String id;
  final String name;
  final DevicePlatform platform;
  final String certFingerprint;
  final TransportType? lastTransportUsed;
  final DateTime? lastConnectedAt;
  final bool isAuthorized;
  final DateTime pairedAt;

  /// Direccion fija para alcanzar esta PC sin mDNS (rol Android). `null`
  /// mientras el usuario no escriba ninguna -- el caso normal en la LAN.
  final ManualHost? manualAddress;

  /// Ultimo recurso para alcanzar esta PC (rol Android): el tunel por relay,
  /// si la PC lo tiene prendido. `null` mientras nunca llego un
  /// `RelayOfferReceived`, o si la PC apago el tunel.
  final RelayEndpoint? relayEndpoint;
}

/// A donde y con que token entrar al tunel por relay -- ver
/// `ConnectionEvent.relayOfferReceived` y `RelayRepository.reconnectViaRelay`.
typedef RelayEndpoint = ({String host, int port, String tokenHex});
