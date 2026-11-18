import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/hardware_metrics_provider.dart';
import '../application/host_components_provider.dart';
import '../application/metrics_visibility_controller.dart';
import '../domain/hardware_snapshot.dart';
import '../domain/host_components.dart';
import '../domain/metric_kind.dart';
import 'widgets/metric_specs.dart';
import 'widgets/metrics_panel.dart';

const _kHistoryLength = 30;

/// Metricas del hardware LOCAL (rol PC). Solo se ocupa de la fuente de
/// datos: suscribirse al stream de Rust y mantener el historial corto que
/// necesitan los sparklines. El layout responsive y el plegado los resuelve
/// [MetricsPanel], que es el mismo widget que usa el espejo remoto del
/// telefono (`ConnectedDeviceScreen`).
///
/// El historial se guarda en memoria y no se persiste -- eso queda para
/// `hardware_history` cuando se implemente la Fase 9.
class MetricsRow extends ConsumerStatefulWidget {
  const MetricsRow({
    super.key,
    this.axis = MetricsPanelAxis.horizontal,
    this.mirrored = false,
    this.selectedMetric,
    this.onSelectMetric,
    this.railWidth,
  });

  final MetricsPanelAxis axis;

  /// Ver [MetricsPanel.mirrored]: el panel queda anclado al borde opuesto al
  /// habitual (derecha en el riel, abajo en las franjas).
  final bool mirrored;

  /// Ver [MetricsPanel.selectedMetric] / [MetricsPanel.onSelectMetric]: en
  /// `null` las tiles no son clicables, que es como queda la ventana compacta.
  final MetricKind? selectedMetric;
  final ValueChanged<MetricKind>? onSelectMetric;

  /// Ver [MetricsPanel.railWidth]: el ancho del riel se lo impone el padre --
  /// es lo que permite arrastrar su divisor en el escritorio-- o se calcula
  /// solo si viene en `null`, que es el caso del telefono.
  final double? railWidth;

  @override
  ConsumerState<MetricsRow> createState() => _MetricsRowState();
}

class _MetricsRowState extends ConsumerState<MetricsRow> {
  final List<double> _cpuHistory = [];
  final List<double> _netRxHistoryKb = [];
  final List<double> _netTxHistoryKb = [];
  final Map<String, List<double>> _diskReadHistoryKb = {};
  final Map<String, List<double>> _diskWriteHistoryKb = {};

  void _recordSnapshot(HardwareSnapshot snapshot) {
    setState(() {
      _pushCapped(_cpuHistory, snapshot.cpuUsage);
      _pushCapped(_netRxHistoryKb, snapshot.netRxBytesPerSec / 1024);
      _pushCapped(_netTxHistoryKb, snapshot.netTxBytesPerSec / 1024);
      _recordDiskHistory(snapshot);
    });
  }

  /// Por `mountPoint`, con el mismo criterio de las otras historias. A
  /// diferencia de esas, la cantidad de claves varia (un disco puede
  /// desaparecer si se desconecta), asi que se podan las que ya no estan en
  /// el snapshot -- sin esto la senal de vida de un disco viejo se quedaria
  /// congelada en su ultimo valor para siempre.
  void _recordDiskHistory(HardwareSnapshot snapshot) {
    final current = snapshot.disks.map((d) => d.mountPoint).toSet();
    _diskReadHistoryKb.removeWhere((key, _) => !current.contains(key));
    _diskWriteHistoryKb.removeWhere((key, _) => !current.contains(key));
    for (final disk in snapshot.disks) {
      if (disk.readBytesPerSec == null) continue;
      _pushCappedForKey(
        _diskReadHistoryKb,
        disk.mountPoint,
        disk.readBytesPerSec! / 1024,
      );
      _pushCappedForKey(
        _diskWriteHistoryKb,
        disk.mountPoint,
        (disk.writeBytesPerSec ?? 0) / 1024,
      );
    }
  }

  static void _pushCapped(List<double> list, double value) {
    list.add(value);
    if (list.length > _kHistoryLength) list.removeAt(0);
  }

  static void _pushCappedForKey(
    Map<String, List<double>> map,
    String key,
    double value,
  ) => _pushCapped(map.putIfAbsent(key, () => []), value);

  @override
  Widget build(BuildContext context) {
    ref.listen(hardwareMetricsProvider, (previous, next) {
      next.whenData(_recordSnapshot);
    });

    final collapsed = ref.watch(metricsCollapsedProvider);
    void toggle() => ref.read(metricsVisibilityControllerProvider).toggle();

    // Plegado no hace falta esperar el primer snapshot: solo se dibuja la
    // barrita del chevron. Ademas el spinner de carga no entraria en sus
    // 28 px de alto.
    if (collapsed) {
      return MetricsPanel(
        specs: const [],
        axis: widget.axis,
        mirrored: widget.mirrored,
        selectedMetric: widget.selectedMetric,
        onSelectMetric: widget.onSelectMetric,
        collapsed: true,
        onToggleCollapsed: toggle,
        railWidth: widget.railWidth,
      );
    }

    final metrics = ref.watch(hardwareMetricsProvider);
    // Las piezas del equipo se leen una vez y pueden no haber llegado todavia
    // (WMI y NVML tardan): hasta entonces las tiles se dibujan sin subtitulo,
    // que es exactamente como estaban antes. No se espera por esto para
    // mostrar las metricas.
    final components =
        ref.watch(hostComponentsProvider).value ?? HostComponents.empty;

    return metrics.when(
      data: (snapshot) => MetricsPanel(
        specs: buildMetricSpecs(
          snapshot: snapshot,
          scheme: Theme.of(context).colorScheme,
          components: components,
          cpuHistory: _cpuHistory,
          netRxHistoryKb: _netRxHistoryKb,
          netTxHistoryKb: _netTxHistoryKb,
          diskReadHistoryKb: _diskReadHistoryKb,
          diskWriteHistoryKb: _diskWriteHistoryKb,
        ),
        axis: widget.axis,
        mirrored: widget.mirrored,
        selectedMetric: widget.selectedMetric,
        onSelectMetric: widget.onSelectMetric,
        collapsed: false,
        onToggleCollapsed: toggle,
        railWidth: widget.railWidth,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Error leyendo hardware: $error')),
    );
  }
}
