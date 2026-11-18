import 'package:flutter/material.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/theme/app_text.dart';
import '../../domain/setup_progress.dart';

/// Lo que NexoDeck detecto del equipo y que decidio a partir de eso.
///
/// Los `reasons` se muestran completos y en el mismo lugar: "te toco la gama
/// baja" sin explicacion es indistinguible de un bug, y es justo el caso en el
/// que el usuario quiere entender si puede hacer algo al respecto.
class HardwareSummaryCard extends StatelessWidget {
  const HardwareSummaryCard({super.key, required this.capabilities});

  final bridge.AiCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gpu = capabilities.gpus.isEmpty
        ? null
        : capabilities.gpus.reduce(
            (a, b) => a.vramTotalMb >= b.vramTotalMb ? a : b,
          );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppSurface.cardDecoration(scheme, hovered: false, focused: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Tu equipo',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text(_tierLabel(capabilities.recommendedTier)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          _Row(
            icon: Icons.developer_board,
            label: capabilities.cpuBrand,
            value:
                '${capabilities.physicalCores ?? capabilities.logicalCores} nucleos'
                '${capabilities.avx2 ? ' · AVX2' : ''}',
          ),
          _Row(
            icon: Icons.videogame_asset_outlined,
            label: gpu?.name ?? 'Sin GPU dedicada',
            value: gpu == null ? '' : '${gpu.vramTotalMb} MB VRAM',
          ),
          _Row(
            icon: Icons.storage_outlined,
            label: 'Memoria y disco',
            value:
                '${formatBytes(capabilities.ramTotalMb * BigInt.from(1024 * 1024))} RAM · '
                '${formatBytes(capabilities.freeDiskMb * BigInt.from(1024 * 1024))} libres',
          ),

          if (capabilities.reasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            for (final reason in capabilities.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  '· $reason',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _tierLabel(bridge.AiTier tier) => switch (tier) {
    bridge.AiTier.light => 'Gama baja',
    bridge.AiTier.balanced => 'Gama media',
    bridge.AiTier.performance => 'Gama alta',
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            // Cifras tabulares: son numeros y conviven en columna.
            style: AppText.numeric(
              theme.textTheme.bodySmall,
            )?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
