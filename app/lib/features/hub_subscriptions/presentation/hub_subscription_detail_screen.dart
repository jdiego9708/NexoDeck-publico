import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/hub_subscriptions_provider.dart';
import '../data/hub_subscriptions_repository.dart';
import '../domain/hub_subscription_summary.dart';
import 'widgets/hub_subscription_status_badge.dart';

Future<void> showHubSubscriptionDetail(
  BuildContext context,
  HubSubscription subscription,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => HubSubscriptionDetailScreen(
        subscriptionId: subscription.id,
      ),
    ),
  );
}

class HubSubscriptionDetailScreen extends ConsumerWidget {
  const HubSubscriptionDetailScreen({required this.subscriptionId, super.key});

  final String subscriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(hubSubscriptionsListProvider).value ?? const [];
    final subscription = subscriptions.where((s) => s.id == subscriptionId).firstOrNull;
    final messages = ref.watch(hubMessagesProvider(subscriptionId)).value ?? const [];

    if (subscription == null) {
      // Se borro (desde este mismo dialogo, u otra sesion). Cerrar sola en
      // vez de mostrar una pantalla vacia sin ninguna accion posible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final repository = ref.read(hubSubscriptionsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(subscription.name),
        actions: [
          if (subscription.status == HubSubscriptionStatus.active)
            IconButton(
              tooltip: 'Detener',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => repository.stop(subscription.id),
            )
          else
            IconButton(
              tooltip: 'Reiniciar',
              icon: const Icon(Icons.replay_rounded),
              onPressed: () => repository.restart(subscription),
            ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, repository, subscription),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                HubSubscriptionStatusBadge(status: subscription.status),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    hubSubscriptionTarget(subscription),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (subscription.status != HubSubscriptionStatus.active)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _GapNotice(status: subscription.status),
            ),
          const Divider(height: AppSpacing.md),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Todavía no llegó ningún mensaje',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // `reverse: true` ya invierte el orden visual; la
                      // lista sigue viniendo mas nuevo primero desde el DAO.
                      final message = messages[index];
                      return _MessageTile(message: message);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    HubSubscriptionsRepository repository,
    HubSubscription subscription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar suscripción'),
        content: Text(
          '¿Eliminar "${subscription.name}"? Se borra también todo su '
          'historial de mensajes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.delete(subscription.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _GapNotice extends StatelessWidget {
  const _GapNotice({required this.status});

  final HubSubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              status == HubSubscriptionStatus.stopped
                  ? 'Detenida. Lo que se emita mientras no esté conectada no '
                        'se recupera -- "Reiniciar" retoma desde ahora.'
                  : 'Se cortó la conexión. Lo que se haya perdido mientras '
                        'tanto no se recupera -- "Reiniciar" vuelve a conectar.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final HubMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
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
                  message.eventName,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              Text(
                _formatTime(message.receivedAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            message.payloadJson,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
