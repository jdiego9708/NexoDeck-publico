import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';

/// Sparkline compacto: una o mas series sobre el mismo eje, sin ejes ni
/// grilla visibles -- pensado para caber en una tarjeta chica de la fila
/// de metricas.
class MiniLineChart extends StatelessWidget {
  const MiniLineChart({
    super.key,
    required this.series,
    required this.maxY,
    this.mirrored = false,
  });

  /// Cada entrada es (valores, color). Todas comparten el mismo eje X
  /// (indice de muestra). El eje Y depende de [mirrored].
  final List<(List<double>, Color)> series;
  final double maxY;

  /// La primera serie baja y la segunda sube desde una linea base
  /// compartida en el medio -- mismo espiritu que la senal de vida del
  /// disco (`DiskHeartbeat`), pero continua en vez de picos. Lo pide la
  /// Red: bajada hacia abajo, subida hacia arriba, en vez de las dos
  /// creciendo para el mismo lado.
  ///
  /// Solo tiene sentido con dos series; con una sola (el sparkline de CPU)
  /// se deja en `false` y el eje sigue siendo 0..[maxY] de siempre.
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final longestSeries = series
        .map((s) => s.$1.length)
        .fold(0, (a, b) => a > b ? a : b);
    if (longestSeries < 2) {
      // `FittedBox`: el placeholder aparece tambien en el riel vertical,
      // donde el chart mide ~36 px de ancho y el texto a 10 px desbordaba.
      return const Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'Recolectando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: mirrored ? -maxY : 0,
        maxY: maxY,
        minX: 0,
        maxX: (longestSeries - 1).toDouble(),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          for (final (index, (values, color)) in series.indexed)
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(
                    i.toDouble(),
                    // Solo la PRIMERA serie (la bajada, en la Red) se
                    // invierte: es lo que la manda al semieje negativo, que
                    // fl_chart dibuja mas abajo en la pantalla.
                    mirrored && index == 0 ? -values[i] : values[i],
                  ),
              ],
              isCurved: true,
              color: color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                // Sin esto el relleno va desde la curva hasta el PISO del
                // grafico (`minY`, muy abajo con el eje espejado) en vez de
                // hasta la linea base compartida -- exactamente lo que
                // convierte el area en dos mitades separadas por el cero.
                applyCutOffY: mirrored,
                cutOffY: 0,
                gradient: LinearGradient(
                  // La primera serie invertida rellena hacia ARRIBA (de la
                  // curva, mas abajo, hacia el cero): el degrade tiene que
                  // salir opaco desde abajo. El resto sigue como siempre.
                  begin: mirrored && index == 0
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  end: mirrored && index == 0
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
        ],
      ),
      duration: AppDuration.chart,
      curve: AppCurves.standard,
    );
  }
}
