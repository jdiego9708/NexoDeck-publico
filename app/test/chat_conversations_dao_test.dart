import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/chat_messages_table.dart';

void main() {
  late NexoDeckDatabase db;
  late ChatConversationsDao dao;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    dao = ChatConversationsDao(db);
  });

  tearDown(() => db.close());

  /// Envejece una conversacion escribiendole la fecha a mano: `archiveStale`
  /// mira `updatedAt`, no `createdAt`.
  Future<void> envejecer(String id, Duration antiguedad) async {
    await db.customStatement(
      'UPDATE chat_conversations SET updated_at = ? WHERE id = ?',
      [
        DateTime.now().subtract(antiguedad).millisecondsSinceEpoch ~/ 1000,
        id,
      ],
    );
  }

  group('el archivado automatico', () {
    test('archives what has been quiet for over a month', () async {
      final vieja = await dao.create('Vieja');
      final reciente = await dao.create('Reciente');
      await envejecer(vieja.id, const Duration(days: 40));

      expect(await dao.archiveStale(), 1);

      expect((await dao.byId(vieja.id))!.archivedAt, isNotNull);
      expect((await dao.byId(reciente.id))!.archivedAt, isNull);
    });

    /// El interruptor de "conservar para siempre" es justo esto: que el
    /// archivado la salte por vieja que sea.
    test('never touches one marked to keep forever', () async {
      final fijada = await dao.create('Fijada');
      await dao.setKeepForever(fijada.id, true);
      await envejecer(fijada.id, const Duration(days: 400));

      expect(await dao.archiveStale(), 0);
      expect((await dao.byId(fijada.id))!.archivedAt, isNull);
    });

    /// Justo en el limite no se archiva: el corte es "mas de un mes", y una
    /// conversacion de hoy mismo nunca puede desaparecer.
    test('a conversation just under the cutoff survives', () async {
      final limite = await dao.create('Al limite');
      await envejecer(limite.id, kArchiveAfter - const Duration(hours: 1));

      expect(await dao.archiveStale(), 0);
      expect((await dao.byId(limite.id))!.archivedAt, isNull);
    });

    /// Es idempotente: correrlo dos veces no vuelve a archivar lo archivado ni
    /// mueve su fecha.
    test('running it twice archives nothing new', () async {
      final vieja = await dao.create('Vieja');
      await envejecer(vieja.id, const Duration(days: 40));

      expect(await dao.archiveStale(), 1);
      expect(await dao.archiveStale(), 0);
    });

    /// **Archivar no borra.** Es la diferencia entera entre esto y perder
    /// datos del usuario sin que los haya pedido borrar.
    test('archiving keeps every message', () async {
      final vieja = await dao.create('Vieja');
      await dao.appendMessage(
        conversationId: vieja.id,
        kind: ChatMessageKind.user,
        content: 'no me pierdas',
        origin: ChatMessageOrigin.local,
        position: 0,
      );
      await envejecer(vieja.id, const Duration(days: 40));
      await dao.archiveStale();

      final mensajes = await dao.messagesOf(vieja.id);
      expect(mensajes, hasLength(1));
      expect(mensajes.single.content, 'no me pierdas');
    });
  });

  group('conservar para siempre', () {
    /// Pedir que se conserve algo que ya estaba archivado tiene que sacarlo
    /// de ahi: conservarlo y dejarlo escondido seria lo contrario de lo
    /// pedido.
    test('marking an archived conversation to keep unarchives it', () async {
      final vieja = await dao.create('Vieja');
      await envejecer(vieja.id, const Duration(days: 40));
      await dao.archiveStale();
      expect((await dao.byId(vieja.id))!.archivedAt, isNotNull);

      await dao.setKeepForever(vieja.id, true);
      final restaurada = (await dao.byId(vieja.id))!;
      expect(restaurada.archivedAt, isNull);
      expect(restaurada.keepForever, isTrue);
    });

    /// Y quitarle la marca NO la archiva de golpe: solo la vuelve a hacer
    /// elegible. Archivarla al instante seria una sorpresa desagradable.
    test('unmarking does not archive it on the spot', () async {
      final fijada = await dao.create('Fijada');
      await dao.setKeepForever(fijada.id, true);
      await dao.setKeepForever(fijada.id, false);
      expect((await dao.byId(fijada.id))!.archivedAt, isNull);
    });
  });

  group('los mensajes', () {
    /// Se ordenan por posicion, no por fecha: dos filas del mismo turno pueden
    /// compartir milisegundo y quedarian barajadas.
    test('come back in the order they were written', () async {
      final conv = await dao.create('Charla');
      for (var i = 0; i < 5; i++) {
        await dao.appendMessage(
          conversationId: conv.id,
          kind: ChatMessageKind.user,
          content: 'mensaje $i',
          origin: ChatMessageOrigin.local,
          position: i,
        );
      }

      final mensajes = await dao.messagesOf(conv.id);
      expect(mensajes.map((m) => m.content), [
        'mensaje 0',
        'mensaje 1',
        'mensaje 2',
        'mensaje 3',
        'mensaje 4',
      ]);
    });

    /// De donde vino el mensaje se guarda: es lo que permite marcar en el chat
    /// los que se escribieron desde el telefono.
    test('remember whether they came from the phone', () async {
      final conv = await dao.create('Charla');
      await dao.appendMessage(
        conversationId: conv.id,
        kind: ChatMessageKind.user,
        content: 'desde el movil',
        origin: ChatMessageOrigin.phone,
        position: 0,
      );
      expect((await dao.messagesOf(conv.id)).single.origin, ChatMessageOrigin.phone);
    });

    /// Guardar un mensaje **marca la conversacion como viva**. Sin esto, una
    /// charla activa se archivaria por tener fecha vieja.
    test('appending one keeps the conversation from going stale', () async {
      final conv = await dao.create('Charla');
      await envejecer(conv.id, const Duration(days: 40));

      await dao.appendMessage(
        conversationId: conv.id,
        kind: ChatMessageKind.user,
        content: 'sigo aca',
        origin: ChatMessageOrigin.local,
        position: 0,
      );

      expect(await dao.archiveStale(), 0);
    });

    /// Borrar la conversacion se lleva sus mensajes. Sin `PRAGMA foreign_keys`
    /// el cascade no correria y quedarian filas huerfanas.
    test('deleting a conversation takes its messages with it', () async {
      final conv = await dao.create('Charla');
      await dao.appendMessage(
        conversationId: conv.id,
        kind: ChatMessageKind.user,
        content: 'chau',
        origin: ChatMessageOrigin.local,
        position: 0,
      );

      await dao.deleteConversation(conv.id);
      expect(await dao.messagesOf(conv.id), isEmpty);
      expect(await dao.byId(conv.id), isNull);
    });
  });
}
