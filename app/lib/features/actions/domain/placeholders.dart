/// Placeholders `{{variable}}` que aparecen en una plantilla.
///
/// Se aceptan espacios alrededor del nombre (`{{ rama }}`) porque es lo que
/// alguien escribe naturalmente, pero el nombre se devuelve recortado: es
/// el que tiene que coincidir con la `key` del parametro.
final _placeholderPattern = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');

Set<String> placeholdersIn(String? template) {
  if (template == null || template.isEmpty) return const {};
  return _placeholderPattern
      .allMatches(template)
      .map((m) => m.group(1)!.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
}

/// Placeholders usados en la plantilla que **no** tienen un parametro
/// declarado que los complete.
///
/// Existe porque el sintoma sin esto es mudo y desconcertante: escribir
/// `{{tema}}` en el comando y no declarar el parametro hace que la accion
/// se ejecute con el texto literal `{{tema}}` adentro. `renderCommand` solo
/// reemplaza los placeholders que tienen parametro (dejar el resto tal cual
/// es deliberado: es un error de captura, no de ejecucion), asi que el
/// lugar donde hay que avisarlo es el editor.
Set<String> undeclaredPlaceholders(String? template, Iterable<String> keys) {
  final declared = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
  return placeholdersIn(template).difference(declared);
}
