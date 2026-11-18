/// Las decisiones de la sincronización de notas del móvil, sin Drift ni FFI.
///
/// Está aquí y no dentro del motor por lo mismo que `macro_plan.dart`: lo que
/// hay que poder probar es **qué se pide, qué se borra y qué se conserva**, y
/// eso no necesita ni base de datos ni teléfono.
library;

/// Un hash del texto **solo para uso interno del teléfono**.
///
/// **No es comparable con el hash de la PC, y no puede serlo.** Allí el hash es
/// el sha256 del fichero tal como está en disco, con su BOM y sus CRLF
/// (`nexodeck-docs/src/notes/editing.rs`); el móvil solo tiene el texto con
/// `\n`, así que nunca podría reproducir ese número. Lo único que se le pide a
/// este es distinguir "lo que hay aquí es lo que llegó de la PC" de "esto lo
/// escribió el usuario y la PC todavía no lo sabe", y para eso basta con que sea
/// estable y propio.
///
/// Por eso tampoco se añade `crypto` como dependencia: un hash que solo se
/// compara consigo mismo no necesita sha256. Es FNV-1a de 64 bits, que para
/// detectar un cambio de texto sobra.
String localNoteHash(String content) {
  // El riesgo de una colisión aquí es que un cambio del usuario pase por "sin
  // cambios". Con 64 bits y textos de una nota, eso no va a pasar; y si pasara,
  // el guardado pendiente ya está en la cola de todos modos.
  var hash = 0xcbf29ce484222325;
  for (final unit in content.codeUnits) {
    hash ^= unit;
    // En Dart web los enteros son de 53 bits, pero esto solo corre en Android.
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Una nota del manifiesto de la PC: lo mínimo para decidir.
class NoteStampView {
  const NoteStampView({required this.path, required this.hash});

  final String path;
  final String hash;
}

/// Una nota de la copia local: lo mínimo para decidir.
class NoteMirrorView {
  const NoteMirrorView({
    required this.path,
    required this.baseHash,
    required this.dirty,
  });

  final String path;

  /// El hash que tenía en la PC cuando llegó. Vacío si la creó el teléfono y
  /// la PC todavía no la conoce.
  final String baseHash;

  /// Hay algo escrito aquí que la PC no tiene.
  final bool dirty;
}

/// Qué hacer tras comparar el manifiesto de la PC con la copia local.
class NoteSyncPlan {
  const NoteSyncPlan({required this.fetch, required this.remove});

  /// Rutas cuyo texto hay que pedir: nuevas en la PC, o cambiadas allí.
  final List<String> fetch;

  /// Rutas que hay que quitar de la copia local: la PC ya no las tiene.
  final List<String> remove;

  bool get isEmpty => fetch.isEmpty && remove.isEmpty;
}

/// Compara el manifiesto de la PC con la copia local del teléfono.
///
/// Se ejecuta **después** de vaciar la cola de cambios pendientes, no antes:
/// mandar primero lo que el usuario escribió sin cobertura hace que el
/// manifiesto que llega ya incluya esos guardados, y así una nota recién
/// mandada no se pide de vuelta para nada.
///
/// Dos reglas que no son obvias:
///
/// - **Una nota cambiada en la PC se pide aunque aquí esté sucia.** Ese es
///   justo el choque, y para conservar las dos versiones —lo que pidió el
///   usuario— hace falta tener la de la PC delante. Quién gana no se decide
///   aquí: `NotesMirrorDao.applyFromHost` guarda la de la PC al lado y elige el
///   usuario.
/// - **Una nota que desapareció de la PC NO se borra si aquí está sucia.**
///   Borrarla tiraría lo que el usuario acaba de escribir sin conexión. Se
///   queda, y su guardado pendiente la vuelve a crear en la bóveda.
NoteSyncPlan planNoteSync({
  required List<NoteStampView> manifest,
  required List<NoteMirrorView> mirror,
}) {
  final local = {for (final note in mirror) note.path: note};
  final remote = {for (final note in manifest) note.path};

  final fetch = <String>[];
  for (final stamp in manifest) {
    final copy = local[stamp.path];
    // Sin copia es nueva; con otro hash base, cambió en la PC. Una copia
    // sucia con el mismo `baseHash` no se pide: lo que hay allí ya se tiene, y
    // lo de aquí va por la cola.
    if (copy == null || copy.baseHash != stamp.hash) {
      fetch.add(stamp.path);
    }
  }

  final remove = [
    for (final note in mirror)
      if (!remote.contains(note.path) && !note.dirty) note.path,
  ];

  return NoteSyncPlan(fetch: fetch, remove: remove);
}
