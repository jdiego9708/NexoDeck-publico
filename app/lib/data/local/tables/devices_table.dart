import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

enum DevicePlatform { android, ios, windows, linux }

enum TransportType { usb, ble, wifi }

/// Dispositivos emparejados (tablet/celular usados como panel remoto).
@TableIndex(name: 'idx_devices_cert_fingerprint', columns: {#certFingerprint})
class Devices extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// "Tablet de Juan" o modelo detectado.
  TextColumn get name => text()();
  TextColumn get platform => textEnum<DevicePlatform>()();

  /// Huella del certificado TLS fijado en el pairing (certificate pinning).
  TextColumn get certFingerprint => text()();

  TextColumn get lastTransportUsed => textEnum<TransportType>().nullable()();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();

  /// Revocable sin borrar el dispositivo -- conserva el historial.
  BoolColumn get isAuthorized =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get pairedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Direccion fija escrita a mano por el usuario (IP o hostname), para
  /// alcanzar la PC cuando mDNS no puede: fuera de la LAN, tipicamente por
  /// una VPN mesh tipo Tailscale.
  ///
  /// Es STICKY a proposito -- no se pisa con la direccion de cada conexion
  /// exitosa. La IP de la LAN la da el DHCP y cambia; la que el usuario
  /// escribio es justamente la que no cambia, y sobrescribirla al volver a
  /// casa dejaria el camino de datos moviles roto sin ningun aviso.
  TextColumn get manualHost => text().nullable()();
  IntColumn get manualPort => integer().nullable()();

  /// Oferta del tunel por relay que la PC manda en cada sesion
  /// (`ConnectionEvent.relayOfferReceived`) -- a diferencia de
  /// `manualHost`/`manualPort` (los escribe el usuario), esto lo escribe
  /// solo el manejador del evento. `null` mientras la PC nunca prendio el
  /// tunel, o si lo apago (llega `host` vacio y se limpian los tres).
  TextColumn get relayHost => text().nullable()();
  IntColumn get relayPort => integer().nullable()();
  TextColumn get relayTokenHex => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
