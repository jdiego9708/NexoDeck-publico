import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/interactive_card.dart';
import '../application/hub_subscriptions_provider.dart';
import '../domain/hub_subscription_summary.dart';
import 'hub_subscription_detail_screen.dart';
import 'new_hub_subscription_dialog.dart';
import 'widgets/hub_subscription_status_badge.dart';

Future<void> showHubSubscriptionsPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Alta y no `DraggableScrollableSheet`: la lista suele ser corta (pocas
    // suscripciones a la vez) y una hoja de tamano fijo evita el salto
    // inicial al medio de la pantalla que da `DraggableScrollableSheet`
    // cuando el contenido es chico.
    builder: (context) => const _HubSubscriptionsPanel(),
  );
}

class _HubSubscriptionsPanel extends ConsumerWidget {
  const _HubSubscriptionsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(hubSubscriptionsListProvider);

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suscripciones',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showNewHubSubscriptionDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: subscriptions.when(
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.podcasts_outlined,
                        title: 'Sin suscripciones todavía',
                        message:
                            'Conectate a un hub SignalR (como los de '
                            'ExampleApi) o a un WebSocket para recibir '
                            'mensajes en vivo, con historial persistido.',
                        action: FilledButton.icon(
                          onPressed: () => showNewHubSubscriptionDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Nueva suscripción'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) =>
                            _SubscriptionRow(subscription: list[index]),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Error cargando suscripciones: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.subscription});

  final HubSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = hubSubscriptionTarget(subscription);

    return InteractiveCard(
      onTap: () => showHubSubscriptionDetail(context, subscription),
      semanticLabel: subscription.name,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              subscription.kind == HubSubscriptionKind.signalR
                  ? Icons.podcasts_rounded
                  : Icons.cable_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subscription.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            HubSubscriptionStatusBadge(status: subscription.status),
          ],
        ),
      ),
    );
  }
}
