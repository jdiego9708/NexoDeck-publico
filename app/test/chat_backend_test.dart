import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/ai_assistant/domain/chat_backend.dart';
import 'package:nexodeck/features/ai_assistant/domain/chat_destination.dart';

void main() {
  /// El reparto de `sendAiMessageBroadcast` compara contra una constante y el
  /// registro guarda otra. Si divergieran, elegir Claude Code en el selector
  /// dejaria de enrutar al corresponsal **sin ningun error**: los mensajes
  /// irian al modelo como si nada.
  test('the routing id and the registry id are the same string', () {
    expect(kClaudeCodeBackendId, kClaudeCodeDestinationId);
    expect(ChatDestination.correspondent.id, kClaudeCodeBackendId);
  });

  /// El aviso de que tarda minutos tiene que estar donde el usuario elige, no
  /// descubrirse esperando.
  test('the correspondent warns up front that it takes minutes', () {
    expect(ChatDestination.correspondent.detail, contains('minutos'));
  });

  group('esperar sin saber por que es el fallo mudo de siempre', () {
    /// Los dos casos se ven igual desde el reloj y **no son lo mismo**: en uno
    /// hay algo que hacer y en el otro solo esperar.
    test('nobody listening reads differently from merely slow', () {
      final sinOyente = correspondentWaitingMessage(
        CorrespondentAskStatus.queued,
        listenerEverSeen: false,
      );
      final conOyente = correspondentWaitingMessage(
        CorrespondentAskStatus.queued,
        listenerEverSeen: true,
      );

      expect(sinOyente, isNot(conOyente));
      // Y el que se puede arreglar dice como.
      expect(sinOyente, contains('nexodeck-listen.sh'));
    });

    test('delivered says someone picked it up', () {
      final texto = correspondentWaitingMessage(
        CorrespondentAskStatus.delivered,
        listenerEverSeen: true,
      );
      expect(texto, contains('recibió'));
      expect(texto, contains('minutos'));
    });

    /// Vencer no puede sonar a que la pregunta se perdio: sigue en la sesion de
    /// Claude Code, solo que aca ya no se espera.
    test('a timeout says where the question still is', () {
      final texto = correspondentWaitingMessage(
        CorrespondentAskStatus.timedOut,
        listenerEverSeen: true,
      );
      expect(texto, contains('Nadie contestó'));
      expect(texto, contains('historial'));
    });

    test('every status says something, none falls through empty', () {
      for (final status in CorrespondentAskStatus.values) {
        for (final visto in [true, false]) {
          final texto = correspondentWaitingMessage(
            status,
            listenerEverSeen: visto,
          );
          expect(texto.trim(), isNotEmpty, reason: '$status / oyente=$visto');
        }
      }
    });
  });
}
