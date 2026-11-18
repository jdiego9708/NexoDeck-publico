import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/notes.dart';

/// Un digest con su traza: en qué quedó, con qué modelo, qué buscó y qué hizo
/// cada agente.
///
/// Existe para poder creer la propuesta. "Esto ya se habló el 3-sep" solo vale
/// si se ve de dónde sale: qué candidatos vio la memoria, qué citó y qué se
/// descartó por no existir.
class DigestTraceView extends StatelessWidget {
  const DigestTraceView({super.key, required this.digest, this.onOpenProposal});

  final NoteDigest digest;

  /// Abre el buzón, donde se aprueba la propuesta. `null` si no hay propuesta.
  final VoidCallback? onOpenProposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = digest.state == NoteDigestState.failed;
    final tone = failed ? theme.colorScheme.error : theme.colorScheme.primary;
    final created = digest.createdAt;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_iconFor(digest.state), size: 18, color: tone),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${digest.state.label} · ${digest.triggerLabel}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (created != null)
                  Text(
                    shortDateTime(created),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (digest.stateDetail != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  digest.stateDetail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: failed ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                'Modelo: ${digest.modelLabel.isEmpty ? '—' : digest.modelLabel}',
                if (digest.hub != null) 'nota de proyecto: ${digest.hub}',
                if (digest.requeried) 'el crítico pidió buscar otra vez',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (digest.redactions > 0)
              Text(
                'Se quitaron ${digest.redactions} secretos antes de mandar nada '
                'al modelo.',
                style: theme.textTheme.bodySmall,
              ),
            if (digest.discardedIds.isNotEmpty)
              Text(
                'Citas descartadas por no existir: '
                '${digest.discardedIds.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            if (digest.steps.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Qué hizo cada agente (${digest.steps.length})',
                  style: theme.textTheme.bodyMedium,
                ),
                children: [for (final step in digest.steps) _StepView(step)],
              ),
            if (digest.candidates.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Lo que encontró Rust (${digest.candidates.length} candidatos)',
                  style: theme.textTheme.bodyMedium,
                ),
                children: [
                  for (final candidate in digest.candidates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate.title}'
                            '${candidate.date == null ? '' : ' · ${candidate.date}'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            candidate.snippet,
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            candidate.id,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (onOpenProposal != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenProposal,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Ver la propuesta en el buzón'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(NoteDigestState state) => switch (state) {
    NoteDigestState.queued => Icons.schedule_outlined,
    NoteDigestState.running => Icons.autorenew,
    NoteDigestState.proposed => Icons.edit_note_outlined,
    NoteDigestState.skipped => Icons.do_not_disturb_on_outlined,
    NoteDigestState.failed => Icons.error_outline,
    NoteDigestState.waitingModel => Icons.hourglass_empty,
    NoteDigestState.unknown => Icons.help_outline,
  };
}

class _StepView extends StatelessWidget {
  const _StepView(this.step);

  final NoteAgentStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = step.ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                step.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: tone,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(step.label, style: theme.textTheme.bodyMedium),
              ),
              Text('${step.millis} ms', style: theme.textTheme.bodySmall),
            ],
          ),
          if (step.detail != null)
            Text(step.detail!, style: theme.textTheme.bodySmall),
          if (step.outputJson != null)
            ConstrainedBox(
              // Una salida larga no puede empujar el resto del diálogo fuera de
              // la pantalla.
              constraints: const BoxConstraints(maxHeight: 240),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: SelectableText(
                    step.outputJson!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['Courier New', 'monospace'],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `15/9 14:05`. Corto a propósito: va al lado de un título.
String shortDateTime(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.day}/${date.month} ${two(date.hour)}:${two(date.minute)}';
}
