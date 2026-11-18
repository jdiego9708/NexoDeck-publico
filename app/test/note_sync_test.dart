import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/di/database_provider.dart';
import 'package:nexodeck/data/local/daos/notes_mirror_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/features/notes/application/notes_sync_engine.dart';
import 'package:nexodeck/features/notes/data/notes_sync_repository.dart';
import 'package:nexodeck/features/notes/domain/note_sync.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

/// Un teléfono con una PC de mentira al otro lado: apunta lo que se mandó y
/// contesta lo que le digan, por el mismo camino que el de verdad (el stream de
/// eventos, correlacionando por `requestId`).
class _FakeHost extends NotesSyncRepository {
  _FakeHost();

  final _events = StreamController<bridge.ConnectionEvent>.broadcast();

  /// Lo que contesta a cada tipo de petición.
  List<bridge.NoteStamp> manifest = const [];
  List<bridge.NoteContent> contents = const [];
  List<bridge.NoteOpResult> results = const [];

  final List<List<bridge.NoteOp>> sentOps = [];
  final List<List<String>> fetched = [];

  @override
  Stream<bridge.ConnectionEvent> watchConnectionEvents() => _events.stream;

  void connect() => _events.add(const bridge.ConnectionEvent.connected());

  void _reply(String requestId, bridge.NotesReply response) {
    // Como en el cable: la respuesta llega después, por el stream.
    scheduleMicrotask(
      () => _events.add(
        bridge.ConnectionEvent.notesResponseReceived(
          requestId: requestId,
          response: response,
        ),
      ),
    );
  }

  @override
  Future<void> requestManifest(String requestId) async =>
      _reply(requestId, bridge.NotesReply.manifest(notes: manifest));

  @override
  Future<void> requestFetch(String requestId, List<String> paths) async {
    fetched.add(paths);
    _reply(
      requestId,
      bridge.NotesReply.fetch(
        notes: contents.where((n) => paths.contains(n.path)).toList(),
      ),
    );
  }

  @override
  Future<void> requestApply(String requestId, List<bridge.NoteOp> ops) async {
    sentOps.add(ops);
    _reply(requestId, bridge.NotesReply.applied(results: results));
  }

  Future<void> close() => _events.close();
}

bridge.NoteStamp _stamp(String path, String hash) =>
    bridge.NoteStamp(path: path, hash: hash, private: false);

bridge.NoteContent _content(String path, String text, String hash) =>
    bridge.NoteContent(
      path: path,
      text: text,
      hash: hash,
      private: false,
      exists: true,
    );

void main() {
  group('el plan de sincronizacion', () {
    test('asks for what is new or changed on the PC', () {
      final plan = planNoteSync(
        manifest: [
          _view('nueva.md', 'h1'),
          _view('cambiada.md', 'h2-nuevo'),
          _view('igual.md', 'h3'),
        ],
        mirror: const [
          NoteMirrorView(path: 'cambiada.md', baseHash: 'h2-viejo', dirty: false),
          NoteMirrorView(path: 'igual.md', baseHash: 'h3', dirty: false),
        ],
      );

      expect(plan.fetch, ['nueva.md', 'cambiada.md']);
      expect(plan.remove, isEmpty);
    });

    test('removes a clean copy of a note the PC no longer has', () {
      final plan = planNoteSync(
        manifest: const [],
        mirror: const [
          NoteMirrorView(path: 'borrada.md', baseHash: 'h1', dirty: false),
        ],
      );

      expect(plan.remove, ['borrada.md']);
    });

    /// Lo escrito sin cobertura no se puede tirar porque la nota ya no esté en
    /// la PC: su guardado sigue en la cola y la va a recrear.
    test('never removes a copy with unsent changes', () {
      final plan = planNoteSync(
        manifest: const [],
        mirror: const [
          NoteMirrorView(path: 'mia.md', baseHash: 'h1', dirty: true),
        ],
      );

      expect(plan.remove, isEmpty);
      expect(plan.fetch, isEmpty);
    });

    /// Es el choque, y para poder conservar las dos versiones hay que tener
    /// delante la de la PC.
    test('asks for a note changed on both sides', () {
      final plan = planNoteSync(
        manifest: [_view('choque.md', 'pc')],
        mirror: const [
          NoteMirrorView(path: 'choque.md', baseHash: 'viejo', dirty: true),
        ],
      );

      expect(plan.fetch, ['choque.md']);
    });
  });

  group('el hash local', () {
    test('changes with the text and is stable for the same text', () {
      expect(localNoteHash('hola'), localNoteHash('hola'));
      expect(localNoteHash('hola'), isNot(localNoteHash('holA')));
      expect(localNoteHash(''), isNotEmpty);
    });
  });

  group('el motor de sincronizacion', () {
    late NexoDeckDatabase db;
    late NotesMirrorDao dao;
    late _FakeHost host;
    late ProviderContainer container;
    late NotesSyncEngine engine;

    setUp(() {
      db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
      dao = NotesMirrorDao(db);
      host = _FakeHost();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notesSyncRepositoryProvider.overrideWithValue(host),
        ],
      );
      engine = NotesSyncEngine(container);
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      container.dispose();
      await host.close();
      await db.close();
    });

    /// Lo que se escribió sin cobertura sale al reconectar, y deja de estar
    /// pendiente solo cuando la PC lo confirma.
    test('sends what was written offline once there is a session', () async {
      await dao.saveLocal('notas/sin-red.md', 'escrito en el tren', 'local-1');
      host.results = const [
        bridge.NoteOpResult.saved(path: 'notas/sin-red.md', hash: 'pc-1'),
      ];
      host.manifest = [_stamp('notas/sin-red.md', 'pc-1')];

      host.connect();
      await _settle();

      expect(host.sentOps.single.single, isA<bridge.NoteOp_Save>());
      expect(await dao.pending(), isEmpty);
      final saved = await dao.byPath('notas/sin-red.md');
      expect(saved!.baseHash, 'pc-1');
      expect(saved.localHash, 'pc-1');
    });

    /// La decisión del usuario: si cambió en los dos sitios, se conservan las
    /// dos y elige él.
    test('keeps both versions when the PC rejects the change', () async {
      await dao.saveLocal('choque.md', 'lo mio', 'local-1');
      host.results = const [
        bridge.NoteOpResult.conflict(
          path: 'choque.md',
          diskText: 'lo de la PC',
          diskHash: 'pc-2',
        ),
      ];
      host.manifest = [_stamp('choque.md', 'pc-2')];
      host.contents = [_content('choque.md', 'lo de la PC', 'pc-2')];

      host.connect();
      await _settle();

      final note = await dao.byPath('choque.md');
      expect(note!.content, 'lo mio');
      expect(note.conflictContent, 'lo de la PC');
      expect(note.conflictHash, 'pc-2');
      // Reintentarlo volvería a chocar: sale de la cola.
      expect(await dao.pending(), isEmpty);
    });

    test('brings down notes that only exist on the PC', () async {
      host.manifest = [_stamp('diario/hoy.md', 'pc-1')];
      host.contents = [_content('diario/hoy.md', '# Hoy', 'pc-1')];

      host.connect();
      await _settle();

      expect(host.fetched.single, ['diario/hoy.md']);
      final note = await dao.byPath('diario/hoy.md');
      expect(note!.content, '# Hoy');
      expect(note.baseHash, 'pc-1');
    });

    /// Una nota que la PC ya no tiene desaparece de la copia, pero solo si aquí
    /// no había nada sin mandar.
    test('drops a clean local copy the PC no longer has', () async {
      await dao.applyFromHost(
        path: 'vieja.md',
        content: 'texto',
        hash: 'pc-1',
        private: false,
      );
      host.manifest = const [];

      host.connect();
      await _settle();

      expect(await dao.byPath('vieja.md'), isNull);
    });

    /// Sin sesión no se manda nada, y lo escrito espera en la cola.
    test('writes offline without touching the network', () async {
      await engine.saveNote('offline.md', 'sin conexión');
      await _settle();

      expect(host.sentOps, isEmpty);
      expect(await dao.pending(), hasLength(1));
      expect((await dao.byPath('offline.md'))!.content, 'sin conexión');
    });
  });
}

NoteStampView _view(String path, String hash) =>
    NoteStampView(path: path, hash: hash);

/// Deja correr las vueltas asíncronas: la respuesta de la PC llega por el
/// stream, no como valor de retorno.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
