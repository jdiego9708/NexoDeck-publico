import 'dart:async';
import 'dart:convert';

import '../domain/mobile_notes_page.dart';
import '../domain/note_sync.dart';

/// Lo que el anfitrión del móvil necesita de la copia local. Lo implementa el
/// motor de sincronización sobre Drift; los tests, un falso en memoria.
abstract class MobileNotesStore {
  Future<List<MirrorNote>> all();
  Future<MirrorNote?> byPath(String path);

  /// Avisa cada vez que cambia algo del espejo (lo escrito aquí o lo que llega
  /// de la PC).
  Stream<void> changes();

  /// Guarda en el espejo y en la cola; sale hacia la PC cuando haya sesión.
  Future<void> save(String path, String content);
  Future<void> keepMine(String path);
  Future<void> takeHost(String path);

  /// Pide una vuelta de sincronización. Sin conexión no hace nada.
  Future<void> sync();
}

/// Hace en el teléfono lo que `session.rs` hace en la PC: contestar a la página
/// del editor. Pero **contra la copia local**, que es la decisión del usuario:
/// en el móvil se lee y se escribe siempre en el espejo, haya o no conexión, y
/// la sincronización va aparte.
///
/// Quedan fuera, a propósito (petición del usuario: lo básico en el móvil),
/// el asistente, importar y exportar y las carpetas: la página ni los enseña.
class MobileNotesHost {
  MobileNotesHost({
    required MobileNotesStore store,
    required void Function(Map<String, Object?> message) send,
    DateTime Function() now = DateTime.now,
  }) : _store = store,
       _send = send,
       _now = now;

  final MobileNotesStore _store;
  final void Function(Map<String, Object?> message) _send;
  final DateTime Function() _now;

  StreamSubscription<void>? _changes;
  Timer? _debounce;
  String? _current;

  /// El hash con el que se cargó o se guardó la nota abierta: si el espejo
  /// cambia a otra cosa (llegó de la PC), hay que volver a cargarla.
  String? _currentHash;
  bool _dirty = false;
  String _lastOverview = '';

  String? get currentPath => _current;

  void start() {
    _changes ??= _store.changes().listen((_) {
      // Una vuelta de sincronización escribe muchas filas seguidas: se redibuja
      // una vez, no una por nota.
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_mirrorChanged()),
      );
    });
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _changes?.cancel();
    _changes = null;
  }

  /// Un mensaje de la página, en crudo.
  Future<void> receive(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    try {
      await _handle(decoded);
    } catch (error) {
      _send({'type': 'error', 'message': '$error'});
    }
  }

  Future<void> _handle(Map<String, Object?> message) async {
    switch (message['type']) {
      case 'ready':
        _lastOverview = '';
        await _pushOverview();
        if (_current != null) await _open(_current!);
      case 'openNote':
        await _open(message['path']! as String);
      case 'save':
        await _save(
          message['path']! as String,
          message['text']! as String,
          message['reason'] as String?,
        );
      case 'dirty':
        _dirty = message['dirty'] == true;
      case 'createNote':
        await _create(
          message['path']! as String,
          newNoteText(message['title'] as String? ?? ''),
        );
      case 'openDaily':
        final (path, text) = dailyNote(_now());
        await _create(path, text);
      case 'openLink':
        final notes = await _store.all();
        final target = message['target']! as String;
        final resolved = resolveMobileLink(notes, target, _current);
        if (resolved != null) {
          await _open(resolved);
        } else {
          // Como en Obsidian: un enlace a una nota que no existe la crea.
          await _create(newNotePathForLink(target, _current), '');
        }
      case 'search':
        final query = message['query'] as String? ?? '';
        final hits = searchNotes(await _store.all(), query);
        _send({'type': 'searchResults', 'query': query, 'hits': hits});
      case 'requestDetails':
        final path = message['path']! as String;
        _send({
          'type': 'details',
          'details': mobileDetails(await _store.all(), path),
        });
      case 'refresh':
        _lastOverview = '';
        await _pushOverview();
        unawaited(_store.sync());
      case 'conflictResolved':
        if (message['kept'] == 'disk') {
          await _store.takeHost(message['path']! as String);
        }
      case 'closeReady':
        // En el móvil no hay ventana que cerrar: la página ya guardó.
        break;
      default:
        // Lo del asistente, las carpetas y exportar no existe en el móvil y la
        // página no lo ofrece. Si llegara, no se hace nada en silencio.
        break;
    }
  }

  Future<void> _open(String path) async {
    final note = await _store.byPath(path);
    if (note == null) {
      _send({
        'type': 'error',
        'message': 'La nota $path ya no está en el teléfono.',
      });
      return;
    }
    await _load(note);
  }

  Future<void> _load(MirrorNote note) async {
    _current = note.path;
    _currentHash = note.localHash;
    _dirty = false;
    final notes = await _store.all();
    _send({
      'type': 'load',
      'note': noteDto(note),
      'targets': linkTargets(notes),
    });
    _sendConflictIfAny(note);
    _send({'type': 'details', 'details': mobileDetails(notes, note.path)});
  }

  void _sendConflictIfAny(MirrorNote note) {
    if (note.conflictHash == null) return;
    // La misma banda que en la PC: "quedarme con lo mío" o "recargar". Aquí
    // "el disco" es la versión que llegó de la PC.
    _send({
      'type': 'conflict',
      'path': note.path,
      'diskText': note.conflictContent ?? '',
      'diskHash': note.conflictHash,
    });
  }

  Future<void> _save(String path, String text, String? reason) async {
    final existing = await _store.byPath(path);
    if (existing?.conflictHash != null) {
      if (reason != 'overwrite') {
        // Con un choque sin resolver no se escribe nada: se vuelve a enseñar.
        _sendConflictIfAny(existing!);
        return;
      }
      await _store.keepMine(path);
    }
    await _store.save(path, text);
    final hash = localNoteHash(text);
    if (path == _current) {
      _currentHash = hash;
      _dirty = false;
    }
    _send({'type': 'saved', 'path': path, 'hash': hash});
  }

  Future<void> _create(String path, String text) async {
    final existing = await _store.byPath(path);
    if (existing == null) {
      await _store.save(path, text);
    }
    await _open(path);
  }

  Future<void> _mirrorChanged() async {
    await _pushOverview();
    final path = _current;
    if (path == null) return;
    final note = await _store.byPath(path);
    if (note == null) return;
    if (note.conflictHash != null) {
      _sendConflictIfAny(note);
    } else if (note.localHash != _currentHash && !_dirty) {
      // Llegó de la PC otra versión y aquí no hay nada sin guardar: se recarga.
      // Con cambios sin guardar no se toca: al guardar, el motor lo reconcilia.
      await _load(note);
      _send({
        'type': 'notice',
        'message': 'La nota cambió en la PC y se ha actualizado.',
      });
    }
  }

  Future<void> _pushOverview() async {
    final overview = buildMobileOverview(await _store.all());
    final encoded = jsonEncode(overview);
    // La página ya compara, pero así no se cruza el puente para nada.
    if (encoded == _lastOverview) return;
    _lastOverview = encoded;
    _send({'type': 'overview', 'overview': overview});
    _send({'type': 'targets', 'targets': linkTargets(await _store.all())});
  }
}
