import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/run_center_controller.dart';
import '../application/run_panel_providers.dart';
import '../domain/command_run.dart';
import '../domain/run_panel_dock.dart';
import 'widgets/run_output.dart';

/// Panel acoplado con lo que se esta ejecutando **ahora**, su salida en vivo
/// y el boton de detener.
///
/// Existe porque los toasts y la hoja de historial no alcanzan para vigilar
/// un comando de horas: el toast se cierra o queda tapado por otra ventana, y
/// la hoja lista todo junto, sin cronometro vivo y sin forma de cortar. Un
/// panel fijo al lado del deck es lo que convierte "lance algo" en "estoy
/// mirando como va".
///
/// No sabe de donde salen los datos: lee `runCenterProvider`, que ya se
/// alimenta del stream de Rust **directo** (nunca con `ref.listen`, porque
/// Riverpod se comeria dos eventos iguales seguidos).
class RunPanel extends ConsumerStatefulWidget {
  const RunPanel({
    super.key,
    required this.dock,
    this.onClose,
    this.onDockChanged,
  });

  final RunPanelDock dock;

  /// Cierra el panel. En el dialogo del escritorio lo pisa el `pop`.
  final VoidCallback? onClose;

  /// Cambia el anclaje. **`null` esconde el menu**: con el panel en un dialogo
  /// no hay costado al que acoplarlo (F4).
  final ValueChanged<RunPanelDock>? onDockChanged;

  @override
  ConsumerState<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends ConsumerState<RunPanel> {
  /// UN solo timer para todo el panel, como el de `RunToastHost`. El
  /// cronometro de una ejecucion no llega por eventos --entre dos lineas de
  /// salida pueden pasar minutos-- asi que sin esto se quedaria congelado.
  /// Un tick por segundo alcanza: arriba del segundo el formato ya no muestra
  /// decimas.
  Timer? _ticker;
  DateTime _now = DateTime.now();

  /// Salida completa traida del anillo de Rust, y de que ejecucion es.
  ///
  /// Hace falta porque la UI puede haber perdido lineas: el broadcast de Rust
  /// tiene 512 eventos y, con un comando que escupe miles de lineas, un Dart
  /// atrasado recibe `Lagged` y **descarta**. El anillo del lado Rust si las
  /// conserva, asi que el boton las recupera.
  List<String>? _fullOutput;
  String? _fullOutputRunId;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runs = ref.watch(runCenterProvider).visible;
    final selected = _resolveSelected(runs);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: widget.dock == RunPanelDock.right
              ? AppSurface.hairline(theme.colorScheme)
              : BorderSide.none,
          right: widget.dock == RunPanelDock.left
              ? AppSurface.hairline(theme.colorScheme)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, runs),
          const Divider(height: 1),
          Expanded(
            child: runs.isEmpty
                ? const EmptyState(
                    icon: Icons.terminal_outlined,
                    title: 'Nada corriendo',
                    message:
                        'Las acciones de terminal que lances van a aparecer '
                        'aca, con su salida y un boton para detenerlas.',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Lado a lado o una sobre otra: lo decide el ancho
                      // MEDIDO y no el dock, mismo criterio que el panel de
                      // procesos y que el de metricas.
                      final sideBySide =
                          constraints.maxWidth >=
                          AppSizes.runPanelSideBySideWidth;
                      final list = _buildRunList(runs, selected);
                      final output = _buildOutput(theme, selected);

                      if (sideBySide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: AppSizes.runPanelMinWidth * 0.85,
                              child: list,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: output),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // La lista se queda con lo justo (hasta cuatro
                          // filas): lo que hay que mirar de un comando largo
                          // es su salida, no la lista de lo que corri hoy.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: AppSizes.runRowHeight * 4,
                            ),
                            child: list,
                          ),
                          const Divider(height: 1),
                          Expanded(child: output),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// La ejecucion elegida a mano, o --si no hay o ya no existe-- la primera
  /// que siga corriendo, y si no la mas reciente. Sin esto el panel se abriria
  /// vacio justo cuando hay algo que mirar.
  CommandRun? _resolveSelected(List<CommandRun> runs) {
    if (runs.isEmpty) return null;
    final id = ref.watch(selectedRunProvider);
    for (final run in runs) {
      if (run.id == id) return run;
    }
    return runs.firstWhere((run) => run.isActive, orElse: () => runs.first);
  }

  Widget _buildHeader(ThemeData theme, List<CommandRun> runs) {
    final active = runs.where((run) => run.isActive).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              active == 0 ? 'Ejecuciones' : 'Ejecuciones · $active en curso',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (runs.any((run) => !run.isActive))
            IconButton(
              tooltip: 'Limpiar terminadas',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(runCenterProvider.notifier).dismissAllFinished(),
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            ),
          if (widget.onDockChanged case final change?)
            PopupMenuButton<RunPanelDock>(
              tooltip: 'Anclar',
              icon: const Icon(Icons.dock_outlined, size: 18),
              onSelected: change,
              itemBuilder: (context) => [
                for (final dock in RunPanelDock.values)
                  PopupMenuItem(
                    value: dock,
                    child: Row(
                      children: [
                        Icon(
                          dock == widget.dock
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(dock.label),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Cerrar el panel',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onClose ?? () {},
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildRunList(List<CommandRun> runs, CommandRun? selected) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: runs.length,
      itemBuilder: (context, index) {
        final run = runs[index];
        return _RunRow(
          run: run,
          now: _now,
          selected: run.id == selected?.id,
          onTap: () {
            ref.read(runPanelControllerProvider).select(run.id);
            // La salida completa es de OTRA ejecucion: se descarta, si no el
            // panel mostraria el log de una debajo del titulo de la otra.
            if (_fullOutputRunId != run.id) {
              setState(() {
                _fullOutput = null;
                _fullOutputRunId = null;
              });
            }
          },
        );
      },
    );
  }

  Widget _buildOutput(ThemeData theme, CommandRun? run) {
    if (run == null) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final full = _fullOutputRunId == run.id ? _fullOutput : null;

    final lines = <Widget>[
      if (run.droppedLines > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            'Se omitieron ${run.droppedLines} lineas',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      if (full != null)
        for (final line in full) RunOutputLine(text: line, isError: false)
      else
        for (final line in run.lines)
          RunOutputLine(text: line.text, isError: line.isError),
      if (run.error case final error?) RunOutputLine(text: error, isError: true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOutputHeader(theme, run),
        Expanded(
          child: Container(
            width: double.infinity,
            color: scheme.surfaceContainerLowest,
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      run.isActive ? 'Todavia sin salida' : 'Sin salida',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                // `reverse: true` pega la vista al final: en un comando de
                // horas lo que importa es la ultima linea, no la primera.
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    children: lines.reversed.toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutputHeader(ThemeData theme, CommandRun run) {
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            run.label,
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: AppSpacing.xxs),
          // El comando renderizado, con los parametros ya sustituidos: es lo
          // que dice QUE se esta ejecutando de verdad, no que boton se toco.
          Text(
            run.command,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                '${run.statusLabel} · ${formatRunElapsed(run.elapsed(_now))}',
                style: AppText.numeric(
                  theme.textTheme.labelMedium?.copyWith(
                    color: run.isFailure ? scheme.error : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (run.isActive && run.cancellable)
                TextButton.icon(
                  onPressed: () =>
                      ref.read(runCenterProvider.notifier).cancel(run.id),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Detener'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                tooltip: 'Traer la salida completa',
                visualDensity: VisualDensity.compact,
                onPressed: () => _loadFullOutput(run.id),
                icon: const Icon(Icons.unfold_more, size: 18),
              ),
              IconButton(
                tooltip: 'Copiar la salida',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copyOutput(run),
                icon: const Icon(Icons.copy_all, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadFullOutput(String runId) async {
    final lines = await ref.read(runCenterProvider.notifier).fullOutput(runId);
    if (!mounted) return;
    setState(() {
      _fullOutput = lines;
      _fullOutputRunId = runId;
    });
  }

  Future<void> _copyOutput(CommandRun run) async {
    final text =
        (_fullOutputRunId == run.id && _fullOutput != null
                ? _fullOutput!
                : run.lines.map((line) => line.text).toList())
            .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Salida copiada')));
  }
}

/// Una fila de la lista: que se esta ejecutando, en que estado y hace cuanto.
class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.run,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final CommandRun run;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: AppSizes.runRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            _StatusDot(run: run),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    run.isActive
                        ? (run.lastLine ?? run.statusLabel)
                        : run.statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: run.isFailure
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              formatRunElapsed(run.elapsed(now)),
              // Cifras tabulares: sin esto el cronometro cambia de ancho una
              // vez por segundo y la fila "baila".
              style: AppText.numeric(
                theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.run});

  final CommandRun run;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (run.isActive) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: scheme.primary,
        ),
      );
    }
    final (icon, color) = switch (run.status) {
      RunStatus.succeeded => (Icons.check_circle, scheme.primary),
      RunStatus.launched => (Icons.open_in_new, scheme.primary),
      RunStatus.failed => (Icons.error, scheme.error),
      RunStatus.cancelled => (Icons.remove_circle_outline, scheme.outline),
      _ => (Icons.circle, scheme.outline),
    };
    return Icon(icon, size: 14, color: color);
  }
}
