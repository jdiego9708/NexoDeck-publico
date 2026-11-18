/// Lo que la página del editor necesita, sacado de la copia local del móvil.
///
/// En la PC estas respuestas las da Rust sobre la bóveda (`nexodeck-editor` +
/// `nexodeck-docs`). En el teléfono **no hay bóveda ni índice**: hay un espejo en
/// Drift que funciona sin conexión. Así que se contesta aquí, con la misma forma
/// de JSON que espera `web/src/protocol.ts`, para que la página sea la misma en
/// las dos puntas.
///
/// Es una versión deliberadamente más simple que la de la PC:
/// - **La búsqueda es por texto** (sin tildes ni mayúsculas), no BM25, y solo en
///   notas: los hallazgos y los commits viven en la PC.
/// - **Las agrupaciones van sin color**: el catálogo de nombre y color está en la
///   configuración de la PC y no viaja con las notas. Salen con el color neutro.
/// - **Nada del asistente** (digests, notas parecidas): son funciones de la PC.
///
/// Todo es puro y trabaja sobre [MirrorNote], no sobre filas de Drift, para
/// poder probarlo sin base de datos.
library;

/// Una nota del espejo, lo justo para la página.
class MirrorNote {
  const MirrorNote({
    required this.path,
    required this.content,
    required this.localHash,
    this.private = false,
    this.updatedAt,
    this.conflictContent,
    this.conflictHash,
  });

  /// Virtual: `@<carpeta>/<ruta>` si es de una carpeta local de la PC.
  final String path;
  final String content;
  final String localHash;
  final bool private;
  final DateTime? updatedAt;

  /// La versión de la PC cuando hubo un choque. `null` sin choque.
  final String? conflictContent;
  final String? conflictHash;
}

/// El color de una agrupación que el móvil no conoce: el mismo por defecto que
/// usa la PC (`DEFAULT_GROUP_COLOR`).
const String kMobileGroupColor = '#6366F1';

/// Carpetas de primer nivel que no son agrupaciones, como en `groups.rs`.
const Set<String> _reservedFolders = {
  'diario',
  'proyectos',
  'privado',
  'inbox',
};

/// `[carpeta local o null, ruta dentro]`, igual que `splitVirtual` en la página.
(String?, String) splitVirtualPath(String path) {
  if (!path.startsWith('@')) return (null, path);
  final slash = path.indexOf('/');
  return slash < 0
      ? (null, path)
      : (path.substring(1, slash), path.substring(slash + 1));
}

String _withMd(String path) =>
    path.toLowerCase().endsWith('.md') ? path : '$path.md';

String _stem(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.toLowerCase().endsWith('.md')
      ? name.substring(0, name.length - 3)
      : name;
}

/// El frontmatter de arriba, clave a valor (solo lo plano: `ai`, `date`,
/// `title`, `tags` en una línea).
Map<String, String> _frontmatter(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return const {};
  final out = <String, String>{};
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') return out;
    final colon = line.indexOf(':');
    if (colon > 0) {
      out[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
  }
  // Sin cierre no es frontmatter.
  return const {};
}

/// El título: el primer `# ` fuera del frontmatter, o el nombre del fichero.
String noteTitle(MirrorNote note) {
  final front = _frontmatter(note.content);
  final explicit = front['title']?.replaceAll(RegExp('^["\']|["\']\$'), '');
  if (explicit != null && explicit.isNotEmpty) return explicit;
  var inFront = note.content.startsWith('---');
  var first = true;
  for (final line in note.content.split('\n')) {
    if (inFront) {
      if (!first && line.trim() == '---') inFront = false;
      first = false;
      continue;
    }
    if (line.startsWith('# ')) return line.substring(2).trim();
  }
  return _stem(note.path);
}

String _role(String inner) {
  final head = inner.split('/').first.toLowerCase();
  return switch (head) {
    'diario' => 'daily',
    'proyectos' => 'hub',
    _ => 'note',
  };
}

/// La agrupación de una nota, con el prefijo de su carpeta local si lo tiene.
String? noteGroupOf(String path) {
  final (folder, inner) = splitVirtualPath(path);
  final parts = inner.split('/');
  if (parts.length < 2) return null;
  final head = parts.first;
  if (head.startsWith('.') || _reservedFolders.contains(head.toLowerCase())) {
    return null;
  }
  return folder == null ? head : '@$folder/$head';
}

final RegExp _task = RegExp(r'^\s*[-*+] \[( |x|X)\] (.*)$');
final RegExp _due = RegExp(r'📅\s*(\d{4}-\d{2}-\d{2})');
final RegExp _inlineTag = RegExp(r'(?:^|\s)#([\p{L}\p{N}_/-]+)', unicode: true);

List<String> _tags(MirrorNote note) {
  final front = _frontmatter(note.content)['tags'];
  final tags = <String>{};
  if (front != null) {
    for (final tag in front.replaceAll(RegExp(r'[\[\]"]'), '').split(',')) {
      final clean = tag.trim().replaceFirst('#', '');
      if (clean.isNotEmpty) tags.add(clean);
    }
  }
  var fence = false;
  for (final line in note.content.split('\n')) {
    if (line.trimLeft().startsWith('```')) fence = !fence;
    // Un `# Título` no es una etiqueta: el `#` va seguido de espacio.
    if (fence || line.startsWith('#')) continue;
    for (final match in _inlineTag.allMatches(line)) {
      tags.add(match.group(1)!);
    }
  }
  return tags.toList();
}

List<Map<String, Object?>> _openTasks(MirrorNote note) {
  final tasks = <Map<String, Object?>>[];
  final lines = note.content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final match = _task.firstMatch(lines[i]);
    if (match == null || match.group(1) != ' ') continue;
    tasks.add({
      'path': note.path,
      'line': i + 1,
      'text': match.group(2)!.trim(),
      'done': false,
      'due': _due.firstMatch(lines[i])?.group(1),
    });
  }
  return tasks;
}

/// Una nota para la lista (`NoteSummaryDto`).
Map<String, Object?> noteSummary(MirrorNote note) {
  final (folder, inner) = splitVirtualPath(note.path);
  final front = _frontmatter(note.content);
  final daily = RegExp(
    r'^diario/(\d{4}-\d{2}-\d{2})\.md$',
  ).firstMatch(inner)?.group(1);
  return {
    'path': note.path,
    'folder': folder,
    'group': noteGroupOf(note.path),
    'title': noteTitle(note),
    'role': _role(inner),
    'date': front['date'] ?? daily,
    'tags': _tags(note),
    'openTasks': _openTasks(note).length,
    'aiExcluded': front['ai']?.toLowerCase() == 'false',
    'modified': note.updatedAt?.toUtc().toIso8601String(),
  };
}

/// La foto de la bóveda para la barra lateral (`OverviewDto`).
Map<String, Object?> buildMobileOverview(
  List<MirrorNote> notes, {
  String rootName = 'Notas',
}) {
  final sorted = [...notes]
    ..sort(
      (a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );

  final groups = <String, int>{};
  final localFolders = <String>{};
  for (final note in sorted) {
    final group = noteGroupOf(note.path);
    if (group != null) groups[group] = (groups[group] ?? 0) + 1;
    final (folder, _) = splitVirtualPath(note.path);
    if (folder != null) localFolders.add(folder);
  }
  final groupIds = groups.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return {
    'configured': true,
    'root': rootName,
    'folders': [
      {
        'id': '',
        'name': rootName,
        'path': rootName,
        'local': false,
        'available': true,
      },
      // El nombre de una carpeta local es de la configuración de la PC, que no
      // viaja: se enseña su id, que es el nombre de la carpeta en minúsculas.
      for (final id in localFolders.toList()..sort())
        {
          'id': id,
          'name': id,
          'path': '@$id',
          'local': true,
          'available': true,
        },
    ],
    'groups': [
      for (final id in groupIds)
        {
          'id': id,
          'name': id.substring(id.lastIndexOf('/') + 1),
          'colorHex': kMobileGroupColor,
          'notes': groups[id],
        },
    ],
    'notes': sorted.map(noteSummary).toList(),
    'tasks': [for (final note in sorted) ..._openTasks(note)],
    'digests': const <Object>[],
    'error': null,
  };
}

/// Lo que va dentro de `[[ ]]` para cada nota (`LinkTargetDto`).
List<Map<String, Object?>> linkTargets(List<MirrorNote> notes) => [
  for (final note in notes)
    {
      'target': note.path.endsWith('.md')
          ? note.path.substring(0, note.path.length - 3)
          : note.path,
      'title': noteTitle(note),
    },
];

/// La nota para cargar en el editor (`NoteDto`). El hash es el local: en el
/// móvil solo sirve para que la página sepa sobre qué versión escribe.
Map<String, Object?> noteDto(MirrorNote note) => {
  'path': note.path,
  'title': noteTitle(note),
  'text': note.content,
  'hash': note.localHash,
  'private': note.private,
};

String _fold(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final unit in lower.split('')) {
    final i = from.indexOf(unit);
    out.write(i < 0 ? unit : to[i]);
  }
  return out.toString();
}

/// Búsqueda por texto en las notas del teléfono: todas las palabras tienen que
/// estar, sin tildes ni mayúsculas. Primero las que lo tienen en el título.
List<Map<String, Object?>> searchNotes(
  List<MirrorNote> notes,
  String query, {
  int limit = 30,
}) {
  final words = _fold(
    query,
  ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final scored = <(int, MirrorNote, String)>[];
  for (final note in notes) {
    final title = _fold(noteTitle(note));
    final body = _fold(note.content);
    if (!words.every((w) => title.contains(w) || body.contains(w))) continue;
    final score = words.where(title.contains).length;
    final line = note.content
        .split('\n')
        .firstWhere((l) => _fold(l).contains(words.first), orElse: () => '');
    scored.add((score, note, line.trim()));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [
    for (final (_, note, line) in scored.take(limit))
      {
        'id': 'n:${note.path}',
        'kind': 'note',
        'title': noteTitle(note),
        'snippet': line.length > 160 ? '${line.substring(0, 160)}…' : line,
        'date': noteSummary(note)['date'],
        'path': note.path,
      },
  ];
}

final RegExp _wikilink = RegExp(
  r'\[\[([^\]|#\n]+)(?:#[^\]|\n]*)?(?:\|[^\]\n]*)?\]\]',
);

/// A qué nota lleva `[[target]]` escrito en [source], como `resolve_link_from`
/// en Rust: dentro de su carpeta local primero, luego la ruta exacta, y un
/// nombre suelto solo si es único. `null` si no lleva a ninguna.
String? resolveMobileLink(
  List<MirrorNote> notes,
  String target,
  String? source,
) {
  final wanted = _withMd(target.trim());
  final byPath = {for (final note in notes) note.path.toLowerCase(): note.path};
  if (!wanted.startsWith('@') && source != null) {
    final (folder, _) = splitVirtualPath(source);
    if (folder != null) {
      final inFolder = byPath['@$folder/$wanted'.toLowerCase()];
      if (inFolder != null) return inFolder;
    }
  }
  final exact = byPath[wanted.toLowerCase()];
  if (exact != null) return exact;
  if (wanted.contains('/')) return null;
  final stem = _stem(wanted).toLowerCase();
  final matches = notes
      .where((n) => _stem(n.path).toLowerCase() == stem)
      .toList();
  return matches.length == 1 ? matches.single.path : null;
}

/// Donde crear la nota de un enlace que no lleva a ninguna: en la carpeta local
/// de la nota que enlaza. Igual que `in_folder_of` en Rust.
String newNotePathForLink(String target, String? source) {
  final path = _withMd(target.trim());
  if (path.startsWith('@') || source == null) return path;
  final (folder, _) = splitVirtualPath(source);
  return folder == null ? path : '@$folder/$path';
}

/// Lo que rodea a una nota (`DetailsDto`): solo quién la enlaza. Lo parecido y
/// los digests son del asistente, que vive en la PC.
Map<String, Object?> mobileDetails(List<MirrorNote> notes, String path) {
  final backlinks = <String>[];
  for (final note in notes) {
    if (note.path == path) continue;
    final links = _wikilink.allMatches(note.content).map((m) => m.group(1)!);
    if (links.any(
      (target) => resolveMobileLink(notes, target, note.path) == path,
    )) {
      backlinks.add(note.path);
    }
  }
  backlinks.sort();
  return {
    'path': path,
    'backlinks': backlinks,
    'related': const <Object>[],
    'digests': const <Object>[],
  };
}

const List<String> _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// La nota del día: ruta y texto con que nace si no existe.
(String, String) dailyNote(DateTime now) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final date = '${now.year}-${pad(now.month)}-${pad(now.day)}';
  return (
    'diario/$date.md',
    '# ${now.day} de ${_months[now.month - 1]} de ${now.year}\n\n',
  );
}

/// El texto con que nace una nota creada desde el diálogo.
String newNoteText(String title) =>
    title.trim().isEmpty ? '' : '# ${title.trim()}\n\n';
