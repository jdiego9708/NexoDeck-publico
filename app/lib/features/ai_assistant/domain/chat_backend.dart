import 'chat_destination.dart';

/// Como se llama el destino del corresponsal. Alias del id del registro para
/// que **no existan dos constantes** que puedan divergir: el reparto de
/// `sendAiMessageBroadcast` compara contra esto y el registro guarda aquello.
const kClaudeCodeBackendId = kClaudeCodeDestinationId;

/// En que estado esta una pregunta hecha al corresponsal.
///
/// Los cuatro estados existen porque **no se pueden deducir unos de otros**, y
/// confundirlos es el fallo mudo de siempre: "todavia no contesto" y "no hay
/// nadie escuchando" se ven igual si solo se mira el reloj.
enum CorrespondentAskStatus {
  /// Encolada. Nadie la ha recogido todavia.
  queued,

  /// Un oyente la recogio: hay alguien al otro lado.
  delivered,

  answered,

  /// Vencio sin respuesta.
  timedOut,
}

/// Que decirle al usuario mientras espera.
///
/// Se separa de la UI para poder testearlo: el texto de cada estado **es** la
/// diferencia entre que el usuario entienda que pasa o que se quede mirando un
/// punto suspensivo.
String correspondentWaitingMessage(
  CorrespondentAskStatus status, {
  required bool listenerEverSeen,
}) {
  return switch (status) {
    // Que nadie lo haya recogido nunca es distinto de que tarde: en el primer
    // caso hay algo que hacer (arrancar el vigilante) y en el segundo no.
    CorrespondentAskStatus.queued when !listenerEverSeen =>
      'En cola. Ninguna sesión de Claude Code está escuchando todavía: '
          'arrancá el vigilante con scripts/nexodeck-listen.sh.',
    CorrespondentAskStatus.queued => 'En cola, esperando a que la recojan.',
    CorrespondentAskStatus.delivered =>
      'Claude Code lo recibió y está trabajando. Puede tardar minutos.',
    CorrespondentAskStatus.answered => 'Contestado.',
    CorrespondentAskStatus.timedOut =>
      'Nadie contestó a tiempo. La pregunta sigue en el historial de la sesión '
          'de Claude Code, pero acá ya no se espera respuesta.',
  };
}
