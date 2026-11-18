import 'dart:math' as math;

import 'package:flutter/material.dart';

/// La GPU dibujada como la placa que es: el PCB con su cooler, llenandose con
/// el uso y con los ventiladores girando mas rapido cuanto mas trabaja.
///
/// Misma idea que los modulos de `RamModuleChart` y por el mismo motivo: el
/// grafico dibuja la pieza que mide, asi la tile se reconoce de un vistazo sin
/// leer el titulo. Lo que aporta de mas es el giro: **la velocidad de los
/// ventiladores es el uso**, asi que desde lejos --sin distinguir el numero--
/// ya se ve si la placa esta trabajando.
class GpuCardChart extends StatefulWidget {
  const GpuCardChart({
    super.key,
    required this.usedFraction,
    required this.color,
  });

  /// 0.0-1.0, o `null` cuando la maquina no informa uso de GPU. Sin dato la
  /// placa se dibuja igual pero quieta y vacia: el hueco explica mas que no
  /// dibujar nada.
  final double? usedFraction;
  final Color color;

  @override
  State<GpuCardChart> createState() => _GpuCardChartState();
}

class _GpuCardChartState extends State<GpuCardChart>
    with SingleTickerProviderStateMixin {
  /// Una vuelta completa a maxima carga. El controlador gira **siempre** a
  /// ritmo constante y quien decide la velocidad aparente es el multiplicador
  /// del painter: reiniciar el controlador con cada cambio de uso (una vez por
  /// segundo) daria saltos en el angulo.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = (widget.usedFraction ?? 0.0).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) => CustomPaint(
        painter: _GpuCardPainter(
          usedFraction: fraction,
          spin: _spin.value,
          color: widget.color,
          bodyColor: scheme.surfaceContainerHighest,
          detailColor: scheme.outlineVariant,
          hasData: widget.usedFraction != null,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GpuCardPainter extends CustomPainter {
  _GpuCardPainter({
    required this.usedFraction,
    required this.spin,
    required this.color,
    required this.bodyColor,
    required this.detailColor,
    required this.hasData,
  });

  final double usedFraction;

  /// 0.0-1.0 de la vuelta del controlador.
  final double spin;
  final Color color;
  final Color bodyColor;
  final Color detailColor;
  final bool hasData;

  /// Aspas por ventilador.
  static const int _blades = 7;

  /// Vueltas por ciclo del controlador a carga maxima. Con la GPU al 100% el
  /// ventilador da varias vueltas en los 3 s del ciclo; en reposo queda
  /// practicamente quieto.
  static const double _maxTurns = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 12 || size.height < 8) return;

    // La placa es apaisada (una GPU real lo es). Se centra en la caja que le
    // den, tomando el mayor rectangulo 2:1 que entre.
    final width = math.min(size.width, size.height * 2.0);
    final height = width / 2.0;
    final board = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
    final radius = Radius.circular(height * 0.14);
    final body = RRect.fromRectAndRadius(board, radius);

    // 1. PCB vacio.
    canvas.drawRRect(body, Paint()..color = bodyColor);

    // 2. Lo usado, recortado al PCB para respetar las esquinas.
    if (usedFraction > 0) {
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRect(
        Rect.fromLTWH(board.left, board.top, board.width * usedFraction, board.height),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      canvas.restore();
    }

    // 3. El conector PCIe: la lengueta de contactos de abajo a la izquierda es
    //    lo que vuelve reconocible la silueta a tamano chico.
    final connector = Rect.fromLTWH(
      board.left + board.width * 0.08,
      board.bottom,
      board.width * 0.26,
      height * 0.12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(connector, Radius.circular(height * 0.04)),
      Paint()..color = detailColor,
    );

    // 4. Los dos ventiladores.
    final fanRadius = height * 0.33;
    for (final dx in [0.32, 0.7]) {
      _paintFan(
        canvas,
        Offset(board.left + board.width * dx, board.center.dy),
        fanRadius,
      );
    }

    // 5. Contorno, para que la placa se despegue del fondo de la tile.
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.5),
    );
  }

  void _paintFan(Canvas canvas, Offset center, double radius) {
    if (radius <= 2) return;

    // El hueco del ventilador: siempre oscuro, tambien sobre la parte llena,
    // asi el aspa se lee con cualquier nivel de uso.
    canvas.drawCircle(center, radius, Paint()..color = bodyColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = detailColor,
    );

    // Sin dato no hay giro: una GPU que no informa nada no puede fingir que
    // esta trabajando.
    final turns = hasData ? spin * _maxTurns * usedFraction : 0.0;
    final angle = turns * 2 * math.pi;

    final bladePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.18)
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < _blades; i++) {
      final theta = angle + i * 2 * math.pi / _blades;
      canvas.drawLine(
        center + Offset(math.cos(theta), math.sin(theta)) * (radius * 0.25),
        center + Offset(math.cos(theta), math.sin(theta)) * (radius * 0.82),
        bladePaint,
      );
    }

    // Buje central.
    canvas.drawCircle(center, radius * 0.2, Paint()..color = detailColor);
  }

  @override
  bool shouldRepaint(_GpuCardPainter old) =>
      old.usedFraction != usedFraction ||
      old.spin != spin ||
      old.color != color ||
      old.bodyColor != bodyColor ||
      old.detailColor != detailColor ||
      old.hasData != hasData;
}
