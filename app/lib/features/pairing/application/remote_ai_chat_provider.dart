import 'package:flutter_riverpod/legacy.dart';

/// Rol Android: ultimo `AiStatus` recibido de la PC (switch de arriba +
/// motor listo) -- ver `ConnectionEvent.AiStatusReceived` en
/// `connected_device_screen.dart`. Vive en un provider (no en el estado
/// privado de la pantalla) porque el boton de entrada al chat remoto
/// (`connected_device_screen.dart`) y la pantalla del chat en si
/// (`remote_ai_chat_screen.dart`) lo necesitan los dos, y no comparten
/// arbol de widgets.
///
/// `enabled: false, ready: false` hasta que llega el primero -- el boton de
/// entrada arranca oculto, igual que en la PC el asistente arranca
/// desactivado.
final remoteAiStatusProvider = StateProvider<({bool enabled, bool ready})>(
  (ref) => (enabled: false, ready: false),
);

/// Si `RemoteAiChatScreen` esta empujada en este momento -- lo que deja que
/// "preguntarle a la IA por un proceso" (`process_panel.dart`) sepa si tiene
/// que abrir la pantalla o si ya hay una arriba (y apilar una segunda seria
/// confuso). Mismo patron que `aiAssistantDialogOpenProvider` del lado PC.
final remoteAiChatScreenOpenProvider = StateProvider<bool>((ref) => false);
