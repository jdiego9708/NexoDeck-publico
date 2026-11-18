import 'package:flutter/material.dart';
import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/data/local/database.dart';

/// Pregunta antes de borrar una conversacion y, si se confirma, la borra.
///
/// Es lo unico irreversible de estas pantallas, asi que se pregunta en las
/// dos: la hoja de conversaciones y el panel compacto comparten el mismo
/// dialogo. El archivado automatico nunca llega hasta aca.
Future<void> confirmDeleteConversation(
  BuildContext context,
  ChatConversationsDao dao,
  ChatConversation conversation,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Borrar la conversación?'),
      content: Text(
        '"${conversation.title}" y todos sus mensajes se pierden. '
        'Esto no se puede deshacer.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  if (confirmado == true) await dao.deleteConversation(conversation.id);
}
