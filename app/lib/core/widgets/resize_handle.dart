import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_surface.dart';

/// Divisor arrastrable entre dos paneles.
///
/// Reemplaza al `Divider`/`VerticalDivider` que separaba las areas del home:
/// se ve igual --un hairline de 1 px-- pero se puede agarrar y mover.
///
/// Cosas que no son obvias:
///
/// - **El area sensible es mucho mas gruesa que la linea**
///   ([AppSizes.resizeHandleThickness]). Un divisor de 1 px es imposible de
///   agarrar: hay que acertarle al pixel. El grosor extra es transparente y no
///   empuja el layout -- el divisor ocupa esos 8 px en lugar del 1 px que
///   ocupaba el `Divider`, que es la unica diferencia visible.
/// - **El cursor cambia al acercarse**, que es la senal de que eso se puede
///   mover. Es `MouseRegion` y no `InkWell`: en touch no existe hover, asi que
///   esto no aporta nada en Android -- por eso el home del telefono
///   (`ConnectedDeviceScreen`) no usa divisores arrastrables.
/// - **Doble clic devuelve el reparto automatico.** Sin esa salida, un
///   arrastre desafortunado solo se deshace volviendo a acertarle al pixel.
/// - **Se puede mover con el teclado.** Toma foco y responde a las flechas del
///   eje que le corresponde: el arrastre con mouse no puede ser la unica forma
///   de repartir la pantalla.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
    this.invert = false,
    this.semanticLabel,
  });

  /// El eje en el que **se mueve** el divisor: [Axis.horizontal] lo mueve a
  /// izquierda y derecha (o sea, es una linea vertical entre dos columnas).
  final Axis axis;

  /// Recibe el desplazamiento en px **en el sentido que agranda el panel**. El
  /// signo ya viene resuelto por [invert], asi que quien escucha siempre suma.
  final ValueChanged<double> onDrag;

  /// Se solto: es el momento de persistir. Durante el arrastre no se escribe
  /// nada (serian decenas de escrituras por segundo).
  final VoidCallback onDragEnd;

  /// Doble clic: volver al reparto automatico.
  final VoidCallback onReset;

  /// El panel esta apoyado contra el borde **opuesto** al habitual (a la
  /// derecha en vez de a la izquierda, abajo en vez de arriba), asi que
  /// arrastrar hacia la derecha lo **achica** en vez de agrandarlo.
  final bool invert;

  final String? semanticLabel;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  bool get _isVertical => widget.axis == Axis.vertical;

  /// Encendido mientras se lo esta usando o se lo va a usar. Es lo unico que
  /// distingue visualmente a este divisor de uno comun: si no se resaltara, no
  /// habria forma de saber que se puede arrastrar hasta toparse con el.
  bool get _active => _hovered || _dragging || _focused;

  void _emit(double primaryDelta) {
    widget.onDrag(widget.invert ? -primaryDelta : primaryDelta);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    const step = AppSizes.resizeKeyboardStep;
    final key = event.logicalKey;

    // Cada divisor responde solo a las flechas de SU eje: en un divisor
    // vertical, arriba/abajo no significan nada y tienen que seguir llegando
    // a la lista que este debajo.
    final double? delta = switch (key) {
      LogicalKeyboardKey.arrowLeft when !_isVertical => -step,
      LogicalKeyboardKey.arrowRight when !_isVertical => step,
      LogicalKeyboardKey.arrowUp when _isVertical => -step,
      LogicalKeyboardKey.arrowDown when _isVertical => step,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    _emit(delta);
    // Con el teclado no hay "soltar": cada pulsacion es un cambio terminado,
    // asi que se persiste en el acto.
    widget.onDragEnd();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // La linea sigue midiendo 1 px, como el `Divider` que reemplaza; lo que
    // cambia al activarse es su color, no su grosor: engordarla moveria el
    // contenido de los dos paneles justo cuando el usuario esta apuntando.
    final line = AnimatedContainer(
      duration: AppDuration.hover,
      curve: AppCurves.emphasized,
      width: _isVertical ? double.infinity : 1,
      height: _isVertical ? 1 : double.infinity,
      color: _active ? scheme.primary : AppSurface.hairline(scheme).color,
    );

    return Semantics(
      label: widget.semanticLabel ?? 'Redimensionar el panel',
      slider: true,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: _isVertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            // `opaque` es lo que hace que los 8 px transparentes de agarre
            // reciban el gesto; sin esto solo respondería el pixel pintado.
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onReset,
            onHorizontalDragStart: _isVertical
                ? null
                : (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: _isVertical
                ? null
                : (details) => _emit(details.delta.dx),
            onHorizontalDragEnd: _isVertical
                ? null
                : (_) {
                    setState(() => _dragging = false);
                    widget.onDragEnd();
                  },
            onVerticalDragStart: _isVertical
                ? (_) => setState(() => _dragging = true)
                : null,
            onVerticalDragUpdate: _isVertical
                ? (details) => _emit(details.delta.dy)
                : null,
            onVerticalDragEnd: _isVertical
                ? (_) {
                    setState(() => _dragging = false);
                    widget.onDragEnd();
                  }
                : null,
            child: SizedBox(
              width: _isVertical ? null : AppSizes.resizeHandleThickness,
              height: _isVertical ? AppSizes.resizeHandleThickness : null,
              child: Center(child: line),
            ),
          ),
        ),
      ),
    );
  }
}
