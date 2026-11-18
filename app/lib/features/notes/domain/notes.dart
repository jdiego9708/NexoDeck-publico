import 'package:nexodeck/src/rust/api/notes.dart' as bridge;

/// El papel de una nota dentro de la bóveda. Lo decide Rust por la carpeta
/// (`diario/`, `proyectos/`) y llega como texto.
enum NoteRole {
  note,
  daily,
  hub,
  unknown;

  static NoteRole parse(String raw) => switch (raw) {
    'note' => NoteRole.note,
    'daily' => NoteRole.daily,
    'hub' => NoteRole.hub,
    _ => NoteRole.unknown,
  };

  String get label => switch (this) {
    NoteRole.note || NoteRole.unknown => 'Nota',
    NoteRole.daily => 'Diario',
    NoteRole.hub => 'Proyecto',
  };
}

class NoteSummary {
  const NoteSummary({
    required this.path,
    required this.title,
    required this.role,
    required this.tags,
    required this.openTasks,
    required this.aiExcluded,
    this.folder,
    this.group,
    this.date,
    this.modified,
  });

  factory NoteSummary.fromBridge(bridge.NoteSummaryItem item) => NoteSummary(
    path: item.path,
    folder: item.folder,
    group: item.group,
    title: item.title,
    role: NoteRole.parse(item.role),
    date: item.date,
    tags: item.tags,
    openTasks: item.openTasks,
    aiExcluded: item.aiExcluded,
    modified: _parseDate(item.modified),
  );

  final String path;

  /// El id de la carpeta local donde vive, o `null` si es de la bóveda
  /// principal. Viene resuelto de Rust: aquí nadie parsea el `@` de la ruta.
  final String? folder;

  /// El id de su agrupación, que es su carpeta. `null` si está en `inbox/`.
  final String? group;
  final String title;
  final NoteRole role;

  /// `AAAA-MM-DD`: la del frontmatter o la del nombre de una nota diaria.
  final String? date;
  final List<String> tags;
  final int openTasks;

  /// `ai: false`: ningún agente la lee.
  final bool aiExcluded;
  final DateTime? modified;
}

class NoteTask {
  const NoteTask({
    required this.path,
    required this.line,
    required this.text,
    required this.done,
    required this.tags,
    this.due,
  });

  factory NoteTask.fromBridge(bridge.NoteTaskItem item) => NoteTask(
    path: item.path,
    line: item.line,
    text: item.text,
    done: item.done,
    due: item.due,
    tags: item.tags,
  );

  final String path;
  final int line;
  final String text;
  final bool done;

  /// `AAAA-MM-DD`, del `📅` de Obsidian Tasks.
  final String? due;
  final List<String> tags;

  /// Con fecha anterior a `today` y sin hacer. Se compara por día: una tarea
  /// para hoy no está vencida.
  bool isOverdue(DateTime today) {
    final date = due == null ? null : DateTime.tryParse(due!);
    if (date == null || done) return false;
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }
}

class NoteSearchHit {
  const NoteSearchHit({
    required this.id,
    required this.kind,
    required this.title,
    required this.snippet,
    this.date,
    this.path,
  });

  factory NoteSearchHit.fromBridge(bridge.NoteSearchHit item) => NoteSearchHit(
    id: item.id,
    kind: item.kind,
    title: item.title,
    snippet: item.snippet,
    date: item.date,
    path: item.path,
  );

  /// `n:<ruta>#<sección>`, `f:<hallazgo>` o `c:<repo>@<sha>`.
  final String id;
  final String kind;
  final String title;
  final String snippet;
  final String? date;

  /// La nota, si el resultado es una sección de nota.
  final String? path;

  String get kindLabel => switch (kind) {
    'note' => 'Nota',
    'finding' => 'Hallazgo',
    'commit' => 'Commit',
    _ => kind,
  };
}

enum NoteDigestState {
  queued,
  running,
  proposed,
  skipped,
  failed,
  waitingModel,
  unknown;

  static NoteDigestState parse(String raw) => switch (raw) {
    'queued' => NoteDigestState.queued,
    'running' => NoteDigestState.running,
    'proposed' => NoteDigestState.proposed,
    'skipped' => NoteDigestState.skipped,
    'failed' => NoteDigestState.failed,
    'waiting_model' => NoteDigestState.waitingModel,
    _ => NoteDigestState.unknown,
  };

  String get label => switch (this) {
    NoteDigestState.queued => 'En cola',
    NoteDigestState.running => 'Procesándose',
    NoteDigestState.proposed => 'Con propuesta',
    NoteDigestState.skipped => 'Sin nada que hacer',
    NoteDigestState.failed => 'Falló',
    NoteDigestState.waitingModel => 'Esperando un modelo',
    NoteDigestState.unknown => 'Desconocido',
  };

  /// Todavía puede acabar en una propuesta: no tiene sentido pedir otro.
  bool get isActive =>
      this == NoteDigestState.queued ||
      this == NoteDigestState.running ||
      this == NoteDigestState.waitingModel;
}

/// Lo que hizo un agente del digest.
class NoteAgentStep {
  const NoteAgentStep({
    required this.agent,
    required this.ok,
    required this.millis,
    this.outputJson,
    this.detail,
  });

  factory NoteAgentStep.fromBridge(bridge.NoteAgentStepItem item) =>
      NoteAgentStep(
        agent: item.agent,
        ok: item.ok,
        millis: item.millis,
        outputJson: item.outputJson,
        detail: item.detail,
      );

  /// `reader`, `memory`, `code`, `critic` o `synthesizer`, con `#2` si repitió.
  final String agent;
  final bool ok;
  final int millis;
  final String? outputJson;
  final String? detail;

  String get label {
    final parts = agent.split('#');
    final name = switch (parts.first) {
      'reader' => 'Lector',
      'memory' => 'Memoria',
      'code' => 'Código',
      'critic' => 'Crítico',
      'synthesizer' => 'Redactor',
      final other => other,
    };
    return parts.length > 1 ? '$name (segunda vuelta)' : name;
  }
}

class NoteCandidate {
  const NoteCandidate({
    required this.id,
    required this.kind,
    required this.title,
    required this.snippet,
    this.date,
  });

  factory NoteCandidate.fromBridge(bridge.NoteCandidateItem item) =>
      NoteCandidate(
        id: item.id,
        kind: item.kind,
        title: item.title,
        snippet: item.snippet,
        date: item.date,
      );

  final String id;
  final String kind;
  final String title;
  final String snippet;
  final String? date;
}

/// Un digest de una nota con su traza: qué buscó Rust, qué vio cada agente y
/// qué citas se descartaron por no existir.
class NoteDigest {
  const NoteDigest({
    required this.id,
    required this.project,
    required this.note,
    required this.trigger,
    required this.state,
    required this.modelLabel,
    required this.requeried,
    required this.discardedIds,
    required this.redactions,
    required this.candidates,
    required this.steps,
    this.createdAt,
    this.updatedAt,
    this.stateDetail,
    this.proposalId,
    this.retryAt,
    this.hub,
  });

  factory NoteDigest.fromBridge(bridge.NoteDigestItem item) => NoteDigest(
    id: item.id,
    project: item.project,
    note: item.note,
    trigger: item.trigger,
    createdAt: _parseDate(item.createdAt),
    updatedAt: _parseDate(item.updatedAt),
    state: NoteDigestState.parse(item.state),
    stateDetail: item.stateDetail,
    proposalId: item.proposalId,
    retryAt: _parseDate(item.retryAt),
    modelLabel: item.modelLabel,
    hub: item.hub,
    requeried: item.requeried,
    discardedIds: item.discardedIds,
    redactions: item.redactions,
    candidates: item.candidates.map(NoteCandidate.fromBridge).toList(),
    steps: item.steps.map(NoteAgentStep.fromBridge).toList(),
  );

  final String id;
  final String project;
  final String note;

  /// `manual`, `idle` o `mcp`.
  final String trigger;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final NoteDigestState state;
  final String? stateDetail;
  final String? proposalId;
  final DateTime? retryAt;
  final String modelLabel;
  final String? hub;
  final bool requeried;
  final List<String> discardedIds;
  final int redactions;
  final List<NoteCandidate> candidates;
  final List<NoteAgentStep> steps;

  String get triggerLabel => switch (trigger) {
    'manual' => 'pedido a mano',
    'idle' => 'automático',
    'mcp' => 'desde Claude Code',
    _ => trigger,
  };
}

class NoteDetails {
  /// La ruta real del fichero en disco. Es la que abre Obsidian o el explorador:
  /// la de una nota local es virtual (`@apuntes/x.md`) y no se puede componer.
  final String realPath;

  const NoteDetails({
    required this.summary,
    required this.text,
    required this.backlinks,
    required this.related,
    required this.tasks,
    required this.digests,
    this.realPath = '',
  });

  factory NoteDetails.fromBridge(bridge.NoteDetailsItem item) => NoteDetails(
    realPath: item.realPath,
    summary: NoteSummary.fromBridge(item.summary),
    text: item.text,
    backlinks: item.backlinks,
    related: item.related.map(NoteSearchHit.fromBridge).toList(),
    tasks: item.tasks.map(NoteTask.fromBridge).toList(),
    digests: item.digests.map(NoteDigest.fromBridge).toList(),
  );

  final NoteSummary summary;
  final String text;

  /// Las notas que enlazan a esta.
  final List<String> backlinks;
  final List<NoteSearchHit> related;
  final List<NoteTask> tasks;

  /// Del más nuevo al más viejo.
  final List<NoteDigest> digests;
}

/// La foto de la bóveda. Como el buzón, Dart no guarda nada: la pide entera.
/// Una agrupación de notas. **Es una carpeta de la bóveda**: `id` es su nombre
/// en el disco, y el nombre y el color son lo que el usuario le puso.
class NoteGroup {
  const NoteGroup({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.order,
    required this.notes,
  });

  factory NoteGroup.fromBridge(bridge.NoteGroupItem item) => NoteGroup(
    id: item.id,
    name: item.name,
    colorHex: item.colorHex,
    order: item.order,
    notes: item.notes,
  );

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String colorHex;
  final int order;
  final int notes;
}

/// Lo que pasó al mover una nota de agrupación.
class NoteMove {
  const NoteMove({
    required this.from,
    required this.to,
    required this.relinked,
    required this.digests,
  });

  factory NoteMove.fromBridge(bridge.NoteMoveItem item) => NoteMove(
    from: item.from,
    to: item.to,
    relinked: [for (final r in item.relinked) (path: r.path, links: r.links)],
    digests: item.digests,
  );

  final String from;

  /// Puede no ser la pedida: si ya había una nota con ese nombre, se apartó.
  final String to;

  /// Las notas cuyos `[[enlaces]]` se reescribieron para seguirla.
  final List<({String path, int links})> relinked;
  final int digests;
}

/// Una carpeta de notas: la bóveda principal o una carpeta local, que NexoDeck
/// lee **en su sitio** sin copiarla.
class NoteFolder {
  const NoteFolder({
    required this.id,
    required this.name,
    required this.path,
    required this.local,
    required this.available,
  });

  factory NoteFolder.fromBridge(bridge.NoteFolderItem item) => NoteFolder(
    id: item.id,
    name: item.name,
    path: item.path,
    local: item.local,
    available: item.available,
  );

  /// El id de su proyecto: lo que se pasa para mover o agrupar en ella.
  final String id;
  final String name;

  /// La ruta real en disco.
  final String path;

  /// Es una carpeta local, no la bóveda principal.
  final bool local;

  /// Existe ahora mismo. Una carpeta en un disco desconectado no enseña notas:
  /// hay que poder decir por qué.
  final bool available;
}

class NotesOverview {
  const NotesOverview({
    required this.configured,
    required this.digestOnIdle,
    required this.notes,
    this.folders = const [],
    this.groups = const [],
    required this.openTasks,
    required this.commits,
    this.vaultProject,
    this.root,
    this.error,
  });

  factory NotesOverview.fromBridge(bridge.NotesOverviewItem item) =>
      NotesOverview(
        configured: item.configured,
        vaultProject: item.vaultProject,
        root: item.root,
        digestOnIdle: item.digestOnIdle,
        notes: item.notes.map(NoteSummary.fromBridge).toList(),
        folders: item.folders.map(NoteFolder.fromBridge).toList(),
        groups: item.groups.map(NoteGroup.fromBridge).toList(),
        openTasks: item.openTasks.map(NoteTask.fromBridge).toList(),
        commits: item.commits,
        error: item.error,
      );

  /// `false` si el buzón no tiene ninguna bóveda configurada.
  final bool configured;
  final String? vaultProject;
  final String? root;
  final bool digestOnIdle;

  /// De la tocada más recientemente a la más vieja.
  final List<NoteSummary> notes;

  /// La bóveda principal primero y después las carpetas locales.
  final List<NoteFolder> folders;

  /// Ya ordenadas. Cada una es una carpeta de la bóveda.
  final List<NoteGroup> groups;
  final List<NoteTask> openTasks;
  final int commits;
  final String? error;

  /// La agrupación con ese id. `null` si la nota está sin agrupar, o si la
  /// carpeta ya no tiene entrada (se borró por fuera entre dos fotos).
  NoteGroup? group(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  NoteSummary? note(String path) {
    for (final n in notes) {
      if (n.path == path) return n;
    }
    return null;
  }

  /// La carpeta de una nota: la local con ese id, o la principal con `null`.
  NoteFolder? folder(String? id) {
    for (final f in folders) {
      if (id == null ? !f.local : f.local && f.id == id) return f;
    }
    return null;
  }
}

/// El enlace que abre una nota en Obsidian. Obsidian registra el esquema
/// `obsidian://` al instalarse y acepta la ruta absoluta del fichero, así que
/// no hace falta saber cómo se llama la bóveda allí.
///
/// Con una raíz de Windows (`D:\Notas`) la ruta relativa se pasa a
/// barras invertidas: una ruta mezclada no la encuentra.
String obsidianUriFor(String root, String relativePath) {
  final windows = root.contains(r'\');
  final separator = windows ? r'\' : '/';
  final base = root.endsWith(separator) ? root : '$root$separator';
  final rel = windows ? relativePath.replaceAll('/', r'\') : relativePath;
  return 'obsidian://open?path=${Uri.encodeComponent('$base$rel')}';
}

/// El enlace de Obsidian para un fichero por su **ruta real**.
///
/// Es el que hay que usar: con varias carpetas de notas, la ruta de una nota
/// local es virtual (`@apuntes/x.md`) y componerla con la raíz de la bóveda
/// principal apuntaría a un fichero que no existe.
String obsidianUriForFile(String absolutePath) =>
    'obsidian://open?path=${Uri.encodeComponent(absolutePath)}';

DateTime? _parseDate(String? raw) =>
    raw == null ? null : DateTime.tryParse(raw)?.toLocal();
