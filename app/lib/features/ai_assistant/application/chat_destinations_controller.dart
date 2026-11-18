import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;
import 'package:nexodeck/src/rust/api/control.dart' as control_bridge;

import '../../../core/di/database_provider.dart';
import '../../control/application/control_settings_controller.dart';
import '../domain/chat_destination.dart';
import 'ai_providers.dart';

const _kPrefsKey = 'chat_destinations';
const _kRemoteConfigKey = 'remote_provider_config';

/// Lo que hace falta para volver a levantar un servicio por internet **sin
/// preguntar nada**.
///
/// La clave NO esta aca: es un secreto y vive en el directorio de datos, del
/// lado Rust. Esto es lo demas, que no lo es, y sin lo cual la clave sola no
/// sirve para nada.
class RemoteProviderConfig {
  const RemoteProviderConfig({
    required this.providerId,
    required this.baseUrl,
    required this.model,
    required this.displayName,
  });

  final String providerId;
  final String baseUrl;
  final String model;
  final String displayName;

  Map<String, Object?> toJson() => {
    'provider_id': providerId,
    'base_url': baseUrl,
    'model': model,
    'display_name': displayName,
  };

  static RemoteProviderConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['provider_id'];
    final baseUrl = raw['base_url'];
    final model = raw['model'];
    if (id is! String || id.isEmpty) return null;
    if (baseUrl is! String || baseUrl.isEmpty) return null;
    if (model is! String || model.isEmpty) return null;
    return RemoteProviderConfig(
      providerId: id,
      baseUrl: baseUrl,
      model: model,
      displayName: raw['display_name'] is String
          ? raw['display_name'] as String
          : id,
    );
  }
}

/// Nunca lanza: una configuracion corrupta se lee como "no hay servicio
/// configurado", que es un estado del que se sale reconfigurandolo.
RemoteProviderConfig? decodeRemoteConfig(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return RemoteProviderConfig.fromJson(jsonDecode(raw));
  } on FormatException {
    return null;
  }
}

class ChatDestinationsState {
  const ChatDestinationsState({
    this.destinations = const [],
    this.prefs = const ChatDestinationPrefs(),
    this.activeId,
    this.loading = true,
  });

  final List<ChatDestination> destinations;
  final ChatDestinationPrefs prefs;

  /// El que esta contestando ahora mismo. `null` si no hay ninguno activo.
  final String? activeId;

  final bool loading;

  /// Los que el usuario dejo encendidos, para el selector del chat.
  List<ChatDestination> get enabled =>
      destinations.where((d) => prefs.isEnabled(d.id)).toList();

  ChatDestination? byId(String? id) {
    if (id == null) return null;
    final found = destinations.where((d) => d.id == id);
    return found.isEmpty ? null : found.first;
  }

  ChatDestinationsState copyWith({
    List<ChatDestination>? destinations,
    ChatDestinationPrefs? prefs,
    String? activeId,
    bool clearActive = false,
    bool? loading,
  }) => ChatDestinationsState(
    destinations: destinations ?? this.destinations,
    prefs: prefs ?? this.prefs,
    activeId: clearActive ? null : (activeId ?? this.activeId),
    loading: loading ?? this.loading,
  );
}

/// El registro de destinos del chat: cuales hay, cuales quiere el usuario, y
/// cual contesta.
class ChatDestinationsController extends Notifier<ChatDestinationsState> {
  AppSettingsDao get _dao => AppSettingsDao(ref.read(databaseProvider));

  StreamSubscription<control_bridge.CorrespondentEvent>? _sessionEvents;

  @override
  ChatDestinationsState build() {
    // Suscripcion DIRECTA, nunca `ref.listen`: dos aperturas de sesion seguidas
    // emiten el mismo evento y Riverpod no re-notifica valores `==`.
    _sessionEvents = ref
        .read(controlRepositoryProvider)
        .watchCorrespondent()
        .listen((event) {
          // Solo el alta o baja de una sesion cambia la lista. Refrescar con
          // cada respuesta seria releer el catalogo de modelos por cada mensaje.
          if (event is control_bridge.CorrespondentEvent_SessionsChanged) {
            unawaited(refresh());
          }
        });
    ref.onDispose(() => _sessionEvents?.cancel());

    Future.microtask(refresh);
    return const ChatDestinationsState();
  }

  /// Vuelve a mirar que hay disponible. Se llama al abrir los ajustes y despues
  /// de instalar o borrar algo.
  Future<void> refresh() async {
    final repository = ref.read(aiRepositoryProvider);
    final prefs = decodeDestinationPrefs(await _dao.getValue(_kPrefsKey));
    final remoteConfig = decodeRemoteConfig(
      await _dao.getValue(_kRemoteConfigKey),
    );

    final destinations = <ChatDestination>[];

    // Una entrada por sesion de Claude Code que este escuchando. Con cinco
    // terminales abiertas hay cinco destinos, y elegir uno dirige el mensaje
    // solo a esa. Si no hay ninguna, se ofrece el puente a secas para poder
    // decir que falta arrancar el vigilante.
    try {
      final sesiones = await ref
          .read(controlRepositoryProvider)
          .claudeCodeSessions();
      if (sesiones.isEmpty) {
        destinations.add(ChatDestination.correspondent);
      } else {
        for (final sesion in sesiones) {
          destinations.add(
            ChatDestination.session(
              sessionId: sesion.id,
              label: sesion.label,
              stale: sesion.stale,
            ),
          );
        }
      }
    } catch (_) {
      // En Android el puente no existe; no puede dejar sin lista al resto.
      destinations.add(ChatDestination.correspondent);
    }

    // Los modelos del catalogo, de las tres gamas. `installed` ya viene del
    // puente: dice si el `.gguf` esta en disco de verdad.
    for (final tier in bridge.AiTier.values) {
      try {
        for (final option in await repository.modelOptions(tier)) {
          destinations.add(
            ChatDestination.local(
              modelId: option.id,
              label: option.displayName,
              detail: option.installed
                  ? 'Descargado, corre en tu equipo'
                  : 'Sin descargar',
              available: option.installed,
            ),
          );
        }
      } catch (_) {
        // Que no se pueda resolver una gama (sin GPU, sin runtime) no puede
        // dejar sin lista a las otras dos.
      }
    }

    // El Ollama del usuario, si lo tiene corriendo.
    try {
      final ollama = await repository.detectOllama();
      for (final model in ollama?.models ?? const <String>[]) {
        destinations.add(ChatDestination.ollama(model: model));
      }
    } catch (_) {
      // No tenerlo es el caso normal.
    }

    // El servicio por internet, si quedo configurado. Se comprueba que la clave
    // siga ahi: sin ella la configuracion no sirve, y decir que esta disponible
    // seria mentir.
    if (remoteConfig != null) {
      var hasKey = false;
      try {
        hasKey =
            (await repository.remoteApiKey(remoteConfig.providerId)) != null;
      } catch (_) {
        hasKey = false;
      }
      destinations.add(
        ChatDestination.remote(
          providerId: remoteConfig.providerId,
          label: remoteDestinationLabel(
            displayName: remoteConfig.displayName,
            baseUrl: remoteConfig.baseUrl,
            model: remoteConfig.model,
          ),
          model: remoteConfig.model,
          available: hasKey,
        ),
      );
    }

    state = state.copyWith(
      destinations: destinations,
      prefs: prefs,
      loading: false,
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final prefs = state.prefs.withEnabled(id, enabled);
    state = state.copyWith(prefs: prefs);
    await _dao.setValue(_kPrefsKey, encodeDestinationPrefs(prefs));
  }

  Future<void> setDefault(String id) async {
    final prefs = state.prefs.withDefault(id);
    state = state.copyWith(prefs: prefs);
    await _dao.setValue(_kPrefsKey, encodeDestinationPrefs(prefs));
  }

  /// Guarda la configuracion del servicio por internet para que sobreviva a
  /// cerrar la app. **La clave no pasa por aca**: la guarda Rust en el
  /// directorio de datos.
  Future<void> saveRemoteConfig(RemoteProviderConfig config) async {
    await _dao.setValue(_kRemoteConfigKey, jsonEncode(config.toJson()));
    await refresh();
  }

  Future<RemoteProviderConfig?> remoteConfig() async =>
      decodeRemoteConfig(await _dao.getValue(_kRemoteConfigKey));

  /// Pone a contestar a este destino. Devuelve `null` si salio bien, o el
  /// motivo si no.
  ///
  /// El corresponsal no tiene nada que activar: no hay motor que levantar.
  Future<String?> activate(ChatDestination destination) async {
    final repository = ref.read(aiRepositoryProvider);

    try {
      switch (destination.kind) {
        case ChatDestinationKind.correspondent:
          break;
        case ChatDestinationKind.ollama:
          await repository.useOllama(destination.modelId!);
        case ChatDestinationKind.localModel:
          await repository.startSetup(modelId: destination.modelId);
        case ChatDestinationKind.remote:
          final config = await remoteConfig();
          if (config == null) return 'No hay ningún servicio configurado.';
          final key = await repository.remoteApiKey(config.providerId);
          if (key == null || key.isEmpty) {
            return 'Falta la clave de ${config.displayName}. Configurala de nuevo.';
          }
          await repository.useRemote(
            providerId: config.providerId,
            baseUrl: config.baseUrl,
            model: config.model,
            apiKey: key,
            displayName: config.displayName,
          );
      }
    } catch (e) {
      return '$e';
    }

    state = state.copyWith(activeId: destination.id);
    ref.read(chatBackendProvider.notifier).state = destination.id;
    return null;
  }

  /// Levanta el destino por defecto al arrancar la app.
  ///
  /// **Es lo que hace que la configuracion sobreviva a cerrar el programa.**
  /// Sin esto, la clave y el modelo quedaban guardados pero nadie volvia a
  /// instalar el proveedor: el asistente arrancaba inactivo y el telefono
  /// recibia `ready: false` sin que nada lo explicara. Se vio en vivo contra
  /// el S24 el 9-sep-2026.
  Future<void> restoreDefault() async {
    await refresh();
    final destination = resolveStartupDestination(
      state.destinations,
      state.prefs,
    );
    if (destination == null) return;
    await activate(destination);
  }
}

final chatDestinationsProvider =
    NotifierProvider<ChatDestinationsController, ChatDestinationsState>(
      ChatDestinationsController.new,
    );
