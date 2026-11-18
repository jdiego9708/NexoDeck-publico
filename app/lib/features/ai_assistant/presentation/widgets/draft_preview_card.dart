import 'package:flutter/material.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../actions/presentation/widgets/action_icons.dart';
import '../../domain/action_draft.dart';
import '../../domain/assistant_mode.dart';
import '../../domain/chat_entry.dart';
import 'risk_badge.dart';

/// Vista previa del borrador propuesto.
///
/// Muestra el boton **como va a verse** (mismo icono y color que va a tener en
/// el deck), el porque escrito por el modelo, y el comando exacto. Es lo que
/// permite aprobar con criterio: sin el comando a la vista, el usuario estaria
/// confiando en un resumen.
///
/// Las acciones que ofrece dependen del [mode]: en `createActions` es la de
/// siempre (un solo boton, "Abrir en el editor"). En `liveExecution` se
/// suman "Ejecutar ahora" y "Descartar" — nada corre ni se guarda hasta que
/// el usuario toca alguno de los tres.
class DraftPreviewCard extends StatelessWidget {
  const DraftPreviewCard({
    super.key,
    required this.draft,
    required this.mode,
    required this.onApply,
    this.onRun,
    this.onDiscard,
    this.outcome,
  });

  final ActionDraft draft;
  final AssistantMode mode;
  final VoidCallback onApply;

  /// Solo se usa (y solo hace falta pasarlo) en `liveExecution`.
  final VoidCallback? onRun;
  final VoidCallback? onDiscard;

  final DraftOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = colorFromHex(draft.colorHex);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppSurface.cardDecoration(
        scheme,
        hovered: false,
        focused: false,
        accent: accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(iconForName(draft.icon), color: accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (draft.description != null)
                      Text(
                        draft.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (draft.isMacro)
                Chip(
                  label: Text('${draft.steps.length} pasos'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),

          if (draft.summary.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              draft.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < draft.steps.length; index++)
            _StepPreview(
              step: draft.steps[index],
              index: index,
              showIndex: draft.isMacro,
            ),

          if (draft.risk != DraftRisk.safe) ...[
            const SizedBox(height: AppSpacing.sm),
            RiskBadge(
              risk: draft.risk,
              notes: [
                for (final step in draft.steps) ...step.riskNotes,
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          if (mode == AssistantMode.liveExecution)
            _LiveActions(outcome: outcome, onRun: onRun, onDiscard: onDiscard)
          else
            _CreateActions(draft: draft, outcome: outcome, onApply: onApply),
        ],
      ),
    );
  }
}

/// Pie de la tarjeta en modo `createActions`: sin cambios respecto de antes
/// de que existiera el modo en vivo.
class _CreateActions extends StatelessWidget {
  const _CreateActions({required this.draft, required this.outcome, required this.onApply});

  final ActionDraft draft;
  final DraftOutcome? outcome;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final applied = outcome == DraftOutcome.saved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: applied ? null : onApply,
                icon: Icon(applied ? Icons.check : Icons.edit_outlined, size: 18),
                label: Text(
                  applied
                      ? 'Ya lo abriste en el editor'
                      : draft.isMacro
                      ? 'Crear la cadena y abrir el editor'
                      : 'Abrir en el editor',
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            // El usuario tiene que saber que todavia no se guardo nada.
            'Nada se guarda ni se ejecuta hasta que lo confirmes en el editor.',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Pie de la tarjeta en modo vivo: la aprobacion del usuario, en dos botones.
///
/// **Rechazar** descarta el borrador; **Aprobar** lo corre de verdad (ver
/// `ai_live_runner.dart`). Con el switch en Automatico esto no se pregunta:
/// `_canAutoRun` lo ejecuta solo, salvo `Dangerous`/admin, que siempre piden
/// confirmacion. Ya no hay un tercer camino de "guardar como boton": el chat
/// ejecuta, no crea botones.
class _LiveActions extends StatelessWidget {
  const _LiveActions({
    required this.outcome,
    required this.onRun,
    required this.onDiscard,
  });

  final DraftOutcome? outcome;
  final VoidCallback? onRun;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final decided = outcome != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: decided ? null : onDiscard,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Rechazar'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: decided ? null : onRun,
                icon: Icon(
                  outcome == DraftOutcome.running
                      ? Icons.hourglass_top_rounded
                      : Icons.check,
                  size: 18,
                ),
                label: Text(
                  outcome == DraftOutcome.running ? 'Ejecutando...' : 'Aprobar',
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            switch (outcome) {
              null => 'Nada corre hasta que apruebes.',
              DraftOutcome.saved => 'Guardado como boton en el deck.',
              DraftOutcome.running =>
                'Aprobado — corriendo; el detalle aparece abajo.',
              DraftOutcome.discarded => 'Rechazado.',
            },
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepPreview extends StatelessWidget {
  const _StepPreview({
    required this.step,
    required this.index,
    required this.showIndex,
  });

  final DraftStep step;
  final int index;
  final bool showIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showIndex) ...[
                Text(
                  '${index + 1}.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  step.name,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _terminalLabel(step),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // El comando **resuelto**: el que realmente se va a guardar y
          // ejecutar, con el `cd` ya adentro. Mostrar el original seria mentir
          // sobre lo que hace el boton.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            child: SelectableText(
              step.resolvedCommand,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
                height: 1.45,
              ),
            ),
          ),

          if (step.parameters.isNotEmpty || step.autoSubscribe != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final param in step.parameters)
                    Chip(
                      label: Text('${param.label} · {{${param.key}}}'),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                  if (step.autoSubscribe != null)
                    Chip(
                      avatar: Icon(
                        Icons.podcasts_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      label: Text('Se suscribe a ${step.autoSubscribe!.hubPath} al terminar'),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _terminalLabel(DraftStep step) {
    if (step.actionType == ActionType.clipboard) return 'Portapapeles';
    final shell = switch (step.terminalType) {
      TerminalType.powershell => 'PowerShell',
      TerminalType.cmd => 'CMD',
      TerminalType.bash => 'Bash',
      TerminalType.defaultShell => 'Terminal',
    };
    return step.requiresAdmin ? '$shell · admin' : shell;
  }
}
