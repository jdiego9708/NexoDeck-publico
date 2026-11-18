import 'notes.dart';

/// Una carpeta del árbol de notas, con sus subcarpetas y sus notas.
class NoteTreeFolder {
  NoteTreeFolder(this.name, this.path);

  /// El nombre de esta carpeta (`clientes`).
  final String name;

  /// Su ruta dentro de la carpeta de notas (`trabajo/clientes`). Vacía en la
  /// raíz. Sirve de clave estable para recordar qué está abierto.
  final String path;

  final List<NoteTreeFolder> folders = [];
  final List<NoteSummary> notes = [];

  /// Cuántas notas hay dentro, contando las subcarpetas.
  int get count =>
      notes.length + folders.fold(0, (sum, folder) => sum + folder.count);
}

/// Una carpeta de notas con su árbol.
class NoteTreeRoot {
  const NoteTreeRoot(this.folder, this.tree);

  final NoteFolder folder;
  final NoteTreeFolder tree;
}

/// Las notas repartidas por carpeta de notas y por subcarpeta, **en el orden del
/// Explorador de Windows**: primero las carpetas y después las notas, cada grupo
/// en orden alfabético natural y sin distinguir mayúsculas.
///
/// Es lo que pidió el usuario —"en el orden que ya tengo"—, y no sale de ningún
/// sitio: el índice ordena por fecha y el disco no garantiza orden. Por eso se
/// ordena aquí, a propósito, en cada nivel.
///
/// La ruta que se reparte es la de dentro de cada carpeta (sin el `@id/` de una
/// local), que es la estructura que el usuario ve en su disco.
List<NoteTreeRoot> buildNoteTree(NotesOverview overview) {
  final folders = overview.folders.isNotEmpty
      ? overview.folders
      : [
          // Una foto sin carpetas (un binario anterior): todo a la principal.
          NoteFolder(
            id: overview.vaultProject ?? '',
            name: 'Bóveda',
            path: overview.root ?? '',
            local: false,
            available: true,
          ),
        ];

  final roots = [
    for (final folder in folders)
      NoteTreeRoot(folder, NoteTreeFolder(folder.name, '')),
  ];
  NoteTreeRoot? rootFor(NoteSummary note) {
    for (final root in roots) {
      final folder = root.folder;
      if (note.folder == null
          ? !folder.local
          : folder.local && folder.id == note.folder) {
        return root;
      }
    }
    return null;
  }

  for (final note in overview.notes) {
    final root = rootFor(note);
    if (root == null) continue;
    final inner = note.folder == null
        ? note.path
        : note.path.substring(note.path.indexOf('/') + 1);
    final segments = inner.split('/');
    var node = root.tree;
    for (final segment in segments.take(segments.length - 1)) {
      node = _child(node, segment);
    }
    node.notes.add(note);
  }

  for (final root in roots) {
    _sort(root.tree);
  }
  return roots;
}

NoteTreeFolder _child(NoteTreeFolder parent, String name) {
  for (final folder in parent.folders) {
    if (folder.name == name) return folder;
  }
  final path = parent.path.isEmpty ? name : '${parent.path}/$name';
  final folder = NoteTreeFolder(name, path);
  parent.folders.add(folder);
  return folder;
}

void _sort(NoteTreeFolder node) {
  node.folders.sort((a, b) => compareNatural(a.name, b.name));
  node.notes.sort(
    (a, b) => compareNatural(_fileName(a.path), _fileName(b.path)),
  );
  for (final folder in node.folders) {
    _sort(folder);
  }
}

String _fileName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Orden alfabético natural sin distinguir mayúsculas, como el Explorador:
/// `nota 2` antes que `nota 10`, y `Acme` junto a `acme`.
int compareNatural(String a, String b) {
  final chunks = RegExp(r'\d+|\D+');
  final left = chunks.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = chunks.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final order = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}
