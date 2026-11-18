import 'dart:convert';

/// De que tipo es un destino del chat.
///
/// Los tres primeros son **modelos**: entran por el bucle de rondas de
/// `nexodeck-ai`, emiten tokens y terminan el turno en segundos. El cuarto no
/// lo es, y por eso existe el enum: Claude Code es un corresponsal con su
/// propia sesion y su propio bucle de herramientas, y tarda minutos.
enum ChatDestinationKind {
  /// Un `.gguf` descargado que corre en el sidecar de llama.cpp.
  localModel,

  /// Un modelo del Ollama que el usuario ya tenia corriendo.
  ollama,

  /// Un servicio por internet con clave de API.
  remote,

  /// El puente con Claude Code.
  correspondent,
}

/// Identificador del corresponsal. Es uno solo: no hay dos Claude Code.
const kClaudeCodeDestinationId = 'claude-code';

/// Un destino elegible del chat.
///
/// El id lleva prefijo por tipo (`local:`, `ollama:`, `remote:`) para que dos
/// cosas distintas no puedan colisionar: un modelo de Ollama y uno descargado
/// pueden llamarse igual, y el que quedo por defecto tiene que poder decir cual
/// de los dos era.
class ChatDestination {
  const ChatDestination({
    required this.id,
    required this.label,
    required this.kind,
    this.detail,
    this.available = true,
    this.modelId,
  });

  final String id;
  final String label;
  final ChatDestinationKind kind;

  /// Una linea bajo el nombre. Para un modelo, su tamaño o de donde sale; para
  /// el corresponsal, que tarda minutos.
  final String? detail;

  /// `false` para un modelo del catalogo que **no esta descargado**. Se muestra
  /// igual, apagado, en vez de esconderlo: que exista y no este bajado es
  /// informacion util.
  final bool available;

  /// El id que hay que pasarle al motor para activarlo. `null` en el
  /// corresponsal, que no tiene nada que activar.
  final String? modelId;

  bool get isCorrespondent => kind == ChatDestinationKind.correspondent;

  static ChatDestination local({
    required String modelId,
    required String label,
    String? detail,
    required bool available,
  }) => ChatDestination(
    id: 'local:$modelId',
    label: label,
    kind: ChatDestinationKind.localModel,
    detail: detail,
    available: available,
    modelId: modelId,
  );

  static ChatDestination ollama({required String model}) => ChatDestination(
    id: 'ollama:$model',
    label: model,
    kind: ChatDestinationKind.ollama,
    detail: 'Del Ollama que ya tenés corriendo',
    modelId: model,
  );

  static ChatDestination remote({
    required String providerId,
    required String label,
    required String model,
    required bool available,
  }) => ChatDestination(
    id: 'remote:$providerId',
    label: label,
    kind: ChatDestinationKind.remote,
    detail: available
        ? 'Por internet, con tu clave. Los mensajes salen de tu máquina.'
        : 'Falta configurar la clave',
    available: available,
    modelId: model,
  );

  /// El puente sin ninguna sesion identificada.
  ///
  /// Se muestra cuando no hay ningun vigilante escuchando, para poder decir que
  /// falta arrancarlo. Preguntar aqui encola para **todas** las sesiones, que
  /// es lo correcto cuando da igual quien conteste.
  static const correspondent = ChatDestination(
    id: kClaudeCodeDestinationId,
    label: 'Claude Code',
    kind: ChatDestinationKind.correspondent,
    detail: 'Lee el repositorio y verifica. Tarda minutos.',
  );

  /// Una sesion concreta de Claude Code.
  ///
  /// El id lleva el de la sesion dentro para poder dirigirle los mensajes. Con
  /// cinco terminales abiertas, sin esto las cinco recibirian todo.
  static ChatDestination session({
    required String sessionId,
    required String label,
    required bool stale,
  }) => ChatDestination(
    id: '$kClaudeCodeDestinationId:$sessionId',
    label: 'Claude Code · $label',
    kind: ChatDestinationKind.correspondent,
    detail: stale
        ? 'Esa terminal se cerró'
        : 'Lee el repositorio y verifica. Tarda minutos.',
    available: !stale,
    modelId: sessionId,
  );
}

/// Nombre visible de un destino remoto.
///
/// La **pasarela del stack** —un proxy local en `127.0.0.1:8888`— se llama
/// «Pasarela NexoDeck»; cualquier otro servicio por internet, «modelo
/// (Proveedor)». Se reconoce por la direccion, que es lo unico que la distingue:
/// el preset con el que se dio de alta es el generico `custom` («Otro (proxy
/// propio)»), pensado tambien para proxies que no son la pasarela. Pura.
String remoteDestinationLabel({
  required String displayName,
  required String baseUrl,
  required String model,
}) {
  final uri = Uri.tryParse(baseUrl);
  final host = uri?.host;
  if ((host == '127.0.0.1' || host == 'localhost') && uri?.port == 8888) {
    return 'Pasarela NexoDeck';
  }
  return '$model ($displayName)';
}

/// El id de sesion que hay dentro de un destino del corresponsal.
///
/// `null` cuando es el puente sin sesion: ahi la pregunta va a todas.
String? sessionIdOf(String destinationId) {
  const prefijo = '$kClaudeCodeDestinationId:';
  if (!destinationId.startsWith(prefijo)) return null;
  final id = destinationId.substring(prefijo.length);
  return id.isEmpty ? null : id;
}

/// Si este destino es el puente con Claude Code, con sesion o sin ella.
bool isCorrespondentId(String destinationId) =>
    destinationId == kClaudeCodeDestinationId ||
    destinationId.startsWith('$kClaudeCodeDestinationId:');

/// Lo que el usuario decidio y hay que recordar entre arranques.
///
/// Se guardan los **desactivados**, no los activados, a proposito: un destino
/// nuevo (un modelo recien descargado, un servicio recien configurado) aparece
/// habilitado sin que haya que tocarlo. Con la lista al reves, todo lo nuevo
/// nacería invisible y el usuario no sabría por que.
class ChatDestinationPrefs {
  const ChatDestinationPrefs({this.disabled = const {}, this.defaultId});

  final Set<String> disabled;

  /// El destino que se activa al arrancar. `null` significa "ninguno elegido
  /// todavia".
  final String? defaultId;

  bool isEnabled(String id) => !disabled.contains(id);

  ChatDestinationPrefs withEnabled(String id, bool enabled) {
    final next = {...disabled};
    if (enabled) {
      next.remove(id);
    } else {
      next.add(id);
    }
    // Desactivar el que era el destino por defecto lo deja sin elegir: seguir
    // apuntando a algo apagado haria que el arranque siguiente no activara
    // nada y nada lo explicara.
    final nextDefault = (!enabled && defaultId == id) ? null : defaultId;
    return ChatDestinationPrefs(disabled: next, defaultId: nextDefault);
  }

  /// Marcar por defecto **habilita** el destino. Elegir como predeterminado
  /// algo apagado es una contradiccion que no vale la pena poder expresar.
  ChatDestinationPrefs withDefault(String id) =>
      ChatDestinationPrefs(disabled: {...disabled}..remove(id), defaultId: id);

  Map<String, Object?> toJson() => {
    'disabled': disabled.toList()..sort(),
    if (defaultId != null) 'default': defaultId,
  };
}

String encodeDestinationPrefs(ChatDestinationPrefs prefs) =>
    jsonEncode(prefs.toJson());

/// Nunca lanza. Una configuracion corrupta se lee como "sin preferencias", que
/// es un estado del que el usuario puede salir, en vez de romper el arranque.
ChatDestinationPrefs decodeDestinationPrefs(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const ChatDestinationPrefs();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const ChatDestinationPrefs();
    // Comprobacion de tipo en vez de `as`: un `disabled` que no sea lista
    // lanzaria un `TypeError`, que **no** es `FormatException` y por tanto no
    // lo atraparia el `catch` de abajo. Lo encontro el test de configuracion
    // corrupta; sin esto, un fichero mal escrito impedia arrancar la app.
    final rawDisabled = decoded['disabled'];
    final disabled = rawDisabled is List
        ? rawDisabled.whereType<String>().toSet()
        : <String>{};
    final defaultId = decoded['default'];
    return ChatDestinationPrefs(
      disabled: disabled,
      defaultId: defaultId is String && defaultId.isNotEmpty ? defaultId : null,
    );
  } on FormatException {
    return const ChatDestinationPrefs();
  }
}

/// Cual se activa al arrancar.
///
/// **El destino guardado puede haber dejado de existir**: un modelo borrado a
/// mano, un Ollama que ya no corre, una clave olvidada. Por eso esto no
/// devuelve el id guardado sin mirar, sino el primero que de verdad sirve.
/// Devolver un id muerto dejaria el asistente inactivo sin que nada lo
/// explicara, que es exactamente el fallo que se vio en el S24.
ChatDestination? resolveStartupDestination(
  List<ChatDestination> destinations,
  ChatDestinationPrefs prefs,
) {
  final usable = destinations
      .where((d) => d.available && prefs.isEnabled(d.id))
      .toList();
  if (usable.isEmpty) return null;

  final preferred = usable.where((d) => d.id == prefs.defaultId);
  if (preferred.isNotEmpty) return preferred.first;

  // Sin preferencia utilizable, se elige el mas barato de activar. El
  // corresponsal no descarga ni carga nada; un modelo local puede tardar y
  // ocupar VRAM, asi que nunca se autoselecciona sin que el usuario lo pida.
  final cheapest = usable.where(
    (d) =>
        d.kind == ChatDestinationKind.correspondent ||
        d.kind == ChatDestinationKind.remote,
  );
  return cheapest.isNotEmpty ? cheapest.first : null;
}
