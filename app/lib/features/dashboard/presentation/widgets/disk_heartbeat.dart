import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Aire arriba/abajo del pico mas alto del historial, para que un pico nuevo
/// no toque el borde del widget apenas aparece.
const _kHeadroom = 1.2;

/// Cuantas muestras recientes se dibujan. El historial completo
/// (`_kHistoryLength` en `metrics_row.dart`, 30 muestras) es demasiado para
/// el ancho angosto de este widget -- 30 picos en 40 dp serian una mancha,
/// no triangulos reconocibles. Con esto cada pico mide ~4 dp de base, que es
/// lo que los mantiene legibles como picos y no como ruido.
const _kVisibleSamples = 10;

/// Senal de vida de actividad de disco, estilo monitor de signos vitales de
/// hospital: una linea base horizontal con picos TRIANGULARES hacia abajo
/// (lectura) o hacia arriba (escritura) -- sube y vuelve a la base en la
/// misma muestra, no un tick suelto -- con altura proporcional a los bytes
/// de esa muestra. Sin actividad, la linea queda plana.
///
/// Ancla al borde derecho de la fila del identificador (`D: Secundario
/// ‹señal›`), con la etiqueta anclada a la izquierda -- no en la fila de la
/// barra/cifra, y no pegada al nombre: son dos ajustes de diseño pedidos
/// despues de ver las dos alternativas en la app real.
///
/// No usa `TweenAnimationBuilder` como los gauges de un solo valor (RAM,
/// GPU): esto es un historial que se redibuja entero en cada muestra nueva,
/// igual que `MiniLineChart` -- el widget mas parecido que ya existe en el
/// proyecto para esta forma de dato.
class DiskHeartbeat extends StatelessWidget {
  const DiskHeartbeat({
    super.key,
    required this.readHistoryKb,
    required this.writeHistoryKb,
    required this.color,
  });

  /// Mismo largo e indice que `writeHistoryKb`: la muestra `i` de lectura y
  /// la `i` de escritura son del mismo instante. En KB para que la escala
  /// visual coincida con la que ya usan las otras senales de red/disco.
  final List<double> readHistoryKb;
  final List<double> writeHistoryKb;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSizes.diskHeartbeatWidth,
      height: AppSizes.diskHeartbeatHeight,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HeartbeatPainter(
          readHistoryKb: readHistoryKb,
          writeHistoryKb: writeHistoryKb,
          color: color,
        ),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  _HeartbeatPainter({
    required this.readHistoryKb,
    required this.writeHistoryKb,
    required this.color,
  });

  final List<double> readHistoryKb;
  final List<double> writeHistoryKb;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height / 2;
    final basePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      basePaint,
    );

    // Solo las ultimas `_kVisibleSamples`: mismo criterio que un monitor de
    // signos vitales, que muestra el tramo reciente, no la sesion entera.
    final start = (readHistoryKb.length - _kVisibleSamples).clamp(
      0,
      readHistoryKb.length,
    );
    final reads = readHistoryKb.sublist(start);
    final writes = writeHistoryKb.sublist(
      (writeHistoryKb.length - reads.length).clamp(0, writeHistoryKb.length),
    );
    if (reads.isEmpty) return;

    final peak = [
      1.0,
      ...reads,
      ...writes,
    ].reduce((a, b) => a > b ? a : b);
    final scale = (baseline - 1) / (peak * _kHeadroom);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final stepX = size.width / reads.length;
    // Base del triangulo: una fraccion del paso entre muestras, para que
    // queden separados entre si en vez de fundirse en una sola cresta.
    final halfBase = stepX * 0.35;

    final path = Path()..moveTo(0, baseline);
    for (var i = 0; i < reads.length; i++) {
      final read = reads[i];
      final write = i < writes.length ? writes[i] : 0.0;
      final center = stepX * i + stepX / 2;

      if (read <= 0 && write <= 0) {
        path.lineTo(center + halfBase, baseline);
        continue;
      }
      // Escritura hacia arriba, lectura hacia abajo -- nunca las dos en la
      // misma muestra: son bytes que se movieron ese segundo, no dos cosas
      // pasando a la vez que haya que sumar.
      final peakY = write >= read
          ? baseline - write * scale
          : baseline + read * scale;
      // Sube y baja DENTRO de la misma muestra -- lo que dibuja un triangulo
      // en vez de un tick suelto o una montana continua con la muestra de al
      // lado.
      path
        ..lineTo(center - halfBase, baseline)
        ..lineTo(center, peakY)
        ..lineTo(center + halfBase, baseline);
    }
    canvas.drawPath(path, linePaint);
  }

  // Siempre repinta. Quien llama muta las listas EN EL LUGAR (`_pushCapped`
  // en `metrics_row.dart`/`connected_device_screen.dart`), asi que comparar
  // `oldDelegate.readHistoryKb != readHistoryKb` compararia el mismo objeto
  // contra si mismo y nunca repintaria una muestra nueva.
  @override
  bool shouldRepaint(_HeartbeatPainter oldDelegate) => true;
}
