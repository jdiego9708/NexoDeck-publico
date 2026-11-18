import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../run_center/application/run_center_controller.dart';
import '../../../run_center/domain/command_run.dart';
import '../../domain/chat_entry.dart';

/// Un paso corrido en modo en vivo, dentro de la conversacion.
///
/// Para un paso capturado (`entry.runId != null`) mira `runCenterProvider`
/// con `select`, acotado a esa unica corrida: cada evento (`Output`,
/// `Finished`...) reemplaza al `CommandRun` de esa fila por un objeto nuevo
/// (`RunCenterController._update`), asi que la comparacion por identidad que
/// hace `select` alcanza para redibujar solo esta tile y no toda la
/// conversacion, y para NO redibujarla cuando cambia una corrida ajena (otro
/// boton del deck, por ejemplo). El Panel de Ejecuciones ya muestra la misma
/// corrida por su cuenta, via el mismo provider: esto no inventa una segunda
/// fuente de verdad, solo la mira desde otro angulo.
class LiveRunTile extends ConsumerWidget {
  const LiveRunTile({super.key, required this.entry});

  final LiveRunEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runId = entry.runId;
    if (runId == null) return _StaticTile(entry: entry);

    final run = ref.watch(
      runCenterProvider.select(
        (state) => state.runs.where((r) => r.id == runId).firstOrNull,
      ),
    );
    if (run == null) return _StaticTile(entry: entry);

    return _RunningTile(stepName: entry.stepName, runId: runId, run: run);
  }
}

class _StaticTile extends StatelessWidget {
  const _StaticTile({required this.entry});

  final LiveRunEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _TileRow(
      leading: Icon(Icons.check_circle_outline, size: 14, color: scheme.onSurfaceVariant),
      child: Text.rich(
        TextSpan(
          text: entry.stepName,
          children: [
            TextSpan(
              text: ' · ${entry.staticMessage}',
              style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.75)),
            ),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _RunningTile extends ConsumerStatefulWidget {
  const _RunningTile({required this.stepName, required this.runId, required this.run});

  final String stepName;
  final String runId;
  final CommandRun run;

  @override
  ConsumerState<_RunningTile> createState() => _RunningTileState();
}

class _RunningTileState extends ConsumerState<_RunningTile> {
  /// `null` = colapsado (solo la cola). Una vez pedida, la salida completa
  /// se guarda aca en vez de volver a pedirla en cada rebuild — el anillo de
  /// Rust no cambia entre pedidos para una corrida ya terminada, y para una
  /// que sigue corriendo `run.lines` (el `ConsumerWidget` de arriba) ya la
  /// mantiene al dia sin volver a pedir nada.
  List<String>? _fullOutput;
  bool _loadingFull = false;

  /// Bug real: `git status` con muchos archivos modificados termina con el
  /// pie generico de git ("no changes added to commit..."), y mostrar SOLO
  /// las ultimas lineas hacia parecer que no habia cambios cuando en
  /// realidad habia decenas mas arriba. "Ultimas N lineas" es una buena
  /// heuristica para un build o un test (lo que importa es el final), pero
  /// mala para un comando que lista cosas — por eso expandir tiene que ser
  /// un click, no algo que haya que adivinar que existe.
  Future<void> _showFull() async {
    setState(() => _loadingFull = true);
    final lines = await ref.read(runCenterProvider.notifier).fullOutput(widget.runId);
    if (!mounted) return;
    setState(() {
      _fullOutput = lines;
      _loadingFull = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final run = widget.run;
    final failed = run.status == RunStatus.failed || run.status == RunStatus.cancelled;
    final color = failed ? scheme.error : scheme.onSurfaceVariant;
    final expanded = _fullOutput != null;
    // Mientras el proceso sigue vivo, "ultimas 4" ya alcanza para saber que
    // esta pasando; el boton de expandir aparece recien con algo mas que
    // mostrar o cuando termino (ahi es cuando de verdad importa leer todo).
    final canExpand = !expanded && (run.lines.length > 4 || !run.isActive);

    return _TileRow(
      leading: run.isActive
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          : Icon(
              failed ? Icons.error_outline : Icons.check_circle_outline,
              size: 14,
              color: color,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: widget.stepName,
              children: [
                TextSpan(
                  text: ' · ${run.statusLabel}',
                  style: TextStyle(color: color.withValues(alpha: 0.85)),
                ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
          if (run.lines.isNotEmpty || expanded)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xxs),
              padding: const EdgeInsets.all(AppSpacing.xs),
              width: double.infinity,
              constraints: expanded ? const BoxConstraints(maxHeight: 240) : null,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.xs),
              ),
              child: expanded
                  ? SingleChildScrollView(child: _outputText(theme, _fullOutput!, maxLines: null))
                  : _outputText(
                      theme,
                      run.lines
                          .skip(run.lines.length > 4 ? run.lines.length - 4 : 0)
                          .map((line) => line.text)
                          .toList(),
                      maxLines: 4,
                    ),
            ),
          if (canExpand || expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: _loadingFull
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
                    )
                  : InkWell(
                      onTap: expanded ? () => setState(() => _fullOutput = null) : _showFull,
                      child: Text(
                        expanded ? 'Ver menos' : 'Mostrando lo ultimo · Ver todo',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _outputText(ThemeData theme, List<String> lines, {required int? maxLines}) {
    final scheme = theme.colorScheme;
    return Text(
      lines.join('\n'),
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
        color: scheme.onSurfaceVariant,
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.leading, required this.child});

  final Widget leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 16, child: leading),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: child),
        ],
      ),
    );
  }
}
