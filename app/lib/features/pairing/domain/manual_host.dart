/// Puerto en el que escucha el host NexoDeck por defecto.
///
/// Espeja `DEFAULT_PORT` de `core/crates/nexodeck-transport/src/server.rs`.
/// Si alguna vez cambia alla, tiene que cambiar aca: el usuario escribe la
/// direccion sin puerto casi siempre, y este es el que se asume.
const int kDefaultTransportPort = 58643;

/// Direccion fija de una PC, escrita a mano por el usuario.
///
/// Existe para alcanzar el host cuando mDNS no puede -- fuera de la LAN,
/// tipicamente a traves de una VPN mesh (Tailscale), donde la IP es estable
/// y el descubrimiento por multicast no cruza.
class ManualHost {
  const ManualHost({required this.host, required this.port});

  final String host;
  final int port;

  /// Como se le muestra al usuario y como se guarda en el campo de texto al
  /// volver a editarla. El puerto por defecto se omite: quien nunca lo toco
  /// no tiene por que verlo.
  String get display =>
      port == kDefaultTransportPort ? host : _join(host, port);

  static String _join(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is ManualHost && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => _join(host, port);
}

/// Resultado de interpretar lo que el usuario escribio.
///
/// Sellado y no `ManualHost?` a proposito: el motivo del rechazo es texto
/// que se le muestra debajo del campo, asi que tiene que viajar con el
/// resultado en vez de reconstruirse aparte.
sealed class ManualHostParse {
  const ManualHostParse();
}

final class ManualHostParsed extends ManualHostParse {
  const ManualHostParsed(this.value);
  final ManualHost value;
}

final class ManualHostInvalid extends ManualHostParse {
  const ManualHostInvalid(this.message);

  /// Mensaje de cara al usuario, en espanol.
  final String message;
}

/// Interpreta `100.64.0.5`, `mi-pc.tail1234.ts.net:58643`, `[fd7a::1]:9000`.
///
/// Funcion pura -- no toca red ni base. Es la unica definicion de que
/// cuenta como direccion valida: la usan el dialogo (para el error inline)
/// y quien guarda en Drift.
ManualHostParse parseManualHost(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return const ManualHostInvalid('Escribi la direccion de la PC.');
  }

  // Tolerar un pegado con esquema: quien copia la direccion de algun lado
  // suele traerse el `http://` adelante, y rechazarlo por eso seria
  // pedante -- lo que importa es el host.
  for (final scheme in const ['http://', 'https://', 'wss://', 'ws://']) {
    if (text.toLowerCase().startsWith(scheme)) {
      text = text.substring(scheme.length);
      break;
    }
  }
  // Y una barra final, por el mismo motivo.
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }

  String host;
  String? portText;

  if (text.startsWith('[')) {
    // IPv6 entre corchetes: `[fd7a::1]` o `[fd7a::1]:58643`. Tailscale
    // reparte direcciones IPv6 ademas de las `100.x`, asi que este caso no
    // es teorico.
    final close = text.indexOf(']');
    if (close == -1) {
      return const ManualHostInvalid('Falta cerrar el corchete de la IPv6.');
    }
    host = text.substring(1, close);
    final rest = text.substring(close + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) {
        return const ManualHostInvalid('Despues de `]` solo puede ir `:puerto`.');
      }
      portText = rest.substring(1);
    }
  } else if (':'.allMatches(text).length > 1) {
    // Mas de un `:` y sin corchetes: es una IPv6 pelada, sin puerto. No se
    // puede partir por el ultimo `:` porque ese caracter es parte de la
    // direccion.
    host = text;
  } else {
    final colon = text.indexOf(':');
    if (colon == -1) {
      host = text;
    } else {
      host = text.substring(0, colon);
      portText = text.substring(colon + 1);
    }
  }

  if (host.isEmpty) {
    return const ManualHostInvalid('Escribi la direccion de la PC.');
  }
  if (host.contains(' ') || host.contains('/')) {
    return const ManualHostInvalid(
      'La direccion no puede tener espacios ni barras.',
    );
  }

  var port = kDefaultTransportPort;
  if (portText != null) {
    if (portText.isEmpty) {
      return const ManualHostInvalid('Falta el numero de puerto.');
    }
    final parsed = int.tryParse(portText);
    if (parsed == null) {
      return ManualHostInvalid('`$portText` no es un numero de puerto.');
    }
    if (parsed < 1 || parsed > 65535) {
      return const ManualHostInvalid('El puerto va entre 1 y 65535.');
    }
    port = parsed;
  }

  return ManualHostParsed(ManualHost(host: host, port: port));
}
