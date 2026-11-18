import 'dart:convert';

/// De donde sale el modelo que llena un slot de un perfil.
///
/// `stack` es un rol local de vLLM (`models.json`); `llamaCpp`, `ollama` y
/// `remote` los sirve el propio NexoDeck; `claudeCode` no es un modelo: es la
/// sesion que el usuario ya tiene vigilada en la terminal.
enum ProfileSlotSource { stack, llamaCpp, ollama, remote, claudeCode }

/// Un slot de un perfil: el router (liviano) o el pensamiento (pesado).
///
/// Es una sola clase con discriminador en vez de un `sealed`: lo que viaja al
/// `profiles.json` que lee el stack es plano, y una jerarquia obligaria a un
/// serializador con etiqueta que despues hay que mantener en dos lados.
class ProfileSlot {
  const ProfileSlot({
    required this.source,
    this.model,
    this.remoteProviderId,
    this.remoteBaseUrl,
    this.remoteModel,
    this.remoteDisplayName,
  });

  final ProfileSlotSource source;

  /// El rol de `models.json` (stack), el id del catalogo de llama.cpp, o el
  /// nombre del modelo en Ollama. `null` cuando el slot es remoto o Claude Code.
  final String? model;

  /// Solo para [ProfileSlotSource.remote]. La clave **no** viaja aca: la guarda
  /// Rust por `remoteProviderId`.
  final String? remoteProviderId;
  final String? remoteBaseUrl;
  final String? remoteModel;
  final String? remoteDisplayName;

  bool get isStack => source == ProfileSlotSource.stack;
  bool get isRemote => source == ProfileSlotSource.remote;
  bool get isClaudeCode => source == ProfileSlotSource.claudeCode;

  /// El texto corto que se muestra en la tarjeta del slot.
  String get label {
    switch (source) {
      case ProfileSlotSource.stack:
        return model ?? 'Sin modelo';
      case ProfileSlotSource.llamaCpp:
        return model ?? 'Sin modelo';
      case ProfileSlotSource.ollama:
        return model ?? 'Sin modelo';
      case ProfileSlotSource.remote:
        return remoteModel ?? remoteDisplayName ?? 'Servicio por internet';
      case ProfileSlotSource.claudeCode:
        return 'Claude Code';
    }
  }

  ProfileSlot copyWith({
    ProfileSlotSource? source,
    String? model,
    bool clearModel = false,
    String? remoteProviderId,
    String? remoteBaseUrl,
    String? remoteModel,
    String? remoteDisplayName,
    bool clearRemote = false,
  }) => ProfileSlot(
    source: source ?? this.source,
    model: clearModel ? null : (model ?? this.model),
    remoteProviderId: clearRemote
        ? null
        : (remoteProviderId ?? this.remoteProviderId),
    remoteBaseUrl: clearRemote ? null : (remoteBaseUrl ?? this.remoteBaseUrl),
    remoteModel: clearRemote ? null : (remoteModel ?? this.remoteModel),
    remoteDisplayName: clearRemote
        ? null
        : (remoteDisplayName ?? this.remoteDisplayName),
  );

  Map<String, Object?> toJson() => {
    'source': source.name,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (remoteProviderId != null && remoteProviderId!.isNotEmpty)
      'provider_id': remoteProviderId,
    if (remoteBaseUrl != null && remoteBaseUrl!.isNotEmpty)
      'base_url': remoteBaseUrl,
    if (remoteModel != null && remoteModel!.isNotEmpty)
      'upstream_model': remoteModel,
    if (remoteDisplayName != null && remoteDisplayName!.isNotEmpty)
      'display_name': remoteDisplayName,
  };

  /// Nunca lanza. Un slot ilegible cae a `stack/router`, que es un estado del
  /// que se sale volviendo a elegir.
  static ProfileSlot fromJson(Object? raw) {
    if (raw is! Map) {
      return const ProfileSlot(
        source: ProfileSlotSource.stack,
        model: 'router',
      );
    }
    final sourceName = raw['source'];
    final source = ProfileSlotSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => ProfileSlotSource.stack,
    );
    String? str(Object? value) {
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    return ProfileSlot(
      source: source,
      model: str(raw['model']),
      remoteProviderId: str(raw['provider_id']),
      remoteBaseUrl: str(raw['base_url']),
      remoteModel: str(raw['upstream_model']),
      remoteDisplayName: str(raw['display_name']),
    );
  }

  static const stackRouter = ProfileSlot(
    source: ProfileSlotSource.stack,
    model: 'router',
  );
}

/// Si un rol del stack es apto para el slot `router` o `thinking`.
///
/// El `router` es el modelo liviano que clasifica; todo lo demas (`fast`,
/// `complex`, `writer`) es trabajador. Pura y testeada: la usa el selector para
/// decir que modelo es para que slot, en vez de ofrecer la misma lista a ciegas.
bool stackRoleFitsSlot(String role, String slot) =>
    slot == 'router' ? role == 'router' : role != 'router';

/// La huella de VRAM (GiB) de los roles del stack de un perfil.
///
/// Cuenta cada rol **distinto** una sola vez: `serve-profile.sh` sirve un mismo
/// rol una vez aunque ocupe los dos slots (es el caso del perfil C, con `writer`
/// en Router y Pensamiento). Pura y testeada.
double stackRolesVramGb(
  Iterable<String> roles,
  Map<String, double> vramByRole,
) {
  var total = 0.0;
  final seen = <String>{};
  for (final role in roles) {
    if (role.isEmpty || !seen.add(role)) continue;
    total += vramByRole[role] ?? 0;
  }
  return total;
}

/// Si un perfil que ya tiene [otherStackRole] en un slot admite
/// [candidateRole] en el otro sin pasarse de la VRAM del equipo.
///
/// `budgetGb <= 0` es "no se sabe cuanta VRAM hay" (sin GPU detectada): no se
/// bloquea nada, que es mejor que inventar un limite. Un rol que no este en
/// [vramByRole], o `null` (slot de otro motor), cuenta 0.
bool stackSelectionFitsVram({
  required String? otherStackRole,
  required String candidateRole,
  required Map<String, double> vramByRole,
  required double budgetGb,
}) {
  if (budgetGb <= 0) return true;
  final total = stackRolesVramGb([?otherStackRole, candidateRole], vramByRole);
  return total <= budgetGb;
}

/// Los dos slots de un perfil.
class AiProfileConfig {
  const AiProfileConfig({required this.router, required this.thinking});

  final ProfileSlot router;
  final ProfileSlot thinking;

  AiProfileConfig copyWith({ProfileSlot? router, ProfileSlot? thinking}) =>
      AiProfileConfig(
        router: router ?? this.router,
        thinking: thinking ?? this.thinking,
      );

  Map<String, Object?> toJson() => {
    'router': router.toJson(),
    'thinking': thinking.toJson(),
  };

  static AiProfileConfig fromJson(Object? raw, AiProfileConfig fallback) {
    if (raw is! Map) return fallback;
    return AiProfileConfig(
      router: ProfileSlot.fromJson(raw['router']),
      thinking: ProfileSlot.fromJson(raw['thinking']),
    );
  }
}

/// La configuracion de los perfiles, tal como se guarda en `profiles.json`.
///
/// El perfil **C** es el del trabajador de texto (preguntas y conocimiento
/// general): router + `writer`. A y B son los de siempre.
class AiProfilesConfig {
  const AiProfilesConfig({
    required this.profileA,
    required this.profileB,
    required this.profileC,
  });

  final AiProfileConfig profileA;
  final AiProfileConfig profileB;
  final AiProfileConfig profileC;

  /// El mapeo historico: A = Router + Gemma, B = Router + Qwen3-Coder,
  /// C = Router + Writer (Qwen3.5 9B). Es lo que hay que asumir cuando no
  /// existe `profiles.json`, para que una instalacion que todavia no tiene el
  /// manifiesto siga arrancando igual.
  static const defaults = AiProfilesConfig(
    profileA: AiProfileConfig(
      router: ProfileSlot.stackRouter,
      thinking: ProfileSlot(source: ProfileSlotSource.stack, model: 'fast'),
    ),
    profileB: AiProfileConfig(
      router: ProfileSlot.stackRouter,
      thinking: ProfileSlot(source: ProfileSlotSource.stack, model: 'complex'),
    ),
    profileC: AiProfileConfig(
      router: ProfileSlot(source: ProfileSlotSource.stack, model: 'writer'),
      thinking: ProfileSlot(source: ProfileSlotSource.stack, model: 'writer'),
    ),
  );

  AiProfileConfig forProfile(String profile) {
    switch (profile.toUpperCase()) {
      case 'B':
        return profileB;
      case 'C':
        return profileC;
      default:
        return profileA;
    }
  }

  AiProfilesConfig withProfile(String profile, AiProfileConfig config) {
    switch (profile.toUpperCase()) {
      case 'B':
        return AiProfilesConfig(
          profileA: profileA,
          profileB: config,
          profileC: profileC,
        );
      case 'C':
        return AiProfilesConfig(
          profileA: profileA,
          profileB: profileB,
          profileC: config,
        );
      default:
        return AiProfilesConfig(
          profileA: config,
          profileB: profileB,
          profileC: profileC,
        );
    }
  }

  Map<String, Object?> toJson() => {
    'profiles': {
      'A': profileA.toJson(),
      'B': profileB.toJson(),
      'C': profileC.toJson(),
    },
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Nunca lanza: un `profiles.json` corrupto se lee como los valores por
  /// defecto. Es la diferencia entre abrir la pantalla y que reviente.
  static AiProfilesConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      final profiles = decoded['profiles'];
      if (profiles is! Map) return defaults;
      return AiProfilesConfig(
        profileA: AiProfileConfig.fromJson(profiles['A'], defaults.profileA),
        profileB: AiProfileConfig.fromJson(profiles['B'], defaults.profileB),
        profileC: AiProfileConfig.fromJson(profiles['C'], defaults.profileC),
      );
    } on FormatException {
      return defaults;
    }
  }
}
