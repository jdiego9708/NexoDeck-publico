import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/theme/app_text.dart';
import '../../domain/history_series.dart';

/// Grafico de una metrica a lo largo del tiempo, con ejes y etiquetas.
///
/// Distinto de `MiniLineChart` (el sparkline de la fila de metricas): aca
/// el eje X es TIEMPO REAL, no el indice de la muestra, porque el historial
/// puede tener huecos (la app estuvo cerrada) y dibujarlo por indice los
/// escondería, mostrando una linea continua donde no hubo datos.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.title,
    required this.unit,
    required this.series,
    this.fixedMaxY,
    this.legend,
  });

  final String title;
  final String unit;

  /// Cada entrada es (puntos, color).
  final List<(List<HistoryPoint>, Color)> series;

  /// Tope fijo del eje Y (100 para porcentajes). Si es `null` se usa el
  /// maximo real de la serie.
  final double? fixedMaxY;

  /// Nombres de cada serie, si hay mas de una.
  final List<String>? legend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = series.expand((s) => s.$1).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppSurface.cardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                unit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (legend != null)
                for (final (index, name) in legend!.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 3,
                          decoration: BoxDecoration(
                            color: series[index].$2,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(name, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 130,
            child: points.isEmpty
                ? Center(
                    child: Text(
                      'Sin datos en este rango',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : _buildChart(context, points),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<HistoryPoint> all) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final minX = all
        .map((p) => p.at.millisecondsSinceEpoch)
        .reduce((a, b) => a < b ? a : b)
        .toDouble();
    final maxX = all
        .map((p) => p.at.millisecondsSinceEpoch)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final maxY = fixedMaxY ?? maxOf(all) * 1.15;

    return LineChart(
      LineChartData(
        minX: minX,
        // Un solo punto dejaria min == max y fl_chart no puede repartir el
        // eje: se le da un ancho minimo artificial.
        maxX: maxX > minX ? maxX : minX + 1000,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: AppText.numeric(theme.textTheme.bodySmall)?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              // Solo 3 marcas: con mas, en 7 dias las horas se encabalgan.
              interval: (maxX - minX) / 3,
              getTitlesWidget: (value, meta) {
                final at = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _formatTick(at, maxX - minX),
                    style: AppText.numeric(theme.textTheme.bodySmall)?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          // Un tramo por cada trozo continuo: los huecos de datos (app
          // cerrada) quedan vacios en vez de unirse con una recta que
          // afirmaria que hubo datos ahi. Ver `splitOnGaps`.
          for (final (points, color) in series)
            for (final segment in splitOnGaps(points))
              LineChartBarData(
                spots: [
                  for (final p in segment)
                    FlSpot(
                      p.at.millisecondsSinceEpoch.toDouble(),
                      p.value.clamp(0, maxY),
                    ),
                ],
                isCurved: true,
                preventCurveOverShooting: true,
                color: color,
                barWidth: 2,
                // Un tramo de UN solo punto no dibuja linea: sin punto
                // visible desapareceria. Pasa de verdad justo despues de un
                // hueco, con la primera muestra nueva (se corrige sola a
                // los 15 s, cuando llega la segunda).
                dotData: FlDotData(show: segment.length == 1),
                belowBarData: BarAreaData(
                  show: series.length == 1,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.22),
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

  /// En rangos de horas alcanza `HH:mm`; en varios dias, la hora sola es
  /// ambigua (¿las 14 de que dia?), asi que se antepone el dia.
  static String _formatTick(DateTime at, double spanMs) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    if (spanMs > const Duration(days: 1).inMilliseconds) {
      return '${at.day}/${at.month} $hh:$mm';
    }
    return '$hh:$mm';
  }
}
