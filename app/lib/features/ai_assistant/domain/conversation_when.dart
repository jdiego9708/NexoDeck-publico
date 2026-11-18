/// Cuando fue una conversacion, en palabras, para las listas de guardadas.
///
/// Una fecha exacta no dice nada util en una lista ordenada por reciente.
/// Recibe los campos sueltos y no la fila de la base para que esto no dependa
/// de Drift: lo comparten la hoja y el panel compacto.
String conversationWhenLabel({
  required DateTime updatedAt,
  required bool keepForever,
  required bool archived,
}) {
  final cuando = _relative(updatedAt);
  if (keepForever) return 'Se conserva · $cuando';
  if (archived) return 'Archivada · $cuando';
  return cuando;
}

String _relative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 30) return 'hace ${diff.inDays} días';
  final meses = diff.inDays ~/ 30;
  return meses == 1 ? 'hace un mes' : 'hace $meses meses';
}
