import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

/// Envuelve el puente de notas del rol Android, para que el motor de
/// sincronización no llame al bridge directo y se pueda probar sin `RustLib`.
///
/// Wrapper delgado a propósito: quién atiende al otro lado es la PC
/// (`nexodeck-transport/src/notes.rs`), y aquí no se decide nada.
///
/// **Ninguna de las tres peticiones espera respuesta.** Mandan y vuelven: la
/// contestación llega después por `watchConnectionEvents` como
/// `NotesResponseReceived`, con el mismo `requestId`. Es lo que permite tener
/// varias en vuelo —el manifiesto, unos textos y la tanda que estaba encolada—
/// sin que una bloquee a las otras.
class NotesSyncRepository {
  const NotesSyncRepository();

  Stream<bridge.ConnectionEvent> watchConnectionEvents() =>
      bridge.watchConnectionEvents();

  /// Pide la foto de la bóveda: ruta y hash de cada nota, `privado/` incluido.
  Future<void> requestManifest(String requestId) =>
      bridge.sendNotesManifestRequest(requestId: requestId);

  /// Pide el texto de esas notas. Varias juntas: por datos móviles, una
  /// petición por nota multiplicaría las idas y vueltas.
  Future<void> requestFetch(String requestId, List<String> paths) =>
      bridge.sendNotesFetchRequest(requestId: requestId, paths: paths);

  /// Manda lo que el teléfono tenía encolado, en tanda y en orden.
  Future<void> requestApply(String requestId, List<bridge.NoteOp> ops) =>
      bridge.sendNotesApplyRequest(requestId: requestId, ops: ops);
}
