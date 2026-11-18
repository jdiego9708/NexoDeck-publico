import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Tratamiento de las superficies: borde, sombra y relleno segun el estado
/// de interaccion.
///
/// Existe porque el tema original apoyaba TODA la separacion visual en el
/// contraste tonal (`surfaceContainer` sobre `surface`, elevacion 0). En
/// modo oscuro pasa; en modo claro las tarjetas casi no se despegan del
/// fondo -- se ve clarisimo en una captura. Un hairline de 1 px resuelve eso
/// sin romper el look plano.
abstract final class AppSurface {
  /// Borde de reposo. El alpha < 1 es deliberado: `outlineVariant` a full
  /// lee como "campo de formulario"; a 0.55 lee como hairline.
  static BorderSide hairline(ColorScheme scheme) => BorderSide(
    color: scheme.outlineVariant.withValues(alpha: 0.55),
    width: 1,
  );

  /// Borde al pasar el mouse. Se tine con el color del elemento (el de la
  /// accion) cuando hay uno; si no, con el primario.
  static BorderSide hairlineHovered(ColorScheme scheme, {Color? accent}) =>
      BorderSide(
        color: (accent ?? scheme.primary).withValues(alpha: 0.40),
        width: 1,
      );

  /// Anillo de foco de teclado. Va en `primary` y no en el color del
  /// elemento a proposito: tiene que ser reconocible como "esto es lo que
  /// esta enfocado" sin depender de que la accion tenga un color legible.
  static BorderSide focusRing(ColorScheme scheme) =>
      BorderSide(color: scheme.primary, width: 2);

  /// Sombra de hover. Una sola capa, difusa y con **spread negativo**: eso
  /// ultimo es lo que evita el halo gris de las sombras Material clasicas y
  /// da el borde limpio que se espera hoy en un desktop app.
  static List<BoxShadow> lift(ColorScheme scheme, {required bool hovered}) {
    if (!hovered) return const [];
    final dark = scheme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.45 : 0.10),
        blurRadius: 16,
        offset: const Offset(0, 4),
        spreadRadius: -4,
      ),
    ];
  }

  /// Decoracion completa de una superficie interactiva. Unica fuente de
  /// verdad del borde: quien la use NO debe envolver ademas en un `Card`, o
  /// se dibujan dos bordes superpuestos.
  static BoxDecoration cardDecoration(
    ColorScheme scheme, {
    bool hovered = false,
    bool focused = false,
    bool selected = false,
    Color? accent,
    double radius = AppRadius.card,
  }) {
    // El foco de teclado gana sobre la seleccion: mientras tabulas necesitas
    // ver DONDE estas parado, aunque ese no sea el elemento elegido.
    final side = focused
        ? focusRing(scheme)
        : selected
        ? selectedEdge(scheme, accent: accent)
        : hovered
        ? hairlineHovered(scheme, accent: accent)
        : hairline(scheme);
    return BoxDecoration(
      color: selected || hovered
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(radius),
      border: Border.fromBorderSide(side),
      boxShadow: lift(scheme, hovered: hovered),
    );
  }

  /// Borde de una superficie que esta **elegida** (no solo con el mouse
  /// encima): mismo color de acento que el hover pero opaco y mas grueso, para
  /// que se distinga de un hover pasajero cuando el puntero se va.
  static BorderSide selectedEdge(ColorScheme scheme, {Color? accent}) =>
      BorderSide(color: accent ?? scheme.primary, width: 1.5);
}
