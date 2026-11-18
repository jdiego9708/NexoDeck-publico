/// Cambiar la bóveda sin tocar el resto de la configuración del buzón.
///
/// La configuración es un solo JSON que comparten los proyectos de
/// documentación (IA, Mapas…), el modelo remoto y la bóveda de notas. Un
/// formulario que la reconstruyera entera se llevaría por delante lo que no sabe
/// editar: por eso esto **lee el JSON, cambia lo justo y devuelve el resto tal
/// como estaba**.
///
/// Vive aparte del widget para poder probarlo: que elegir una carpeta no borre
/// los proyectos del buzón es justo lo que no se puede comprobar a ojo.
library;

import 'dart:convert';

/// La bóveda tal como está hoy en la configuración.
class VaultSettings {
  const VaultSettings({this.projectId, this.root, this.repos = const []});

  /// `null` si todavía no hay ninguna bóveda configurada.
  final String? projectId;

  /// La carpeta de las notas.
  final String? root;

  /// Repositorios cuyos commits se cruzan con las notas.
  final List<String> repos;

  bool get configured => root != null && root!.trim().isNotEmpty;
}

/// El identificador que se le pone al proyecto de la bóveda cuando no había
/// ninguno. No se reutiliza el de un proyecto de documentación: son cosas
/// distintas y el usuario los ve juntos en la lista.
const String kVaultProjectId = 'notas';

/// Lee la bóveda de un JSON de configuración del buzón.
///
/// Nunca lanza por un JSON raro: si no se puede leer, es que no hay bóveda que
/// enseñar, y el diálogo ya sabe pintar eso.
VaultSettings readVaultSettings(String configJson) {
  final root = _decode(configJson);
  if (root == null) return const VaultSettings();

  final notes = root['notes'];
  final projectId = notes is Map<String, dynamic>
      ? notes['vault_project'] as String?
      : null;
  final repos = notes is Map<String, dynamic>
      ? (notes['repos'] as List?)?.whereType<String>().toList() ?? const []
      : const <String>[];

  final projects = (root['projects'] as List?)?.whereType<Map>() ?? const [];
  final locals = _localIds(root);
  // Se busca por id, y si el bloque `notes` no apunta a nada, por clase: una
  // configuración a medias es justo la que hay que poder arreglar desde aquí.
  // Una carpeta local también es de clase `vault`, pero no es la bóveda.
  final project = projects.cast<Map<dynamic, dynamic>>().where((p) {
    if (projectId != null) return p['id'] == projectId;
    return p['kind'] == 'vault' && !locals.contains(p['id']);
  }).firstOrNull;

  return VaultSettings(
    projectId: project?['id'] as String? ?? projectId,
    root: project?['repo_root'] as String?,
    repos: repos,
  );
}

/// Devuelve el JSON con la bóveda apuntando a [folder], creando el proyecto y el
/// bloque `notes` si no existían.
///
/// Todo lo demás se conserva byte a byte en cuanto a contenido: los proyectos de
/// documentación, el modelo remoto y los interruptores no se tocan. Si ya había
/// un proyecto de bóveda, se le cambia la carpeta en vez de añadir otro: dos
/// bóvedas en la lista dejarían al usuario eligiendo entre dos cosas que se
/// llaman igual.
String writeVaultFolder(String configJson, String folder) {
  final root = _decode(configJson) ?? <String, dynamic>{};
  final path = folder.trim();
  if (path.isEmpty) {
    throw const FormatException(
      'La carpeta de la bóveda no puede estar vacía.',
    );
  }

  final projects = <dynamic>[...?(root['projects'] as List?)];
  final existingId = readVaultSettings(configJson).projectId;
  final locals = _localIds(root);
  bool isMain(dynamic p) =>
      p is Map &&
      !locals.contains(p['id']) &&
      (p['id'] == existingId || p['kind'] == 'vault');

  final index = projects.indexWhere(isMain);
  if (index >= 0) {
    final project = Map<String, dynamic>.from(projects[index] as Map);
    project['repo_root'] = path;
    // Un proyecto que era de documentación y pasa a ser la bóveda tiene que
    // decirlo, o Rust no lo tratará como tal.
    project['kind'] = 'vault';
    projects[index] = project;
  } else {
    projects.add(<String, dynamic>{
      'id': kVaultProjectId,
      'name': 'Notas',
      'kind': 'vault',
      'repo_root': path,
      'conventions': '',
      'documents': <dynamic>[],
    });
  }
  root['projects'] = projects;

  final notes = <String, dynamic>{
    ...?(root['notes'] as Map?)?.cast<String, dynamic>(),
  };
  notes['vault_project'] = (projects.firstWhere(isMain) as Map)['id'];
  notes.putIfAbsent('repos', () => <dynamic>[]);
  notes.putIfAbsent('digest_on_idle', () => false);
  root['notes'] = notes;

  return const JsonEncoder.withIndent('  ').convert(root);
}

/// Los repositorios cuyos commits se cruzan con las notas.
String writeVaultRepos(String configJson, List<String> repos) {
  final root = _decode(configJson) ?? <String, dynamic>{};
  final notes = <String, dynamic>{
    ...?(root['notes'] as Map?)?.cast<String, dynamic>(),
  };
  notes['repos'] = repos
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  notes.putIfAbsent('digest_on_idle', () => false);
  root['notes'] = notes;
  return const JsonEncoder.withIndent('  ').convert(root);
}

/// Una carpeta local tal como está en la configuración.
class LocalFolder {
  const LocalFolder({required this.id, required this.name, required this.path});

  final String id;
  final String name;
  final String path;
}

/// Las carpetas locales configuradas, en su orden.
List<LocalFolder> readLocalFolders(String configJson) {
  final root = _decode(configJson);
  if (root == null) return const [];
  final ids =
      ((root['notes'] as Map?)?['local_folders'] as List?)
          ?.whereType<String>()
          .toList() ??
      const <String>[];
  final projects = (root['projects'] as List?)?.whereType<Map>() ?? const [];
  return [
    for (final id in ids)
      for (final project in projects)
        if (project['id'] == id)
          LocalFolder(
            id: id,
            name: project['name'] as String? ?? id,
            path: project['repo_root'] as String? ?? '',
          ),
  ];
}

/// Añade una carpeta local: un proyecto `vault` más y su id en
/// `notes.local_folders`. El resto del JSON queda intacto.
///
/// **No valida nada aquí**: que no sea documentación del buzón o que no esté
/// dentro de otra carpeta lo decide Rust al guardar (`folder_problems`), que es
/// quien lo sabe hacer con las rutas resueltas. Validar dos veces es tener dos
/// criterios que acaban discrepando.
String addLocalFolder(String configJson, String folderPath) {
  final root = _decode(configJson) ?? <String, dynamic>{};
  final path = folderPath.trim();
  if (path.isEmpty) {
    throw const FormatException('La carpeta no puede estar vacía.');
  }
  final projects = <dynamic>[...?(root['projects'] as List?)];
  final taken = {
    for (final p in projects)
      if (p is Map && p['id'] is String) p['id'] as String,
  };
  final name = _baseName(path);
  final id = _uniqueId(folderId(name), taken);
  projects.add(<String, dynamic>{
    'id': id,
    'name': name,
    'kind': 'vault',
    'repo_root': path,
    'conventions': '',
    'documents': <dynamic>[],
  });
  root['projects'] = projects;

  final notes = <String, dynamic>{
    ...?(root['notes'] as Map?)?.cast<String, dynamic>(),
  };
  notes['local_folders'] = <dynamic>[...?(notes['local_folders'] as List?), id];
  root['notes'] = notes;
  return const JsonEncoder.withIndent('  ').convert(root);
}

/// Quita una carpeta local de NexoDeck. **No toca el disco**: sus notas siguen
/// donde estaban, solo dejan de salir.
String removeLocalFolder(String configJson, String id) {
  final root = _decode(configJson) ?? <String, dynamic>{};
  final notes = <String, dynamic>{
    ...?(root['notes'] as Map?)?.cast<String, dynamic>(),
  };
  notes['local_folders'] = [
    for (final entry in (notes['local_folders'] as List?) ?? const [])
      if (entry != id) entry,
  ];
  root['notes'] = notes;
  // El proyecto sale tambien: dejarlo huerfano confundiria en el editor del
  // buzón. Solo el de esa carpeta y solo si es de clase `vault`.
  root['projects'] = [
    for (final project in (root['projects'] as List?) ?? const [])
      if (!(project is Map &&
          project['id'] == id &&
          project['kind'] == 'vault'))
        project,
  ];
  return const JsonEncoder.withIndent('  ').convert(root);
}

/// Un id de proyecto válido para Rust: minúsculas, cifras y guiones.
String folderId(String name) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final char in name.toLowerCase().split('')) {
    final mapped = accents[char] ?? char;
    buffer.write(RegExp(r'[a-z0-9]').hasMatch(mapped) ? mapped : '-');
  }
  final id = buffer
      .toString()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return id.isEmpty ? 'carpeta' : id;
}

String _uniqueId(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  for (var n = 2; ; n++) {
    final candidate = '$base-$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

String _baseName(String path) {
  final parts = path
      .replaceAll(r'\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? path : parts.last;
}

Set<Object?> _localIds(Map<String, dynamic> root) => {
  ...?((root['notes'] as Map?)?['local_folders'] as List?),
};

Map<String, dynamic>? _decode(String configJson) {
  try {
    final decoded = jsonDecode(configJson);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
