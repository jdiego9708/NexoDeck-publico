/// Un punto ya listo para dibujar: instante y valor.
class HistoryPoint {
  const HistoryPoint(this.at, this.value);

  final DateTime at;
  final double value;
}

/// Agrupa las muestras en [buckets] cubos de igual duracion y promedia cada
/// uno.
///
/// Hace falta porque una semana de historial son ~40.000 filas y un grafico
/// de 600 px no puede (ni necesita) dibujar mas de unos cientos de puntos:
/// pasarle todas es tiempo de layout tirado y una linea ilegible.
///
/// Decisiones que importan:
///
/// - **Se promedia, no se toma una muestra de cada N.** Submuestrear
///   "salteando" pierde los picos: en un rango de 7 dias, un pico de CPU de
///   30 s desaparece si justo cae entre dos muestras elegidas. El promedio
///   al menos lo refleja.
/// - **Los cubos vacios se omiten** (no se dibujan como 0). Si la app
///   estuvo cerrada tres horas, ese tramo no tiene datos; dibujar 0 seria
///   afirmar que la CPU estuvo en reposo, que es distinto de "no se sabe".
/// - **Los valores `null` no cuentan para el promedio.** Una GPU que
///   aparece a mitad del rango (o un sensor que dejo de responder) no tiene
///   por que arrastrar la curva hacia abajo.
/// - El instante del punto es el **centro** del cubo, no su borde: es donde
///   realmente cae el promedio.
List<HistoryPoint> bucketSeries(
  List<(DateTime, double?)> samples, {
  int buckets = 120,
}) {
  if (samples.isEmpty || buckets <= 0) return const [];

  final from = samples.first.$1;
  final to = samples.last.$1;
  final totalMs = to.difference(from).inMilliseconds;

  // Todas las muestras en el mismo instante (o una sola): no hay rango que
  // repartir, se devuelve el promedio como un unico punto.
  if (totalMs <= 0) {
    final values = samples.map((s) => s.$2).whereType<double>().toList();
    if (values.isEmpty) return const [];
    final avg = values.reduce((a, b) => a + b) / values.length;
    return [HistoryPoint(from, avg)];
  }

  final bucketMs = totalMs / buckets;
  final sums = List<double>.filled(buckets, 0);
  final counts = List<int>.filled(buckets, 0);

  for (final (at, value) in samples) {
    if (value == null) continue;
    var index = (at.difference(from).inMilliseconds / bucketMs).floor();
    // La ultima muestra cae exactamente en el borde superior y daria
    // `buckets` (fuera de rango).
    if (index >= buckets) index = buckets - 1;
    if (index < 0) index = 0;
    sums[index] += value;
    counts[index]++;
  }

  final result = <HistoryPoint>[];
  for (var i = 0; i < buckets; i++) {
    if (counts[i] == 0) continue;
    final centerMs = (bucketMs * (i + 0.5)).round();
    result.add(
      HistoryPoint(
        from.add(Duration(milliseconds: centerMs)),
        sums[i] / counts[i],
      ),
    );
  }
  return result;
}

/// Parte la serie en tramos continuos, cortando donde hay un hueco de
/// datos.
///
/// `bucketSeries` omite los cubos vacios, pero eso **no alcanza**: un
/// grafico de lineas une los dos puntos que quedan a los lados del hueco
/// con un segmento recto, y esa recta afirma que hubo datos donde no los
/// hubo. Se ve clarisimo con la app cerrada un rato: aparece una linea
/// perfectamente recta cruzando media hora.
///
/// Cada tramo se dibuja como una linea aparte, asi que el hueco queda
/// vacio de verdad.
///
/// El umbral se deriva del espaciado **mediano** de la propia serie (por
/// [gapFactor]) en vez de fijarse en segundos: el ancho del cubo depende
/// del rango elegido (1 hora vs 7 dias), asi que un numero fijo cortaria de
/// mas en un rango y de menos en el otro. La mediana, ademas, no se
/// desvirtua por los huecos que justamente estamos buscando.
List<List<HistoryPoint>> splitOnGaps(
  List<HistoryPoint> points, {
  double gapFactor = 2.5,
}) {
  if (points.length < 2) {
    return points.isEmpty ? const [] : [points];
  }

  final gaps = <int>[];
  for (var i = 1; i < points.length; i++) {
    gaps.add(points[i].at.difference(points[i - 1].at).inMilliseconds);
  }
  final sorted = [...gaps]..sort();
  final median = sorted[sorted.length ~/ 2];
  if (median <= 0) return [points];
  final threshold = median * gapFactor;

  final segments = <List<HistoryPoint>>[];
  var current = <HistoryPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    if (gaps[i - 1] > threshold) {
      segments.add(current);
      current = <HistoryPoint>[];
    }
    current.add(points[i]);
  }
  segments.add(current);
  return segments;
}

/// Maximo de una serie, con un piso para que un grafico plano en 0 no
/// quede con el eje colapsado.
double maxOf(List<HistoryPoint> points, {double floor = 1}) {
  var max = floor;
  for (final p in points) {
    if (p.value > max) max = p.value;
  }
  return max;
}
