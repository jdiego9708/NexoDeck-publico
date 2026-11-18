import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Lo que el teléfono escribió y la PC todavía no sabe.
///
/// Es la pieza que hace que el móvil funcione sin conexión: guardar y borrar
/// escriben en el espejo **y** dejan aquí el cambio, que sale hacia la PC en
/// cuanto hay sesión. El nombre y las reglas vienen del único precedente del
/// proyecto, `nexodeck-control/src/outbox.rs`: cola con id por mensaje, y nada
/// se da por entregado hasta que la otra punta lo confirma.
///
/// **No se borra al mandar, sino al recibir el resultado.** Si la sesión se cae
/// entre una cosa y la otra, el cambio sigue aquí y se reintenta; repetir un
/// guardado idéntico no hace daño, perderlo sí.
class NoteOutbox extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// La nota, relativa a la bóveda.
  TextColumn get path => text()();

  /// `save` o `delete`.
  TextColumn get kind => text()();

  /// El texto a guardar. Vacío en un borrado.
  TextColumn get content => text().withDefault(const Constant(''))();

  /// El hash con el que el teléfono vio la nota. Vacío significa "nota nueva":
  /// la PC la crea y **nunca pisa** una que ya exista.
  TextColumn get baseHash => text().withDefault(const Constant(''))();

  /// Para mandar en el mismo orden en que se escribieron. Aplicar una tanda
  /// desordenada dejaría el espejo diciendo algo distinto de la bóveda.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Cuántas veces se intentó. Sirve para no reintentar en bucle algo que la PC
  /// rechaza siempre, y para poder decirlo en pantalla.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Lo último que contestó la PC cuando falló. `null` mientras no haya fallado.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
