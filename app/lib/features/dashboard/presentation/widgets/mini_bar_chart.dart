import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';

/// Barra vertical compacta usado-vs-total (relleno sobre un track de
/// fondo, via `backDrawRodData`) -- pensada para caber en una tarjeta
/// chica de la fila de metricas.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.usedFraction,
    required this.color,
  });

  /// 0.0-1.0.
  final double usedFraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = usedFraction.clamp(0.0, 1.0);
    final trackColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    // Ancho de la barra derivado del box (ver el mismo criterio en
    // `MiniPieChart`): a 36 px de tile una barra de 20 px fijos ocupaba
    // practicamente todo el ancho.
    return LayoutBuilder(
      builder: (context, constraints) {
        final rodWidth = (constraints.biggest.shortestSide * 0.4).clamp(
          6.0,
          20.0,
        );
        return _buildChart(fraction, trackColor, rodWidth);
      },
    );
  }

  Widget _buildChart(double fraction, Color trackColor, double rodWidth) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        alignment: BarChartAlignment.center,
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: fraction,
                color: color,
                width: rodWidth,
                borderRadius: BorderRadius.circular(AppRadius.badge - 2),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 1,
                  color: trackColor,
                ),
              ),
            ],
          ),
        ],
      ),
      duration: AppDuration.chart,
      curve: AppCurves.standard,
    );
  }
}
