import 'package:flutter/material.dart';

import '../../dashboard/presentation/widgets/metrics_panel.dart';

/// Como se reparten la pantalla principal las metricas y el deck.
///
/// Los cuatro salen de combinar dos cosas que el panel de metricas ya sabia
/// hacer por separado: el **eje** ([MetricsPanelAxis], que ya usaba el
/// telefono para elegir franja o riel segun la orientacion) y el **borde** al
/// que queda anclado ([MetricsPanel.mirrored]). No hay ningun layout que
/// necesite un widget nuevo: la pantalla principal solo elige la
/// combinacion.
///
/// El orden del enum ES el orden en que cicla el boton, y va de mas a menos
/// metricas visibles.
enum HomeLayout {
  /// Centro de control: metricas a la izquierda, **el chat de IA al centro** y
  /// el panel de acciones a la derecha. Es el layout por defecto.
  ///
  /// No sale de la combinacion de eje + espejo como los otros cuatro: es una
  /// composicion propia (`_ControlCenterLayout`) con DOS paneles laterales.
  controlCenter(
    label: 'Centro de control',
    description: 'Métricas, chat del asistente y acciones',
    icon: Icons.dashboard_outlined,
    axis: MetricsPanelAxis.vertical,
    mirrored: false,
  ),

  /// El de siempre: franja de metricas arriba, deck abajo.
  metricsTop(
    label: 'Métricas arriba',
    description: 'Franja de métricas sobre el deck',
    icon: Icons.splitscreen_outlined,
    axis: MetricsPanelAxis.horizontal,
    mirrored: false,
  ),

  /// Riel de metricas a la izquierda, deck a la derecha. El riel muestra las
  /// 5 metricas apiladas con sus badges, asi que es el que mas datos deja
  /// ver a la vez.
  metricsLeft(
    label: 'Métricas a la izquierda',
    description: 'Riel lateral con el deck al lado',
    icon: Icons.vertical_split_outlined,
    axis: MetricsPanelAxis.vertical,
    mirrored: false,
  ),

  /// El espejo del anterior. No es un capricho: con el deck pegado al borde
  /// izquierdo, los botones quedan del lado donde suele estar la ventana que
  /// el usuario acaba de dejar, y en un monitor ancho se acorta el viaje del
  /// mouse.
  metricsRight(
    label: 'Métricas a la derecha',
    description: 'Riel lateral del otro lado',
    icon: Icons.vertical_split_outlined,
    axis: MetricsPanelAxis.vertical,
    mirrored: true,
  ),

  /// Todo para el deck: las metricas caen a la franja **micro** (grafico y
  /// valor, sin titulo ni badges) pegada al borde de abajo. Es la misma
  /// franja que usa la ventana compacta, aca al servicio de meter la mayor
  /// cantidad de botones posible sin quedarse ciego de hardware.
  deckFocus(
    label: 'Deck al máximo',
    description: 'Franja mínima de métricas abajo',
    icon: Icons.grid_view_outlined,
    axis: MetricsPanelAxis.microStrip,
    mirrored: true,
  );

  const HomeLayout({
    required this.label,
    required this.description,
    required this.icon,
    required this.axis,
    required this.mirrored,
  });

  /// Nombre corto, el que ve el usuario en el tooltip y en el menu.
  final String label;

  /// Una linea de contexto para el menu. El label solo dice donde estan las
  /// metricas, no que cambia de verdad entre un layout y otro.
  final String description;

  final IconData icon;
  final MetricsPanelAxis axis;
  final bool mirrored;

  /// Si las metricas van al costado (riel) en vez de en una franja. Lo
  /// consulta la pantalla para saber si reparte ancho o alto.
  bool get isSideRail => axis == MetricsPanelAxis.vertical;

  /// Si es la composicion de tres zonas (metricas | chat | acciones), que no
  /// sale del par eje + espejo como los otros.
  bool get isControlCenter => this == HomeLayout.controlCenter;

  /// El siguiente en la rueda, volviendo al primero despues del ultimo. Es
  /// lo que hace el boton de la barra con un clic.
  HomeLayout get next => values[(index + 1) % values.length];

  /// El icono se dibuja espejado cuando el layout lo esta: [metricsLeft] y
  /// [metricsRight] comparten `vertical_split`, y sin esto el boton se veria
  /// igual en los dos.
  bool get flipIcon => mirrored && isSideRail;

  /// Tolera un valor guardado que ya no exista (una version vieja, o un
  /// enum renombrado): cae al **centro de control** --el de por defecto-- en
  /// vez de romper el arranque.
  static HomeLayout fromName(String? name) {
    return values.firstWhere(
      (layout) => layout.name == name,
      orElse: () => controlCenter,
    );
  }
}
