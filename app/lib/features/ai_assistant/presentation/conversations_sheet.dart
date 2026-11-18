import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/chat_conversation_controller.dart';
import '../application/chat_conversations_providers.dart';
import '../domain/conversation_when.dart';
import 'conversation_confirm.dart';

/// Las conversaciones guardadas: abrir una vieja, marcarla para conservar, o
/// mandarla al archivo a mano.
///
/// El panel compacto del centro de control (`widgets/conversations_panel.dart`)
/// es el mismo repertorio en formato indice; esta hoja sigue siendo la vista
/// con las dos listas (activas y archivadas) y la que se abre desde el dialogo
/// del asistente (icono de historial).
Future<void> showConversationsSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ConversationsSheet(),
  );
}

class _ConversationsSheet extends ConsumerWidget {
  const _ConversationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activas = ref.watch(activeConversationsProvider);
    final archivadas = ref.watch(archivedConversationsProvider);

    return AlertDialog(
      title: const Text('Conversaciones'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: ListView(
          children: [
            Text(
              'Las que llevan más de un mes sin actividad se archivan solas. '
              'Marcá con el interruptor las que quieras conservar siempre: '
              'esas nunca se archivan. Nada se borra sin que lo pidas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _Section(
              title: 'Activas',
              conversations: activas,
              emptyText: 'Todavía no hay ninguna conversación guardada.',
            ),
            const SizedBox(height: AppSpacing.lg),
            _Section(
              title: 'Archivadas',
              conversations: archivadas,
              emptyText: 'No hay ninguna archivada.',
              archived: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _Section extends ConsumerWidget {
  const _Section({
    required this.title,
    required this.conversations,
    required this.emptyText,
    this.archived = false,
  });

  final String title;
  final AsyncValue<List<ChatConversation>> conversations;
  final String emptyText;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        conversations.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            'No se pudieron leer: $error',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (list) => list.isEmpty
              ? Text(emptyText, style: theme.textTheme.bodySmall)
              : Column(
                  children: [
                    for (final conversation in list)
                      _Row(conversation: conversation, archived: archived),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.conversation, required this.archived});

  final ChatConversation conversation;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dao = ref.watch(chatConversationsDaoProvider);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(conversation.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        conversationWhenLabel(
          updatedAt: conversation.updatedAt,
          keepForever: conversation.keepForever,
          archived: conversation.archivedAt != null,
        ),
        style: theme.textTheme.bodySmall,
      ),
      onTap: () async {
        await ref.read(chatConversationProvider.notifier).open(conversation.id);
        if (context.mounted) Navigator.of(context).pop();
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // El interruptor de conservar. Ponerlo tambien la desarchiva: pedir
          // que algo se guarde y dejarlo escondido seria lo contrario.
          Tooltip(
            message: 'Conservar para siempre',
            child: Switch(
              value: conversation.keepForever,
              onChanged: (value) => dao.setKeepForever(conversation.id, value),
            ),
          ),
          IconButton(
            tooltip: archived ? 'Desarchivar' : 'Archivar ahora',
            icon: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              size: 18,
            ),
            onPressed: () => dao.setArchived(conversation.id, !archived),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () =>
                confirmDeleteConversation(context, dao, conversation),
          ),
        ],
      ),
    );
  }
}
