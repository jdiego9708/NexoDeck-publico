import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../domain/cpu_frequency.dart';
import 'cpu_chip_chart.dart';
import 'thermometer_chart.dart';

/// El cuerpo del grafico de la tile de CPU: las cifras del procesador a la
/// izquierda, el chip con su historial en el medio y el termometro a la
/// derecha.
///
/// Va como `MetricSpec.chart` --y no como badges-- porque la temperatura y la
/// frecuencia son **lo que el chip esta haciendo**, no datos al margen: puestas
/// al lado del dibujo se leen juntas. Los hilos y el porcentaje quedan abajo,
/// en la fila de valores de la tile.
///
/// **Las tres columnas son un pedido, no una garantia**, igual que el ancho
/// doble de la tile de disco: se conceden solo si hay
/// [AppSizes.cpuGaugesFullWidth] de ancho. En el reparto lateral --el riel del
/// telefono y la franja de un telefono vertical, donde el grafico mide 36-48
/// dp-- el chip se queda con toda la caja, y de la temperatura y la frecuencia
/// se encarga `MetricSpec.fallbackBadges`. Repartir esos 36 dp entre tres
/// columnas dejaba el chip del tamano de un badge y las cifras escaladas hasta
/// no leerse, que es justo lo que se veia en el telefono.
class CpuGauges extends StatelessWidget {
  const CpuGauges({
    super.key,
    required this.usedFraction,
    required this.color,
    required this.history,
    required this.celsius,
    required this.clockMhz,
  });

  final double usedFraction;
  final Color color;

  /// El sparkline que va dentro del chip.
  final Widget history;

  /// `null` cuando esta maquina no informa temperatura (en Windows hace falta
  /// un proveedor con driver; ver `cpu_temp.rs`).
  final double? celsius;
  final int? clockMhz;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppSizes.cpuGaugesFullWidth) {
          // Solo el chip, con toda la caja: es el dibujo que identifica a la
          // metrica, y compartido a este ancho no se reconoce ninguno de los
          // tres.
          return CpuChipChart(
            usedFraction: usedFraction,
            color: color,
            child: history,
          );
        }
        return _buildGauges(context);
      },
    );
  }

  Widget _buildGauges(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Las cifras se achican antes que desbordar: en el riel la tile mide
        // ~190 dp de ancho y aca comparten fila con dos dibujos.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  celsius == null
                      ? '— °C'
                      : '${celsius!.toStringAsFixed(0)}°C',
                  style: AppText.numeric(
                    theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      // Sin dato, atenuado: el hueco tiene que verse como
                      // "no se puede medir" y no como un cero.
                      color: celsius == null
                          ? theme.colorScheme.onSurfaceVariant
                          : color,
                    ),
                  ),
                  maxLines: 1,
                ),
                if (clockMhz != null)
                  Text(
                    formatCpuFrequency(clockMhz!),
                    style: AppText.numeric(
                      theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // El chip se lleva el espacio que sobra: es el protagonista.
        Expanded(
          flex: 2,
          child: CpuChipChart(
            usedFraction: usedFraction,
            color: color,
            child: history,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // El termometro es alto y angosto, asi que se le da un ancho fijo
        // proporcional en vez de un `Expanded` que lo dejaria gordo.
        SizedBox(
          width: AppSizes.thermometerWidth,
          child: ThermometerChart(celsius: celsius),
        ),
      ],
    );
  }
}
