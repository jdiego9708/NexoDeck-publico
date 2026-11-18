import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/control.dart' as bridge;

import '../../control/application/control_settings_controller.dart';
import '../domain/chat_backend.dart';

/// Una pregunta hecha a Claude Code y en que estado esta.
class CorrespondentAsk {
  const CorrespondentAsk({
    required this.id,
    required this.question,
    required this.status,
    this.answer,
  });

  final String id;
  final String question;
  final CorrespondentAskStatus status;
  final String? answer;

  CorrespondentAsk copyWith({CorrespondentAskStatus? status, String? answer}) {
    return CorrespondentAsk(
      id: id,
      question: question,
      status: status ?? this.status,
      answer: answer ?? this.answer,
    );
  }
}

class ClaudeCodeChatState {
  const ClaudeCodeChatState({
    this.asks = const {},
    this.listenerEverSeen = false,
  });

  /// Por id, para poder colocar cada respuesta en su turno.
  final Map<String, CorrespondentAsk> asks;

  /// Si algun oyente recogio algo alguna vez en esta sesion. Con preguntas
  /// encoladas y esto en `false`, **no hay nadie escuchando**.
  final bool listenerEverSeen;

  bool get hasPending => asks.values.any(
    (a) =>
        a.status == CorrespondentAskStatus.queued ||
        a.status == CorrespondentAskStatus.delivered,
  );

  ClaudeCodeChatState copyWith({
    Map<String, CorrespondentAsk>? asks,
    bool? listenerEverSeen,
  }) {
    return ClaudeCodeChatState(
      asks: asks ?? this.asks,
      listenerEverSeen: listenerEverSeen ?? this.listenerEverSeen,
    );
  }
}

/// Lo que llega de Claude Code, listo para que el chat lo pinte.
///
/// **Se suscribe DIRECTO al `Stream` del puente, nunca con `ref.listen`.**
/// Riverpod no vuelve a notificar cuando el valor nuevo es `==` al anterior, y
/// dos `Posted` con el mismo texto seguidos son perfectamente posibles. Ver
/// "Eventos del bridge" en `CLAUDE.md`.
class ClaudeCodeChatController extends Notifier<ClaudeCodeChatState> {
  StreamSubscription<bridge.CorrespondentEvent>? _subscription;

  /// Mensajes que Claude Code manda sin que nadie pregunte. El chat los inserta
  /// como entradas sueltas.
  final _posted = StreamController<String>.broadcast();

  Stream<String> get posted => _posted.stream;

  @override
  ClaudeCodeChatState build() {
    _subscription = ref
        .read(controlRepositoryProvider)
        .watchCorrespondent()
        .listen(_onEvent);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
      _posted.close();
    });
    return const ClaudeCodeChatState();
  }

  /// Encola una pregunta y devuelve su id, para que el chat lo asocie a su
  /// turno.
  Future<String> ask(String question, {String? session}) async {
    final id = await ref
        .read(controlRepositoryProvider)
        .askClaudeCode(question, session: session);
    state = state.copyWith(
      asks: {
        ...state.asks,
        id: CorrespondentAsk(
          id: id,
          question: question,
          status: CorrespondentAskStatus.queued,
        ),
      },
    );
    return id;
  }

  void _onEvent(bridge.CorrespondentEvent event) {
    switch (event) {
      case bridge.CorrespondentEvent_Delivered(:final id):
        // Que alguien recoja CUALQUIER mensaje prueba que hay un oyente vivo,
        // aunque ese id ya no este en el mapa (una sesion anterior, por
        // ejemplo). Por eso la bandera se levanta siempre.
        state = state.copyWith(listenerEverSeen: true);
        _update(id, (ask) {
          // Una respuesta puede ganarle la carrera al acuse. Retroceder de
          // "contestado" a "recibido" mentiria.
          if (ask.status != CorrespondentAskStatus.queued) return ask;
          return ask.copyWith(status: CorrespondentAskStatus.delivered);
        });
      case bridge.CorrespondentEvent_Replied(:final id, :final text):
        _update(
          id,
          (ask) => ask.copyWith(
            status: CorrespondentAskStatus.answered,
            answer: text,
          ),
        );
      case bridge.CorrespondentEvent_TimedOut(:final id):
        _update(id, (ask) {
          // Vencer despues de contestar no puede borrar la respuesta.
          if (ask.status == CorrespondentAskStatus.answered) return ask;
          return ask.copyWith(status: CorrespondentAskStatus.timedOut);
        });
      case bridge.CorrespondentEvent_Posted(:final text):
        if (!_posted.isClosed) _posted.add(text);
      case bridge.CorrespondentEvent_SessionsChanged():
        // Lo atiende el registro de destinos, que es quien lista las sesiones.
        break;
    }
  }

  void _update(String id, CorrespondentAsk Function(CorrespondentAsk) change) {
    final existing = state.asks[id];
    if (existing == null) return;
    state = state.copyWith(asks: {...state.asks, id: change(existing)});
  }
}

final claudeCodeChatProvider =
    NotifierProvider<ClaudeCodeChatController, ClaudeCodeChatState>(
      ClaudeCodeChatController.new,
    );
