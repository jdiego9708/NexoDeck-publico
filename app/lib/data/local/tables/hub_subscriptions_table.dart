import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Como conectar: `signalR` habla el protocolo de hubs de ASP.NET Core
/// (negotiate + handshake + invocar un metodo, ej. `SubscribeToJob`);
/// `rawWebSocket` solo abre el socket y lee lo que llegue, sin protocolo
/// encima. Es la misma distincion que ve el usuario en el formulario
/// "Nueva suscripcion".
enum HubSubscriptionKind { signalR, rawWebSocket }

/// Estado de la conexion, no del registro: la fila sigue existiendo aunque
/// la conexion se haya caido o el usuario la haya detenido a mano -- es lo
/// que permite "Reiniciar" sin tener que volver a cargar el formulario.
enum HubSubscriptionStatus { active, stopped, failed }

/// Una suscripcion en vivo a un hub SignalR o un WebSocket crudo. El
/// mensaje que reciba queda en [HubMessages] -- esta tabla es solo la
/// configuracion + el ultimo estado conocido.
class HubSubscriptions extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// Etiqueta que pone el usuario (ej. "Entrenamiento IA -- tanda K").
  TextColumn get name => text().withLength(min: 1, max: 80)();

  TextColumn get kind => textEnum<HubSubscriptionKind>()();

  /// Origen `http(s)://host:puerto` si `kind = signalR`, o la URL
  /// `ws(s)://` completa si `kind = rawWebSocket`.
  TextColumn get baseUrl => text()();

  /// Solo `signalR`: ej. `/hubs/plant-training-progress`.
  TextColumn get hubPath => text().nullable()();

  /// Solo `signalR`: metodo del hub a invocar apenas conecta, ej.
  /// `SubscribeToJob`.
  TextColumn get invokeMethod => text().nullable()();

  /// Solo `signalR`: JSON de la lista de argumentos (`["job-123"]`).
  TextColumn get invokeArgsJson => text().nullable()();

  /// Acepta un certificado TLS invalido (perfiles `https` de desarrollo con
  /// certificado autofirmado). Apagado por defecto -- prenderlo es una
  /// eleccion explicita del usuario, no un default silencioso.
  BoolColumn get allowInvalidCert =>
      boolean().withDefault(const Constant(false))();

  TextColumn get status =>
      textEnum<HubSubscriptionStatus>().withDefault(const Constant('stopped'))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  DateTimeColumn get lastEventAt => dateTime().nullable()();

  /// Resumen corto del ultimo mensaje recibido (`eventName` + payload
  /// recortado) -- se actualiza junto con `lastEventAt` en `recordMessage`,
  /// nunca se limpia al desconectar/detener. Es lo que viaja en
  /// `HubSubscriptionSummary.lastEventSummary` hacia el panel remoto de
  /// Android sin tener que consultar el historial completo de mensajes.
  TextColumn get lastEventSummary => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
