import 'package:nexodeck/src/rust/api/docs.dart' as docs_bridge;
import 'package:nexodeck/src/rust/api/editor.dart' as editor_bridge;
import 'package:nexodeck/src/rust/api/notes.dart' as bridge;

import '../domain/note_editor.dart';
import '../domain/notes.dart';

/// Envuelve el puente del asistente de notas, para que ninguna pantalla llame
/// al bridge directo y para poder sustituirlo en los tests, que no cargan
/// `RustLib`.
///
/// Las notas viven en el servicio del buzón de documentación: no hay stream
/// propio, los avisos son los del buzón.
class NotesRepository {
  const NotesRepository();

  Future<NotesOverview> overview() async =>
      NotesOverview.fromBridge(await bridge.notesOverview());

  /// Del más nuevo al más viejo.
  Future<List<NoteDigest>> digests() async =>
      (await bridge.noteDigests()).map(NoteDigest.fromBridge).toList();

  Future<List<NoteSearchHit>> search(String query, {int limit = 20}) async =>
      (await bridge.searchNotes(
        query: query,
        limit: limit,
      )).map(NoteSearchHit.fromBridge).toList();

  Future<NoteDetails> details(String path) async =>
      NoteDetails.fromBridge(await bridge.noteDetails(path: path));

  Future<NoteDigest> digest(String path) async =>
      NoteDigest.fromBridge(await bridge.digestNote(path: path));

  Future<void> setDigestOnIdle(bool enabled) =>
      bridge.setNotesDigestOnIdle(enabled: enabled);

  /// Crea una agrupación, o con [id] le cambia nombre y color **sin mover su
  /// carpeta**.
  Future<NoteGroup> upsertGroup(
    String name,
    String colorHex, {
    String? id,
    String? folder,
  }) async => NoteGroup.fromBridge(
    await bridge.upsertNoteGroup(
      name: name,
      colorHex: colorHex,
      id: id,
      folder: folder,
    ),
  );

  /// Mueve una nota a otra agrupación, o a `inbox/` con [group] nulo; y con
  /// [folder], a otra carpeta de notas.
  Future<NoteMove> moveToGroup(
    String path,
    String? group, {
    String? folder,
  }) async => NoteMove.fromBridge(
    await bridge.moveNoteToGroup(path: path, group: group, folder: folder),
  );

  /// Un número por cada cambio en el buzón, que incluye los digests. Nunca se
  /// repite seguido: es lo que evita que dos avisos se confundan en uno.
  Stream<int> watchChanges() =>
      docs_bridge.watchDocsInboxEvents().map((event) => event.seq);

  Future<NoteEditorAvailability> editorAvailability() async =>
      NoteEditorAvailability.fromBridge(
        await editor_bridge.editorAvailability(),
      );

  /// Abre la ventana de notas (o la trae al frente) sin abrir ninguna nota.
  Future<void> openNotesWindow(NoteEditorTheme theme) =>
      editor_bridge.openNotesWindow(theme: theme.toBridge());

  /// Abre la nota en la ventana del editor. Devuelve su ruta.
  Future<String> openInEditor(String path, NoteEditorTheme theme) =>
      editor_bridge.openNoteEditor(path: path, theme: theme.toBridge());

  Future<String> openDailyNote(NoteEditorTheme theme) =>
      editor_bridge.openDailyNoteEditor(theme: theme.toBridge());

  /// Crea la nota (o abre la que ya haya en esa ruta) en el editor.
  Future<String> createNote(String path, String title, NoteEditorTheme theme) =>
      editor_bridge.createNoteEditor(
        path: path,
        title: title,
        theme: theme.toBridge(),
      );

  Stream<NoteEditorEvent> watchEditorEvents() =>
      editor_bridge.watchEditorEvents().map(NoteEditorEvent.fromBridge);
}
