import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_providers.dart';
import 'chat_conversation_controller.dart';

/// Empieza una conversacion nueva: reinicia el historial del motor (lado Rust)
/// y limpia lo que hay en pantalla.
///
/// Una sola definicion para los dos botones que lo hacen: "Empezar de nuevo"
/// (pie del chat) y "Nueva conversacion" (indice de conversaciones). Tenerlo
/// dos veces era la misma decision escrita dos veces.
Future<void> startNewConversation(WidgetRef ref) async {
  await ref.read(aiRepositoryProvider).resetConversation();
  ref.read(chatConversationProvider.notifier).clear();
}
