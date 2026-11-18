/// Una cifra sola, con la unidad que le corresponda.
///
/// El escalon de TB existe desde que la metrica de almacenamiento suma varios
/// discos: un equipo con tres discos da totales de cuatro cifras en GB
/// (`2338.9 GB`), que se lee peor que `2.3 TB` y ademas no entra en el ancho
/// de un badge.
String formatMb(double mb) {
  if (mb >= 1024 * 1024) return '${(mb / (1024 * 1024)).toStringAsFixed(1)} TB';
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  return '${mb.toStringAsFixed(0)} MB';
}

/// `387/476 GB`: usado y total en la MISMA unidad, escrita una sola vez.
///
/// Es la forma que usa cada fila de la lista de discos, y por eso difiere de
/// [formatMb] en dos cosas deliberadas: la unidad la fija el total (para que
/// las dos cifras sean comparables de un vistazo, aunque el usado caiga en el
/// escalon de abajo) y en GB no lleva decimales, porque son dos numeros
/// compitiendo por el ancho de una fila de ~20 dp de alto.
String formatMbPair(double usedMb, double totalMb) {
  final (divisor, unit, decimals) = _unitFor(totalMb);
  final used = (usedMb / divisor).toStringAsFixed(decimals);
  final total = (totalMb / divisor).toStringAsFixed(decimals);
  return '$used/$total $unit';
}

(double, String, int) _unitFor(double mb) {
  if (mb >= 1024 * 1024) return (1024 * 1024, 'TB', 1);
  if (mb >= 1024) return (1024, 'GB', 0);
  return (1, 'MB', 0);
}

String formatBytesPerSec(int bytesPerSec) {
  if (bytesPerSec >= 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSec >= 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  return '$bytesPerSec B/s';
}
