import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Una conversacion con el asistente.
///
/// Se guarda entera y **no se borra nunca sola**. Lo unico automatico es
/// archivar: pasado un mes sin tocarla, sale de la lista principal pero sigue
/// estando. Borrar datos del usuario sin que el lo pida es la clase de cosa
/// que no se puede deshacer, asi que no se hace.
class ChatConversations extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// Sale de las primeras palabras del primer mensaje. Es lo unico que hace
  /// reconocible una charla en una lista de treinta.
  TextColumn get title => text()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Cuando entro el ultimo mensaje. **Es lo que decide el archivado**, no
  /// `createdAt`: una conversacion que empezo hace tres meses pero que sigue
  /// viva hoy no tiene por que desaparecer.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// El interruptor de "conservar para siempre". Con esto puesto, el
  /// archivado automatico la salta.
  BoolColumn get keepForever => boolean().withDefault(const Constant(false))();

  /// Cuando se archivo. `null` es "activa". Archivar **no borra**: la
  /// conversacion sigue completa y se puede volver a abrir.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
