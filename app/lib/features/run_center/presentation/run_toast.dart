import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../../core/theme/app_text.dart';
import '../domain/command_run.dart';
import 'widgets/run_output.dart';

/// Ancho de la pila de notificaciones en escritorio. Fijo a proposito: una
/// tarjeta que cambia de ancho segun el largo del comando hace saltar toda la
/// pila cada vez que entra una nueva.
const kRunToastWidth = 380.0;

/// Alto maximo del panel de salida cuando la tarjeta esta expandida.
const _kOutputMaxHeight = 220.0;

/// Notificacion de una ejecucion de comando.
///
/// Todo lo visual sale de los tokens (`AppSurface`, `AppSpacing`,
/// `AppDuration`): no hay ni un color ni un radio escrito a mano. En
/// particular el cronometro usa `AppText.numeric()` porque se redibuja 5
/// veces por segundo -- sin cifras tabulares el numero cambia de ancho al
/// pasar de `9s` a `10s` y la tarjeta "baila".
class RunToast extends StatefulWidget {
  const RunToast({
    super.key,
    required this.run,
    required this.now,
    required this.onDismiss,
    required this.onCancel,
    required this.loadOutput,
  });

  final CommandRun run;
  final DateTime now;
  final VoidCallback onDismiss;
  final VoidCallback onCancel;
  final Future<List<String>> Function() loadOutput;

  @override
  State<RunToast> createState() => _RunToastState();
}

class _RunToastState extends State<RunToast> {
  bool _expanded = false;
  List<String>? _fullOutput;

  Future<void> _toggleExpanded() async {
    final expanding = !_expanded;
    setState(() => _expanded = expanding);
    if (!expanding || _fullOutput != null) return;
    // El anillo completo vive del lado Rust: la UI puede tener menos lineas
    // (se suscribio tarde, o el limite de la lista la recorto).
    final output = await widget.loadOutput();
    if (mounted) setState(() => _fullOutput = output);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final run = widget.run;
    final elapsed = run.elapsed(widget.now);
    final slow = run.isActive && elapsed >= kSlowRunThreshold;
    final accent = _accentFor(run, scheme, slow: slow);

    // `Material` transparente por la misma razon que no hay tooltips: fuera
    // del Navigator no hay ningun `Material` ancestro, y los `IconButton` /
    // `TextButton` de adentro lo necesitan para dibujar su tinta. El fondo lo
    // sigue poniendo el `Container` con los tokens.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedSize(
        duration: AppDuration.state,
        curve: AppCurves.emphasized,
        alignment: Alignment.topCenter,
        child: Container(
          width: kRunToastWidth,
          decoration: AppSurface.cardDecoration(scheme, accent: accent),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de acento a la izquierda + contenido. La barra es lo que
              // hace legible el estado de un vistazo desde el rabillo del ojo,
              // sin tener que leer el texto.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: accent),
                    Expanded(
                      child: _buildHeader(
                        context,
                        scheme,
                        accent,
                        elapsed,
                        slow,
                      ),
                    ),
                  ],
                ),
              ),
              if (run.isActive)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.15),
                ),
              if (_expanded) _buildOutput(context, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme scheme,
    Color accent,
    Duration elapsed,
    bool slow,
  ) {
    final theme = Theme.of(context);
    final run = widget.run;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusGlyph(run: run, accent: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      run.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            slow
                                ? 'Tardando mas de lo normal'
                                : run.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          formatRunElapsed(elapsed),
                          style: AppText.numeric(
                            theme.textTheme.labelSmall,
                          )?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (run.origin == RunOrigin.remote) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.smartphone,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _buildActions(context, scheme),
            ],
          ),
          if (_summaryLine(run) case final summary? when !_expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme scheme) {
    final run = widget.run;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sin `tooltip:` en NINGUNO de estos botones, a proposito: el host de
        // notificaciones vive por ENCIMA del Navigator (cuelga de
        // `MaterialApp.builder`), asi que este subarbol no tiene un `Overlay`
        // ancestro y `Tooltip` explota con "No Overlay widget found" en cada
        // frame. Por lo mismo se usa `Text` y no `SelectableText` en la
        // salida: para copiarla esta el boton. El dialogo de historial si
        // vive dentro del Navigator y ahi ambos se pueden usar.
        if (run.lines.isNotEmpty || run.isActive || run.isFailure)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: _toggleExpanded,
            icon: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: AppDuration.state,
              curve: AppCurves.standard,
              child: const Icon(Icons.expand_more),
            ),
          ),
        // Cancelar solo mientras corre y solo si de verdad se puede: una
        // ejecucion elevada no es cancelable desde un proceso sin elevar, y
        // un boton que no hace nada es peor que no tenerlo.
        if (run.isActive && run.cancellable)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: widget.onCancel,
            icon: const Icon(Icons.stop_circle_outlined),
          )
        else if (!run.isActive)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: widget.onDismiss,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }

  Widget _buildOutput(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    final run = widget.run;
    final full = _fullOutput;

    final children = <Widget>[
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

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: _kOutputMaxHeight),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: AppSurface.hairline(scheme)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: children.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Sin salida',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    reverse: true,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    children: children.reversed.toList(),
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                0,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: TextButton.icon(
                onPressed: () => _copyOutput(context),
                icon: const Icon(Icons.copy_all, size: 14),
                label: const Text('Copiar'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyOutput(BuildContext context) async {
    final text = (_fullOutput ?? widget.run.lines.map((l) => l.text).toList())
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Salida copiada')));
    }
  }

  /// Que mostrar en la linea de resumen cuando esta contraida: el error si
  /// fallo, la ultima linea si esta corriendo.
  String? _summaryLine(CommandRun run) {
    if (run.error case final error?) return error;
    return run.lastLine;
  }

  Color _accentFor(CommandRun run, ColorScheme scheme, {required bool slow}) {
    if (slow) return scheme.tertiary;
    return switch (run.status) {
      RunStatus.starting || RunStatus.running => scheme.primary,
      RunStatus.launched => scheme.secondary,
      RunStatus.succeeded => scheme.primary,
      RunStatus.failed => scheme.error,
      RunStatus.cancelled => scheme.outline,
    };
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.run, required this.accent});

  final CommandRun run;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (run.isActive) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    }
    final icon = switch (run.status) {
      RunStatus.launched => Icons.open_in_new,
      RunStatus.succeeded => Icons.check_circle,
      RunStatus.failed => Icons.error,
      RunStatus.cancelled => Icons.remove_circle_outline,
      _ => Icons.circle,
    };
    return Icon(icon, size: 18, color: accent);
  }
}

