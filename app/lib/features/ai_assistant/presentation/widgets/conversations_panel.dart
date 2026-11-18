import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../application/chat_conversation_controller.dart';
import '../../application/chat_conversations_providers.dart';
import '../../application/new_conversation.dart';
import '../../domain/conversation_when.dart';
import '../conversation_confirm.dart';

/// El indice de conversaciones guardadas, al lado del hilo.
///
/// Compacto a proposito: es para saltar de una charla a otra **de un vistazo**
/// (titulo y cuando fue), no para leerlas. Las acciones son las mismas de la
/// hoja -- abrir, conservar, archivar, borrar -- plegadas en un menu, que es
/// lo que cabe en este ancho.
///
/// Va dentro del panel del chat del centro de control, no como una zona propia:
/// acompana al hilo, no compite por el ancho con metricas y acciones.
class ConversationsPanel extends ConsumerWidget {
  const ConversationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(conversationsPanelCollapsedProvider);
    if (collapsed) return const _CollapsedBar();

    return SizedBox(
      width: AppSizes.conversationsPanelWidth,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          Divider(height: 1),
          Expanded(child: _ConversationsList()),
          Divider(height: 1),
          _NewConversationButton(),
        ],
      ),
    );
  }
}

/// Barrita que queda plegado, con el boton para volver a mostrarlo. El chevron
/// apunta hacia adentro (el panel vive contra el borde izquierdo del chat).
class _CollapsedBar extends ConsumerWidget {
  const _CollapsedBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: AppSizes.collapsedMetricsExtent,
      child: Center(
        child: IconButton(
          tooltip: 'Mostrar conversaciones',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: () =>
              ref.read(conversationsPanelControllerProvider).setCollapsed(false),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xxs,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Conversaciones',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ocultar conversaciones',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: () =>
                ref.read(conversationsPanelControllerProvider).setCollapsed(true),
          ),
        ],
      ),
    );
  }
}

class _ConversationsList extends ConsumerWidget {
  const _ConversationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final conversations = ref.watch(activeConversationsProvider);

    return conversations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          'No se pudieron leer: $error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              'Todavía no hay conversaciones guardadas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: list.length,
          itemBuilder: (context, index) =>
              _ConversationRow(conversation: list[index]),
        );
      },
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dao = ref.watch(chatConversationsDaoProvider);

    return InkWell(
      onTap: () =>
          ref.read(chatConversationProvider.notifier).open(conversation.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xxs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    conversationWhenLabel(
                      updatedAt: conversation.updatedAt,
                      keepForever: conversation.keepForever,
                      archived: conversation.archivedAt != null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _RowMenu(conversation: conversation, dao: dao),
          ],
        ),
      ),
    );
  }
}

/// Las acciones de la fila, en un menu: conservar, archivar y borrar. El mismo
/// repertorio que la hoja, en el espacio que hay.
class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.conversation, required this.dao});

  final ChatConversation conversation;
  final ChatConversationsDao dao;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RowAction>(
      tooltip: 'Más',
      icon: const Icon(Icons.more_vert, size: 16),
      iconSize: 16,
      padding: EdgeInsets.zero,
      onSelected: (action) async {
        switch (action) {
          case _RowAction.keepForever:
            await dao.setKeepForever(
              conversation.id,
              !conversation.keepForever,
            );
          case _RowAction.archive:
            await dao.setArchived(conversation.id, true);
          case _RowAction.delete:
            if (context.mounted) {
              await confirmDeleteConversation(context, dao, conversation);
            }
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _RowAction.keepForever,
          checked: conversation.keepForever,
          child: const Text('Conservar siempre'),
        ),
        const PopupMenuItem(
          value: _RowAction.archive,
          child: Text('Archivar'),
        ),
        const PopupMenuItem(
          value: _RowAction.delete,
          child: Text('Borrar'),
        ),
      ],
    );
  }
}

enum _RowAction { keepForever, archive, delete }

/// El boton de "Nueva conversacion", al pie del indice.
///
/// Es el mismo gesto que "Empezar de nuevo" del chat, donde se esta mirando el
/// hilo: aca queda a mano cuando lo que se esta mirando es la lista.
class _NewConversationButton extends ConsumerWidget {
  const _NewConversationButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: FilledButton.tonalIcon(
        onPressed: () => startNewConversation(ref),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
        icon: const Icon(Icons.add, size: 16),
        label: const Text(
          'Nueva conversación',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
