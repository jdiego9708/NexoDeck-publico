import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/docs_inbox/application/docs_inbox_controller.dart';
import 'package:nexodeck/features/docs_inbox/data/docs_inbox_repository.dart';
import 'package:nexodeck/features/docs_inbox/domain/docs_inbox.dart';
import 'package:nexodeck/src/rust/api/docs.dart' as bridge;

bridge.DocProposalItem _proposal(
  String id,
  String state, {
  String origin = 'findings',
  String? note,
}) => bridge.DocProposalItem(
  id: id,
  project: 'ia',
  revision: 2,
  createdAt: '2026-09-15T07:00:00Z',
  updatedAt: '2026-09-15T07:05:00Z',
  summary: 'seccion nueva',
  state: state,
  staleReasons: const [],
  modelLabel: 'deepseek-chat (deepseek)',
  localModel: false,
  warnings: const [],
  findingIds: note == null ? const ['f-1'] : const [],
  origin: origin,
  note: note,
  digestId: note == null ? null : 'd-1',
  unresolved: const [],
  operations: const [
    bridge.DocOperationItem(
      kind: 'insert_section_top',
      file: 'docs/estado.md',
      title: '## 15-sep: algo',
      line: 5,
      before: '## 14-sep',
      after: '## 15-sep: algo',
      removedLines: 0,
      addedLines: 4,
      destructive: false,
    ),
  ],
);

bridge.DocFindingItem _finding(String id, String state) => bridge.DocFindingItem(
  id: id,
  batchId: 'b-1',
  project: 'ia',
  createdAt: '2026-09-15T07:00:00Z',
  kind: 'measurement',
  title: 'titulo',
  body: 'cuerpo',
  evidence: const [
    bridge.DocEvidenceItem(label: 'M', text: '474 s', source: 'log'),
  ],
  state: state,
  stateDetail: state == 'waiting_model' ? 'sin red' : null,
);

DocsInbox _inbox() => DocsInbox.fromBridge(
  bridge.DocsInboxSnapshot(
    root: 'D:/datos/docs_inbox',
    workerEnabled: true,
    working: false,
    localFallback: true,
    projects: const [],
    findings: [
      _finding('f-1', 'proposed'),
      _finding('f-2', 'waiting_model'),
      _finding('f-3', 'applied'),
    ],
    proposals: [
      _proposal('p-1', 'applied'),
      _proposal('p-2', 'needs_review'),
      _proposal('p-3', 'ready'),
    ],
  ),
);

class _FakeRepository extends Fake implements DocsInboxRepository {
  final changes = StreamController<int>.broadcast();
  int snapshots = 0;

  @override
  Stream<int> watchChanges() => changes.stream;

  @override
  Future<DocsInbox> snapshot() async {
    snapshots++;
    return _inbox();
  }
}

void main() {
  group('DocsInbox.fromBridge', () {
    test('translates the states that come as text from Rust', () {
      final inbox = _inbox();
      expect(inbox.proposal('p-2')!.state, DocProposalState.needsReview);
      expect(inbox.findings[1].state, DocFindingState.waitingModel);
      expect(inbox.findings[1].stateDetail, 'sin red');
      expect(inbox.findings[0].evidence.single.label, '[M]');
      expect(DocProposalState.parse('algo_nuevo'), DocProposalState.unknown);
    });

    test('pending proposals exclude decided ones and newest come first', () {
      final inbox = _inbox();
      expect(inbox.pendingProposals.map((p) => p.id), ['p-3', 'p-2']);
      expect(inbox.decidedProposals.map((p) => p.id), ['p-1']);
      expect(inbox.waitingFindings.map((f) => f.id), ['f-2']);
    });

    test('keeps the revision that has to be sent back when approving', () {
      final proposal = _inbox().proposal('p-3')!;
      expect(proposal.revision, 2);
      expect(proposal.files, ['docs/estado.md']);
    });

    test('knows when a proposal comes from a note digest', () {
      final fromFindings = DocProposal.fromBridge(_proposal('p-1', 'ready'));
      expect(fromFindings.origin, DocProposalOrigin.findings);
      expect(fromFindings.note, isNull);

      final fromNote = DocProposal.fromBridge(
        _proposal(
          'p-9',
          'ready',
          origin: 'note_digest',
          note: 'temas/malla.md',
        ),
      );
      expect(fromNote.origin, DocProposalOrigin.noteDigest);
      expect(fromNote.note, 'temas/malla.md');
      expect(fromNote.digestId, 'd-1');
      expect(DocProposalOrigin.parse('algo_nuevo'), DocProposalOrigin.findings);
    });

    test('an operation it does not know yet keeps its raw name as label', () {
      const known = DocOperation(
        kind: 'set_frontmatter_key',
        file: 'a.md',
        title: 'status: procesada',
        line: 1,
        before: '',
        after: '',
        removedLines: 0,
        addedLines: 3,
        destructive: false,
      );
      expect(known.kindLabel, 'Propiedad de la nota');
      const future = DocOperation(
        kind: 'algo_futuro',
        file: 'a.md',
        title: '',
        line: 1,
        before: '',
        after: '',
        removedLines: 0,
        addedLines: 0,
        destructive: false,
      );
      expect(future.kindLabel, 'algo_futuro');
    });
  });

  group('DocsInboxController', () {
    test('two identical change events refresh twice', () async {
      final repository = _FakeRepository();
      final container = ProviderContainer(
        overrides: [docsInboxRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(docsInboxProvider);
      await pumpEventQueue();
      expect(repository.snapshots, 1);
      expect(container.read(docsInboxProvider).pendingCount, 2);

      repository.changes.add(7);
      await pumpEventQueue();
      repository.changes.add(7);
      await pumpEventQueue();
      expect(repository.snapshots, 3);
    });
  });
}
