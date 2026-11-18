import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/chat_conversations_table.dart';
import '../tables/chat_messages_table.dart';

part 'chat_conversations_dao.g.dart';

/// Cuanto tiene que estar quieta una conversacion para archivarse sola.
const kArchiveAfter = Duration(days: 30);

@DriftAccessor(tables: [ChatConversations, ChatMessages])
class ChatConversationsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ChatConversationsDaoMixin {
  ChatConversationsDao(super.db);

  /// Las activas, de la mas reciente a la mas vieja.
  Stream<List<ChatConversation>> watchActive() {
    return (select(chatConversations)
          ..where((c) => c.archivedAt.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]))
        .watch();
  }

  Stream<List<ChatConversation>> watchArchived() {
    return (select(chatConversations)
          ..where((c) => c.archivedAt.isNotNull())
          ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]))
        .watch();
  }

  Future<ChatConversation?> byId(String id) => (select(
    chatConversations,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<ChatConversation> create(String title) async {
    final row = ChatConversationsCompanion.insert(title: title);
    return into(chatConversations).insertReturning(row);
  }

  /// Marca actividad. Es lo que retrasa el archivado: una charla que sigue
  /// viva no se archiva aunque haya empezado hace meses.
  Future<void> touch(String id) =>
      (update(chatConversations)..where((c) => c.id.equals(id))).write(
        ChatConversationsCompanion(updatedAt: Value(DateTime.now())),
      );

  Future<void> rename(String id, String title) =>
      (update(chatConversations)..where((c) => c.id.equals(id)))
          .write(ChatConversationsCompanion(title: Value(title)));

  /// El interruptor de "conservar para siempre".
  ///
  /// Ponerlo **desarchiva**: pedir que algo se conserve y dejarlo escondido
  /// entre lo archivado seria justo lo contrario de lo que el usuario pidio.
  Future<void> setKeepForever(String id, bool keep) =>
      (update(chatConversations)..where((c) => c.id.equals(id))).write(
        ChatConversationsCompanion(
          keepForever: Value(keep),
          archivedAt: keep ? const Value(null) : const Value.absent(),
        ),
      );

  Future<void> setArchived(String id, bool archived) =>
      (update(chatConversations)..where((c) => c.id.equals(id))).write(
        ChatConversationsCompanion(
          archivedAt: Value(archived ? DateTime.now() : null),
        ),
      );

  /// **Lo unico que se borra, y solo si el usuario lo pide.** No hay ninguna
  /// ruta automatica hasta aca: el archivado esconde, no destruye.
  ///
  /// No se llama `delete` porque ese nombre ya es el de Drift
  /// (`delete(tabla)`) y taparlo rompe todo el DAO.
  Future<void> deleteConversation(String id) =>
      (delete(chatConversations)..where((c) => c.id.equals(id))).go();

  /// Archiva lo que lleve mas de [kArchiveAfter] quieto, **saltando lo que el
  /// usuario marco para conservar**. Devuelve cuantas archivo.
  ///
  /// Se calcula el corte en Dart y no con `datetime('now')` en SQL: asi el
  /// test puede fijar la fecha y esto no depende del reloj de sqlite.
  Future<int> archiveStale({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(kArchiveAfter);
    return (update(chatConversations)..where(
          (c) =>
              c.archivedAt.isNull() &
              c.keepForever.equals(false) &
              c.updatedAt.isSmallerThanValue(cutoff),
        ))
        .write(ChatConversationsCompanion(archivedAt: Value(DateTime.now())));
  }

  // ---------------------------------------------------------------
  // Mensajes
  // ---------------------------------------------------------------

  /// Las filas de una conversacion, **en el orden en que se escribieron**.
  ///
  /// Ordenado por `position` y no por `createdAt`: dos filas del mismo turno
  /// pueden compartir milisegundo y quedarian barajadas al releer.
  Future<List<ChatMessage>> messagesOf(String conversationId) {
    return (select(chatMessages)
          ..where((m) => m.conversationId.equals(conversationId))
          ..orderBy([(m) => OrderingTerm.asc(m.position)]))
        .get();
  }

  Future<int> messageCount(String conversationId) async {
    final count = chatMessages.id.count();
    final row =
        await (selectOnly(chatMessages)
              ..addColumns([count])
              ..where(chatMessages.conversationId.equals(conversationId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Guarda una fila y marca la conversacion como viva, en una sola
  /// transaccion: si lo segundo fallara, la conversacion quedaria con un
  /// mensaje nuevo y fecha vieja, y se archivaria estando activa.
  Future<void> appendMessage({
    required String conversationId,
    required ChatMessageKind kind,
    required String content,
    required ChatMessageOrigin origin,
    required int position,
    String? payload,
  }) {
    return transaction(() async {
      await into(chatMessages).insert(
        ChatMessagesCompanion.insert(
          conversationId: conversationId,
          kind: kind,
          content: content,
          origin: Value(origin),
          position: position,
          payload: Value(payload),
        ),
      );
      await touch(conversationId);
    });
  }

  Future<void> clearMessages(String conversationId) =>
      (delete(chatMessages)
            ..where((m) => m.conversationId.equals(conversationId)))
          .go();
}
