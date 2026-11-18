import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/assistant_mode.dart';
import '../../domain/chat_entry.dart';
import 'draft_preview_card.dart';
import 'live_run_tile.dart';

/// Fila colapsable para un [DraftEntry]: por defecto solo se ve una linea
/// ("Borrador listo" / "Ejecutando..." / "Guardado" / "Descartado") con un
/// icono de estado, igual que una llamada a herramienta — es "una fase mas"
/// de la conversacion, no algo que se imponga a la vista. Tocarla revela la
/// tarjeta completa (`DraftPreviewCard`, con sus botones) y, si ya corrio
/// algo, los pasos en vivo debajo (`LiveRunTile` por cada uno).
class DraftTraceTile extends StatelessWidget {
  const DraftTraceTile({
    super.key,
    required this.entry,
    required this.mode,
    required this.onToggle,
    required this.onApply,
    this.onRun,
    this.onDiscard,
  });

  final DraftEntry entry;
  final AssistantMode mode;
  final VoidCallback onToggle;
  final VoidCallback onApply;
  final VoidCallback? onRun;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, spinning, label, color) = _headerFor(entry, scheme);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: spinning
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
                        )
                      : Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  entry.expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: color.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
          if (entry.expanded) ...[
            const SizedBox(height: AppSpacing.xs),
            DraftPreviewCard(
              draft: entry.draft,
              mode: mode,
              outcome: entry.outcome,
              onApply: onApply,
              onRun: onRun,
              onDiscard: onDiscard,
            ),
            for (final step in entry.liveSteps) LiveRunTile(entry: step),
          ],
        ],
      ),
    );
  }

  (IconData, bool, String, Color) _headerFor(DraftEntry entry, ColorScheme scheme) {
    switch (entry.outcome) {
      case null:
        return (Icons.check_circle_outline, false, 'Borrador listo · ${entry.draft.name}', scheme.onSurfaceVariant);
      case DraftOutcome.saved:
        return (Icons.check_circle_outline, false, 'Guardado como boton', scheme.onSurfaceVariant);
      case DraftOutcome.running:
        // El detalle real (que paso termino, si alguno fallo) esta un click
        // mas adentro, en cada `LiveRunTile` — este encabezado se queda con
        // el estado grueso a proposito, para no tener que mirar el
        // `runCenterProvider` dos veces (aca y adentro de cada tile).
        return entry.isExecuting
            ? (Icons.play_arrow_rounded, true, 'Ejecutando...', scheme.onSurfaceVariant)
            : (Icons.check_circle_outline, false, 'Ejecutado — toca para ver el detalle', scheme.onSurfaceVariant);
      case DraftOutcome.discarded:
        return (Icons.remove_circle_outline, false, 'Descartado', scheme.onSurfaceVariant);
    }
  }
}
