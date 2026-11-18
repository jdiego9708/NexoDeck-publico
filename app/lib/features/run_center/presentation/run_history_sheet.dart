import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/run_center_controller.dart';
import '../domain/command_run.dart';

/// Historial de ejecuciones de la sesion.
///
/// Es en memoria a proposito: no hay tabla de Drift ni migracion. Lo que se
/// mira aca es "que corri hace un rato y como salio", no una bitacora
/// historica -- y la salida completa de cada una sigue viva del lado Rust
/// mientras el anillo la recuerde.
Future<void> showRunHistorySheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: _RunHistoryDialog()),
  );
}

class _RunHistoryDialog extends ConsumerWidget {
  const _RunHistoryDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final runs = ref.watch(runCenterProvider).runs;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ejecuciones',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: runs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: EmptyState(
                      icon: Icons.terminal,
                      title: 'Todavia no corriste nada',
                      message:
                          'Cuando ejecutes una accion de terminal vas a ver '
                          'aca como termino y su salida completa.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: runs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _HistoryTile(run: runs[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerStatefulWidget {
  const _HistoryTile({required this.run});

  final CommandRun run;

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile> {
  List<String>? _output;
  bool _loading = false;

  Future<void> _load() async {
    if (_output != null || _loading) return;
    setState(() => _loading = true);
    final output = await ref
        .read(runCenterProvider.notifier)
        .fullOutput(widget.run.id);
    if (mounted) {
      setState(() {
        _output = output;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final run = widget.run;
    final elapsed = run.elapsed(DateTime.now());

    return ExpansionTile(
      onExpansionChanged: (expanded) {
        if (expanded) _load();
      },
      leading: Icon(_iconFor(run), color: _colorFor(run, scheme), size: 20),
      title: Text(
        run.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Row(
        children: [
          Text(
            run.statusLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: _colorFor(run, scheme),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _formatDuration(elapsed),
            style: AppText.numeric(
              theme.textTheme.labelSmall,
            )?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (run.origin == RunOrigin.remote) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.smartphone, size: 12, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.fromBorderSide(AppSurface.hairline(scheme)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                run.command,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
                ),
              ),
              const Divider(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _outputText(run),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const [
                          'Consolas',
                          'Menlo',
                          'monospace',
                        ],
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _outputText(run)),
                    );
                  },
                  icon: const Icon(Icons.copy_all, size: 14),
                  label: const Text('Copiar'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// El anillo de Rust es la fuente preferida: la UI puede tener menos lineas
  /// si se suscribio tarde o si su propio limite la recorto.
  String _outputText(CommandRun run) {
    final full = _output;
    if (full != null && full.isNotEmpty) return full.join('\n');
    if (run.lines.isNotEmpty) return run.lines.map((l) => l.text).join('\n');
    return run.error ?? 'Sin salida';
  }
}

IconData _iconFor(CommandRun run) => switch (run.status) {
  RunStatus.starting || RunStatus.running => Icons.play_circle_outline,
  RunStatus.launched => Icons.open_in_new,
  RunStatus.succeeded => Icons.check_circle,
  RunStatus.failed => Icons.error,
  RunStatus.cancelled => Icons.remove_circle_outline,
};

Color _colorFor(CommandRun run, ColorScheme scheme) => switch (run.status) {
  RunStatus.starting || RunStatus.running => scheme.primary,
  RunStatus.launched => scheme.secondary,
  RunStatus.succeeded => scheme.primary,
  RunStatus.failed => scheme.error,
  RunStatus.cancelled => scheme.outline,
};

String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
