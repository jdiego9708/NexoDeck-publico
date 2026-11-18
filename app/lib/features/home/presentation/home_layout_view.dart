import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/resize_handle.dart';
import '../../actions/application/actions_panel_controller.dart';
import '../../actions/presentation/widgets/actions_deck_grid.dart';
import '../../actions/presentation/widgets/actions_panel.dart';
import '../../ai_assistant/application/ai_enabled_controller.dart';
import '../../ai_assistant/presentation/ai_assistant_dialog.dart';
import '../../dashboard/application/metrics_visibility_controller.dart';
import '../../dashboard/presentation/widgets/metrics_panel.dart';
import '../../dashboard/domain/metric_kind.dart';
import '../../dashboard/presentation/metrics_row.dart';
import '../../processes/presentation/process_panel_dialog.dart';
import '../application/home_layout_controller.dart';
import '../application/panel_split_controller.dart';
import '../domain/home_layout.dart';
import '../domain/panel_split.dart';

/// Mantiene vivo el `State` de [MetricsRow] cuando el layout lo mueve de una
/// `Column` a un `Row`.
///
/// Sin esto Flutter no lo reconoce como el mismo widget --cambia de padre y
/// de posicion-- y lo reconstruye desde cero: el historial en memoria de los
/// sparklines de CPU y Red se pierde, y las dos metricas quedan diciendo
/// "Recolectando..." unos 30 segundos **cada vez que se cambia de layout**.
/// Verificado en la app real antes de agregar la key.
///
/// Es seguro porque nunca hay dos [MetricsRow] vivos a la vez en esta
/// pantalla: el layout elige uno de los cuatro repartos, no los compone.
final _metricsKey = GlobalKey();

/// Cuerpo de la pantalla principal: metricas y el contenido central (el deck
/// de acciones o el chat), repartidos segun el [HomeLayout] activo.
///
/// El **desglose de procesos** y el **panel de ejecuciones** ya no se acoplan
/// al costado: se abren como **dialogo** (ver `process_panel_dialog.dart` y
/// `run_panel_dialog.dart`), asi no compiten por el ancho con los paneles
/// laterales del centro de control. La tile de una metrica de CPU/RAM/GPU/Disco
/// abre el primero.
///
/// **Todos los divisores se arrastran** ([ResizeHandle]), y lo que el usuario
/// reparte se guarda por panel (ver [PanelSlot]).
class HomeLayoutView extends ConsumerWidget {
  const HomeLayoutView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final collapsed = ref.watch(metricsCollapsedProvider);

    void openProcesses(MetricKind kind) =>
        showProcessPanelDialog(context, kind);

    if (layout.isControlCenter) {
      return _ControlCenterLayout(onSelectMetric: openProcesses);
    }
    if (layout.isSideRail) {
      return _SideRailLayout(
        layout: layout,
        collapsed: collapsed,
        onSelectMetric: openProcesses,
      );
    }
    return _StripLayout(
      layout: layout,
      collapsed: collapsed,
      onSelectMetric: openProcesses,
    );
  }
}

/// Lo que comparten los tres sitios que dibujan un divisor: resolver el tamano
/// de un panel y armar el [ResizeHandle] que lo mueve.
///
/// **Recibe el reparto y el controller ya leidos, no el `WidgetRef`**, y eso
/// no es un detalle de estilo: los tres los usan dentro del callback de un
/// `LayoutBuilder`, que corre en la fase de *layout* y no en la de build. Un
/// `ref.watch` ahi adentro revienta en tiempo de ejecucion ("Cannot use
/// ref.watch outside of the build method"). Leerlos arriba, en `build`, y
/// bajarlos como parametros es lo que lo evita.
mixin _SplitHost {
  /// Tamano del panel en px, ya con los topes aplicados. Ante un `null` de
  /// [PanelSlot.extentFor] --el panel no entra ni en su minimo-- se dibuja
  /// igual en su minimo: las metricas son parte de la pantalla, no un extra
  /// que se pueda esconder por falta de espacio.
  ///
  /// Recibe la fraccion YA seleccionada (`splits[slot]`, resuelta afuera con
  /// `panelSplitsProvider.select`) y no el mapa entero -- ver el comentario
  /// largo en `_SidePanelArea.build` sobre por que ese recorte importa.
  double extentOf(double? fraction, PanelSlot slot, double available) {
    return slot.extentFor(available: available, fraction: fraction) ??
        slot.min;
  }

  Widget handleFor(
    PanelSplitController controller, {
    required PanelSlot slot,
    required Axis axis,
    required double available,
    required double extent,
    required bool invert,
    required String label,
  }) {
    return ResizeHandle(
      axis: axis,
      invert: invert,
      semanticLabel: label,
      onDrag: (delta) => controller.drag(
        slot,
        slot.fractionAfterDrag(
          available: available,
          currentExtent: extent,
          delta: delta,
        ),
      ),
      onDragEnd: () => controller.commit(slot),
      onReset: () => controller.reset(slot),
    );
  }
}

/// Franja horizontal arriba ([HomeLayout.metricsTop]) o abajo
/// ([HomeLayout.deckFocus]).
class _StripLayout extends ConsumerWidget with _SplitHost {
  const _StripLayout({
    required this.layout,
    required this.collapsed,
    required this.onSelectMetric,
  });

  final HomeLayout layout;
  final bool collapsed;
  final ValueChanged<MetricKind> onSelectMetric;

  /// La franja de abajo es la micro del layout "Deck al maximo", que tiene sus
  /// propios topes: solo se puede agrandar.
  PanelSlot get _slot => layout == HomeLayout.deckFocus
      ? PanelSlot.metricsMicroStrip
      : PanelSlot.metricsStrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select`: ver el comentario largo en `_SidePanelArea.build`. Aca
    // importa todavia mas, porque esta franja envuelve al deck entero.
    final fraction = ref.watch(
      panelSplitsProvider.select((splits) => splits[_slot]),
    );
    final controller = ref.read(panelSplitControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        final height = collapsed
            ? AppSizes.collapsedMetricsExtent
            : extentOf(fraction, _slot, available);

        final strip = SizedBox(
          height: height,
          child: Padding(
            // Plegada, la barrita del chevron ocupa exactamente su alto:
            // cualquier padding vertical la desbordaria.
            padding: collapsed
                ? const EdgeInsets.symmetric(horizontal: AppSpacing.gutter)
                : _stripPadding,
            child: MetricsRow(
              key: _metricsKey,
              axis: layout.axis,
              mirrored: layout.mirrored,
              selectedMetric: null,
              onSelectMetric: onSelectMetric,
            ),
          ),
        );

        final deck = const Expanded(child: ActionsDeckGrid());

        // Plegada no hay nada que repartir: la barrita del chevron mide lo
        // que mide. Un divisor arrastrable ahi prometeria algo que no puede
        // cumplir.
        final divider = collapsed
            ? const Divider(height: 1)
            : handleFor(
                controller,
                slot: _slot,
                axis: Axis.vertical,
                available: available,
                extent: height,
                // Con la franja abajo, arrastrar hacia abajo la achica.
                invert: layout.mirrored,
                label: 'Redimensionar las métricas',
              );

        return Column(
          children: layout.mirrored
              ? [deck, divider, strip]
              : [strip, divider, deck],
        );
      },
    );
  }

  EdgeInsets get _stripPadding => layout.mirrored
      ? const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.sm,
        )
      : const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.sm,
        );
}

/// Riel lateral a la izquierda ([HomeLayout.metricsLeft]) o a la derecha
/// ([HomeLayout.metricsRight]).
class _SideRailLayout extends ConsumerWidget with _SplitHost {
  const _SideRailLayout({
    required this.layout,
    required this.collapsed,
    required this.onSelectMetric,
  });

  final HomeLayout layout;
  final bool collapsed;
  final ValueChanged<MetricKind> onSelectMetric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select`: ver el comentario largo en `_SidePanelArea.build`. Aca
    // importa todavia mas, porque este riel envuelve al deck entero.
    final fraction = ref.watch(
      panelSplitsProvider.select((splits) => splits[PanelSlot.metricsRail]),
    );
    final controller = ref.read(panelSplitControllerProvider);

    // El gutter va del lado de AFUERA (contra el borde de la ventana); del
    // lado de adentro ya separa el divisor, y sumarle padding dejaria un
    // canal vacio entre el riel y el deck.
    final padding = collapsed
        ? EdgeInsets.zero
        : EdgeInsets.only(
            left: layout.mirrored ? 0 : AppSpacing.gutter,
            right: layout.mirrored ? AppSpacing.gutter : 0,
            top: AppSpacing.md,
            bottom: AppSpacing.md,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final width = collapsed
            ? AppSizes.collapsedMetricsExtent
            : extentOf(fraction, PanelSlot.metricsRail, available);

        // El riel calcula su propio ancho desde `MediaQuery` cuando nadie se
        // lo impone --es lo que necesita en el telefono, donde vive dentro de
        // un `Row` que le pasa ancho no acotado-- pero aca se lo imponemos, y
        // eso es justo lo que lo hace arrastrable.
        final rail = SizedBox(
          width: width,
          child: Padding(
            padding: padding,
            child: MetricsRow(
              key: _metricsKey,
              axis: layout.axis,
              mirrored: layout.mirrored,
              selectedMetric: null,
              onSelectMetric: onSelectMetric,
              railWidth: collapsed ? null : width - padding.horizontal,
            ),
          ),
        );

        final deck = const Expanded(child: ActionsDeckGrid());

        final divider = collapsed
            ? const VerticalDivider(width: 1)
            : handleFor(
                controller,
                slot: PanelSlot.metricsRail,
                axis: Axis.horizontal,
                available: available,
                extent: width,
                // Con el riel a la derecha, arrastrar hacia la derecha lo
                // achica.
                invert: layout.mirrored,
                label: 'Redimensionar las métricas',
              );

        return Row(
          children: layout.mirrored
              ? [deck, divider, rail]
              : [rail, divider, deck],
        );
      },
    );
  }
}

/// Centro de control ([HomeLayout.controlCenter]): metricas a la izquierda, el
/// **chat del asistente** al centro y el panel de acciones a la derecha.
///
/// Es la unica composicion que no sale del par eje + espejo: tiene DOS paneles
/// laterales, cada uno con su divisor y su plegado. El ancho del panel de
/// acciones se resuelve contra el hueco que dejo el riel de metricas, para que
/// su `minRemaining` proteja al **chat** y no a un deck que aca no existe.
///
/// El chat no se reimplementa: es el mismo `AiAssistantPanel` del dialogo, con
/// `embedded: true`. El hilo vive en providers, asi que el estado no depende de
/// donde este montado.
class _ControlCenterLayout extends ConsumerWidget with _SplitHost {
  const _ControlCenterLayout({required this.onSelectMetric});

  final ValueChanged<MetricKind> onSelectMetric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsCollapsed = ref.watch(metricsCollapsedProvider);
    final actionsCollapsed = ref.watch(actionsPanelCollapsedProvider);
    final metricsFraction = ref.watch(
      panelSplitsProvider.select((s) => s[PanelSlot.metricsRail]),
    );
    final actionsFraction = ref.watch(
      panelSplitsProvider.select((s) => s[PanelSlot.actionsPanel]),
    );
    final controller = ref.read(panelSplitControllerProvider);

    // El gutter va del lado de AFUERA (contra el borde de la ventana), como en
    // `_SideRailLayout`: del lado de adentro ya separa el divisor.
    const railPadding = EdgeInsets.only(
      left: AppSpacing.gutter,
      top: AppSpacing.md,
      bottom: AppSpacing.md,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;

        final metricsWidth = metricsCollapsed
            ? AppSizes.collapsedMetricsExtent
            : extentOf(metricsFraction, PanelSlot.metricsRail, total);

        final metricsHandleWidth = metricsCollapsed
            ? 1.0
            : AppSizes.resizeHandleThickness;
        final afterMetrics = total - metricsWidth - metricsHandleWidth;
        final actionsWidth = actionsCollapsed
            ? AppSizes.collapsedMetricsExtent
            : extentOf(actionsFraction, PanelSlot.actionsPanel, afterMetrics);

        final metrics = SizedBox(
          width: metricsWidth,
          child: Padding(
            padding: metricsCollapsed ? EdgeInsets.zero : railPadding,
            child: MetricsRow(
              key: _metricsKey,
              axis: MetricsPanelAxis.vertical,
              mirrored: false,
              selectedMetric: null,
              onSelectMetric: onSelectMetric,
              railWidth: metricsCollapsed
                  ? null
                  : metricsWidth - railPadding.horizontal,
            ),
          ),
        );

        final metricsHandle = metricsCollapsed
            ? const VerticalDivider(width: 1)
            : handleFor(
                controller,
                slot: PanelSlot.metricsRail,
                axis: Axis.horizontal,
                available: total,
                extent: metricsWidth,
                invert: false,
                label: 'Redimensionar las métricas',
              );

        final actions = SizedBox(
          width: actionsWidth,
          child: const ActionsPanel(),
        );

        final actionsHandle = actionsCollapsed
            ? const VerticalDivider(width: 1)
            : handleFor(
                controller,
                slot: PanelSlot.actionsPanel,
                axis: Axis.horizontal,
                available: afterMetrics,
                extent: actionsWidth,
                // Contra el borde derecho, arrastrar hacia la derecha achica.
                invert: true,
                label: 'Redimensionar las acciones',
              );

        final center = const Expanded(child: _ChatCenter());

        return Row(
          children: [metrics, metricsHandle, center, actionsHandle, actions],
        );
      },
    );
  }
}

/// El centro del centro de control: el chat del asistente, o una invitacion a
/// activarlo.
///
/// **Gateado por el opt-in de la IA.** El asistente descarga modelos y levanta
/// un proceso hijo, y su `aiSetupStateProvider` dispara el probe de capacidades
/// (NVML + Vulkan). Montarlo con el flag apagado romperia la regla de que
/// ninguna funcion del bridge de IA se llama hasta que el usuario la pida.
class _ChatCenter extends ConsumerWidget {
  const _ChatCenter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(aiEnabledProvider)) {
      // El MISMO panel del dialogo: no hay una segunda implementacion del chat.
      return const AiAssistantPanel(embedded: true);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: EmptyState(
          icon: Icons.auto_awesome,
          title: 'Asistente de IA',
          message:
              'Actívalo para preguntarle lo que necesites y crear acciones '
              'con lenguaje natural.',
          action: FilledButton.icon(
            onPressed: () =>
                ref.read(aiEnabledControllerProvider).setEnabled(true),
            icon: const Icon(Icons.power_settings_new, size: 18),
            label: const Text('Activar el asistente'),
          ),
        ),
      ),
    );
  }
}
