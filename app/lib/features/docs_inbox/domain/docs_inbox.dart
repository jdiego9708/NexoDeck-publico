import 'package:nexodeck/src/rust/api/docs.dart' as bridge;

/// Estado de un hallazgo. Llega del puente como texto (`"waiting_model"`) para
/// que el esquema de disco pueda crecer sin regenerar nada; aca se traduce una
/// sola vez.
enum DocFindingState {
  queued,
  proposing,
  proposed,
  applied,
  rejected,
  failed,
  waitingModel,
  unknown;

  static DocFindingState parse(String raw) => switch (raw) {
    'queued' => DocFindingState.queued,
    'proposing' => DocFindingState.proposing,
    'proposed' => DocFindingState.proposed,
    'applied' => DocFindingState.applied,
    'rejected' => DocFindingState.rejected,
    'failed' => DocFindingState.failed,
    'waiting_model' => DocFindingState.waitingModel,
    _ => DocFindingState.unknown,
  };

  String get label => switch (this) {
    DocFindingState.queued => 'En cola',
    DocFindingState.proposing => 'Preparando la propuesta',
    DocFindingState.proposed => 'Con propuesta',
    DocFindingState.applied => 'Aplicado',
    DocFindingState.rejected => 'Rechazado',
    DocFindingState.failed => 'Falló',
    DocFindingState.waitingModel => 'Esperando un modelo',
    DocFindingState.unknown => 'Desconocido',
  };

  /// Todavia no tiene propuesta que revisar.
  bool get isWaiting =>
      this == DocFindingState.queued ||
      this == DocFindingState.proposing ||
      this == DocFindingState.waitingModel ||
      this == DocFindingState.failed;
}

enum DocProposalState {
  ready,
  needsReview,
  stale,
  applied,
  rejected,
  failed,
  undone,
  unknown;

  static DocProposalState parse(String raw) => switch (raw) {
    'ready' => DocProposalState.ready,
    'needs_review' => DocProposalState.needsReview,
    'stale' => DocProposalState.stale,
    'applied' => DocProposalState.applied,
    'rejected' => DocProposalState.rejected,
    'failed' => DocProposalState.failed,
    'undone' => DocProposalState.undone,
    _ => DocProposalState.unknown,
  };

  String get label => switch (this) {
    DocProposalState.ready => 'Lista para revisar',
    DocProposalState.needsReview => 'Revísala otra vez',
    DocProposalState.stale => 'Ya no aplica',
    DocProposalState.applied => 'Aplicada',
    DocProposalState.rejected => 'Rechazada',
    DocProposalState.failed => 'Falló',
    DocProposalState.undone => 'Deshecha',
    DocProposalState.unknown => 'Desconocido',
  };

  /// Esperando una decision del usuario.
  bool get isPending =>
      this == DocProposalState.ready ||
      this == DocProposalState.needsReview ||
      this == DocProposalState.stale;
}

class DocEvidence {
  const DocEvidence({required this.measured, required this.text, this.source});

  factory DocEvidence.fromBridge(bridge.DocEvidenceItem item) => DocEvidence(
    measured: item.label == 'M',
    text: item.text,
    source: item.source,
  );

  final bool measured;
  final String text;
  final String? source;

  String get label => measured ? '[M]' : '[S]';
}

class DocFinding {
  const DocFinding({
    required this.id,
    required this.batchId,
    required this.project,
    required this.createdAt,
    required this.kind,
    required this.title,
    required this.body,
    required this.evidence,
    required this.state,
    this.from,
    this.supersedes,
    this.stateDetail,
    this.proposalId,
    this.retryAt,
  });

  factory DocFinding.fromBridge(bridge.DocFindingItem item) => DocFinding(
    id: item.id,
    batchId: item.batchId,
    project: item.project,
    from: item.from,
    createdAt: _parseDate(item.createdAt),
    kind: item.kind,
    title: item.title,
    body: item.body,
    evidence: item.evidence.map(DocEvidence.fromBridge).toList(),
    supersedes: item.supersedes,
    state: DocFindingState.parse(item.state),
    stateDetail: item.stateDetail,
    proposalId: item.proposalId,
    retryAt: item.retryAt == null ? null : _parseDate(item.retryAt!),
  );

  final String id;
  final String batchId;
  final String project;
  final String? from;
  final DateTime? createdAt;
  final String kind;
  final String title;
  final String body;
  final List<DocEvidence> evidence;
  final String? supersedes;
  final DocFindingState state;
  final String? stateDetail;
  final String? proposalId;
  final DateTime? retryAt;

  String get kindLabel => switch (kind) {
    'measurement' => 'Medición',
    'decision' => 'Decisión',
    'bug' => 'Error',
    'change' => 'Cambio',
    'correction' => 'Corrección',
    'open_question' => 'Pregunta abierta',
    _ => kind,
  };
}

class DocOperation {
  const DocOperation({
    required this.kind,
    required this.file,
    required this.title,
    required this.line,
    required this.before,
    required this.after,
    required this.removedLines,
    required this.addedLines,
    required this.destructive,
  });

  factory DocOperation.fromBridge(bridge.DocOperationItem item) => DocOperation(
    kind: item.kind,
    file: item.file,
    title: item.title,
    line: item.line,
    before: item.before,
    after: item.after,
    removedLines: item.removedLines,
    addedLines: item.addedLines,
    destructive: item.destructive,
  );

  final String kind;
  final String file;
  final String title;
  final int line;
  final String before;
  final String after;
  final int removedLines;
  final int addedLines;
  final bool destructive;

  String get kindLabel => switch (kind) {
    'insert_section_top' => 'Sección nueva',
    'set_last_updated' => 'Fecha de actualización',
    'replace_exact' => 'Reemplazo',
    'append_under_heading' => 'Añadido a una sección',
    'add_section' => 'Sección nueva al final',
    'set_frontmatter_key' => 'Propiedad de la nota',
    // Una operacion que Rust aprenda mas adelante se enseña con su nombre en
    // vez de romper la tarjeta.
    _ => kind,
  };
}

/// De dónde sale una propuesta. Llega como texto; uno desconocido se trata como
/// de hallazgos, que es lo que eran todas antes de que existieran las notas.
enum DocProposalOrigin {
  findings,
  noteDigest;

  static DocProposalOrigin parse(String raw) => switch (raw) {
    'note_digest' => DocProposalOrigin.noteDigest,
    _ => DocProposalOrigin.findings,
  };
}

class DocProposal {
  const DocProposal({
    required this.id,
    required this.project,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.summary,
    required this.state,
    required this.staleReasons,
    required this.modelLabel,
    required this.localModel,
    required this.warnings,
    required this.findingIds,
    required this.unresolved,
    required this.operations,
    this.from,
    this.stateDetail,
    this.origin = DocProposalOrigin.findings,
    this.note,
    this.digestId,
  });

  /// Hallazgos de Claude Code o el digest de una nota de la bóveda.
  final DocProposalOrigin origin;

  /// La nota y su digest, si viene de una nota.
  final String? note;
  final String? digestId;

  factory DocProposal.fromBridge(bridge.DocProposalItem item) => DocProposal(
    id: item.id,
    project: item.project,
    revision: item.revision,
    createdAt: _parseDate(item.createdAt),
    updatedAt: _parseDate(item.updatedAt),
    from: item.from,
    summary: item.summary,
    state: DocProposalState.parse(item.state),
    stateDetail: item.stateDetail,
    staleReasons: item.staleReasons,
    modelLabel: item.modelLabel,
    localModel: item.localModel,
    warnings: item.warnings,
    findingIds: item.findingIds,
    unresolved: [
      for (final u in item.unresolved) (findingId: u.findingId, why: u.why),
    ],
    operations: item.operations.map(DocOperation.fromBridge).toList(),
    origin: DocProposalOrigin.parse(item.origin),
    note: item.note,
    digestId: item.digestId,
  );

  final String id;
  final String project;

  /// La que se manda al aprobar: si la propuesta cambio desde que se vio, Rust
  /// se niega a aplicarla.
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? from;
  final String summary;
  final DocProposalState state;
  final String? stateDetail;
  final List<String> staleReasons;
  final String modelLabel;
  final bool localModel;
  final List<String> warnings;
  final List<String> findingIds;
  final List<({String findingId, String why})> unresolved;
  final List<DocOperation> operations;

  /// Los documentos que toca, sin repetir.
  List<String> get files => {for (final op in operations) op.file}.toList();
}

class DocProjectDocument {
  const DocProjectDocument({
    required this.path,
    required this.role,
    required this.answers,
  });

  final String path;
  final String role;
  final String answers;
}

class DocProject {
  const DocProject({
    required this.id,
    required this.name,
    required this.repoRoot,
    required this.documents,
  });

  factory DocProject.fromBridge(bridge.DocProjectItem item) => DocProject(
    id: item.id,
    name: item.name,
    repoRoot: item.repoRoot,
    documents: [
      for (final d in item.documents)
        DocProjectDocument(path: d.path, role: d.role, answers: d.answers),
    ],
  );

  final String id;
  final String name;
  final String repoRoot;
  final List<DocProjectDocument> documents;
}

/// La foto del buzon. Dart no guarda nada: la pide entera cada vez que Rust
/// avisa de un cambio.
class DocsInbox {
  const DocsInbox({
    required this.root,
    required this.workerEnabled,
    required this.working,
    required this.localFallback,
    required this.projects,
    required this.findings,
    required this.proposals,
    this.lastError,
    this.remoteLabel,
  });

  factory DocsInbox.fromBridge(bridge.DocsInboxSnapshot snapshot) => DocsInbox(
    root: snapshot.root,
    workerEnabled: snapshot.workerEnabled,
    working: snapshot.working,
    lastError: snapshot.lastError,
    remoteLabel: snapshot.remoteLabel,
    localFallback: snapshot.localFallback,
    projects: snapshot.projects.map(DocProject.fromBridge).toList(),
    findings: snapshot.findings.map(DocFinding.fromBridge).toList(),
    proposals: snapshot.proposals.map(DocProposal.fromBridge).toList(),
  );

  final String root;
  final bool workerEnabled;
  final bool working;
  final String? lastError;
  final String? remoteLabel;
  final bool localFallback;
  final List<DocProject> projects;
  final List<DocFinding> findings;
  final List<DocProposal> proposals;

  /// Las que esperan al usuario, las mas recientes primero.
  List<DocProposal> get pendingProposals =>
      proposals.reversed.where((p) => p.state.isPending).toList();

  /// Las ya decididas, las mas recientes primero.
  List<DocProposal> get decidedProposals =>
      proposals.reversed.where((p) => !p.state.isPending).toList();

  /// Hallazgos que todavia no tienen propuesta, incluidos los que fallaron.
  List<DocFinding> get waitingFindings =>
      findings.reversed.where((f) => f.state.isWaiting).toList();

  DocProject? project(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  DocProposal? proposal(String id) {
    for (final p in proposals) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<DocFinding> findingsOf(DocProposal proposal) => [
    for (final f in findings)
      if (proposal.findingIds.contains(f.id)) f,
  ];
}

DateTime? _parseDate(String raw) => DateTime.tryParse(raw)?.toLocal();
