import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/domain/history_series.dart';

void main() {
  final t0 = DateTime(2026, 8, 2, 12);

  List<(DateTime, double?)> samplesEvery(
    Duration step,
    List<double?> values,
  ) => [
    for (final (i, v) in values.indexed) (t0.add(step * i), v),
  ];

  group('bucketSeries', () {
    test('reduce muchas muestras a la cantidad de cubos pedida', () {
      final samples = samplesEvery(
        const Duration(seconds: 15),
        List.generate(1000, (i) => i.toDouble()),
      );

      final points = bucketSeries(samples, buckets: 10);

      expect(points, hasLength(10));
      // Creciente: el promedio de cada cubo sube igual que los datos.
      for (var i = 1; i < points.length; i++) {
        expect(points[i].value, greaterThan(points[i - 1].value));
      }
    });

    test('promedia en vez de saltear, así un pico no desaparece', () {
      // Un pico aislado en medio de valores bajos. Si se submuestreara
      // salteando, con alta probabilidad se perdería; promediando, el cubo
      // que lo contiene queda por encima del resto.
      final values = List<double?>.filled(100, 10.0);
      values[50] = 900.0;
      final samples = samplesEvery(const Duration(seconds: 15), values);

      final points = bucketSeries(samples, buckets: 10);

      expect(points, hasLength(10));
      final max = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
      expect(max, greaterThan(10.0));
    });

    test('omite los cubos sin datos en vez de dibujarlos como 0', () {
      // Dos islas de muestras con un hueco de horas en el medio: es lo que
      // pasa cuando la app estuvo cerrada. Dibujar 0 ahí afirmaría que la
      // CPU estuvo en reposo, que no es lo mismo que "no se sabe".
      final samples = <(DateTime, double?)>[
        (t0, 50.0),
        (t0.add(const Duration(seconds: 15)), 52.0),
        (t0.add(const Duration(hours: 5)), 48.0),
        (t0.add(const Duration(hours: 5, seconds: 15)), 47.0),
      ];

      final points = bucketSeries(samples, buckets: 20);

      expect(points.length, lessThan(20));
      expect(points.every((p) => p.value > 40), isTrue);
    });

    test('los null no arrastran el promedio', () {
      // Caso real: una GPU que no se puede leer guarda null. Si contara
      // como 0, la curva se hundiría a la mitad.
      final samples = <(DateTime, double?)>[
        (t0, 80.0),
        (t0.add(const Duration(seconds: 15)), null),
        (t0.add(const Duration(seconds: 30)), 80.0),
      ];

      final points = bucketSeries(samples, buckets: 1);

      expect(points.single.value, 80.0);
    });

    test('una serie entera de null no produce ningún punto', () {
      final samples = samplesEvery(const Duration(seconds: 15), [
        null,
        null,
        null,
      ]);

      expect(bucketSeries(samples), isEmpty);
    });

    test('una sola muestra devuelve un punto', () {
      expect(bucketSeries([(t0, 42.0)]).single.value, 42.0);
    });

    test('muestras todas en el mismo instante no rompen la división', () {
      // `to - from == 0` haría una división por cero al calcular el ancho
      // del cubo.
      final samples = <(DateTime, double?)>[(t0, 10.0), (t0, 20.0)];

      final points = bucketSeries(samples);

      expect(points.single.value, 15.0);
    });

    test('lista vacía devuelve vacío', () {
      expect(bucketSeries(const []), isEmpty);
    });

    test('el punto cae en el centro del cubo, no en el borde', () {
      final samples = samplesEvery(const Duration(minutes: 10), [
        1.0,
        2.0,
        3.0,
        4.0,
      ]);

      final points = bucketSeries(samples, buckets: 1);

      // Rango total 30 min; el centro del único cubo es t0 + 15 min.
      expect(points.single.at, t0.add(const Duration(minutes: 15)));
    });
  });

  group('splitOnGaps', () {
    test('una serie sin huecos queda en un solo tramo', () {
      final points = [
        for (var i = 0; i < 10; i++)
          HistoryPoint(t0.add(Duration(minutes: i)), 50),
      ];

      expect(splitOnGaps(points), hasLength(1));
    });

    test('corta donde hay un hueco de datos', () {
      // Sin esto, el gráfico une los dos lados del hueco con una recta que
      // afirma que hubo datos donde no los hubo (app cerrada).
      final points = [
        for (var i = 0; i < 5; i++)
          HistoryPoint(t0.add(Duration(minutes: i)), 50),
        for (var i = 0; i < 5; i++)
          HistoryPoint(t0.add(Duration(minutes: 40 + i)), 60),
      ];

      final segments = splitOnGaps(points);

      expect(segments, hasLength(2));
      expect(segments[0], hasLength(5));
      expect(segments[1], hasLength(5));
    });

    test('el umbral es relativo, así sirve igual en 1 hora que en 7 días', () {
      // Mismas proporciones, escala 100x: debe cortar en los dos casos.
      List<HistoryPoint> build(Duration step) => [
        for (var i = 0; i < 4; i++) HistoryPoint(t0.add(step * i), 10),
        for (var i = 0; i < 4; i++) HistoryPoint(t0.add(step * (20 + i)), 20),
      ];

      expect(splitOnGaps(build(const Duration(seconds: 15))), hasLength(2));
      expect(splitOnGaps(build(const Duration(minutes: 25))), hasLength(2));
    });

    test('no corta por variaciones pequeñas del espaciado', () {
      // El submuestreo puede dejar cubos ligeramente desiguales; eso no es
      // un hueco.
      final points = [
        HistoryPoint(t0, 10),
        HistoryPoint(t0.add(const Duration(seconds: 60)), 11),
        HistoryPoint(t0.add(const Duration(seconds: 125)), 12),
        HistoryPoint(t0.add(const Duration(seconds: 185)), 13),
      ];

      expect(splitOnGaps(points), hasLength(1));
    });

    test('casos límite: vacío y un solo punto', () {
      expect(splitOnGaps(const []), isEmpty);
      expect(splitOnGaps([HistoryPoint(t0, 1)]), hasLength(1));
    });
  });

  group('maxOf', () {
    test('devuelve el máximo de la serie', () {
      final points = [
        HistoryPoint(t0, 10),
        HistoryPoint(t0, 55),
        HistoryPoint(t0, 30),
      ];
      expect(maxOf(points), 55);
    });

    test('respeta un piso para que un gráfico plano en 0 no colapse', () {
      expect(maxOf([HistoryPoint(t0, 0)]), 1);
      expect(maxOf(const []), 1);
    });
  });
}
