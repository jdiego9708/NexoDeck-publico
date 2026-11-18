import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/notes/application/mobile_notes_host.dart';
import 'package:nexodeck/features/notes/domain/mobile_notes_page.dart';
import 'package:nexodeck/features/notes/domain/note_sync.dart';

MirrorNote _note(
  String path,
  String content, {
  DateTime? at,
  String? conflict,
}) => MirrorNote(
  path: path,
  content: content,
  localHash: localNoteHash(content),
  updatedAt: at ?? DateTime(2026, 9, 16),
  conflictContent: conflict,
  conflictHash: conflict == null ? null : 'pc-hash',
);

class _FakeStore implements MobileNotesStore {
  _FakeStore(List<MirrorNote> notes) {
    for (final note in notes) {
      this.notes[note.path] = note;
    }
  }

  final Map<String, MirrorNote> notes = {};
  final changesController = StreamController<void>.broadcast();
  final List<String> calls = [];

  @override
  Future<List<MirrorNote>> all() async => notes.values.toList();

  @override
  Future<MirrorNote?> byPath(String path) async => notes[path];

  @override
  Stream<void> changes() => changesController.stream;

  @override
  Future<void> save(String path, String content) async {
    calls.add('save $path');
    final previous = notes[path];
    notes[path] = MirrorNote(
      path: path,
      content: content,
      localHash: localNoteHash(content),
      updatedAt: DateTime(2026, 9, 17),
      conflictContent: previous?.conflictContent,
      conflictHash: previous?.conflictHash,
    );
  }

  @override
  Future<void> keepMine(String path) async {
    calls.add('keepMine $path');
    final n = notes[path]!;
    notes[path] = MirrorNote(
      path: n.path,
      content: n.content,
      localHash: n.localHash,
    );
  }

  @override
  Future<void> takeHost(String path) async => calls.add('takeHost $path');

  @override
  Future<void> sync() async => calls.add('sync');
}

void main() {
  group('la foto de la boveda en el movil', () {
    test('summarizes each note like the PC does', () {
      final overview = buildMobileOverview([
        _note(
          'diario/2026-09-16.md',
          '# 16 de septiembre\n\n- [ ] llamar 📅 2026-09-20\n- [x] hecho\n',
        ),
        _note(
          'odm/vuelo-27.md',
          '---\nai: false\ntags: odm, malla\n---\n# Vuelo 27\n\nVer #urgente\n',
        ),
        _note('@apuntes/clientes/acme.md', '# Acme\n'),
        _note('suelta.md', 'sin titulo'),
      ]);

      final notes = {
        for (final n in overview['notes']! as List) (n as Map)['path']: n,
      };
      final daily = notes['diario/2026-09-16.md']!;
      expect(daily['role'], 'daily');
      expect(daily['date'], '2026-09-16');
      expect(daily['openTasks'], 1);
      expect(daily['group'], isNull, reason: 'diario no es una agrupacion');

      final vuelo = notes['odm/vuelo-27.md']!;
      expect(vuelo['title'], 'Vuelo 27');
      expect(vuelo['group'], 'odm');
      expect(vuelo['aiExcluded'], isTrue);
      expect(vuelo['tags'], containsAll(['odm', 'malla', 'urgente']));

      final acme = notes['@apuntes/clientes/acme.md']!;
      expect(acme['folder'], 'apuntes');
      expect(acme['group'], '@apuntes/clientes');
      expect(
        notes['suelta.md']!['title'],
        'suelta',
        reason: 'sin encabezado, el nombre',
      );

      final tasks = overview['tasks']! as List;
      expect(tasks.single, containsPair('due', '2026-09-20'));
      expect(tasks.single, containsPair('line', 3));

      final folders = overview['folders']! as List;
      expect(folders.map((f) => (f as Map)['id']), ['', 'apuntes']);
      final groups = overview['groups']! as List;
      expect(groups.map((g) => (g as Map)['id']), ['@apuntes/clientes', 'odm']);
    });

    test('search ignores accents and case, and titles go first', () {
      final notes = [
        _note('a.md', '# Otra\n\nLa acción de hoy'),
        _note('b.md', '# Acción pendiente\n'),
        _note('c.md', '# Nada\n'),
      ];
      final hits = searchNotes(notes, 'ACCION');
      expect(hits.map((h) => h['path']), ['b.md', 'a.md']);
      expect(hits.last['snippet'], 'La acción de hoy');
    });
  });

  group('enlaces en el movil', () {
    final notes = [
      _note('temas/malla.md', '# Malla\n'),
      _note('@apuntes/clientes/acme.md', '# Acme\n\nVer [[temas/malla]]'),
      _note('@apuntes/indice.md', '[[clientes/acme|Acme]] y [[malla]]'),
      _note('otra/malla.md', '# Otra malla\n'),
    ];

    test(
      'resolves inside the folder first, then by exact path, then a unique name',
      () {
        expect(
          resolveMobileLink(notes, 'clientes/acme', '@apuntes/indice.md'),
          '@apuntes/clientes/acme.md',
        );
        expect(
          resolveMobileLink(notes, 'temas/malla', '@apuntes/indice.md'),
          'temas/malla.md',
        );
        expect(
          resolveMobileLink(notes, 'acme', null),
          '@apuntes/clientes/acme.md',
        );
        expect(
          resolveMobileLink(notes, 'malla', null),
          isNull,
          reason: 'dos notas se llaman malla',
        );
      },
    );

    test('a missing link is created in the folder of the note that links', () {
      expect(
        newNotePathForLink('nueva', '@apuntes/indice.md'),
        '@apuntes/nueva.md',
      );
      expect(newNotePathForLink('nueva', 'temas/malla.md'), 'nueva.md');
    });

    test('backlinks follow the same resolution', () {
      expect(mobileDetails(notes, 'temas/malla.md')['backlinks'], [
        '@apuntes/clientes/acme.md',
      ]);
      expect(mobileDetails(notes, '@apuntes/clientes/acme.md')['backlinks'], [
        '@apuntes/indice.md',
      ]);
    });
  });

  group('el anfitrion de la pagina', () {
    late _FakeStore store;
    late List<Map<String, Object?>> sent;
    late MobileNotesHost host;

    setUp(() {
      store = _FakeStore([_note('temas/malla.md', '# Malla\n')]);
      sent = [];
      host = MobileNotesHost(
        store: store,
        send: sent.add,
        now: () => DateTime(2026, 9, 16),
      );
    });

    Iterable<Object?> types() => sent.map((m) => m['type']);
    Future<void> page(Map<String, Object?> message) =>
        host.receive(jsonEncode(message));

    test('ready sends the overview, and opening a note loads it', () async {
      await page({'type': 'ready'});
      expect(types(), containsAllInOrder(['overview', 'targets']));
      await page({'type': 'openNote', 'path': 'temas/malla.md'});
      final load = sent.firstWhere((m) => m['type'] == 'load');
      expect((load['note']! as Map)['text'], '# Malla\n');
      expect(host.currentPath, 'temas/malla.md');
    });

    test(
      'saving writes to the local copy and answers with the new hash',
      () async {
        await page({
          'type': 'save',
          'path': 'temas/malla.md',
          'text': '# Malla\n\nmas',
          'baseHash': null,
          'reason': 'auto',
        });
        expect(store.calls, ['save temas/malla.md']);
        expect(sent.single, {
          'type': 'saved',
          'path': 'temas/malla.md',
          'hash': localNoteHash('# Malla\n\nmas'),
        });
      },
    );

    test('the daily note and a new note are created once and opened', () async {
      await page({'type': 'openDaily'});
      expect(
        store.notes['diario/2026-09-16.md']!.content,
        '# 16 de septiembre de 2026\n\n',
      );
      await page({'type': 'openDaily'});
      expect(
        store.calls.where((c) => c.startsWith('save')),
        hasLength(1),
        reason: 'la segunda vez solo abre',
      );
      await page({
        'type': 'createNote',
        'path': 'inbox/idea.md',
        'title': 'Idea',
      });
      expect(store.notes['inbox/idea.md']!.content, '# Idea\n\n');
      expect(host.currentPath, 'inbox/idea.md');
    });

    // Decision del usuario: con la nota cambiada en los dos sitios se conservan
    // las dos, y ningun guardado automatico decide por el.
    test(
      'a conflict is shown, blocks saving, and keeping mine resolves it',
      () async {
        store.notes['temas/malla.md'] = _note(
          'temas/malla.md',
          '# Mia\n',
          conflict: '# De la PC\n',
        );
        await page({'type': 'openNote', 'path': 'temas/malla.md'});
        final conflict = sent.firstWhere((m) => m['type'] == 'conflict');
        expect(conflict['diskText'], '# De la PC\n');

        sent.clear();
        await page({
          'type': 'save',
          'path': 'temas/malla.md',
          'text': '# Mia 2\n',
          'baseHash': null,
          'reason': 'auto',
        });
        expect(
          store.calls,
          isEmpty,
          reason: 'con el choque sin resolver no se escribe',
        );
        expect(types(), ['conflict']);

        await page({
          'type': 'save',
          'path': 'temas/malla.md',
          'text': '# Mia 2\n',
          'baseHash': 'pc-hash',
          'reason': 'overwrite',
        });
        expect(store.calls, ['keepMine temas/malla.md', 'save temas/malla.md']);
      },
    );

    test('taking the PC version tells the local copy', () async {
      await page({
        'type': 'conflictResolved',
        'path': 'temas/malla.md',
        'kept': 'disk',
      });
      expect(store.calls, ['takeHost temas/malla.md']);
    });

    test(
      'a link to a missing note creates it next to the current one',
      () async {
        store.notes['@apuntes/a.md'] = _note('@apuntes/a.md', '[[b]]');
        await page({'type': 'openNote', 'path': '@apuntes/a.md'});
        await page({'type': 'openLink', 'target': 'b'});
        expect(store.notes.containsKey('@apuntes/b.md'), isTrue);
        expect(host.currentPath, '@apuntes/b.md');
      },
    );

    test('what only exists on the PC is ignored without breaking', () async {
      await page({'type': 'exportVault', 'fileName': 'x.zip'});
      await page({'type': 'digest', 'path': 'temas/malla.md'});
      await host.receive('no es json');
      expect(sent, isEmpty);
    });
  });
}
