import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../domain/metric_thresholds.dart';

/// Termometro que sube y baja con la temperatura del procesador.
///
/// Misma idea que el resto de los graficos de esta pantalla: dibuja la cosa
/// que mide. Lo que aporta sobre el numero suelto es el **color**: de un
/// vistazo se ve si el equipo esta fresco o al limite, sin tener que saber de
/// memoria a partir de cuantos grados hay que preocuparse.
class ThermometerChart extends StatelessWidget {
  const ThermometerChart({super.key, required this.celsius});

  /// `null` cuando la maquina no informa temperatura. Ahi el termometro se
  /// dibuja vacio y apagado en vez de fingir un valor.
  final double? celsius;

  /// Rango util de un procesador de escritorio. Por debajo de [coldC] el tubo
  /// queda casi vacio y por encima de [hotC] lleno: fuera de esa banda el dato
  /// ya no aporta matiz.
  static const double coldC = 30;
  static const double hotC = 95;

  /// A partir de aca se considera caliente y el color vira al de alerta.
  /// `kCpuHotTempC` y no un numero propio: el chip, el numero de grados y el
  /// badge de hilos (`metric_specs.dart`) tienen que virar todos al mismo
  /// umbral, no cada uno al suyo.
  static const double warnC = kCpuHotTempC;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = celsius;

    return TweenAnimationBuilder<double>(
      // Se anima el valor, no el widget: la temperatura llega una vez por
      // segundo y sin esto el mercurio saltaria.
      tween: Tween(begin: coldC, end: value ?? coldC),
      duration: AppDuration.chart,
      curve: AppCurves.standard,
      builder: (context, animated, _) {
        final fraction = ((animated - coldC) / (hotC - coldC)).clamp(0.0, 1.0);
        return CustomPaint(
          painter: _ThermometerPainter(
            fraction: value == null ? 0 : fraction,
            // El color lo decide la temperatura REAL y no la fraccion: asi el
            // viraje ocurre siempre a los mismos grados, aunque se cambie el
            // rango del tubo.
            color: value != null && animated >= warnC
                ? scheme.error
                : scheme.primary,
            emptyColor: scheme.surfaceContainerHighest,
            outlineColor: scheme.outlineVariant,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ThermometerPainter extends CustomPainter {
  _ThermometerPainter({
    required this.fraction,
    required this.color,
    required this.emptyColor,
    required this.outlineColor,
  });

  final double fraction;
  final Color color;
  final Color emptyColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 6 || size.height < 12) return;

    // El termometro es alto y angosto: se centra en la caja que le den.
    final bulbRadius = (size.width * 0.42).clamp(3.0, size.height * 0.16);
    final tubeWidth = bulbRadius * 1.05;
    final centerX = size.width / 2;
    final bulbCenter = Offset(centerX, size.height - bulbRadius);
    final tubeTop = size.height * 0.06;
    final tubeBottom = bulbCenter.dy;

    final tube = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        centerX - tubeWidth / 2,
        tubeTop,
        centerX + tubeWidth / 2,
        tubeBottom,
      ),
      Radius.circular(tubeWidth / 2),
    );

    // 1. Tubo y bulbo vacios.
    canvas.drawRRect(tube, Paint()..color = emptyColor);
    canvas.drawCircle(bulbCenter, bulbRadius, Paint()..color = emptyColor);

    // 2. El bulbo SIEMPRE va coloreado: es el deposito, y un termometro con el
    //    bulbo vacio no se lee como termometro.
    canvas.drawCircle(bulbCenter, bulbRadius * 0.82, Paint()..color = color);

    // 3. La columna, recortada al tubo para respetar las puntas redondeadas.
    if (fraction > 0) {
      final columnTop = tubeBottom - (tubeBottom - tubeTop) * fraction;
      canvas.save();
      canvas.clipRRect(tube);
      canvas.drawRect(
        Rect.fromLTRB(
          centerX - tubeWidth / 2,
          columnTop,
          centerX + tubeWidth / 2,
          tubeBottom,
        ),
        Paint()..color = color,
      );
      canvas.restore();
    }

    // 4. Las marcas de la escala, a un costado. Son lo que lo vuelve
    //    reconocible como termometro y no como una barra vertical.
    final tickPaint = Paint()
      ..color = outlineColor
      ..strokeWidth = 1;
    final tickX = centerX + tubeWidth / 2 + 1.5;
    if (tickX + 3 <= size.width) {
      for (var i = 1; i <= 3; i++) {
        final y = tubeTop + (tubeBottom - tubeTop) * (i / 4);
        canvas.drawLine(Offset(tickX, y), Offset(tickX + 3, y), tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ThermometerPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.emptyColor != emptyColor ||
      old.outlineColor != outlineColor;
}
