import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/notes/application/notes_controller.dart';
import 'package:nexodeck/features/notes/data/notes_repository.dart';
import 'package:nexodeck/features/notes/domain/note_editor.dart';
import 'package:nexodeck/features/notes/domain/notes.dart';
import 'package:nexodeck/src/rust/api/notes.dart' as bridge;

bridge.NoteDigestItem _digest(String id, String note, String state) =>
    bridge.NoteDigestItem(
      id: id,
      project: 'notas',
      note: note,
      trigger: 'idle',
      createdAt: '2026-09-15T14:05:00Z',
      updatedAt: '2026-09-15T14:06:00Z',
      state: state,
      stateDetail: state == 'waiting_model' ? 'sin red' : null,
      proposalId: state == 'proposed' ? 'p-1' : null,
      modelLabel: 'deepseek-chat (deepseek)',
      hub: 'proyectos/ODM.md',
      requeried: true,
      discardedIds: const ['n:inventada.md#0'],
      redactions: 1,
      candidates: const [
        bridge.NoteCandidateItem(
          id: 'c:ExampleApi@abcdef1',
          kind: 'commit',
          title: 'ExampleApi: reprocesar con malla 3D',
          snippet: 'La 2.5D deformaba la ortofoto.',
          date: '2026-09-14',
        ),
      ],
      steps: const [
        bridge.NoteAgentStepItem(agent: 'reader', ok: true, millis: 812),
        bridge.NoteAgentStepItem(
          agent: 'memory#2',
          ok: false,
          millis: 40,
          detail: 'no es JSON valido',
        ),
      ],
    );

bridge.NotesOverviewItem _overview() => const bridge.NotesOverviewItem(
  configured: true,
  vaultProject: 'notas',
  folders: [],
  groups: [],
  root: r'D:\Notas',
  digestOnIdle: false,
  notes: [
    bridge.NoteSummaryItem(
      path: 'diario/2026-09-15.md',
      title: '15 de septiembre',
      role: 'daily',
      date: '2026-09-15',
      tags: ['odm'],
      openTasks: 1,
      aiExcluded: false,
      modified: '2026-09-15T13:00:00Z',
    ),
    bridge.NoteSummaryItem(
      path: 'temas/nomina.md',
      title: 'Nomina',
      role: 'note',
      tags: [],
      openTasks: 0,
      aiExcluded: true,
    ),
  ],
  openTasks: [
    bridge.NoteTaskItem(
      path: 'diario/2026-09-15.md',
      line: 7,
      text: 'reprocesar la tanda R 📅 2026-09-10',
      done: false,
      due: '2026-09-10',
      tags: [],
    ),
  ],
  commits: 12,
);

class _FakeRepository extends Fake implements NotesRepository {
  final changes = StreamController<int>.broadcast();
  final editorEvents = StreamController<NoteEditorEvent>.broadcast();
  int overviews = 0;

  @override
  Stream<int> watchChanges() => changes.stream;

  @override
  Stream<NoteEditorEvent> watchEditorEvents() => editorEvents.stream;

  @override
  Future<NoteEditorAvailability> editorAvailability() async =>
      const NoteEditorAvailability(available: true, version: '153.0');

  @override
  Future<NotesOverview> overview() async {
    overviews++;
    return NotesOverview.fromBridge(_overview());
  }

  @override
  Future<List<NoteDigest>> digests() async => [
    NoteDigest.fromBridge(_digest('d-2', 'diario/2026-09-15.md', 'running')),
    NoteDigest.fromBridge(_digest('d-1', 'temas/malla.md', 'proposed')),
  ];
}

void main() {
  group('notes domain', () {
    test('the overview keeps roles, tasks and the excluded flag', () {
      final overview = NotesOverview.fromBridge(_overview());
      expect(overview.notes.first.role, NoteRole.daily);
      expect(overview.notes.first.role.label, 'Diario');
      expect(overview.note('temas/nomina.md')!.aiExcluded, isTrue);
      expect(NoteRole.parse('algo_nuevo'), NoteRole.unknown);

      final task = overview.openTasks.single;
      expect(task.isOverdue(DateTime(2026, 9, 15)), isTrue);
      expect(task.isOverdue(DateTime(2026, 9, 10)), isFalse, reason: 'hoy no está vencida');
    });

    test('a digest translates its state and names each agent in Spanish', () {
      final digest = NoteDigest.fromBridge(
        _digest('d-1', 'temas/malla.md', 'waiting_model'),
      );
      expect(digest.state, NoteDigestState.waitingModel);
      expect(digest.state.isActive, isTrue);
      expect(digest.stateDetail, 'sin red');
      expect(digest.triggerLabel, 'automático');
      expect(digest.steps.map((s) => s.label), [
        'Lector',
        'Memoria (segunda vuelta)',
      ]);
      expect(digest.candidates.single.kind, 'commit');
      expect(NoteDigestState.parse('proposed').isActive, isFalse);
    });

    test('the Obsidian link carries the absolute path, encoded', () {
      expect(
        obsidianUriFor(r'D:\Notas', 'temas/malla 3D.md'),
        'obsidian://open?path=${Uri.encodeComponent(r'D:\Notas\temas\malla 3D.md')}',
      );
      expect(
        obsidianUriFor('/home/juan/notas/', 'a.md'),
        'obsidian://open?path=${Uri.encodeComponent('/home/juan/notas/a.md')}',
      );
    });
  });

  group('NotesController', () {
    test('two identical change events refresh twice', () async {
      final repository = _FakeRepository();
      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(notesProvider);
      await pumpEventQueue();
      expect(repository.overviews, 1);

      final state = container.read(notesProvider);
      expect(state.configured, isTrue);
      expect(state.activeDigests, 1);
      expect(state.isProcessing('diario/2026-09-15.md'), isTrue);
      expect(state.isProcessing('temas/malla.md'), isFalse);

      repository.changes.add(3);
      await pumpEventQueue();
      repository.changes.add(3);
      await pumpEventQueue();
      expect(repository.overviews, 3);
    });

    test('the editor window is tracked and closing it refreshes', () async {
      final repository = _FakeRepository();
      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(notesProvider);
      await pumpEventQueue();
      expect(container.read(notesProvider).canEdit, isTrue);
      expect(repository.overviews, 1);

      repository.editorEvents.add(
        const NoteEditorEvent(
          seq: 1,
          kind: NoteEditorEventKind.opened,
          path: 'temas/malla.md',
        ),
      );
      await pumpEventQueue();
      expect(container.read(notesProvider).editorPath, 'temas/malla.md');
      expect(container.read(notesProvider).configured, isTrue);

      repository.editorEvents.add(
        const NoteEditorEvent(seq: 2, kind: NoteEditorEventKind.saved),
      );
      await pumpEventQueue();
      expect(repository.overviews, 1, reason: 'guardar avisa por el buzón');

      repository.editorEvents.add(
        const NoteEditorEvent(
          seq: 3,
          kind: NoteEditorEventKind.closed,
          path: 'temas/malla.md',
        ),
      );
      await pumpEventQueue();
      expect(container.read(notesProvider).editorPath, isNull);
      expect(repository.overviews, 2);
    });
  });

  group('notes window', () {
    test('the window asking for the inbox reaches the app', () async {
      final repository = _FakeRepository();
      var opened = 0;
      final container = ProviderContainer(
        overrides: [
          notesRepositoryProvider.overrideWithValue(repository),
          notesInboxOpenerProvider.overrideWithValue(() => opened++),
        ],
      );
      addTearDown(container.dispose);

      container.read(notesProvider);
      await pumpEventQueue();
      for (final seq in [1, 2]) {
        repository.editorEvents.add(
          NoteEditorEvent(seq: seq, kind: NoteEditorEventKind.showInbox),
        );
        await pumpEventQueue();
      }
      expect(opened, 2);
    });
  });

  group('note editor domain', () {
    test('an unknown event kind does not break the app', () {
      expect(NoteEditorEventKind.parse('saved'), NoteEditorEventKind.saved);
      expect(
        NoteEditorEventKind.parse('show_inbox'),
        NoteEditorEventKind.showInbox,
      );
      expect(NoteEditorEventKind.parse('unknown'), NoteEditorEventKind.unknown);
      expect(NoteEditorEventKind.parse('otro'), NoteEditorEventKind.unknown);
    });

    test('colors go to the page as #RRGGBB without alpha', () {
      expect(hexColor(const Color(0x8012141A)), '#12141A');
      final dark = NoteEditorTheme.fromColorScheme(
        ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      );
      expect(dark.dark, isTrue);
      expect(dark.surface, matches(RegExp(r'^#[0-9A-F]{6}$')));
    });

    test('a new note path stays inside the vault', () {
      expect(normalizeNewNotePath(' temas/reunión soporte '), 'temas/reunión soporte.md');
      expect(normalizeNewNotePath(r'\privado\claves.md'), 'privado/claves.md');
      expect(normalizeNewNotePath('../fuera'), isNull);
      expect(normalizeNewNotePath('.obsidian/workspace'), isNull);
      expect(normalizeNewNotePath(r'D:\Notas\x'), isNull);
      expect(normalizeNewNotePath('temas//x'), isNull);
      expect(normalizeNewNotePath(''), isNull);
    });

    test('the suggested path comes from the title', () {
      expect(suggestNotePath('Reunión de soporte: ODM?'), 'reunión-de-soporte-odm');
      expect(isPrivateNotePath('Privado/claves.md'), isTrue);
      expect(isPrivateNotePath('temas/privados.md'), isFalse);
    });
  });
}
