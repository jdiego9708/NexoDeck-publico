import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/interactive_card.dart';
import '../../docs_inbox/presentation/docs_inbox_dialog.dart';
import '../../docs_inbox/presentation/docs_projects_dialog.dart';
import '../application/notes_controller.dart';
import '../domain/note_editor.dart';
import '../domain/notes.dart';
import '../domain/note_tree.dart';
import 'note_groups.dart';
import 'note_tree_view.dart';
import 'vault_dialog.dart';
import 'widgets/digest_trace_view.dart';

/// Las notas de trabajo: buscar, ver tareas y lo que se parece, y mandar una
/// nota al asistente. Lo que propone se aprueba en el buzón de documentación,
/// como cualquier otra propuesta.
Future<void> showNotesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _NotesDialog(),
  );
}

/// Abre las notas: la ventana propia (lista, editor y asistente, que se
/// maximiza y minimiza aparte) si hay editor en esta máquina, y si no el
/// diálogo de siempre.
Future<void> openNotes(BuildContext context, WidgetRef ref) async {
  if (!ref.read(notesProvider).canEdit) {
    return showNotesDialog(context);
  }
  final theme = NoteEditorTheme.fromColorScheme(Theme.of(context).colorScheme);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(notesProvider.notifier).openNotesWindow(theme);
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('No se pudo abrir la ventana de notas: $error')),
    );
  }
}

/// A partir de este ancho, la lista y el detalle van lado a lado.
const double _sideBySideWidth = 760;
const double _listWidth = 360;

enum _Tab { notes, tasks, digests }

class _NotesDialog extends ConsumerStatefulWidget {
  const _NotesDialog();

  @override
  ConsumerState<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends ConsumerState<_NotesDialog> {
  final _query = TextEditingController();
  _Tab _tab = _Tab.notes;

  /// La agrupación por la que se filtra la lista. `null` = todas.
  String? _groupFilter;
  String? _selectedPath;
  List<NoteSearchHit>? _hits;

  /// Qué se está haciendo, para el indicador. `null` si nada.
  String? _busy;

  /// Sube cada vez que algo pudo cambiar la nota abierta.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    // Una nota editada en Obsidian no avisa a nadie: al abrir se lee otra vez.
    Future.microtask(() => ref.read(notesProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = label);
    try {
      await action();
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _hits = null);
      return;
    }
    await _run('Buscando…', () async {
      final hits = await ref.read(notesProvider.notifier).search(query);
      if (mounted) setState(() => _hits = hits);
    });
  }

  void _select(String path) => setState(() {
    _selectedPath = path;
    _version++;
  });

  Future<void> _digest(String path) =>
      _run('Mandando la nota al asistente…', () async {
        final digest = await ref.read(notesProvider.notifier).digest(path);
        _snack(switch (digest.state) {
          NoteDigestState.running => 'Esa nota ya se está procesando.',
          _ =>
            'En cola. Cuando esté lista, la propuesta aparece en el buzón de '
                'documentación.',
        });
      });

  Future<void> _open(String target) async {
    try {
      await _openExternally(target);
    } catch (error) {
      _snack('No se pudo abrir: $error', error: true);
    }
  }

  NoteEditorTheme _editorTheme() =>
      NoteEditorTheme.fromColorScheme(Theme.of(context).colorScheme);

  /// Abrir no pasa por `_run`: la ventana aparece enseguida, y bloquear el
  /// resto de botones mientras tanto no aporta nada.
  Future<void> _edit(String path) async {
    try {
      await ref.read(notesProvider.notifier).openInEditor(path, _editorTheme());
    } catch (error) {
      _snack('No se pudo abrir el editor: $error', error: true);
    }
  }

  Future<void> _openToday() => _run('Abriendo la nota de hoy…', () async {
    final path = await ref
        .read(notesProvider.notifier)
        .openDailyNote(_editorTheme());
    if (mounted) _select(path);
  });

  Future<void> _newNote() async {
    final request = await showDialog<_NewNoteRequest>(
      context: context,
      builder: (_) => const _NewNoteDialog(),
    );
    if (request == null || !mounted) return;
    await _run('Creando la nota…', () async {
      final path = await ref
          .read(notesProvider.notifier)
          .createNote(request.path, request.title, _editorTheme());
      // Una privada no está en el índice: no hay detalle que enseñar.
      if (mounted && !isPrivateNotePath(path)) _select(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(notesProvider);
    final overview = state.overview;
    final errors = [state.error, overview?.error].whereType<String>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notas', style: theme.textTheme.titleLarge),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                overview?.root ?? 'Sin bóveda configurada',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            // Cambiar de carpeta sin salir a editar el JSON del
                            // buzón, que es donde viven también los proyectos
                            // de documentación.
                            TextButton(
                              onPressed: () => showVaultDialog(context),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Cambiar…'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (overview != null && overview.configured) ...[
                    if (state.canEdit) ...[
                      FilledButton.tonalIcon(
                        onPressed: _busy != null ? null : _openToday,
                        icon: const Icon(Icons.today_outlined),
                        label: const Text('Nota de hoy'),
                      ),
                      IconButton(
                        tooltip: 'Nota nueva…',
                        onPressed: _busy != null ? null : _newNote,
                        icon: const Icon(Icons.note_add_outlined),
                      ),
                    ] else if (state.editor?.reason case final reason?)
                      Tooltip(
                        message: 'No se puede editar aquí: $reason',
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Icon(Icons.edit_off_outlined, size: 20),
                        ),
                      ),
                    Tooltip(
                      message:
                          'Procesa sola una nota tocada hoy que lleva cinco '
                          'minutos sin cambios',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Automático', style: theme.textTheme.bodySmall),
                          Switch(
                            value: overview.digestOnIdle,
                            onChanged: _busy != null
                                ? null
                                : (value) => _run(
                                    value
                                        ? 'Encendiendo el modo automático…'
                                        : 'Apagando el modo automático…',
                                    () => ref
                                        .read(notesProvider.notifier)
                                        .setDigestOnIdle(value),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Volver a leer la bóveda',
                      onPressed: () {
                        ref.read(notesProvider.notifier).refresh();
                        setState(() => _version++);
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_busy != null) ...[
                const SizedBox(height: AppSpacing.xs),
                const LinearProgressIndicator(),
                Text(_busy!, style: theme.textTheme.bodySmall),
              ],
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: switch (overview) {
                  null => const Center(child: CircularProgressIndicator()),
                  NotesOverview(configured: false) => const _NotConfigured(),
                  final NotesOverview configured => LayoutBuilder(
                    builder: (context, constraints) =>
                        _body(state, configured, constraints.maxWidth),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(NotesState state, NotesOverview overview, double width) {
    final list = _NotesList(
      overview: overview,
      digests: state.digests,
      tab: _tab,
      hits: _hits,
      query: _query,
      selectedPath: _selectedPath,
      onTab: (tab) => setState(() => _tab = tab),
      groupFilter: _groupFilter,
      onGroupFilter: (group) => setState(() => _groupFilter = group),
      onSearch: _search,
      onClearSearch: () => setState(() {
        _query.clear();
        _hits = null;
      }),
      onSelect: _select,
    );
    final path = _selectedPath;
    final detail = path == null
        ? const _EmptyDetail()
        : _NoteDetail(
            key: ValueKey(path),
            path: path,
            version: _version,
            groups: overview.groups,
            folders: overview.folders,
            onMoved: (to) => setState(() {
              _selectedPath = to;
              _version++;
            }),
            modified: overview.note(path)?.modified,
            busy: _busy != null,
            processing: state.isProcessing(path),
            digests: state.digestsOf(path),
            onDigest: () => _digest(path),
            onSelect: _select,
            onOpen: _open,
            onEdit: state.canEdit ? () => _edit(path) : null,
            editing: state.editorPath == path,
            onBack: width < _sideBySideWidth
                ? () => setState(() => _selectedPath = null)
                : null,
          );

    if (width >= _sideBySideWidth) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: _listWidth, child: list),
          const VerticalDivider(width: AppSpacing.lg),
          Expanded(child: detail),
        ],
      );
    }
    return path == null ? list : detail;
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  static const _example = r'''"projects": [
  { "id": "notas", "name": "Notas", "kind": "vault", "repo_root": "D:\\Notas" }
],
"notes": {
  "vault_project": "notas",
  "repos": ["D:\\Repositorios\\NexoDeck"],
  "digest_on_idle": false
}''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Todavía no hay una bóveda de notas',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Las notas son ficheros .md de una carpeta: puedes seguir '
                'abriéndolas en Obsidian o en cualquier editor. Para que NexoDeck '
                'las lea, añade en la configuración del buzón un proyecto de clase '
                '"vault" que apunte a esa carpeta, y un bloque "notes" con los '
                'repositorios cuyos commits quieres cruzar con ellas. Lo que haya '
                'en "privado/" o lleve "ai: false" no lo lee ningún agente.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Framed(
                child: SelectableText(
                  _example,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const ['Courier New', 'monospace'],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  // El camino corto: elegir la carpeta y listo. El editor del
                  // buzón sigue estando para lo demás (los repositorios a
                  // cruzar, el modelo), pero ya no hace falta para empezar.
                  FilledButton.icon(
                    onPressed: () => showVaultDialog(context),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Elegir carpeta…'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () => showDocsProjectsDialog(context),
                    child: const Text('Configuración del buzón…'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.overview,
    required this.digests,
    required this.tab,
    required this.hits,
    required this.query,
    required this.selectedPath,
    required this.onTab,
    required this.groupFilter,
    required this.onGroupFilter,
    required this.onSearch,
    required this.onClearSearch,
    required this.onSelect,
  });

  final NotesOverview overview;
  final List<NoteDigest> digests;
  final _Tab tab;
  final List<NoteSearchHit>? hits;
  final TextEditingController query;
  final String? selectedPath;
  final ValueChanged<_Tab> onTab;

  /// `null` = todas; [kUngroupedFilter] = sin agrupar; si no, el id.
  final String? groupFilter;
  final ValueChanged<String?> onGroupFilter;
  final VoidCallback onSearch;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onSelect;

  /// Una nota, igual en el árbol que en la lista. En el árbol la carpeta ya se
  /// ve arriba, así que la ruta solo se enseña en la lista plana ([path]).
  Widget _noteTile(NoteSummary note, {bool path = false}) {
    final group = overview.group(note.group);
    return _Tile(
      accent: group == null ? null : noteGroupColor(group),
      meta: [
        ?group?.name,
        note.role.label,
        ?note.date,
        if (note.openTasks > 0) '${note.openTasks} tareas',
        if (note.aiExcluded) 'sin IA',
      ].join(' · '),
      title: note.title,
      subtitle: path ? note.path : '',
      selected: note.path == selectedPath,
      onTap: () => onSelect(note.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = this.hits;
    final today = DateTime.now();
    final visibleNotes = switch (groupFilter) {
      null => overview.notes,
      kUngroupedFilter => overview.notes.where((n) => n.group == null).toList(),
      final id => overview.notes.where((n) => n.group == id).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar en notas, hallazgos y commits',
            suffixIcon: hits == null
                ? null
                : IconButton(
                    tooltip: 'Quitar la búsqueda',
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hits == null)
          SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Tab.notes,
                label: Text('Notas (${overview.notes.length})'),
              ),
              ButtonSegment(
                value: _Tab.tasks,
                label: Text('Tareas (${overview.openTasks.length})'),
              ),
              ButtonSegment(
                value: _Tab.digests,
                label: Text('Procesadas (${digests.length})'),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (selection) => onTab(selection.first),
          ),
        // Solo en la pestaña de notas y sin búsqueda: filtrar tareas o
        // resultados por agrupación sería otra cosa, y mezclarlo confunde.
        if (hits == null && tab == _Tab.notes) ...[
          const SizedBox(height: AppSpacing.sm),
          NoteGroupBar(
            groups: overview.groups,
            folders: overview.folders,
            selected: groupFilter,
            ungrouped: overview.notes.where((n) => n.group == null).length,
            onSelected: onGroupFilter,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListView(
            children: [
              if (hits != null) ...[
                if (hits.isEmpty)
                  Text('Nada coincide.', style: theme.textTheme.bodySmall),
                for (final hit in hits)
                  _Tile(
                    meta: [hit.kindLabel, ?hit.date].join(' · '),
                    title: hit.title,
                    subtitle: hit.snippet,
                    selected: hit.path != null && hit.path == selectedPath,
                    onTap: hit.path == null ? null : () => onSelect(hit.path!),
                  ),
              ] else
                ...switch (tab) {
                  // Sin filtro, el árbol: es como el usuario ordenó sus
                  // carpetas. Con un filtro de agrupación, la lista plana,
                  // porque una agrupación ya es una sola carpeta.
                  _Tab.notes
                      when groupFilter == null && overview.folders.isNotEmpty =>
                    [
                      NoteTreeView(
                        roots: buildNoteTree(overview),
                        selectedPath: selectedPath,
                        leaf: (note) => _noteTile(note),
                      ),
                    ],
                  _Tab.notes => [
                    if (visibleNotes.isEmpty)
                      Text(
                        overview.notes.isEmpty
                            ? 'La bóveda está vacía.'
                            : 'No hay notas aquí.',
                        style: theme.textTheme.bodySmall,
                      ),
                    for (final note in visibleNotes)
                      _noteTile(note, path: true),
                  ],
                  _Tab.tasks => [
                    if (overview.openTasks.isEmpty)
                      Text(
                        'No hay tareas abiertas.',
                        style: theme.textTheme.bodySmall,
                      ),
                    for (final task in overview.openTasks)
                      _Tile(
                        meta: task.due == null
                            ? 'Sin fecha'
                            : task.isOverdue(today)
                            ? 'Vencida · ${task.due}'
                            : 'Para el ${task.due}',
                        warn: task.isOverdue(today),
                        title: task.text,
                        subtitle: '${task.path}:${task.line}',
                        selected: task.path == selectedPath,
                        onTap: () => onSelect(task.path),
                      ),
                  ],
                  _Tab.digests => [
                    if (digests.isEmpty)
                      Text(
                        'Todavía no se procesó ninguna nota.',
                        style: theme.textTheme.bodySmall,
                      ),
                    for (final digest in digests)
                      _Tile(
                        meta: [
                          digest.state.label,
                          if (digest.createdAt != null)
                            shortDateTime(digest.createdAt!),
                        ].join(' · '),
                        warn: digest.state == NoteDigestState.failed,
                        title: digest.note,
                        subtitle: digest.stateDetail ?? digest.triggerLabel,
                        selected: digest.note == selectedPath,
                        onTap: () => onSelect(digest.note),
                      ),
                  ],
                },
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.meta,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.warn = false,
    this.accent,
  });

  final String meta;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final bool warn;

  /// El color de su agrupación. Tiñe el borde al pasar por encima, como las
  /// tarjetas del deck: identifica sin gritar.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        radius: AppRadius.chip,
        selected: selected,
        onTap: onTap,
        // Un aviso manda sobre la agrupación: una tarea vencida tiene que verse.
        accent: warn ? error : accent,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meta,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: warn ? error : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Elige una nota para ver sus tareas, lo que se le parece y lo que hizo '
        'el asistente con ella.',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _NoteDetail extends ConsumerStatefulWidget {
  const _NoteDetail({
    super.key,
    required this.path,
    required this.version,
    required this.busy,
    required this.processing,
    required this.digests,
    required this.onDigest,
    required this.onSelect,
    required this.onOpen,
    this.modified,
    this.onEdit,
    this.editing = false,
    this.onBack,
    this.groups = const [],
    this.folders = const [],
    this.onMoved,
  });

  final String path;
  final int version;

  /// Las agrupaciones a las que se puede mover la nota.
  final List<NoteGroup> groups;

  /// Las carpetas de notas, para moverla a otra.
  final List<NoteFolder> folders;

  /// Mover cambia la ruta: quien la tenía seleccionada tiene que seguirla.
  final ValueChanged<String>? onMoved;

  /// Cuándo cambió el fichero, según la última foto. Si cambia (se aprobó una
  /// propuesta, se editó en Obsidian), el texto se vuelve a pedir.
  final DateTime? modified;
  final bool busy;
  final bool processing;

  /// Del controlador, que se actualiza con cada aviso: más fresco que el
  /// detalle, que solo se pide al abrir la nota.
  final List<NoteDigest> digests;
  final VoidCallback onDigest;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  /// `null` si no hay editor en esta máquina.
  final VoidCallback? onEdit;

  /// La nota ya está abierta en la ventana del editor.
  final bool editing;
  final VoidCallback? onBack;

  @override
  ConsumerState<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends ConsumerState<_NoteDetail> {
  late Future<NoteDetails> _details;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _NoteDetail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.version != widget.version ||
        old.modified != widget.modified) {
      _load();
    }
  }

  void _load() {
    _details = ref.read(notesProvider.notifier).details(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<NoteDetails>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '${snapshot.error}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
        }
        final details = snapshot.data;
        if (details == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = details.summary;
        final digests = widget.digests;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    summary.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  [summary.role.label, ?summary.date].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                MoveNoteButton(
                  path: summary.path,
                  current: summary.group,
                  folder: summary.folder,
                  folders: widget.folders,
                  groups: widget.groups,
                  onMoved: widget.onMoved,
                ),
              ],
            ),
            Text(
              [
                summary.path,
                if (summary.tags.isNotEmpty)
                  summary.tags.map((t) => '#$t').join(' '),
              ].join('  ·  '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                children: [
                  if (summary.aiExcluded)
                    _Notice(
                      text:
                          'Esta nota tiene "ai: false": ningún agente la lee ni '
                          'la procesa, y no sale en las búsquedas de Claude Code.',
                      color: theme.colorScheme.tertiary,
                    ),
                  if (widget.processing)
                    _Notice(
                      text:
                          'El asistente está con esta nota. La propuesta aparecerá '
                          'en el buzón de documentación.',
                      color: theme.colorScheme.primary,
                    ),
                  const _SectionTitle('Texto'),
                  _Framed(
                    child: MarkdownBody(data: details.text, selectable: true),
                  ),
                  if (details.tasks.isNotEmpty) ...[
                    _SectionTitle('Tareas (${details.tasks.length})'),
                    for (final task in details.tasks) _TaskRow(task),
                  ],
                  if (details.backlinks.isNotEmpty) ...[
                    const _SectionTitle('Enlazan a esta nota'),
                    for (final path in details.backlinks)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => widget.onSelect(path),
                          child: Text(path),
                        ),
                      ),
                  ],
                  if (details.related.isNotEmpty) ...[
                    const _SectionTitle('Se le parecen'),
                    for (final hit in details.related)
                      _Tile(
                        meta: hit.date ?? hit.kindLabel,
                        title: hit.title,
                        subtitle: hit.snippet,
                        selected: false,
                        onTap: hit.path == null
                            ? null
                            : () => widget.onSelect(hit.path!),
                      ),
                  ],
                  _SectionTitle('Lo que hizo el asistente (${digests.length})'),
                  if (digests.isEmpty)
                    Text(
                      'Esta nota todavía no se procesó.',
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final digest in digests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: DigestTraceView(
                        digest: digest,
                        onOpenProposal: digest.proposalId == null
                            ? null
                            : () => showDocsInboxDialog(context),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (widget.onEdit != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(widget.editing ? 'Ir al editor' : 'Editar'),
                  ),
                // La ruta real la da Rust: la de una nota local es virtual
                // (`@apuntes/x.md`), y componerla con la raíz de la bóveda
                // apuntaría a un fichero que no existe.
                if (details.realPath.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () =>
                        widget.onOpen(obsidianUriForFile(details.realPath)),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir en Obsidian'),
                  ),
                  TextButton.icon(
                    onPressed: () => widget.onOpen(details.realPath),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Abrir el fichero'),
                  ),
                ],
                FilledButton.icon(
                  onPressed:
                      widget.busy || widget.processing || summary.aiExcluded
                      ? null
                      : widget.onDigest,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    digests.isEmpty ? 'Procesar nota' : 'Procesar otra vez',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow(this.task);

  final NoteTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = task.isOverdue(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            task.done
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              task.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: task.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (task.due != null)
            Text(
              overdue ? 'vencida · ${task.due}' : task.due!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.badge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

/// Un recuadro con altura acotada: una nota larga no puede empujar las
/// tareas y las trazas fuera del diálogo.
class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.badge),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}

class _NewNoteRequest {
  const _NewNoteRequest(this.path, this.title);

  final String path;
  final String title;
}

/// Título y ruta de una nota nueva. La ruta se deriva del título mientras el
/// usuario no escriba la suya.
class _NewNoteDialog extends StatefulWidget {
  const _NewNoteDialog();

  @override
  State<_NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<_NewNoteDialog> {
  final _title = TextEditingController();
  final _path = TextEditingController();
  bool _pathEdited = false;

  /// Solo se enseña el error después de intentar crear: marcar en rojo un
  /// campo vacío antes de escribir nada es ruido.
  bool _tried = false;

  @override
  void dispose() {
    _title.dispose();
    _path.dispose();
    super.dispose();
  }

  void _submit() {
    final path = normalizeNewNotePath(_path.text);
    if (path == null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(_NewNoteRequest(path, _title.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final private = isPrivateNotePath(_path.text);
    final invalid = _tried && normalizeNewNotePath(_path.text) == null;

    return AlertDialog(
      title: const Text('Nota nueva'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (value) {
                if (!_pathEdited) {
                  setState(() => _path.text = suggestNotePath(value));
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _path,
              decoration: InputDecoration(
                labelText: 'Ruta en la bóveda',
                hintText: 'proyectos/odm o privado/ideas',
                helperText: private
                    ? 'Privada: ningún agente la lee ni sale en las búsquedas.'
                    : 'Dentro de privado/ ningún agente la lee.',
                errorText: invalid
                    ? 'Una ruta dentro de la bóveda, sin «..» ni carpetas '
                          'ocultas.'
                    : null,
              ),
              onChanged: (_) => setState(() => _pathEdited = true),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crear y editar')),
      ],
    );
  }
}

/// Abre un enlace o un fichero con lo que el sistema tenga asociado.
///
/// En Windows con `explorer.exe` y no con `cmd /c start`: con cmd, un `&` en la
/// ruta o en el enlace se interpretaría como otro comando.
Future<void> _openExternally(String target) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [target]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [target]);
  } else {
    await Process.start('xdg-open', [target]);
  }
}
