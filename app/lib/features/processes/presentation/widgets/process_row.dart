import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../dashboard/domain/metric_kind.dart';
import '../../domain/process_group.dart';
import '../../domain/process_panel_dock.dart';
import 'process_table.dart';

/// Una fila de la tabla: la app, lo que consume y hace cuanto corre.
///
/// Las columnas salen de [ProcessColumns], la misma definicion que usa el
/// encabezado: con dos listas de `flex` separadas, tocar una desalinea la
/// tabla entera y el error es dificil de ver.
class ProcessRow extends StatelessWidget {
  const ProcessRow({
    super.key,
    required this.group,
    required this.metric,
    required this.density,
    required this.accentColor,
    this.totalRamMb,
    this.onTerminate,
    this.terminating = false,
    this.onAskAi,
  });

  final ProcessGroup group;
  final MetricKind metric;
  final ProcessRowDensity density;
  final Color accentColor;

  /// RAM total del equipo, para poder decir **cuanto del total** se lleva este
  /// proceso. `null` mientras no se sepa.
  final double? totalRamMb;

  /// `null` cuando el grupo no se puede cerrar (el propio NexoDeck).
  final VoidCallback? onTerminate;

  /// Ya se pidio cerrarlo y se esta esperando la proxima muestra.
  final bool terminating;

  /// `null` esconde el boton entero -- la IA sigue siendo opt-in, tambien
  /// aca. No es "deshabilitado": si esta apagada, el boton ni aparece.
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = density == ProcessRowDensity.full;
    final (timeValue, timeCaption) = splitRunTime(group.runTimeSecs);

    return Opacity(
      // Mientras se cierra, la fila se atenua en vez de desaparecer: borrarla
      // en el acto mentiria si el cierre falla por permisos.
      opacity: terminating ? 0.45 : 1.0,
      child: Padding(
        // Mismo margen que el encabezado (ver `processRowGutter`): es lo que
        // mantiene las columnas alineadas entre los dos.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.processRowGutter,
        ),
        child: Row(
          children: [
            Expanded(
              flex: ProcessColumns.name,
              child: _NameCell(group: group, theme: theme),
            ),
            if (full) ...[
              _cell(
                value: '${group.cpuPercent.toStringAsFixed(1)}%',
                highlighted: metric == MetricKind.cpu,
              ),
              _cell(
                value: formatMetricValue(group, MetricKind.ram),
                caption: shareOfTotal(group, MetricKind.ram, totalRamMb),
                highlighted: metric == MetricKind.ram,
              ),
              _cell(
                value: formatMetricValue(group, MetricKind.gpu),
                highlighted: metric == MetricKind.gpu,
              ),
              _cell(
                value: formatMetricValue(group, MetricKind.disk),
                highlighted: metric == MetricKind.disk,
              ),
            ] else
              _cell(
                value: formatMetricValue(group, metric),
                caption: shareOfTotal(group, metric, totalRamMb),
                highlighted: true,
              ),
            Expanded(
              flex: ProcessColumns.time,
              child: StackedCell(
                value: terminating ? 'Cerrando…' : timeValue,
                caption: terminating ? null : timeCaption,
              ),
            ),
            if (onAskAi != null) _AskAiButton(group: group, onAskAi: onAskAi),
            _TerminateButton(
              group: group,
              onTerminate: terminating ? null : onTerminate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell({
    required String value,
    String? caption,
    required bool highlighted,
  }) => Expanded(
    flex: ProcessColumns.metric,
    child: StackedCell(
      value: value,
      caption: caption,
      highlighted: highlighted,
      accentColor: accentColor,
    ),
  );
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.group, required this.theme});

  final ProcessGroup group;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          group.name,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Solo cuando agrupa varios: "1 proceso" en cada fila seria ruido.
        if (group.processCount > 1)
          Text(
            '${group.processCount} procesos',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _AskAiButton extends StatelessWidget {
  const _AskAiButton({required this.group, required this.onAskAi});

  final ProcessGroup group;
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Preguntarle a la IA sobre «${group.name}»',
      child: IconButton(
        onPressed: onAskAi,
        icon: const Icon(Icons.psychology_outlined, size: 16),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: ProcessColumns.actionWidth,
          height: 32,
        ),
      ),
    );
  }
}

class _TerminateButton extends StatelessWidget {
  const _TerminateButton({required this.group, required this.onTerminate});

  final ProcessGroup group;
  final VoidCallback? onTerminate;

  @override
  Widget build(BuildContext context) {
    // El propio NexoDeck se muestra en la lista --esconderlo seria
    // deshonesto-- pero no se deja cerrar desde su propio panel. Rust ademas
    // lo rechaza, por si alguien llama la API por otro camino.
    final tooltip = group.isSelf
        ? 'No se puede cerrar NexoDeck desde su propio panel'
        : 'Cerrar ${group.name}';

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: group.isSelf ? null : onTerminate,
        icon: const Icon(Icons.close, size: 16),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: ProcessColumns.actionWidth,
          height: 32,
        ),
      ),
    );
  }
}
