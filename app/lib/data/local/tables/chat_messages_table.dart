import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'chat_conversations_table.dart';

/// Que tipo de fila es. Espejo persistente de `ChatEntry`.
///
/// Sellado a proposito: si aparece un tipo nuevo de entrada, esto tiene que
/// romper en compilacion en vez de guardarse como algo que al releer no se
/// sabe pintar.
enum ChatMessageKind { user, assistant, tool, draft, error }

/// De donde salio el mensaje.
///
/// Solo importa en los del usuario, y solo para poder distinguirlos de un
/// vistazo: la conversacion es **una sola** y quien escribio desde donde no
/// cambia nada de como se procesa.
enum ChatMessageOrigin { local, phone }

/// Una fila de una conversacion.
class ChatMessages extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  TextColumn get conversationId =>
      text().references(ChatConversations, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<ChatMessageKind>()();

  /// El texto que se muestra. En una herramienta es su resumen; en un
  /// borrador, su titulo.
  ///
  /// **No se puede llamar `text`**: ese es el nombre del constructor de
  /// columna de Drift (`text()`), y el getter lo taparia. drift_dev no genera
  /// nada para la tabla y el sintoma es que la tabla simplemente no existe,
  /// sin ningun error.
  TextColumn get content => text()();

  TextColumn get origin =>
      textEnum<ChatMessageOrigin>().withDefault(const Constant('local'))();

  /// Lo que no cabe en `text` y hace falta para volver a pintar la fila: el
  /// resultado de una herramienta, o el borrador entero en JSON.
  ///
  /// Se guarda como texto opaco a proposito. Darle columnas propias a cada
  /// tipo obligaria a migrar el esquema cada vez que cambie un borrador, que
  /// es justo lo que mas cambia.
  TextColumn get payload => text().nullable()();

  /// Orden dentro de la conversacion. **No se ordena por `createdAt`**: dos
  /// filas del mismo turno pueden compartir milisegundo y quedarian barajadas
  /// al releer, que en una charla se nota enseguida.
  IntColumn get position => integer()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
