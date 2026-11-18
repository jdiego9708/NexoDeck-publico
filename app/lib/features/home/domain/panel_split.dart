import 'dart:math' as math;

import '../../../core/theme/app_spacing.dart';

/// Los repartos que el usuario puede mover arrastrando un divisor.
///
/// Cada uno es **un eje entre dos cosas**: el panel y lo que queda (el
/// contenido central: el deck o el chat). Viven en un solo enum y no como
/// constantes sueltas por widget porque la regla es la misma para los cuatro
/// --un tamano preferido que se calcula solo, unos topes de arrastre y un
/// minimo para el otro lado-- y tenerla cuatro veces era exactamente el tipo de
/// copia que se desincroniza.
///
/// **La fraccion guardada es del espacio disponible, no un tamano en px.** Con
/// px, achicar la ventana dejaba al panel comiendose casi todo (o al deck sin
/// nada) hasta que el usuario lo volviera a arrastrar; con fraccion, el reparto
/// que eligio se mantiene al cambiar de tamano de ventana o de monitor, que es
/// lo que uno espera de un divisor.
enum PanelSlot {
  /// Franja horizontal de metricas (`HomeLayout.metricsTop`). Eje vertical.
  metricsStrip(
    settingKey: 'split_metrics_strip',
    preferredFactor: AppSizes.metricStripFactor,
    preferredMin: AppSizes.metricStripPreferredMinHeight,
    preferredMax: AppSizes.metricStripPreferredMaxHeight,
    min: AppSizes.metricStripDragMinHeight,
    max: AppSizes.metricStripDragMaxHeight,
    minRemaining: AppSizes.minDeckHeightWithStrip,
  ),

  /// Franja micro del layout "Deck al maximo". Eje vertical.
  ///
  /// Su minimo **es** su alto natural: la franja micro ya es lo minimo que se
  /// puede mostrar, asi que este divisor solo agranda. Lo que cambia al
  /// crecer son los charts, que derivan su radio del box que reciben.
  metricsMicroStrip(
    settingKey: 'split_metrics_micro',
    preferredFactor: 0,
    preferredMin: AppSizes.microMetricStripHeight,
    preferredMax: AppSizes.microMetricStripHeight,
    min: AppSizes.microMetricStripHeight,
    max: AppSizes.microMetricStripDragMaxHeight,
    minRemaining: AppSizes.minDeckHeightWithStrip,
  ),

  /// Riel vertical de metricas (`metricsLeft` / `metricsRight`). Eje
  /// horizontal.
  ///
  /// **Una sola clave para los dos lados**: es el mismo panel cambiado de
  /// borde, y el ancho que necesita para que entren los badges no depende de
  /// contra que lado de la ventana este apoyado.
  metricsRail(
    settingKey: 'split_metrics_rail',
    preferredFactor: AppSizes.metricRailWidthFactor,
    preferredMin: AppSizes.metricRailMinWidth,
    preferredMax: AppSizes.metricRailMaxWidth,
    min: AppSizes.metricRailMinWidth,
    max: AppSizes.metricRailDragMaxWidth,
    minRemaining: AppSizes.minDeckWidthWithPanel,
  ),

  /// Panel de acciones del centro de control, acoplado a un costado. Eje
  /// horizontal.
  ///
  /// `minRemaining` es el ancho minimo del CHAT, no del deck: el panel de
  /// acciones vive al lado del chat, y lo que hay que proteger por debajo es
  /// que las burbujas y el composer sigan leyendose.
  actionsPanel(
    settingKey: 'split_actions_panel',
    preferredFactor: AppSizes.actionsPanelWidthFactor,
    preferredMin: AppSizes.actionsPanelMinWidth,
    preferredMax: AppSizes.actionsPanelMaxWidth,
    min: AppSizes.actionsPanelMinWidth,
    max: AppSizes.actionsPanelDragMaxWidth,
    minRemaining: AppSizes.minChatWidthWithPanels,
  );

  const PanelSlot({
    required this.settingKey,
    required this.preferredFactor,
    required this.preferredMin,
    required this.preferredMax,
    required this.min,
    required this.max,
    required this.minRemaining,
  });

  /// Clave en `app_settings`. Clave/valor, asi que no hay migracion de Drift
  /// -- mismo patron que `theme_mode_controller.dart`.
  final String settingKey;

  /// El reparto que se calcula solo, para quien nunca toca el divisor: una
  /// fraccion del espacio disponible acotada entre [preferredMin] y
  /// [preferredMax].
  ///
  /// Es **lo que habia antes** de que el divisor fuera arrastrable, y por eso
  /// tiene su propio par de topes: el rango de arrastre ([min]/[max]) es mas
  /// ancho a proposito, y usarlo tambien para el automatico habria cambiado en
  /// silencio el aspecto por defecto de la app.
  final double preferredFactor;
  final double preferredMin;
  final double preferredMax;

  /// Hasta donde deja estirar y encoger el arrastre.
  final double min;
  final double max;

  /// Lo que le tiene que quedar al otro lado --el deck-- para que el panel se
  /// pueda dibujar acoplado.
  final double minRemaining;

  /// El tamano por defecto, sin nada guardado.
  double preferredExtent(double available) {
    if (preferredFactor <= 0) return preferredMin;
    return (available * preferredFactor).clamp(preferredMin, preferredMax);
  }

  /// Tamano final del panel en px, ya con todos los topes aplicados.
  ///
  /// [fraction] es lo que el usuario dejo guardado, o `null` si nunca movio
  /// este divisor.
  ///
  /// Devuelve `null` cuando **no entra**: al otro lado le quedaria menos de
  /// [minRemaining] incluso con el panel en su [min]. Que decide cada llamador
  /// ante un `null` es cosa suya -- el panel de procesos no se dibuja y el de
  /// ejecuciones se maximiza.
  double? extentFor({required double available, double? fraction}) {
    final ceiling = math.min(max, available - minRemaining);
    // El panel no entra ni en su tamano minimo: no hay reparto posible.
    if (ceiling < min) return null;

    final wanted = fraction == null
        ? preferredExtent(available)
        : available * fraction;
    return wanted.clamp(min, ceiling);
  }

  /// La fraccion que hay que guardar despues de arrastrar [delta] px, con el
  /// panel midiendo [currentExtent].
  ///
  /// [delta] ya viene **en el sentido que agranda el panel** (el widget del
  /// divisor le da vuelta el signo cuando esta apoyado contra el borde
  /// opuesto), asi que aca siempre se suma.
  ///
  /// El resultado sale clampeado en px y recien despues se pasa a fraccion:
  /// al reves, una fraccion valida podria caer fuera de los topes en px y el
  /// panel se movera un instante mas alla del tope antes de volver.
  double fractionAfterDrag({
    required double available,
    required double currentExtent,
    required double delta,
  }) {
    if (available <= 0) return 0;
    final ceiling = math.max(min, math.min(max, available - minRemaining));
    final next = (currentExtent + delta).clamp(min, ceiling);
    return next / available;
  }
}
