import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';

/// El CPU dibujado como el chip que es: encapsulado con sus pines y la muesca
/// del pin 1, y **adentro** el mismo historial de uso que se mostraba antes.
///
/// Misma idea que los modulos de `RamModuleChart` y la placa de
/// `GpuCardChart`: el grafico dibuja la pieza que mide, asi la tile se
/// reconoce sin leer el titulo. La diferencia es que aca el chip es el marco
/// --no se llena-- y quien informa sigue siendo la curva de adentro.
///
/// El borde se enciende con el uso: no es adorno, es lo que hace que desde
/// lejos, sin distinguir el numero, se note que el procesador esta cargado.
class CpuChipChart extends StatelessWidget {
  const CpuChipChart({
    super.key,
    required this.usedFraction,
    required this.color,
    required this.child,
  });

  /// 0.0-1.0 de uso, para la intensidad del borde.
  final double usedFraction;
  final Color color;

  /// El grafico que va dentro del encapsulado (el historial de CPU).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // El chip es cuadrado y se centra en la caja que le den: en la franja
        // manda el alto, en el riel el ancho.
        final side = constraints.biggest.shortestSide;
        if (side <= 0) return const SizedBox.shrink();

        return Center(
          child: SizedBox.square(
            dimension: side,
            // Se anima el VALOR y no el widget, igual que los modulos de RAM:
            // el uso llega una vez por segundo y sin esto el borde saltaria.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: usedFraction.clamp(0.0, 1.0)),
              duration: AppDuration.chart,
              curve: AppCurves.standard,
              builder: (context, value, inner) => CustomPaint(
                painter: ChipFramePainter(
                  intensity: value,
                  color: color,
                  bodyColor: scheme.surfaceContainerHighest,
                  detailColor: scheme.outlineVariant,
                ),
                child: inner,
              ),
              // El hijo se construye una vez y el builder lo reusa: si no, se
              // reconstruiria en cada frame de la animacion.
              child: Padding(
                padding: EdgeInsets.all(side * ChipFramePainter.contentInset),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dibuja el encapsulado: cuerpo, pines y muesca. Publico porque el marco es
/// reutilizable -- lo que cambia entre metricas es lo que va adentro.
class ChipFramePainter extends CustomPainter {
  ChipFramePainter({
    required this.intensity,
    required this.color,
    required this.bodyColor,
    required this.detailColor,
  });

  /// 0.0-1.0. Sube el brillo del borde con la carga.
  final double intensity;
  final Color color;
  final Color bodyColor;
  final Color detailColor;

  /// Fraccion del lado que queda por fuera del encapsulado, reservada a los
  /// pines. Publica para que el widget aplique el mismo margen al contenido y
  /// quede centrado dentro del chip y no dentro de la caja entera.
  static const double contentInset = 0.19;

  static const int _pinsPerSide = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 10) return;

    final inset = side * contentInset * 0.6;
    final body = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final radius = Radius.circular(side * 0.12);

    _paintPins(canvas, body, side);

    canvas.drawRRect(
      RRect.fromRectAndRadius(body, radius),
      Paint()..color = bodyColor,
    );

    // El borde: `lerp` sobre el alfa y no sobre el color, para que el tono no
    // se desvie del acento de la metrica.
    canvas.drawRRect(
      RRect.fromRectAndRadius(body.deflate(0.75), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.03
        ..color = color.withValues(alpha: 0.35 + intensity * 0.6),
    );

    // La muesca del pin 1: es lo que vuelve reconocible la silueta a 40 dp.
    final notch = side * 0.045;
    canvas.drawCircle(
      Offset(body.left + notch * 2.2, body.top + notch * 2.2),
      notch,
      Paint()..color = color.withValues(alpha: 0.8),
    );
  }

  void _paintPins(Canvas canvas, Rect body, double side) {
    final paint = Paint()..color = detailColor;
    final length = side * contentInset * 0.5;
    final thickness = side * 0.04;
    final radius = Radius.circular(thickness / 2);

    for (var i = 0; i < _pinsPerSide; i++) {
      // Repartidos dejando aire en las esquinas, como un chip real.
      final t = (i + 1) / (_pinsPerSide + 1);
      final x = body.left + body.width * t;
      final y = body.top + body.height * t;

      for (final pin in [
        Rect.fromLTWH(x - thickness / 2, body.top - length, thickness, length),
        Rect.fromLTWH(x - thickness / 2, body.bottom, thickness, length),
        Rect.fromLTWH(body.left - length, y - thickness / 2, length, thickness),
        Rect.fromLTWH(body.right, y - thickness / 2, length, thickness),
      ]) {
        canvas.drawRRect(RRect.fromRectAndRadius(pin, radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(ChipFramePainter old) =>
      old.intensity != intensity ||
      old.color != color ||
      old.bodyColor != bodyColor ||
      old.detailColor != detailColor;
}
