import 'dart:convert';

/// Por donde recibe el texto el programa del canal.
///
/// Espejo de `MessageDelivery` en `nexodeck-notify`. Los nombres del JSON
/// tienen que coincidir exactamente con lo que espera serde del lado Rust.
enum NotifyDelivery {
  /// Sustituyendo `{{message}}` en los argumentos.
  argv,

  /// Escribiendolo en la entrada estandar. Es la via sin ambiguedad posible,
  /// y la recomendada.
  stdin;

  String get wireName => name;

  static NotifyDelivery fromWire(Object? raw) => NotifyDelivery.values.firstWhere(
    (value) => value.wireName == raw,
    orElse: () => NotifyDelivery.argv,
  );
}

/// Nivel minimo que un canal acepta.
enum NotifyMinLevel {
  milestone,
  always;

  String get wireName => name;

  static NotifyMinLevel fromWire(Object? raw) => NotifyMinLevel.values.firstWhere(
    (value) => value.wireName == raw,
    orElse: () => NotifyMinLevel.milestone,
  );
}

/// Un canal de aviso: un programa que se ejecuta con el texto del aviso.
///
/// NexoDeck no sabe nada de WhatsApp ni de OpenClaw, y eso es deliberado. El
/// pegamento concreto de cada maquina vive aca, en configuracion, no dentro del
/// codigo. Ver la cabecera de `nexodeck-notify`.
class NotifyChannel {
  const NotifyChannel({
    required this.id,
    required this.label,
    required this.program,
    this.args = const [],
    this.delivery = NotifyDelivery.stdin,
    this.minLevel = NotifyMinLevel.milestone,
    this.timeoutSecs,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String program;
  final List<String> args;
  final NotifyDelivery delivery;
  final NotifyMinLevel minLevel;
  final int? timeoutSecs;
  final bool enabled;

  /// Ruta corta 8.3 de Git Bash. **No es una manía**: con la ruta larga hay que
  /// citarla, y las comillas quedarian anidadas con las del `-lc`. Es la misma
  /// decision que ya toma un script de siembra interno.
  static const gitBashShortPath = r'C:\PROGRA~1\Git\bin\bash.exe';

  /// Un canal que invoca un script de bash y le pasa el texto **por stdin**.
  ///
  /// Dos cosas que no son adorno:
  ///
  /// - `-l` (login shell) fija `HOME`. Sin eso, un script que haga `ssh` no
  ///   encuentra su `~/.ssh/config` y el aviso no sale nunca.
  /// - El texto va por stdin y no interpolado en la linea: asi ningun shell lo
  ///   parsea, y un acento, una comilla o un `$` en el mensaje no pueden
  ///   comerse el resto de la orden.
  ///
  /// El script tiene que aceptar el texto por su entrada estandar. El
  /// `avisar.sh` del pipeline de ODM ya lo hace con el argumento `-`.
  factory NotifyChannel.bashScript({
    required String id,
    required String label,
    required String scriptPath,
    String bashPath = gitBashShortPath,
    NotifyMinLevel minLevel = NotifyMinLevel.milestone,
    int? timeoutSecs,
    bool enabled = true,
  }) {
    return NotifyChannel(
      id: id,
      label: label,
      program: bashPath,
      args: ['-lc', 'bash "\$0" -', scriptPath],
      delivery: NotifyDelivery.stdin,
      minLevel: minLevel,
      timeoutSecs: timeoutSecs,
      enabled: enabled,
    );
  }

  NotifyChannel copyWith({
    String? label,
    String? program,
    List<String>? args,
    NotifyDelivery? delivery,
    NotifyMinLevel? minLevel,
    int? timeoutSecs,
    bool? enabled,
  }) {
    return NotifyChannel(
      id: id,
      label: label ?? this.label,
      program: program ?? this.program,
      args: args ?? this.args,
      delivery: delivery ?? this.delivery,
      minLevel: minLevel ?? this.minLevel,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'program': program,
    'args': args,
    'delivery': delivery.wireName,
    'min_level': minLevel.wireName,
    if (timeoutSecs != null) 'timeout_secs': timeoutSecs,
    'enabled': enabled,
  };

  /// Tolera campos ausentes por el mismo motivo que el lado Rust: una
  /// configuracion escrita por otra version no puede dejar la maquina sin
  /// ningun aviso.
  static NotifyChannel? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final program = raw['program'];
    if (id is! String || id.isEmpty) return null;
    if (program is! String || program.trim().isEmpty) return null;

    return NotifyChannel(
      id: id,
      label: raw['label'] is String && (raw['label'] as String).isNotEmpty
          ? raw['label'] as String
          : id,
      program: program,
      args: (raw['args'] as List?)?.whereType<String>().toList() ?? const [],
      delivery: NotifyDelivery.fromWire(raw['delivery']),
      minLevel: NotifyMinLevel.fromWire(raw['min_level']),
      timeoutSecs: raw['timeout_secs'] is int ? raw['timeout_secs'] as int : null,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
    );
  }
}

/// Serializa la lista tal como la espera `channels_from_json` en Rust.
String encodeNotifyChannels(List<NotifyChannel> channels) =>
    jsonEncode(channels.map((c) => c.toJson()).toList());

/// Nunca lanza. Una configuracion corrupta devuelve lista vacia, que la UI
/// muestra como "sin canales" — un estado que el usuario puede arreglar — en
/// vez de romper el arranque de la app.
List<NotifyChannel> decodeNotifyChannels(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map(NotifyChannel.fromJson)
        .whereType<NotifyChannel>()
        .toList();
  } on FormatException {
    return const [];
  }
}
