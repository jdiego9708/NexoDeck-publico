import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/core/di/database_provider.dart';
import 'package:nexodeck/data/local/daos/notes_mirror_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;
import 'package:uuid/uuid.dart';

import '../data/notes_sync_repository.dart';
import '../domain/note_sync.dart';

final notesSyncRepositoryProvider = Provider<NotesSyncRepository>(
  (ref) => const NotesSyncRepository(),
);

final notesMirrorDaoProvider = Provider<NotesMirrorDao>(
  (ref) => NotesMirrorDao(ref.watch(databaseProvider)),
);

/// El motor que arranca `main()` en Android, para que la pantalla de notas
/// guarde por él. `null` fuera de Android o antes de arrancar.
final notesSyncEngineProvider = StateProvider<NotesSyncEngine?>((ref) => null);

/// Lo que la pantalla de notas del móvil necesita saber para poder decirlo.
final notesSyncStatusProvider = StateProvider<NotesSyncStatus>(
  (ref) => const NotesSyncStatus(),
);

class NotesSyncStatus {
  const NotesSyncStatus({
    this.online = false,
    this.syncing = false,
    this.lastError,
    this.lastSyncAt,
  });

  /// Hay sesión con la PC ahora mismo.
  final bool online;

  final bool syncing;

  /// El último fallo. Se conserva aunque vuelva la conexión: es lo que permite
  /// decir por qué una nota sigue pendiente.
  final String? lastError;

  final DateTime? lastSyncAt;

  NotesSyncStatus copyWith({
    bool? online,
    bool? syncing,
    Object? lastError = _keep,
    DateTime? lastSyncAt,
  }) => NotesSyncStatus(
    online: online ?? this.online,
    syncing: syncing ?? this.syncing,
    lastError: identical(lastError, _keep)
        ? this.lastError
        : lastError as String?,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );
}

const Object _keep = Object();

/// La PC contestó que la petición entera no se pudo atender.
class NotesSyncException implements Exception {
  const NotesSyncException(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

/// Mantiene la copia local de la bóveda al día con la PC.
///
/// **Vive fuera del árbol de widgets**, arrancado desde `main()`, por la misma
/// razón que `HostRuntime`: lo que el usuario escribió sin cobertura tiene que
/// salir hacia la PC en cuanto haya sesión, esté o no montada la pantalla de
/// notas. Un widget solo escucha mientras está montado.
///
/// El orden de una vuelta no es casual:
///
/// 1. **Primero se vacía la cola** de lo que el teléfono escribió. Así el
///    manifiesto que llega después ya incluye esos guardados y no se piden de
///    vuelta para nada.
/// 2. **Después se pide el manifiesto** y se compara con la copia local
///    (`planNoteSync`).
/// 3. **Al final se piden los textos** de lo que de verdad cambió, en lotes.
///
/// Nada de esto pisa trabajo del usuario: un choque conserva las dos versiones
/// y elige él (`NotesMirrorDao.applyFromHost` y `recordConflict`).
class NotesSyncEngine {
  NotesSyncEngine(
    this._container, {
    Duration replyTimeout = const Duration(seconds: 30),
  }) : _replyTimeout = replyTimeout;

  /// Cuántos textos se piden de una vez. Con la bóveda entera en una sola
  /// petición, el primer arranque mandaría un mensaje de megabytes por datos
  /// móviles; de uno en uno serían mil idas y vueltas.
  static const int _fetchBatch = 40;

  final ProviderContainer _container;

  /// La PC puede tardar: la lectura de la bóveda va a `spawn_blocking` y el
  /// enlace puede ser un túnel. Lo que no puede es dejar una petición colgada
  /// para siempre, que es lo que bloquearía la vuelta siguiente.
  final Duration _replyTimeout;

  final Map<String, Completer<bridge.NotesReply>> _pending = {};
  StreamSubscription<bridge.ConnectionEvent>? _subscription;
  bool _online = false;
  bool _syncing = false;
  bool _again = false;
  bool _started = false;

  NotesSyncRepository get _repository =>
      _container.read(notesSyncRepositoryProvider);

  NotesMirrorDao get _dao => _container.read(notesMirrorDaoProvider);

  void start() {
    if (_started) return;
    _started = true;
    // Suscripción directa al stream, nunca `ref.listen`: dos `NotesChanged`
    // seguidos son `==` y Riverpod descartaría el segundo, que es justo el que
    // traería el último guardado.
    _subscription = _repository.watchConnectionEvents().listen(
      _onEvent,
      onError: (Object error) => _fail(error.toString()),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _failPending('la aplicación se cerró');
    _started = false;
  }

  void _onEvent(bridge.ConnectionEvent event) {
    switch (event) {
      case bridge.ConnectionEvent_Connected():
        _online = true;
        _status((s) => s.copyWith(online: true));
        unawaited(sync());
      case bridge.ConnectionEvent_Disconnected():
        _online = false;
        _status((s) => s.copyWith(online: false));
        // Sin sesión, lo que estaba esperando respuesta no la va a recibir
        // nunca. Dejarlo colgado hasta el timeout retrasaría la vuelta
        // siguiente justo cuando vuelva la conexión.
        _failPending('se perdió la conexión con la PC');
      case bridge.ConnectionEvent_NotesChanged():
        unawaited(sync());
      case bridge.ConnectionEvent_NotesResponseReceived(
        :final requestId,
        :final response,
      ):
        _onReply(requestId, response);
      default:
        break;
    }
  }

  void _onReply(String requestId, bridge.NotesReply response) {
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    switch (response) {
      // `Failed` es la petición entera sin atender (por ejemplo, la PC todavía
      // no tiene bóveda enganchada). Corta la vuelta en vez de seguir con datos
      // a medias.
      case bridge.NotesReply_Failed(:final detail):
        completer.completeError(NotesSyncException(detail));
      default:
        completer.complete(response);
    }
  }

  /// Manda una petición y espera **su** respuesta, correlacionada por id.
  Future<bridge.NotesReply> _ask(
    Future<void> Function(String requestId) send,
  ) async {
    final requestId = const Uuid().v4();
    final completer = Completer<bridge.NotesReply>();
    _pending[requestId] = completer;
    try {
      await send(requestId);
    } catch (error) {
      _pending.remove(requestId);
      rethrow;
    }
    return completer.future.timeout(
      _replyTimeout,
      onTimeout: () {
        _pending.remove(requestId);
        throw const NotesSyncException('la PC no contestó a tiempo');
      },
    );
  }

  void _failPending(String detail) {
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) {
        completer.completeError(NotesSyncException(detail));
      }
    }
  }

  /// Una vuelta entera. Los avisos que lleguen mientras corre se juntan en una
  /// vuelta más, en vez de encadenar una sincronización por aviso: cada
  /// guardado de la PC emite `NotesChanged`, y escribiendo seguido eso serían
  /// varias por segundo.
  Future<void> sync() async {
    if (!_online) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    _status((s) => s.copyWith(syncing: true));
    try {
      do {
        _again = false;
        await _drainOutbox();
        await _pullChanges();
      } while (_again && _online);
      _status(
        (s) => s.copyWith(
          syncing: false,
          lastError: null,
          lastSyncAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _fail(error.toString());
    } finally {
      _syncing = false;
    }
  }

  /// Manda lo que el teléfono escribió, en tanda y en orden, y aplica lo que la
  /// PC conteste de cada cambio.
  Future<void> _drainOutbox() async {
    final pending = await _dao.pending();
    if (pending.isEmpty) return;

    final reply = await _ask(
      (id) =>
          _repository.requestApply(id, [for (final row in pending) _toOp(row)]),
    );
    if (reply is! bridge.NotesReply_Applied) return;

    // Los resultados vienen en el mismo orden que se mandaron, así que cada uno
    // se casa con su fila por posición. Si llegaran menos (no debería), las
    // filas restantes se quedan en la cola y se reintentan.
    for (final (index, result) in reply.results.indexed) {
      if (index >= pending.length) break;
      final row = pending[index];
      switch (result) {
        case bridge.NoteOpResult_Saved(:final hash):
          await _dao.confirmSaved(row.id, row.path, hash);
        case bridge.NoteOpResult_Deleted():
          await _dao.confirmDeleted(row.id);
        // La nota cambió en la PC mientras el teléfono estaba sin cobertura. No
        // se escribió nada allí: se conservan las dos y elige el usuario.
        //
        // En un borrado la fila del espejo ya no existe, así que esto no
        // guarda nada visible; la nota vuelve igual en el `_pullChanges` de
        // esta misma vuelta, porque sigue en el manifiesto y no en la copia.
        case bridge.NoteOpResult_Conflict(:final diskText, :final diskHash):
          await _dao.recordConflict(
            id: row.id,
            path: row.path,
            diskText: diskText,
            diskHash: diskHash,
          );
        case bridge.NoteOpResult_Failed(:final detail):
          await _dao.recordFailure(row.id, detail);
          await _dao.markAttempt(row.id, row.attempts + 1);
      }
    }
  }

  /// Pide el manifiesto, compara con la copia local y trae solo lo que cambió.
  Future<void> _pullChanges() async {
    final reply = await _ask(_repository.requestManifest);
    if (reply is! bridge.NotesReply_Manifest) return;

    final manifest = reply.notes;
    final mirror = await _dao.all();
    final plan = planNoteSync(
      manifest: [
        for (final note in manifest)
          NoteStampView(path: note.path, hash: note.hash),
      ],
      mirror: [
        for (final note in mirror)
          NoteMirrorView(
            path: note.path,
            baseHash: note.baseHash,
            dirty: note.localHash != note.baseHash,
          ),
      ],
    );

    for (final path in plan.remove) {
      await _dao.removeFromHost(path);
    }
    if (plan.fetch.isEmpty) return;

    // La fecha de modificación solo viaja en el manifiesto, no con el texto.
    final stamps = {for (final note in manifest) note.path: note};

    for (var start = 0; start < plan.fetch.length; start += _fetchBatch) {
      final batch = plan.fetch.sublist(
        start,
        math.min(start + _fetchBatch, plan.fetch.length),
      );
      final fetched = await _ask((id) => _repository.requestFetch(id, batch));
      if (fetched is! bridge.NotesReply_Fetch) continue;
      for (final note in fetched.notes) {
        // Una nota que ya no existe no es un error: es lo que hace falta saber
        // para quitarla de la copia.
        if (!note.exists) {
          await _dao.removeFromHost(note.path);
          continue;
        }
        await _dao.applyFromHost(
          path: note.path,
          content: note.text,
          hash: note.hash,
          private: note.private,
          modifiedSecs: stamps[note.path]?.modifiedSecs?.toInt(),
        );
      }
    }
  }

  static bridge.NoteOp _toOp(NoteOutboxData row) {
    // Vacío significa "nota nueva": la PC la crea y nunca pisa una existente.
    final baseHash = row.baseHash.isEmpty ? null : row.baseHash;
    return row.kind == kNoteOpDelete
        ? bridge.NoteOp.delete(path: row.path, baseHash: baseHash)
        : bridge.NoteOp.save(
            path: row.path,
            text: row.content,
            baseHash: baseHash,
          );
  }

  // --- Lo que la pantalla de notas del móvil llama ---------------------------

  /// El usuario guardó. Entra en la copia local y en la cola **en la misma
  /// transacción**, y se intenta mandar en el acto: sin conexión se queda
  /// esperando y sale al reconectar, sin que quien escribe note la diferencia.
  Future<void> saveNote(String path, String content) async {
    await _dao.saveLocal(path, content, localNoteHash(content));
    unawaited(sync());
  }

  Future<void> deleteNote(String path) async {
    await _dao.deleteLocal(path);
    unawaited(sync());
  }

  /// El usuario resolvió un choque quedándose con lo del teléfono.
  Future<void> keepMine(String path) async {
    await _dao.keepMine(path);
    unawaited(sync());
  }

  /// El usuario resolvió un choque quedándose con lo de la PC. No manda nada:
  /// la bóveda ya tiene esa versión.
  Future<void> takeHost(String path) => _dao.takeHost(path);

  void _fail(String detail) =>
      _status((s) => s.copyWith(syncing: false, lastError: detail));

  void _status(NotesSyncStatus Function(NotesSyncStatus) update) {
    final notifier = _container.read(notesSyncStatusProvider.notifier);
    notifier.state = update(notifier.state);
  }
}
