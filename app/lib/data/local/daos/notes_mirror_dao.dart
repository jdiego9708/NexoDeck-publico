import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/note_mirror_table.dart';
import '../tables/note_outbox_table.dart';

part 'notes_mirror_dao.g.dart';

/// Tipos de cambio que caben en la cola.
const kNoteOpSave = 'save';
const kNoteOpDelete = 'delete';

/// La copia local de la bóveda y la cola de lo que falta mandar.
///
/// **Escribir aquí nunca depende de la red.** Guardar y borrar tocan el espejo y
/// dejan el cambio en la cola en la MISMA transacción: si solo se hiciera lo
/// primero, el teléfono mostraría algo que la PC nunca va a saber; si solo lo
/// segundo, la pantalla no reflejaría lo que el usuario acaba de escribir.
///
/// El método de borrar no se llama `delete`: ese nombre ya es el de Drift
/// (`delete(tabla)`) y taparlo rompe el DAO entero (mismo gotcha que
/// `ChatConversationsDao.deleteConversation`).
@DriftAccessor(tables: [NoteMirror, NoteOutbox])
class NotesMirrorDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$NotesMirrorDaoMixin {
  NotesMirrorDao(super.db);

  /// Las notas del espejo, de la tocada más recientemente a la más vieja.
  Stream<List<NoteMirrorData>> watchAll() =>
      (select(noteMirror)..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .watch();

  Stream<NoteMirrorData?> watchOne(String path) =>
      (select(noteMirror)..where((n) => n.path.equals(path)))
          .watchSingleOrNull();

  Future<NoteMirrorData?> byPath(String path) =>
      (select(noteMirror)..where((n) => n.path.equals(path))).getSingleOrNull();

  Future<List<NoteMirrorData>> all() => select(noteMirror).get();

  /// Las notas con un choque sin resolver: cambiaron aquí y en la PC.
  Stream<List<NoteMirrorData>> watchConflicts() =>
      (select(noteMirror)..where((n) => n.conflictHash.isNotNull())).watch();

  /// Lo que falta mandar, en el orden en que se escribió.
  Future<List<NoteOutboxData>> pending() =>
      (select(noteOutbox)..orderBy([(o) => OrderingTerm.asc(o.createdAt)])).get();

  Stream<int> watchPendingCount() {
    final count = noteOutbox.id.count();
    final query = selectOnly(noteOutbox)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// El usuario escribió una nota. Entra en el espejo y en la cola.
  ///
  /// `localHash` guarda lo que hay ahora; `baseHash` no se toca, porque sigue
  /// siendo la versión de la PC sobre la que se está escribiendo.
  Future<void> saveLocal(String path, String content, String localHash) {
    return transaction(() async {
      final existing = await byPath(path);
      await into(noteMirror).insertOnConflictUpdate(
        NoteMirrorCompanion.insert(
          path: path,
          content: content,
          baseHash: Value(existing?.baseHash ?? ''),
          localHash: Value(localHash),
          private: Value(existing?.private ?? _looksPrivate(path)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _enqueue(path, kNoteOpSave, content, existing?.baseHash ?? '');
    });
  }

  /// El usuario borró una nota. Desaparece del espejo y el borrado va a la cola.
  Future<void> deleteLocal(String path) {
    return transaction(() async {
      final existing = await byPath(path);
      await (delete(noteMirror)..where((n) => n.path.equals(path))).go();
      await _enqueue(path, kNoteOpDelete, '', existing?.baseHash ?? '');
    });
  }

  /// Lo que llegó de la PC: se escribe tal cual y queda como base.
  ///
  /// **No pisa una nota con cambios sin mandar**: si el espejo tiene algo que la
  /// PC no conoce, se guarda la versión de la PC al lado como conflicto y elige
  /// el usuario.
  Future<void> applyFromHost({
    required String path,
    required String content,
    required String hash,
    required bool private,
    int? modifiedSecs,
  }) {
    return transaction(() async {
      final existing = await byPath(path);
      final dirty = existing != null && existing.localHash != existing.baseHash;
      if (dirty && existing.localHash != hash) {
        await (update(noteMirror)..where((n) => n.path.equals(path))).write(
          NoteMirrorCompanion(
            conflictContent: Value(content),
            conflictHash: Value(hash),
            modifiedSecs: Value(modifiedSecs),
          ),
        );
        return;
      }
      await into(noteMirror).insertOnConflictUpdate(
        NoteMirrorCompanion.insert(
          path: path,
          content: content,
          baseHash: Value(hash),
          localHash: Value(hash),
          private: Value(private),
          modifiedSecs: Value(modifiedSecs),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// La PC dice que esa nota ya no está.
  Future<void> removeFromHost(String path) =>
      (delete(noteMirror)..where((n) => n.path.equals(path))).go();

  /// La PC aceptó el cambio: deja de estar pendiente y su hash pasa a ser la
  /// base. Si el usuario siguió escribiendo mientras tanto, el texto local se
  /// respeta y solo se actualiza la base.
  Future<void> confirmSaved(String id, String path, String hash) {
    return transaction(() async {
      await (delete(noteOutbox)..where((o) => o.id.equals(id))).go();
      final existing = await byPath(path);
      if (existing == null) return;
      final stillPending = await (select(
        noteOutbox,
      )..where((o) => o.path.equals(path))).get();
      await (update(noteMirror)..where((n) => n.path.equals(path))).write(
        NoteMirrorCompanion(
          baseHash: Value(hash),
          // Sin nada más en la cola para esta nota, lo de aquí es exactamente
          // lo que quedó en la PC.
          localHash: stillPending.isEmpty ? Value(hash) : const Value.absent(),
        ),
      );
    });
  }

  Future<void> confirmDeleted(String id) =>
      (delete(noteOutbox)..where((o) => o.id.equals(id))).go();

  /// La PC rechazó el cambio porque la nota cambió allí. Se conservan las dos
  /// versiones y el cambio sale de la cola: reintentarlo volvería a chocar.
  Future<void> recordConflict({
    required String id,
    required String path,
    required String diskText,
    required String diskHash,
  }) {
    return transaction(() async {
      await (delete(noteOutbox)..where((o) => o.id.equals(id))).go();
      await (update(noteMirror)..where((n) => n.path.equals(path))).write(
        NoteMirrorCompanion(
          conflictContent: Value(diskText),
          conflictHash: Value(diskHash),
        ),
      );
    });
  }

  /// El cambio falló por algo que puede ser pasajero. Se queda en la cola con el
  /// motivo, para reintentar y para poder decirlo en pantalla.
  Future<void> recordFailure(String id, String detail) =>
      (update(noteOutbox)..where((o) => o.id.equals(id))).write(
        NoteOutboxCompanion(
          lastError: Value(detail),
          attempts: const Value.absent(),
        ),
      );

  Future<void> markAttempt(String id, int attempts) =>
      (update(noteOutbox)..where((o) => o.id.equals(id)))
          .write(NoteOutboxCompanion(attempts: Value(attempts)));

  /// El usuario eligió quedarse con lo del teléfono: se manda encima de la
  /// versión de la PC, usando su hash como base.
  Future<void> keepMine(String path) {
    return transaction(() async {
      final existing = await byPath(path);
      if (existing == null) return;
      await (update(noteMirror)..where((n) => n.path.equals(path))).write(
        NoteMirrorCompanion(
          baseHash: Value(existing.conflictHash ?? existing.baseHash),
          conflictContent: const Value(null),
          conflictHash: const Value(null),
        ),
      );
      await _enqueue(
        path,
        kNoteOpSave,
        existing.content,
        existing.conflictHash ?? existing.baseHash,
      );
    });
  }

  /// El usuario eligió la versión de la PC: se descarta lo local.
  Future<void> takeHost(String path) {
    return transaction(() async {
      final existing = await byPath(path);
      if (existing?.conflictHash == null) return;
      await (delete(noteOutbox)..where((o) => o.path.equals(path))).go();
      await (update(noteMirror)..where((n) => n.path.equals(path))).write(
        NoteMirrorCompanion(
          content: Value(existing!.conflictContent ?? existing.content),
          baseHash: Value(existing.conflictHash!),
          localHash: Value(existing.conflictHash!),
          conflictContent: const Value(null),
          conflictHash: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Un cambio nuevo reemplaza al que hubiera pendiente **de la misma nota**:
  /// mandar tres versiones intermedias de lo que el usuario acaba de escribir
  /// sería gastar el enlace para que la PC guarde tres veces seguidas.
  Future<void> _enqueue(
    String path,
    String kind,
    String content,
    String baseHash,
  ) async {
    await (delete(noteOutbox)..where((o) => o.path.equals(path))).go();
    await into(noteOutbox).insert(
      NoteOutboxCompanion.insert(
        path: path,
        kind: kind,
        content: Value(content),
        baseHash: Value(baseHash),
      ),
    );
  }

  static bool _looksPrivate(String path) =>
      path.toLowerCase().split('/').contains('privado');
}
