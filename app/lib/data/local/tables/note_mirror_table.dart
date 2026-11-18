import 'package:drift/drift.dart';

/// La copia local de la bóveda en el móvil.
///
/// **La dueña de la bóveda es la PC.** Esto es un espejo: lo que el teléfono
/// tiene de cada nota y el hash con el que lo recibió, que es lo que permite
/// saber después si la PC la cambió mientras tanto.
///
/// Lleva la bóveda **entera, `privado/` incluida** (decisión del usuario): en el
/// teléfono las notas son suyas, y lo que protege a las privadas es que ningún
/// agente las lee, no que no salgan de la PC.
class NoteMirror extends Table {
  /// Relativa a la bóveda, con `/` y `.md`. Es la identidad de una nota en las
  /// dos puntas.
  TextColumn get path => text()();

  /// El texto, con `\n`. La PC conserva el CRLF y el BOM del fichero al
  /// guardar, así que eso no viaja ni se guarda aquí.
  ///
  /// **No se puede llamar `text`**: ese es el nombre del constructor de columna
  /// de Drift y el getter lo taparía; drift_dev no generaría nada para la tabla
  /// y la tabla simplemente no existiría, sin ningún error (mismo gotcha que
  /// `chat_messages_table.dart`).
  TextColumn get content => text()();

  /// El hash que tenía la nota en la PC cuando llegó. **Es la base de todo
  /// guardado posterior**: con él la PC decide si alguien la tocó mientras el
  /// teléfono estaba sin conexión.
  ///
  /// Vacío en una nota creada aquí que la PC todavía no conoce.
  TextColumn get baseHash => text().withDefault(const Constant(''))();

  /// El hash de lo que hay ahora mismo en `content`. Si difiere de `baseHash`,
  /// hay algo escrito en el teléfono que la PC todavía no tiene.
  TextColumn get localHash => text().withDefault(const Constant(''))();

  /// Está en `privado/`: ningún agente la lee.
  BoolColumn get private => boolean().withDefault(const Constant(false))();

  /// Cuándo cambió en la PC, en segundos desde época (lo que da su sistema de
  /// ficheros). `null` si no lo dijo.
  IntColumn get modifiedSecs => integer().nullable()();

  /// Cuándo se tocó aquí. Ordena la lista del móvil sin depender de la PC.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// La versión de la PC cuando hubo un choque, guardada al lado en vez de
  /// pisar nada. `null` mientras no haya conflicto.
  ///
  /// Decisión del usuario: si la nota cambió en los dos sitios, **se conservan
  /// las dos** y elige él.
  TextColumn get conflictContent => text().nullable()();

  /// El hash de esa versión de la PC. Es el que hay que mandar como base si el
  /// usuario decide quedarse con lo del teléfono.
  TextColumn get conflictHash => text().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}
