import 'package:flutter/material.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';

import '../../../../core/theme/app_spacing.dart';

class HubSubscriptionStatusBadge extends StatelessWidget {
  const HubSubscriptionStatusBadge({required this.status, super.key});

  final HubSubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      HubSubscriptionStatus.active => ('Activa', Colors.green),
      HubSubscriptionStatus.stopped => ('Detenida', scheme.onSurfaceVariant),
      HubSubscriptionStatus.failed => ('Desconectada', scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
