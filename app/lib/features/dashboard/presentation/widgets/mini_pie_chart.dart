import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text.dart';

/// Donut compacto de dos secciones (usado/libre) con el porcentaje en el
/// centro -- pensado para caber en una tarjeta chica de la fila de
/// metricas.
class MiniPieChart extends StatelessWidget {
  const MiniPieChart({
    super.key,
    required this.usedFraction,
    required this.color,
  });

  /// 0.0-1.0. `null` cuando no hay dato (ej. sin GPU detectada) -- se
  /// dibuja un donut vacio en gris.
  final double? usedFraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = usedFraction?.clamp(0.0, 1.0);
    final trackColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    // Los radios se derivan del box real en vez de ser fijos: la misma tile
    // se pinta a 48 px en la franja de escritorio y a ~32 px en el riel de
    // un telefono en horizontal, y con valores fijos el donut se recortaba.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final centerSpaceRadius = side * 0.30;
        final sectionRadius = (side * 0.20).clamp(3.0, 14.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sections: fraction == null
                    ? [
                        PieChartSectionData(
                          value: 1,
                          color: trackColor,
                          showTitle: false,
                          radius: sectionRadius,
                        ),
                      ]
                    : [
                        PieChartSectionData(
                          value: fraction,
                          color: color,
                          showTitle: false,
                          radius: sectionRadius,
                        ),
                        PieChartSectionData(
                          value: 1 - fraction,
                          color: trackColor,
                          showTitle: false,
                          radius: sectionRadius,
                        ),
                      ],
                sectionsSpace: 0,
                centerSpaceRadius: centerSpaceRadius,
              ),
              duration: AppDuration.chart,
              curve: AppCurves.standard,
            ),
            Text(
              fraction == null
                  ? 'N/D'
                  : '${(fraction * 100).toStringAsFixed(0)}%',
              // Tabular, igual que el valor de la tile: el porcentaje del
              // centro del donut tambien cambia cada segundo y sin esto se
              // descentra al pasar de 9% a 10%.
              style: AppText.numeric(
                TextStyle(
                  fontSize: (side * 0.24).clamp(8.0, 13.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
