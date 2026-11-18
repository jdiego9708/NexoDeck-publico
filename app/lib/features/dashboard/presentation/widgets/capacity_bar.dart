import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text.dart';

/// Barra de progreso con la cifra **adentro**, para capacidades que se leen
/// como "cuanto de cuanto" (la VRAM de la GPU).
///
/// Reemplaza al badge de texto que decia `2.5 GB/15.9 GB`: ese numero solo
/// contaba la historia si uno hacia la division mentalmente. Metido en una
/// barra, la proporcion se ve antes de leer.
///
/// El texto se dibuja **una vez sobre cada mitad** con un color distinto, como
/// el porcentaje de los modulos de RAM: un solo color siempre se pierde contra
/// uno de los dos fondos, y la cifra cae justo sobre la frontera del relleno.
class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.fraction,
    required this.label,
    required this.color,
    this.labelOnFilled,
    this.height = 16,
  });

  /// 0.0-1.0 de ocupacion.
  final double fraction;

  /// Lo que va escrito adentro, ya formateado (`2.5 / 15.9 GB`).
  final String label;
  final Color color;

  /// Color de la cifra sobre la mitad rellena. `null` = `scheme.onSecondary`,
  /// el de siempre -- pensado para cuando [color] es `scheme.secondary` o
  /// parecido. Un [color] de alerta (`scheme.error`) necesita su propio
  /// contraste (`scheme.onError`); pasarlo aca es lo que evita que la cifra
  /// se pierda contra un relleno que ya no es el de siempre.
  final Color? labelOnFilled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(height / 2);
    final clamped = fraction.clamp(0.0, 1.0);

    final textStyle = AppText.numeric(
      theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: height * 0.6,
      ),
    );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHighest),
            Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                // Animada por el mismo motivo que el resto de los charts: el
                // valor cambia una vez por segundo y un salto seco llama mas
                // la atencion que el dato.
                duration: AppDuration.chart,
                curve: AppCurves.standard,
                widthFactor: clamped,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
            // El texto, en dos colores partidos exactamente donde termina
            // el relleno: un `LinearGradient` con los dos `stops` en el mismo
            // punto da un corte duro, y `srcIn` lo aplica a las letras. Un
            // solo color siempre se pierde contra uno de los dos fondos, y
            // esta cifra cae justo sobre la frontera.
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                stops: [clamped, clamped],
                colors: [
                  labelOnFilled ?? scheme.onSecondary,
                  scheme.onSurfaceVariant,
                ],
              ).createShader(bounds),
              child: Center(
                child: Text(
                  label,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
