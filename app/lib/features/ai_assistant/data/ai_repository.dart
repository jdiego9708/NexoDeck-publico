import 'dart:io';

import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../actions/domain/deck_action.dart';
import '../domain/action_draft.dart';

/// Unica capa que importa `package:nexodeck/src/rust/api/ai.dart`.
///
/// Todo lo que sube de aca ya viene en tipos del dominio, que es lo que permite
/// testear el resto de la feature sin FFI. Mismo criterio que
/// `PairingRepository` con el bridge de emparejamiento.
class AiRepository {
  const AiRepository();

  // ---- Setup ----

  Future<bridge.AiCapabilities> probeCapabilities() =>
      bridge.probeAiCapabilities();

  Future<List<bridge.AiModelOption>> modelOptions(bridge.AiTier tier) =>
      bridge.aiModelOptions(tier: tier);

  Future<bridge.AiSetupState> setupState() => bridge.aiSetupState();

  /// Descarga lo que falte y levanta el motor. **La Future resuelve cuando
  /// termino todo**, que puede ser una hora: el progreso hay que mirarlo por
  /// [watchSetupEvents], no esperando esto.
  Future<void> startSetup({String? modelId}) =>
      bridge.startAiSetup(modelId: modelId);

  /// Descarga (o verifica) el modelo y su runtime **sin arrancar el motor**.
  /// La Future resuelve cuando termina; el progreso sale por [watchSetupEvents].
  Future<void> downloadModel({String? modelId}) =>
      bridge.downloadAiModel(modelId: modelId);

  Future<void> cancelSetup() => bridge.cancelAiSetup();

  Future<bridge.AiOllamaInstallation?> detectOllama() => bridge.detectOllama();

  Future<void> useOllama(String model) =>
      bridge.useOllamaProvider(model: model);

  // --- Control del Ollama instalado ---
  //
  // Encender y apagar la instalacion del usuario desde el menu "Mas". Ojo:
  // apagarlo apaga el Ollama de toda la maquina, no solo el que usa NexoDeck.

  Future<bridge.AiOllamaControlStatus> ollamaControlStatus() =>
      bridge.ollamaControlStatus();

  Future<bridge.AiOllamaControlStatus> startOllama() => bridge.startOllama();

  Future<bridge.AiOllamaControlStatus> stopOllama() => bridge.stopOllama();

  // --- Proveedores remotos (DeepSeek, OpenAI, un proxy propio) ---
  //
  // Hablan el mismo dialecto que el sidecar y que Ollama, asi que para el chat
  // son un modelo mas. Lo unico que cambia es la direccion, el modelo y una
  // clave.

  Future<List<bridge.AiRemotePreset>> remotePresets() =>
      bridge.aiRemotePresets();

  Future<String?> remoteApiKey(String providerId) =>
      bridge.aiRemoteApiKey(providerId: providerId);

  /// Ids de proveedores con una clave **ya guardada** (p. ej. `deepseek`).
  ///
  /// No hay un "listar claves" en el puente, y no hace falta: se prueba la ruta
  /// que Rust da para cada id conocido y se mira si el fichero existe. Es lo que
  /// permite ofrecer la DeepSeek que el usuario ya tenia sin pedirle la clave
  /// otra vez. Un id que no resuelve no es un error: simplemente no tiene clave.
  Future<Set<String>> remoteKeyIdsWithSavedKey(Iterable<String> ids) async {
    final saved = <String>{};
    for (final id in ids) {
      try {
        final path = await bridge.aiRemoteKeyPath(providerId: id);
        if (File(path).existsSync()) saved.add(id);
      } catch (_) {
        // Sin clave para ese id.
      }
    }
    return saved;
  }

  /// Ruta del fichero donde Rust guarda la clave de un proveedor. La usa la
  /// pasarela del stack para reenviar a un remoto sin duplicar el secreto.
  Future<String> remoteKeyPath(String providerId) =>
      bridge.aiRemoteKeyPath(providerId: providerId);

  Future<void> forgetRemoteApiKey(String providerId) =>
      bridge.forgetAiRemoteApiKey(providerId: providerId);

  Future<List<String>> remoteModels({
    required String baseUrl,
    required String apiKey,
  }) => bridge.listAiRemoteModels(baseUrl: baseUrl, apiKey: apiKey);

  /// Comprueba la clave **antes** de instalar el proveedor, y solo la guarda si
  /// el servicio contesto. Una clave mal pegada tiene que fallar aca, en el
  /// dialogo donde se puede corregir, no dentro de la conversacion.
  Future<void> useRemote({
    required String providerId,
    required String baseUrl,
    required String model,
    required String apiKey,
    required String displayName,
  }) => bridge.useRemoteProvider(
    providerId: providerId,
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    displayName: displayName,
  );

  Future<List<String>> defaultAllowedRoots() => bridge.defaultAiAllowedRoots();

  Future<void> setAllowedRoots(List<String> roots) =>
      bridge.setAiAllowedRoots(roots: roots);

  // ---- Chat ----

  /// Manda un mensaje. La Future resuelve cuando el **turno entero** termino
  /// (puede incluir varias llamadas a herramientas), no cuando se envio: es lo
  /// que usa la UI para saber cuando volver a habilitar el campo de texto.
  Future<void> sendMessage(String text) => bridge.sendAiMessage(text: text);

  Future<void> resetConversation() => bridge.resetAiConversation();

  Future<void> cancelTurn() => bridge.cancelAiTurn();

  Future<void> stop() => bridge.stopAiAssistant();

  /// Le pasa al asistente los botones que ya existen para que no proponga
  /// duplicados.
  Future<void> setDeckContext(List<DeckAction> actions) =>
      bridge.setAiDeckContext(
        actions: [
          for (final action in actions)
            bridge.AiDeckActionRef(
              id: action.id,
              name: action.name,
              kind: action.actionType.name,
              description: action.description,
            ),
        ],
      );

  // ---- Streams ----
  //
  // Se exponen crudos a proposito. **No los envuelvas en un StreamProvider que
  // se consuma con `ref.listen`**: Riverpod no vuelve a notificar cuando el
  // valor nuevo es `==` al anterior, y dos `AssistantToken(delta: " ")`
  // seguidos son identicos. Un stream de tokens es el peor caso posible de ese
  // bug, ya documentado en `CLAUDE.md`.

  Stream<bridge.AiSetupEvent> watchSetupEvents() => bridge.watchAiSetupEvents();

  Stream<bridge.AiChatEvent> watchChatEvents() => bridge.watchAiChatEvents();

  /// Convierte el borrador del bridge al dominio.
  ActionDraft draftFromBridge(bridge.AiActionDraft draft) =>
      ActionDraft.fromBridge(draft);
}
