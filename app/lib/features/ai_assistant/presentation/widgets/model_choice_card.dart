import 'package:flutter/material.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../domain/setup_progress.dart';

/// Una opcion de modelo en el wizard.
///
/// Usa [InteractiveCard] y **no** va envuelta en un `Card`: el `cardTheme`
/// global ya dibuja un hairline y quedarian dos bordes superpuestos.
class ModelChoiceCard extends StatelessWidget {
  const ModelChoiceCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final bridge.AiModelOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        onTap: onTap,
        accent: selected ? scheme.primary : null,
        semanticLabel: option.displayName,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      option.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (option.isDefault)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Chip(
                        label: const Text('Recomendado'),
                        visualDensity: VisualDensity.compact,
                        labelStyle: theme.textTheme.labelSmall,
                      ),
                    ),
                  if (option.installed)
                    Icon(Icons.download_done, size: 16, color: scheme.primary),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                option.notes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Tag(
                    icon: Icons.download_outlined,
                    // El total incluye el runtime que falte, no solo el
                    // modelo: si prometemos 9 GB y terminan siendo 9,5 la barra
                    // "se pasa" y queda como un bug.
                    text: option.installed
                        ? 'Ya descargado'
                        : formatBytes(option.totalDownloadBytes),
                  ),
                  _Tag(icon: Icons.tag, text: option.quantization),
                  _Tag(icon: Icons.balance, text: option.license),
                  if (option.fitsInGpu)
                    const _Tag(icon: Icons.bolt, text: 'Entra entero en la GPU'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
