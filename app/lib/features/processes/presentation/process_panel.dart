import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/processes.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../ai_assistant/application/ai_enabled_controller.dart';
import '../../ai_assistant/application/ai_providers.dart';
import '../../ai_assistant/presentation/ai_assistant_dialog.dart';
import '../../dashboard/domain/metric_kind.dart';
import '../../dashboard/application/hardware_metrics_provider.dart';
import '../../pairing/application/remote_ai_chat_provider.dart';
import '../../pairing/presentation/remote_ai_chat_screen.dart';
import '../application/process_providers.dart';
import '../domain/process_ai_prompt.dart';
import '../domain/process_group.dart';
import '../domain/process_panel_dock.dart';
import 'confirm_kill_dialog.dart';
import 'widgets/process_row.dart';
import 'widgets/process_table.dart';

/// Panel de procesos cableado a los providers.
///
/// Deliberadamente delgado: todo lo que se puede ver vive en
/// [ProcessPanelBody], que no sabe de Riverpod y por eso se puede testear
/// montando widgets sin `ProviderScope` --como el resto de los tests de este
/// proyecto--.
class ProcessPanel extends ConsumerStatefulWidget {
  const ProcessPanel({
    super.key,
    required this.metric,
    required this.dock,
    this.remote = false,
    this.totalRamMb,
    this.onClose,
    this.onDockChanged,
  });

  final MetricKind metric;
  final ProcessPanelDock dock;

  /// Los procesos son **de la PC y llegan por red** (rol Android). Cambia de
  /// donde salen los datos y por donde va el pedido de cerrar; la tabla es
  /// exactamente la misma.
  final bool remote;

  /// RAM total del equipo medido. En remoto la trae el snapshot que ya
  /// recibe el telefono, porque no puede leer la RAM de la PC por su cuenta.
  final double? totalRamMb;

  /// Cierra el panel. Por defecto limpia la metrica elegida --que es lo que
  /// cierra la hoja del movil--; el dialogo del escritorio lo pisa con el
  /// `pop`.
  final VoidCallback? onClose;

  /// Cambia el anclaje. **`null` esconde el menu de anclaje**: ya no hay un
  /// costado al que acoplarse (F4: los paneles se abren como dialogo).
  final ValueChanged<ProcessPanelDock>? onDockChanged;

  @override
  ConsumerState<ProcessPanel> createState() => _ProcessPanelState();
}

class _ProcessPanelState extends ConsumerState<ProcessPanel> {
  /// Grupos a los que ya se les pidio cerrarse. Se limpian solos cuando
  /// dejan de aparecer en una muestra.
  final Set<String> _terminating = {};

  Future<void> _terminate(ProcessGroup group) async {
    final confirmed = await showConfirmKillDialog(context, group);
    if (!confirmed || !mounted) return;

    setState(() => _terminating.add(group.name));
    try {
      if (widget.remote) {
        // El pedido viaja a la PC y la respuesta llega como evento: aca no
        // hay reporte que esperar. La fila queda en "Cerrando…" hasta la
        // proxima muestra, que es lo mismo que pasa en local.
        await sendTerminateProcessGroup(group);
        return;
      }
      final report = await terminateProcessGroup(group);
      if (!mounted) return;
      _showResult(group, report.killed, report.failed);
    } catch (error) {
      if (!mounted) return;
      setState(() => _terminating.remove(group.name));
      // Rust rechaza la operacion entera cuando es un proceso critico de
      // Windows o el propio NexoDeck. Ese texto ya viene explicando por que.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _askAi(ProcessGroup group) async {
    try {
      if (widget.remote) {
        // La respuesta no llega por un evento propio: la PC arma la
        // pregunta y la reenvia como un mensaje normal del chat, que ya
        // escucha `RemoteAiChatScreen`. Aca solo hace falta pedirla y abrir
        // (o enfocar) la pantalla.
        await sendAiAskAboutProcess(group);
        if (!mounted) return;
        await showRemoteAiChatScreen(context);
        return;
      }
      final details = await bridge.processDetails(
        name: group.name,
        pids: group.pids,
      );
      if (!mounted) return;
      final prompt = buildProcessQuestionPrompt(group, details: details);
      await askAiInChat(context, ref, prompt);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _showResult(ProcessGroup group, int killed, int failed) {
    if (failed == 0) return;
    // Que algunos no se hayan podido cerrar no puede quedar en silencio: la
    // fila desaparece a medias y el usuario no sabria por que.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se pudieron cerrar $failed de ${killed + failed} procesos de '
          '${group.name} — probablemente necesiten permisos de administrador.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(processPanelControllerProvider);

    // Dos fuentes, un solo cuerpo: local lee el stream del bridge; remoto, lo
    // que el telefono viene recibiendo por red.
    final TopProcesses? value;
    final String? error;
    if (widget.remote) {
      value = ref.watch(remoteTopProcessesProvider);
      error = null;
    } else {
      final sample = ref.watch(topProcessesProvider);
      // `value` es null mientras no llego la primera muestra y tambien si
      // hubo error; el orden de los dos casos lo decide `hasError`.
      value = sample.value;
      error = sample.hasError ? '${sample.error}' : null;
    }

    // La RAM total del equipo, para poder decir cuanto del total se lleva cada
    // proceso. `4.0 GB` no dice si es mucho sin saber cuanta hay.
    final totalRamMb =
        widget.totalRamMb ??
        ref.watch(hardwareMetricsProvider).value?.ramTotalMb;

    final aiAvailable = widget.remote
        ? ref.watch(remoteAiStatusProvider).ready
        : ref.watch(aiEnabledProvider) && ref.watch(aiReadyProvider);

    return ProcessPanelBody(
      totalRamMb: totalRamMb,
      metric: widget.metric,
      dock: widget.dock,
      groups: value?.forMetric(widget.metric),
      gpuAvailable: value?.gpuAvailable ?? false,
      error: error,
      terminating: _terminating,
      onClose: widget.onClose ?? controller.close,
      onDockChanged: widget.onDockChanged,
      onTerminate: _terminate,
      onAskAi: aiAvailable ? _askAi : null,
    );
  }
}

/// La parte visible del panel, sin providers.
class ProcessPanelBody extends StatelessWidget {
  const ProcessPanelBody({
    super.key,
    required this.metric,
    required this.dock,
    required this.groups,
    required this.gpuAvailable,
    required this.onClose,
    this.onDockChanged,
    this.totalRamMb,
    this.error,
    this.terminating = const {},
    this.onTerminate,
    this.onAskAi,
  });

  final MetricKind metric;
  final ProcessPanelDock dock;

  /// `null` mientras llega la primera muestra.
  final List<ProcessGroup>? groups;
  final bool gpuAvailable;

  /// RAM total del equipo, para la columna de "cuanto del total". `null`
  /// mientras no se sepa: ahi la fila muestra solo los GB.
  final double? totalRamMb;
  final String? error;
  final Set<String> terminating;
  final VoidCallback onClose;

  /// `null` esconde los botones de anclaje.
  final ValueChanged<ProcessPanelDock>? onDockChanged;
  final ValueChanged<ProcessGroup>? onTerminate;

  /// `null` esconde el boton en las 4 listas -- la IA sigue siendo opt-in.
  final ValueChanged<ProcessGroup>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _accentFor(metric, theme.colorScheme);

    // `Escape` cierra el panel: es la expectativa basica de cualquier panel
    // de escritorio, y el boton de cerrar queda lejos con el mouse.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onClose();
              return null;
            },
          ),
        },
        child: FocusScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                metric: metric,
                dock: dock,
                accentColor: accentColor,
                onClose: onClose,
                onDockChanged: onDockChanged,
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildList(
                    context,
                    accentColor,
                    ProcessRowDensity.forWidth(constraints.maxWidth),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    Color accentColor,
    ProcessRowDensity density,
  ) {
    if (error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudieron leer los procesos',
        message: error,
      );
    }
    if (groups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups!.isEmpty) {
      // Los tres vacios posibles dicen cosas distintas, y confundirlos es
      // justo el sintoma mudo que este proyecto persigue.
      if (metric == MetricKind.gpu && !gpuAvailable) {
        return const EmptyState(
          icon: Icons.videogame_asset_off_outlined,
          title: 'Sin datos por proceso',
          message:
              'Este equipo no informa uso de GPU por aplicación. La métrica '
              'general sigue funcionando.',
        );
      }
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: metric == MetricKind.gpu
            ? 'Nadie está usando la GPU'
            : 'Sin procesos destacados',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El padding derecho no es cosmetico: maximizado --y acoplado a la
        // derecha-- el panel llega hasta el borde de la ventana, y sin el la
        // «x» de cada fila quedaba cortada por la mitad contra el marco.
        // Verificado en la app real.
        Padding(
          padding: EdgeInsets.zero,
          child: ProcessTableHeader(
            metric: metric,
            density: density,
            accentColor: accentColor,
            showAskAi: onAskAi != null,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemExtent: AppSizes.processRowHeight,
            itemCount: groups!.length,
            itemBuilder: (context, index) {
              final group = groups![index];
              return ColoredBox(
                // Filas alternadas: con doce lineas de cifras alineadas a la
                // derecha, el ojo se salta de fila sin una guia. Muy tenue,
                // para que sea una guia y no un patron.
                color: index.isEven
                    ? Colors.transparent
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.03),
                child: ProcessRow(
                  // Por nombre y no por indice: la lista se reordena sola.
                  key: ValueKey(group.name),
                  group: group,
                  metric: metric,
                  density: density,
                  accentColor: accentColor,
                  totalRamMb: totalRamMb,
                  terminating: terminating.contains(group.name),
                  onTerminate: onTerminate == null
                      ? null
                      : () => onTerminate!(group),
                  onAskAi: onAskAi == null ? null : () => onAskAi!(group),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// El panel se tine con el color de la metrica que desglosa, que es lo que
  /// lo ata visualmente a la tile que se toco.
  static Color _accentFor(MetricKind metric, ColorScheme scheme) =>
      switch (metric) {
        MetricKind.cpu => scheme.primary,
        MetricKind.ram => scheme.secondary,
        MetricKind.gpu => scheme.error,
        MetricKind.disk || MetricKind.network => scheme.tertiary,
      };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.metric,
    required this.dock,
    required this.accentColor,
    required this.onClose,
    this.onDockChanged,
  });

  final MetricKind metric;
  final ProcessPanelDock dock;
  final Color accentColor;
  final VoidCallback onClose;
  final ValueChanged<ProcessPanelDock>? onDockChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.processPanelTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onDockChanged case final change?)
            for (final option in ProcessPanelDock.values)
              IconButton(
                tooltip: option.label,
                isSelected: dock == option,
                onPressed: dock == option ? null : () => change(option),
                icon: Icon(_dockIcon(option), size: 18),
                visualDensity: VisualDensity.compact,
              ),
          IconButton(
            tooltip: 'Cerrar (Esc)',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static IconData _dockIcon(ProcessPanelDock dock) => switch (dock) {
    ProcessPanelDock.left => Icons.align_horizontal_left,
    ProcessPanelDock.right => Icons.align_horizontal_right,
    ProcessPanelDock.maximized => Icons.open_in_full,
  };
}
