import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/action_draft.dart';

/// Aviso de riesgo de un comando generado.
///
/// `safe` **no dibuja nada**: un badge verde en cada borrador entrena al
/// usuario a ignorar la fila entera, y entonces el aviso rojo tampoco se lee.
/// Solo aparece cuando hay algo que decir.
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.risk, this.notes = const []});

  final DraftRisk risk;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (risk == DraftRisk.safe) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final (color, icon, label) = switch (risk) {
      DraftRisk.dangerous => (
        scheme.error,
        Icons.gpp_maybe_outlined,
        'Revisalo con atencion',
      ),
      DraftRisk.caution => (
        scheme.tertiary,
        Icons.info_outline,
        'Hace cambios reales',
      ),
      DraftRisk.safe => (scheme.primary, Icons.check, ''),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      '· $note',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
