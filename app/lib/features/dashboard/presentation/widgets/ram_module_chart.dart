import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text.dart';

/// Dos modulos de memoria que se van llenando con el uso de RAM.
///
/// Es la unica metrica cuyo grafico **dibuja la cosa que mide** en vez de un
/// donut o una linea: un par de modulos DIMM que se llenan de izquierda a
/// derecha, el primero antes que el segundo, como se ocuparia la memoria de
/// verdad. Con 50% queda el primero lleno y el segundo vacio; con 74%, el
/// primero lleno y el segundo por la mitad.
///
/// Los chips son parte del dibujo y no adorno: son la escala. Sin ellos el
/// modulo es un rectangulo y no se distingue de la barra de disco.
class RamModuleChart extends StatelessWidget {
  const RamModuleChart({
    super.key,
    required this.usedFraction,
    required this.color,
    this.alertColor,
    this.alertThreshold = 1.1,
  });

  /// 0.0-1.0. Se clampea: un dato roto no puede pintar fuera del modulo.
  final double usedFraction;
  final Color color;

  /// Color de un modulo cuando SU PROPIO llenado (no el total de RAM) cruza
  /// [alertThreshold]. `null` = sin alerta, todo modulo usa siempre [color]
  /// -- es lo que preserva el comportamiento de antes en cualquier lugar
  /// que todavia no pase un color de alerta.
  final Color? alertColor;

  /// Con el valor por defecto (>1.0) ningun modulo alerta nunca: hace falta
  /// pasar un umbral real (0.0-1.0) junto con [alertColor] para activarlo.
  final double alertThreshold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Se anima el VALOR, no el widget: `TweenAnimationBuilder` interpola
    // entre el porcentaje viejo y el nuevo cada vez que llega un snapshot,
    // asi el llenado se desliza en vez de saltar una vez por segundo. Mismo
    // criterio (y misma duracion) que las barras de la lista de discos.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: usedFraction.clamp(0.0, 1.0)),
      duration: AppDuration.chart,
      curve: AppCurves.standard,
      builder: (context, value, child) => CustomPaint(
        painter: _RamModulePainter(
          usedFraction: value,
          color: color,
          alertColor: alertColor,
          alertThreshold: alertThreshold,
          emptyColor: scheme.surfaceContainerHighest,
          outlineColor: scheme.outlineVariant,
          // El porcentaje se dibuja DOS veces, recortado a cada mitad, para
          // que se lea tanto sobre el relleno como sobre el hueco: un solo
          // color siempre se pierde contra uno de los dos fondos. Sobre un
          // modulo en alerta el relleno pasa a ser `alertColor` (rojo), asi
          // que el label de ESE lado tambien cambia -- `onSecondary` no
          // esta pensado para contrastar contra rojo.
          labelOnFilled: scheme.onSecondary,
          labelOnFilledAlert: scheme.onError,
          labelOnEmpty: scheme.onSurfaceVariant,
          labelStyle: AppText.numeric(
            theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        // Sin `size` propio: toma el que le da la tile, igual que los otros
        // charts, para que sirva en la franja, en el riel y en el movil.
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Cuanto le toca al modulo `index` de un total de `count`, en 0.0-1.0.
///
/// Los modulos se llenan **en orden**, como se ocuparia la memoria de verdad:
/// el primero cubre la primera mitad del total, el segundo la segunda. Con la
/// RAM al 74% y dos modulos, el primero queda al 100% y el segundo al 48%.
///
/// Pura y publica porque es lo que decide el numero que el usuario lee en el
/// centro de cada modulo.
double ramModuleFill(double usedFraction, int index, int count) {
  final total = usedFraction.clamp(0.0, 1.0);
  final start = index / count;
  return ((total - start) * count).clamp(0.0, 1.0);
}

class _RamModulePainter extends CustomPainter {
  _RamModulePainter({
    required this.usedFraction,
    required this.color,
    required this.alertColor,
    required this.alertThreshold,
    required this.emptyColor,
    required this.outlineColor,
    required this.labelOnFilled,
    required this.labelOnFilledAlert,
    required this.labelOnEmpty,
    required this.labelStyle,
  });

  final double usedFraction;
  final Color color;
  final Color? alertColor;
  final double alertThreshold;
  final Color emptyColor;
  final Color outlineColor;
  final Color labelOnFilled;
  final Color labelOnFilledAlert;
  final Color labelOnEmpty;
  final TextStyle? labelStyle;

  /// Por debajo de este alto de modulo el porcentaje no se dibuja: entraria
  /// a un tamano en el que no se lee, y tapando los chips deja al modulo sin
  /// su unica sena de identidad.
  static const double _minHeightForLabel = 22.0;

  /// Cuantos modulos se dibujan. Dos es lo que tiene un equipo tipico y lo
  /// que hace legible el llenado por etapas.
  static const int _moduleCount = 2;

  /// Chips por modulo. Ocho es lo que trae un DIMM real de una cara, y da una
  /// escala lo bastante fina como para que se note el avance.
  static const int _chipsPerModule = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Los modulos se apilan verticalmente y ocupan todo el ancho: en una
    // tile ancha y baja quedan como dos barras finas, que es exactamente lo
    // que son.
    const gap = 4.0;
    final moduleHeight = (size.height - gap * (_moduleCount - 1)) / _moduleCount;
    if (moduleHeight <= 2) return;

    for (var index = 0; index < _moduleCount; index++) {
      final top = index * (moduleHeight + gap);
      final rect = Rect.fromLTWH(0, top, size.width, moduleHeight);

      _paintModule(
        canvas,
        rect,
        ramModuleFill(usedFraction, index, _moduleCount),
      );
    }
  }

  void _paintModule(Canvas canvas, Rect rect, double fill) {
    final radius = Radius.circular(rect.height * 0.18);
    final body = RRect.fromRectAndRadius(rect, radius);
    // Este modulo, y no el total de RAM, es lo que decide si alerta: con dos
    // modulos que se llenan en orden, el primero puede estar al 100% (rojo)
    // mientras el segundo sigue vacio.
    final isAlert = alertColor != null && fill >= alertThreshold;
    final fillColor = isAlert ? alertColor! : color;

    // 1. El cuerpo vacio.
    canvas.drawRRect(body, Paint()..color = emptyColor);

    // 2. La parte llena, recortada al cuerpo para que respete las esquinas.
    if (fill > 0) {
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width * fill, rect.height),
        Paint()..color = fillColor,
      );
      canvas.restore();
    }

    // 3. Los chips, en negativo sobre el modulo. Se dibujan del color del
    //    fondo con transparencia, asi se leen tanto sobre la parte llena
    //    como sobre la vacia sin necesitar dos colores distintos.
    final chipPaint = Paint()..color = outlineColor.withValues(alpha: 0.55);
    final margin = rect.height * 0.22;
    final chipTop = rect.top + margin;
    final chipHeight = rect.height - margin * 2;
    if (chipHeight <= 0) return;

    final usableWidth = rect.width - margin * 2;
    final chipSlot = usableWidth / _chipsPerModule;
    final chipWidth = chipSlot * 0.6;
    if (chipWidth <= 0.5) return;

    for (var i = 0; i < _chipsPerModule; i++) {
      final left = rect.left + margin + chipSlot * i + (chipSlot - chipWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, chipTop, chipWidth, chipHeight),
          Radius.circular(chipWidth * 0.2),
        ),
        chipPaint,
      );
    }

    // 4. Cuanto esta usado ESTE modulo, en el centro. Es el dato que hace
    //    que los dos modulos se puedan leer por separado: con la RAM al 74%,
    //    el primero dice 100% y el segundo 48%.
    _paintFillLabel(canvas, rect, fill, isAlert);
  }

  void _paintFillLabel(Canvas canvas, Rect rect, double fill, bool isAlert) {
    if (rect.height < _minHeightForLabel) return;

    final text = '${(fill * 100).round()}%';
    // La tipografia crece con el modulo pero con techo: en el riel el modulo
    // mide ~60 dp de alto y un porcentaje gigante le comeria los chips.
    final fontSize = (rect.height * 0.42).clamp(9.0, 15.0);
    final splitX = rect.left + rect.width * fill;
    final onFilledColor = isAlert ? labelOnFilledAlert : labelOnFilled;

    for (final onFilled in [true, false]) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: (labelStyle ?? const TextStyle()).copyWith(
            fontSize: fontSize,
            color: onFilled ? onFilledColor : labelOnEmpty,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final offset = Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      );
      // Nada que recortar de ese lado: sin esto, con el modulo lleno o vacio
      // se pagaria un `saveLayer` para dibujar en un rect de ancho cero.
      final clip = onFilled
          ? Rect.fromLTRB(rect.left, rect.top, splitX, rect.bottom)
          : Rect.fromLTRB(splitX, rect.top, rect.right, rect.bottom);
      if (clip.width <= 0) continue;

      canvas.save();
      canvas.clipRect(clip);
      painter.paint(canvas, offset);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RamModulePainter old) =>
      old.usedFraction != usedFraction ||
      old.color != color ||
      old.alertColor != alertColor ||
      old.alertThreshold != alertThreshold ||
      old.emptyColor != emptyColor ||
      old.outlineColor != outlineColor ||
      old.labelOnFilled != labelOnFilled ||
      old.labelOnFilledAlert != labelOnFilledAlert ||
      old.labelOnEmpty != labelOnEmpty ||
      old.labelStyle != labelStyle;
}
