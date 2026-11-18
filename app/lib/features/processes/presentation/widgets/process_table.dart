import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../../dashboard/domain/metric_kind.dart';
import '../../domain/process_group.dart';
import '../../domain/process_panel_dock.dart';

/// El reparto de ancho de la tabla, en una sola definicion.
///
/// Encabezado y filas leen de aca: con dos listas de `flex` separadas, la
/// primera vez que alguien toca una se desalinean las columnas y el bug es
/// dificil de ver (todo "parece" bien, solo esta corrido).
class ProcessColumns {
  const ProcessColumns._();

  static const int name = 5;
  static const int metric = 3;
  static const int time = 2;

  /// Ancho del boton de cerrar. Fijo, no flex: es un icono.
  static const double actionWidth = 32;
}

/// Encabezado de la tabla. Sin esto, las columnas eran cuatro numeros sueltos
/// sin decir de que son -- un `4.0 GB` al lado de un `3.5%` no se explica solo.
class ProcessTableHeader extends StatelessWidget {
  const ProcessTableHeader({
    super.key,
    required this.metric,
    required this.density,
    required this.accentColor,
    this.showAskAi = false,
  });

  final MetricKind metric;
  final ProcessRowDensity density;
  final Color accentColor;

  /// Si las filas van a mostrar el boton de preguntarle a la IA -- el hueco
  /// reservado al final del encabezado tiene que saber si son uno o dos
  /// botones, o encabezado y filas se desalinean.
  final bool showAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 10,
      letterSpacing: 0.4,
    );
    final full = density == ProcessRowDensity.full;

    Widget cell(String text, int flex, {bool highlighted = false}) => Expanded(
      flex: flex,
      child: Text(
        text.toUpperCase(),
        style: highlighted ? style?.copyWith(color: accentColor) : style,
        textAlign: flex == ProcessColumns.name
            ? TextAlign.start
            : TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.processRowGutter,
        AppSpacing.xs,
        AppSizes.processRowGutter,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          cell('Aplicación', ProcessColumns.name),
          if (full) ...[
            cell('CPU', ProcessColumns.metric, highlighted: metric == MetricKind.cpu),
            cell('Memoria', ProcessColumns.metric, highlighted: metric == MetricKind.ram),
            cell('GPU', ProcessColumns.metric, highlighted: metric == MetricKind.gpu),
            cell('Disco', ProcessColumns.metric, highlighted: metric == MetricKind.disk),
          ] else
            cell(_shortName(metric), ProcessColumns.metric, highlighted: true),
          cell('Tiempo', ProcessColumns.time),
          SizedBox(width: ProcessColumns.actionWidth * (showAskAi ? 2 : 1)),
        ],
      ),
    );
  }

  static String _shortName(MetricKind metric) => switch (metric) {
    MetricKind.cpu => 'CPU',
    MetricKind.ram => 'Memoria',
    MetricKind.gpu => 'GPU',
    MetricKind.disk => 'Disco',
    MetricKind.network => 'Red',
  };
}

/// Una celda con la cifra grande y, debajo, su contexto en chico.
///
/// Es lo que permite meter dos datos en el ancho de uno: `4.0 GB` con `12%`
/// abajo, o `3 h` con `21 min`. Antes el tiempo se escribia entero en una
/// linea (`3 h 21 min`) y se comia el ancho de una columna de datos.
class StackedCell extends StatelessWidget {
  const StackedCell({
    super.key,
    required this.value,
    this.caption,
    this.highlighted = false,
    this.accentColor,
  });

  final String value;
  final String? caption;
  final bool highlighted;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          // Cifras tabulares: la tabla se refresca cada 2 s y sin esto las
          // columnas bailan de ancho.
          style: AppText.numeric(
            theme.textTheme.bodySmall?.copyWith(
              color: highlighted
                  ? (accentColor ?? theme.colorScheme.primary)
                  : theme.colorScheme.onSurface,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null)
          Text(
            caption!,
            style: AppText.numeric(
              theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                height: 1.1,
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Cuanto del total del equipo se lleva este proceso, ya formateado.
///
/// El porcentaje de CPU y el de GPU **ya son** fraccion del total, asi que
/// para esos dos no hay nada que calcular. El que faltaba era el de memoria:
/// `4.0 GB` no dice si es mucho sin saber cuanta RAM tiene la maquina.
String? shareOfTotal(ProcessGroup group, MetricKind metric, double? totalMb) {
  if (metric != MetricKind.ram || totalMb == null || totalMb <= 0) return null;
  final percent = group.memoryMb / totalMb * 100;
  return '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}% del total';
}

/// `3 h 21 min` partido en dos lineas: `3 h` y `21 min`.
///
/// Devuelve `(valor, detalle)`. El detalle es `null` cuando la unidad sola ya
/// alcanza, para no dibujar una segunda linea vacia.
(String, String?) splitRunTime(int seconds) {
  if (seconds <= 0) return ('—', null);
  if (seconds < 60) return ('$seconds s', null);
  if (seconds < 3600) return ('${seconds ~/ 60} min', null);
  if (seconds < 86400) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return ('$hours h', minutes == 0 ? null : '$minutes min');
  }
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  return ('$days d', hours == 0 ? null : '$hours h');
}
