import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/hub_subscriptions_provider.dart';
import 'widgets/hub_subscription_status_badge.dart';

/// Version de solo lectura de `showHubSubscriptionsPanel` (escritorio), para
/// el rol Android: muestra el snapshot que la PC empuja por
/// `ConnectionEvent.hubSubscriptionsSnapshotReceived`
/// (`remoteHubSubscriptionsProvider`). Crear/detener/reiniciar sigue siendo
/// exclusivo de la PC -- por eso no hay boton "Nueva" ni fila clicable.
Future<void> showRemoteHubSubscriptionsPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _RemoteHubSubscriptionsPanel(),
  );
}

class _RemoteHubSubscriptionsPanel extends ConsumerWidget {
  const _RemoteHubSubscriptionsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(remoteHubSubscriptionsProvider) ?? const [];

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Suscripciones',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: subscriptions.isEmpty
                  ? const EmptyState(
                      icon: Icons.podcasts_outlined,
                      title: 'Sin suscripciones',
                      message:
                          'La PC no tiene ninguna suscripción en vivo '
                          'activa ahora mismo.',
                    )
                  : ListView.separated(
                      itemCount: subscriptions.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _RemoteSubscriptionRow(subscription: subscriptions[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteSubscriptionRow extends StatelessWidget {
  const _RemoteSubscriptionRow({required this.subscription});

  final bridge.HubSubscriptionSummary subscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastEventSummary = subscription.lastEventSummary;
    final lastEventAt = subscription.lastEventAt;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subscription.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              HubSubscriptionStatusBadge(status: _toDomainStatus(subscription.status)),
            ],
          ),
          Text(
            subscription.target,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (lastEventSummary != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    lastEventSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (lastEventAt != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _formatTime(lastEventAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// El resumen que viaja por la red usa los mismos 3 valores que el estado
  /// local de la fila (`HubSubscriptionStatus`) -- son tipos distintos
  /// (bridge vs Drift) por la misma razon que `HubSubscriptionSummary` no es
  /// `HubSubscription`: uno describe el cable, el otro la fila persistida.
  static HubSubscriptionStatus _toDomainStatus(
    bridge.HubSubscriptionSummaryStatus status,
  ) => switch (status) {
    bridge.HubSubscriptionSummaryStatus.active => HubSubscriptionStatus.active,
    bridge.HubSubscriptionSummaryStatus.stopped =>
      HubSubscriptionStatus.stopped,
    bridge.HubSubscriptionSummaryStatus.failed => HubSubscriptionStatus.failed,
  };

  /// `lastEventAt` llega en segundos Unix. Mismo formato que
  /// `_MessageTile._formatTime` en `hub_subscription_detail_screen.dart`.
  static String _formatTime(int unixSeconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
