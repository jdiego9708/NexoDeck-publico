import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_repository.dart';
import '../domain/note_editor.dart';
import '../domain/notes.dart';

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => const NotesRepository(),
);

/// Qué hacer cuando la ventana de notas pide el buzón. Lo pone `main()`: abrir
/// un diálogo necesita el Navigator de la ventana principal, que el controlador
/// no tiene. Por defecto no hace nada (tests, modo sin interfaz).
final notesInboxOpenerProvider = Provider<void Function()>((ref) => () {});

const Object _keep = Object();

class NotesState {
  const NotesState({
    this.overview,
    this.digests = const [],
    this.error,
    this.editor,
    this.editorPath,
  });

  /// `null` hasta la primera foto.
  final NotesOverview? overview;

  /// Del más nuevo al más viejo.
  final List<NoteDigest> digests;

  /// El último fallo al pedir la foto. Se conserva la anterior: un error
  /// pasajero no puede vaciar la lista que el usuario está mirando.
  final String? error;

  /// Si hay editor en esta máquina. `null` hasta saberlo.
  final NoteEditorAvailability? editor;

  /// La nota abierta ahora en la ventana del editor.
  final String? editorPath;

  bool get configured => overview?.configured ?? false;

  bool get canEdit => editor?.available ?? false;

  /// Digests que todavía pueden acabar en propuesta.
  int get activeDigests => digests.where((d) => d.state.isActive).length;

  List<NoteDigest> digestsOf(String path) =>
      digests.where((d) => d.note == path).toList();

  /// Hay un digest en marcha para esa nota: pedir otro no tiene sentido.
  bool isProcessing(String path) =>
      digests.any((d) => d.note == path && d.state.isActive);

  NotesState copyWith({
    NotesOverview? overview,
    List<NoteDigest>? digests,
    Object? error = _keep,
    NoteEditorAvailability? editor,
    Object? editorPath = _keep,
  }) => NotesState(
    overview: overview ?? this.overview,
    digests: digests ?? this.digests,
    error: identical(error, _keep) ? this.error : error as String?,
    editor: editor ?? this.editor,
    editorPath: identical(editorPath, _keep)
        ? this.editorPath
        : editorPath as String?,
  );
}

/// La bóveda de notas: la foto de Rust, los digests y la ventana del editor.
///
/// Mismo patrón que `DocsInboxController`, y por lo mismo: **suscripción
/// directa al `Stream`, nunca `ref.listen`** (dos avisos iguales tienen que dar
/// dos refrescos), y los avisos que llegan mientras se pide la foto se juntan en
/// una vuelta más.
///
/// Un aviso llega cuando cambia algo del buzón (un digest, una propuesta, una
/// nota guardada desde el editor), no cuando alguien edita un `.md` desde
/// Obsidian: por eso el diálogo pide la foto al abrirse.
class NotesController extends Notifier<NotesState> {
  StreamSubscription<int>? _subscription;
  StreamSubscription<NoteEditorEvent>? _editorSubscription;
  bool _refreshing = false;
  bool _again = false;

  NotesRepository get _repository => ref.read(notesRepositoryProvider);

  @override
  NotesState build() {
    _subscription = _repository.watchChanges().listen(
      (_) => refresh(),
      onError: (Object error) => _fail(error),
    );
    _editorSubscription = _repository.watchEditorEvents().listen(
      _onEditorEvent,
      onError: (Object error) => _fail(error),
    );
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
      _editorSubscription?.cancel();
      _editorSubscription = null;
    });
    scheduleMicrotask(refresh);
    scheduleMicrotask(_loadEditorAvailability);
    return const NotesState();
  }

  Future<void> refresh() async {
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _again = false;
        try {
          final overview = await _repository.overview();
          final digests = overview.configured
              ? await _repository.digests()
              : const <NoteDigest>[];
          if (!ref.mounted) return;
          state = state.copyWith(
            overview: overview,
            digests: digests,
            error: null,
          );
        } catch (error) {
          _fail(error);
        }
      } while (_again);
    } finally {
      _refreshing = false;
    }
  }

  void _fail(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(error: error.toString());
  }

  Future<void> _loadEditorAvailability() async {
    NoteEditorAvailability availability;
    try {
      availability = await _repository.editorAvailability();
    } catch (error) {
      availability = NoteEditorAvailability(
        available: false,
        reason: error.toString(),
      );
    }
    if (!ref.mounted) return;
    state = state.copyWith(editor: availability);
  }

  /// Guardar no refresca desde aquí: la nota guardada ya avisa por el stream
  /// del buzón. Cerrar sí, por si lo último fue crear una nota.
  void _onEditorEvent(NoteEditorEvent event) {
    switch (event.kind) {
      case NoteEditorEventKind.opened:
        state = state.copyWith(editorPath: event.path);
      case NoteEditorEventKind.closed:
        state = state.copyWith(editorPath: null);
        unawaited(refresh());
      case NoteEditorEventKind.error:
        state = state.copyWith(error: event.detail);
      case NoteEditorEventKind.showInbox:
        ref.read(notesInboxOpenerProvider)();
      case NoteEditorEventKind.saved:
      case NoteEditorEventKind.conflict:
      case NoteEditorEventKind.unknown:
        break;
    }
  }

  /// Toda acción refresca al terminar, haya ido bien o no: el estado real está
  /// en Rust.
  Future<T> _then<T>(Future<T> action) async {
    try {
      return await action;
    } finally {
      unawaited(refresh());
    }
  }

  Future<NoteDigest> digest(String path) => _then(_repository.digest(path));

  Future<void> setDigestOnIdle(bool enabled) =>
      _then(_repository.setDigestOnIdle(enabled));

  /// Crea una agrupación, o con [id] le cambia nombre y color sin mover su
  /// carpeta.
  Future<NoteGroup> upsertGroup(
    String name,
    String colorHex, {
    String? id,
    String? folder,
  }) => _then(_repository.upsertGroup(name, colorHex, id: id, folder: folder));

  /// Mueve una nota de agrupación. **Mueve el fichero**: cada agrupación es una
  /// carpeta. Rust reescribe los enlaces que la citaban por ruta y devuelve qué
  /// notas tocó, para poder decírselo al usuario.
  Future<NoteMove> moveToGroup(String path, String? group, {String? folder}) =>
      _then(_repository.moveToGroup(path, group, folder: folder));

  Future<NoteDetails> details(String path) => _repository.details(path);

  Future<List<NoteSearchHit>> search(String query) => _repository.search(query);

  Future<void> openNotesWindow(NoteEditorTheme theme) =>
      _repository.openNotesWindow(theme);

  Future<String> openInEditor(String path, NoteEditorTheme theme) =>
      _repository.openInEditor(path, theme);

  /// Puede crear el fichero: refresca.
  Future<String> openDailyNote(NoteEditorTheme theme) =>
      _then(_repository.openDailyNote(theme));

  Future<String> createNote(String path, String title, NoteEditorTheme theme) =>
      _then(_repository.createNote(path, title, theme));
}

final notesProvider = NotifierProvider<NotesController, NotesState>(
  NotesController.new,
);
