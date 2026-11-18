import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as remote_bridge;

import '../../../core/di/provider_reader.dart';
import '../../pairing/application/connection_provider.dart';
import '../data/ai_repository.dart';
import '../domain/chat_destination.dart';
import 'chat_conversation_controller.dart';
import 'claude_code_chat_controller.dart';

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => const AiRepository(),
);

/// Si el motor ya esta listo para conversar. **No es `aiSetupStateProvider`**
/// (ese es un `FutureProvider.autoDispose` de una sola lectura, pensado para
/// el wizard) -- esto es un valor vivo que `HostRuntime` mantiene al dia desde
/// su suscripcion a los eventos de setup, para que
/// cualquier otra parte de la UI (hoy, el boton nuevo del panel de procesos)
/// pueda leer "esta listo ahora mismo" sin re-preguntarle al engine.
final aiReadyProvider = StateProvider<bool>((ref) => false);

/// Rol PC: si el dialogo "Crear con IA" esta abierto ahora mismo.
/// `showAiAssistantDialog` lo prende al abrir y lo apaga cuando se cierra.
/// Sirve para no apilar un segundo dialogo si algo (como preguntar por un
/// proceso) pide abrirlo mientras ya hay uno -- ver `askAiInChat`.
final aiAssistantDialogOpenProvider = StateProvider<bool>((ref) => false);

/// Pedido de meter este texto en el chat y mandarlo, como si el usuario lo
/// hubiera escrito. `nonce` (un timestamp, nunca dos veces igual) es lo que
/// hace que preguntar dos veces SEGUIDAS por el mismo texto no se pierda por
/// el chequeo de igualdad de Riverpod -- la misma trampa de los eventos
/// repetibles documentada en `CLAUDE.md`, aca aplicada a un `StateProvider`
/// en vez de a un stream porque esto si necesita sobrevivir a que el
/// dialogo este cerrado todavia (ver `askAiInChat`).
final aiPendingPromptProvider = StateProvider<({int nonce, String text})?>(
  (ref) => null,
);

/// Manda un mensaje del usuario al asistente y lo hace visible en todos los
/// dispositivos conectados **menos** `exceptDeviceId` (el que ya se mostro
/// su propio mensaje solo, si vino de un telefono escribiendo directo -- ver
/// `main.dart`). Un mensaje que se origina en la PC (tecleado, o disparado
/// por un boton como "preguntar por este proceso") no excluye a nadie: todos
/// los conectados tienen que verlo.
///
/// Unico punto que llama a `sendMessage` -- antes cada llamador reenviaba el
/// eco a mano por su cuenta, y quedaba facil de olvidar en un camino nuevo
/// (como el de este mismo cambio).
/// Devuelve el id de la pregunta **solo cuando fue al corresponsal**, y `null`
/// cuando la contesta un modelo.
///
/// Ese id no es opcional para quien pinta el chat: con el campo de texto sin
/// bloquear se pueden encolar varias preguntas a la vez, y sin id la respuesta
/// se colocaria en la burbuja equivocada. Correlacionar "por la ultima que
/// esta esperando" funciona con una sola pregunta y miente con dos.
///
/// Recibe un [ProviderReader] y no un `WidgetRef` porque la llaman los dos
/// lados: el dialogo (con `ref.read`) y `HostRuntime`, que vive fuera del
/// arbol de widgets y lee del `ProviderContainer`.
Future<String?> sendAiMessageBroadcast(
  ProviderReader read,
  String text, {
  String? exceptDeviceId,
}) async {
  final devices = read(connectedDeviceIdsProvider);
  if (devices.isNotEmpty) {
    final repository = read(connectionRepositoryProvider);
    final event = remote_bridge.AiRemoteChatEvent.userMessage(text: text);
    for (final deviceId in devices) {
      if (deviceId == exceptDeviceId) continue;
      unawaited(repository.sendAiChatEvent(deviceId, event).catchError((_) {}));
    }
  }

  // **La conversacion se anota aca, no en el dialogo.** Es lo que hace que un
  // mensaje escrito en el telefono aparezca tambien en la PC: por aca pasan las
  // dos puntas, y el dialogo puede estar cerrado.
  // `exceptDeviceId` solo viene puesto cuando el mensaje **llego de un
  // telefono**: es el aparato al que no hay que devolverle su propio eco. Sirve
  // igual para saber desde donde se escribio, sin agregar otro parametro que
  // diga lo mismo.
  read(
    chatConversationProvider.notifier,
  ).addUserMessage(text, fromPhone: exceptDeviceId != null);

  // **Este es el unico punto de reparto, y por eso el telefono sale gratis.**
  // Aca llegan los tres caminos: lo que se escribe en la PC, lo que llega por
  // `AiMessageRequested` desde el telefono, y los prompts internos. Enrutar
  // aqui significa que elegir Claude Code vale para todos ellos sin tocar el
  // protocolo del cable.
  final destino = read(chatBackendProvider);
  if (isCorrespondentId(destino)) {
    // No se espera la respuesta: Claude Code tarda minutos y bloquear aqui
    // dejaria el campo de texto inerte todo ese rato. La respuesta llega por
    // `claudeCodeChatProvider`, con su id.
    // El id del destino lleva dentro a que terminal va. Sin sesion (el puente
    // a secas) encola para todas, que es lo correcto cuando da igual quien
    // conteste.
    return await read(
      claudeCodeChatProvider.notifier,
    ).ask(text, session: sessionIdOf(destino));
  }

  await read(aiRepositoryProvider).sendMessage(text);
  return null;
}

/// Id del destino que esta contestando **ahora**.
///
/// Es estado de sesion, no una preferencia: cual arranca lo decide el registro
/// (`chatDestinationsProvider`) resolviendo el destino por defecto contra lo
/// que de verdad existe. Guardar aqui un id que a lo mejor ya no sirve seria
/// tener la misma decision en dos sitios, y uno de los dos se equivocaria.
///
/// Vacio significa que todavia no hay ninguno activo.
final chatBackendProvider = StateProvider<String>((ref) => '');

/// Probe del hardware. **Sin `autoDispose` a proposito**: cuesta unos cientos
/// de milisegundos (inicializar NVML y crear una instancia de Vulkan) y nada de
/// lo que devuelve cambia mientras la app este abierta. Con autoDispose, cerrar
/// y reabrir el wizard lo re-ejecutaria cada vez.
final aiCapabilitiesProvider = FutureProvider<bridge.AiCapabilities>(
  (ref) => ref.watch(aiRepositoryProvider).probeCapabilities(),
);

/// Estado del setup. Este si es `autoDispose`: cambia (se instala un modelo, se
/// levanta el motor) y hay que releerlo al abrir el asistente.
final aiSetupStateProvider = FutureProvider.autoDispose<bridge.AiSetupState>(
  (ref) => ref.watch(aiRepositoryProvider).setupState(),
);

/// Modelos ofrecidos para una gama.
final aiModelOptionsProvider = FutureProvider.autoDispose
    .family<List<bridge.AiModelOption>, bridge.AiTier>(
      (ref, tier) => ref.watch(aiRepositoryProvider).modelOptions(tier),
    );

/// Ollama detectado en el equipo, si lo hay. `null` no es un error: no tenerlo
/// instalado es el caso normal.
final aiOllamaProvider =
    FutureProvider.autoDispose<bridge.AiOllamaInstallation?>(
      (ref) => ref.watch(aiRepositoryProvider).detectOllama(),
    );

/// La VRAM util del equipo (GiB) y el nombre de la GPU mas grande. La usa el
/// selector de modelos del stack para no dejar elegir dos que no caben juntos.
/// `budgetGb == 0` es "no se pudo leer" (sin GPU o sin probe): no se bloquea
/// nada, que es mejor que inventar un limite.
final aiVramBudgetProvider = Provider<({double budgetGb, String? gpu})>((ref) {
  final caps = ref.watch(aiCapabilitiesProvider).value;
  final gpus = caps?.gpus ?? const <bridge.AiGpuInfo>[];
  if (gpus.isEmpty) return (budgetGb: 0.0, gpu: null);
  final top = gpus.reduce((a, b) => a.vramTotalMb >= b.vramTotalMb ? a : b);
  return (budgetGb: top.vramTotalMb.toDouble() / 1024, gpu: top.name);
});

/// Los servicios por internet conocidos (DeepSeek, OpenAI, proxy propio).
final aiRemotePresetsProvider = FutureProvider<List<bridge.AiRemotePreset>>(
  (ref) => ref.watch(aiRepositoryProvider).remotePresets(),
);

/// Ids de esos servicios que ya tienen la **clave guardada** en este equipo.
/// Se sondea la ruta que da Rust para cada preset: es lo que hace que la
/// DeepSeek que el usuario ya tenia aparezca sola como opcion por slot.
final aiRemoteKeysSavedProvider = FutureProvider<Set<String>>((ref) async {
  final presets = await ref.watch(aiRemotePresetsProvider.future);
  return ref
      .watch(aiRepositoryProvider)
      .remoteKeyIdsWithSavedKey(presets.map((preset) => preset.id));
});

// ---------------------------------------------------------------------
// Streams crudos
// ---------------------------------------------------------------------

/// Eventos del chat, **suscripcion directa**.
///
/// No existe un `StreamProvider` para esto y no hay que crearlo: Riverpod no
/// vuelve a notificar cuando el valor nuevo es `==` al anterior, y dos
/// `AssistantToken(delta: " ")` seguidos son identicos — el chat perderia
/// tokens en silencio. Es el mismo bug que ya mordio dos veces con los eventos
/// de conexion y de emparejamiento (ver "Eventos del bridge" en `CLAUDE.md`),
/// y un stream de tokens es su peor caso posible.
///
/// Se consume con `.listen(...)` en `initState` y se cancela en `dispose()`.
Stream<bridge.AiChatEvent> aiChatEventStream(Ref ref) =>
    ref.read(aiRepositoryProvider).watchChatEvents();

/// Igual que arriba para el progreso del setup: dos eventos `Verifying` del
/// mismo asset seguidos son `==`, y perder el segundo deja el wizard mostrando
/// un paso que ya paso.
Stream<bridge.AiSetupEvent> aiSetupEventStream(Ref ref) =>
    ref.read(aiRepositoryProvider).watchSetupEvents();

/// Variante para widgets, que tienen `WidgetRef` y no `Ref`.
Stream<bridge.AiChatEvent> aiChatEventStreamOf(WidgetRef ref) =>
    ref.read(aiRepositoryProvider).watchChatEvents();

Stream<bridge.AiSetupEvent> aiSetupEventStreamOf(WidgetRef ref) =>
    ref.read(aiRepositoryProvider).watchSetupEvents();
