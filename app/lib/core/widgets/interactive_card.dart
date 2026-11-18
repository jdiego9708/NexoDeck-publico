import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_surface.dart';

/// Superficie interactiva con estados de escritorio de verdad: hover, foco
/// de teclado y presionado.
///
/// Es la pieza que faltaba para que la app se sienta de escritorio y no un
/// port de movil. Aporta tres cosas que antes no existian:
///
/// - **Hover**: borde tenido con el color del elemento + sombra + un escalon
///   tonal de relleno. Inerte en touch, asi que no cuesta nada en Android.
/// - **Foco de teclado**: anillo visible y `Enter`/`Espacio` activan. Antes
///   el deck no era navegable por teclado en absoluto.
/// - **Click derecho**: `onSecondaryTap`, para menu contextual.
///
/// **No la envuelvas en un `Card`**: el `cardTheme` global ya dibuja un
/// hairline y quedarian dos bordes superpuestos. Esta clase es la unica
/// fuente de verdad del borde de las superficies interactivas.
class InteractiveCard extends StatefulWidget {
  const InteractiveCard({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTapUp,
    this.accent,
    this.radius = AppRadius.card,
    this.semanticLabel,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Click derecho. Llega con la posicion para poder abrir un menu
  /// contextual justo donde el usuario hizo clic.
  final void Function(TapUpDetails details)? onSecondaryTapUp;

  /// Color con el que se tine el borde al hacer hover. Sin esto se usa el
  /// primario del tema.
  final Color? accent;

  final double radius;
  final String? semanticLabel;

  /// La superficie esta elegida y tiene que seguir viendose asi aunque el
  /// puntero se vaya. Lo usa la tile de metricas cuyo desglose de procesos
  /// esta abierto.
  final bool selected;

  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<InteractiveCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  void _set(void Function() change) {
    if (!mounted) return;
    setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(widget.radius);

    return FocusableActionDetector(
      mouseCursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onShowHoverHighlight: (value) => _set(() => _hovered = value),
      onShowFocusHighlight: (value) => _set(() => _focused = value),
      // Sin esto, tabular hasta la tarjeta la enfoca pero Enter no hace
      // nada -- que es peor que no poder enfocarla.
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        selected: widget.selected,
        child: AnimatedScale(
          // 1.012 y no mas: la grilla deja `AppSpacing.md` entre tarjetas, y
          // con un scale mayor la sombra del hover se recorta contra la
          // tarjeta vecina.
          scale: _pressed
              ? 0.97
              : _hovered
              ? 1.012
              : 1.0,
          duration: AppDuration.press,
          curve: AppCurves.press,
          child: AnimatedContainer(
            duration: AppDuration.hover,
            curve: AppCurves.emphasized,
            decoration: AppSurface.cardDecoration(
              scheme,
              hovered: _hovered,
              focused: _focused,
              selected: widget.selected,
              accent: widget.accent,
              radius: widget.radius,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onSecondaryTapUp: widget.onSecondaryTapUp,
                  onTapDown: (_) => _set(() => _pressed = true),
                  onTapUp: (_) => _set(() => _pressed = false),
                  onTapCancel: () => _set(() => _pressed = false),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
