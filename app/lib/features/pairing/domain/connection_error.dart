/// Traduce a algo legible el error crudo de un intento de conexion.
///
/// Los errores llegan del bridge como `AnyhowException(io: Failed host
/// lookup: 'relay.example.com' (OS Error: ...))` o
/// `SocketException: Failed host lookup: ...`: son los mensajes del sistema
/// operativo en INGLES, metidos dentro del `Display` de Rust. Mostrarlos tal
/// cual en pantalla ("Reconectando... (Failed host lookup...)") no le dice
/// nada a nadie.
///
/// La regla es conservadora: **los mensajes que ya vienen en castellano del
/// protocolo se dejan intactos** --"la PC no esta conectada al tunel" es
/// informacion util que no hay que perder-- y solo se reemplaza lo que huele a
/// error tecnico. Lo que no se puede traducir cae a un mensaje generico, nunca
/// al texto crudo.
library;

/// Fallback para un error que no reconocimos: preferible a filtrar jerga.
const String _genericMessage = 'No se pudo conectar con la PC.';

/// Un fragmento que delata un error del sistema o de una libreria (en ingles)
/// y que por lo tanto no se le muestra al usuario si no supimos traducirlo.
///
/// Ojo con las palabras: los mensajes propios del protocolo estan en
/// castellano y no las contienen, asi que no caen aca. `host invalido` se
/// traduce aparte.
const List<String> _technicalMarkers = [
  'error',
  'failed',
  'failure',
  'exception',
  'os error',
  'errno',
  'socket',
  'certificate',
  'handshake',
  'rustls',
  'tls',
];

class _Rule {
  const _Rule(this.patterns, this.message);
  final List<String> patterns;
  final String message;
}

/// De lo mas especifico a lo mas general: la primera coincidencia gana.
const List<_Rule> _rules = [
  _Rule(
    [
      'failed host lookup',
      'failed to lookup',
      'name or service not known',
      'nodename nor servname',
      'no address associated',
      'temporary failure in name resolution',
      'servfail',
    ],
    'No encontramos la PC. Revisa que este encendida y con internet.',
  ),
  _Rule(
    ['connection refused'],
    'La PC rechazo la conexion.',
  ),
  _Rule(
    ['timed out', 'timeout', 'tiempo de espera'],
    'La PC no respondio a tiempo.',
  ),
  _Rule(
    [
      'connection reset',
      'reset by peer',
      'broken pipe',
      'connection aborted',
      'software caused connection abort',
    ],
    'Se corto la conexion con la PC.',
  ),
  _Rule(
    ['network is unreachable', 'network unreachable', 'no route to host', 'unreachable'],
    'No hay red o no se llega a la PC.',
  ),
  _Rule(
    ['host invalido', 'host inválido'],
    'La direccion escrita no es valida.',
  ),
  _Rule(
    ['certificate', 'unknownissuer', 'invalid peer', 'handshake', 'rustls'],
    'El certificado de la PC no coincide. Vuelve a emparejar.',
  ),
];

String describeConnectionError(Object error) {
  final detail = _detail(error);
  if (detail.isEmpty) return _genericMessage;

  final probe = detail.toLowerCase();
  for (final rule in _rules) {
    if (rule.patterns.any(probe.contains)) return rule.message;
  }

  // Sigue pareciendo jerga tecnica y no la pudimos traducir: generico.
  if (_technicalMarkers.any(probe.contains)) return _genericMessage;

  // Ya viene en castellano (un mensaje del protocolo): se respeta.
  return detail;
}

/// Saca el mensaje util de `error.toString()`.
///
/// Quita el envoltorio de `AnyhowException(x)` / `PanicException(x)` y el
/// prefijo de tipo de Rust (`io:`, `tls:`, `protocolo invalido:`), que no
/// aportan nada. Se conservan `SocketException: ...` y compania porque el
/// corte por el primer `: ` ya deja el detalle, que es lo que se traduce.
String _detail(Object error) {
  var text = error.toString().trim();

  final open = text.indexOf('(');
  if (open != -1 &&
      text.endsWith(')') &&
      !text.substring(0, open).contains(' ')) {
    text = text.substring(open + 1, text.length - 1).trim();
  }

  final marker = text.indexOf(': ');
  if (marker != -1) text = text.substring(marker + 2).trim();

  return text;
}
