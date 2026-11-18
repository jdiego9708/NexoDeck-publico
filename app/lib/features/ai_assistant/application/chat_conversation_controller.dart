import 'dart:async';
import 'dart:collection';

import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/chat_messages_table.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;
import 'package:nexodeck/src/rust/api/control.dart' as control_bridge;

import '../../../core/di/database_provider.dart';
import '../../control/application/control_settings_controller.dart';
import '../domain/action_draft.dart';
import '../domain/assistant_mode.dart';
import '../domain/chat_backend.dart';
import '../domain/chat_entry.dart';
import 'ai_providers.dart';

/// Lo que hay **en pantalla** de la conversacion con el asistente.
///
/// Se llama transcripcion y no conversacion porque `ChatConversation` ya es la
/// fila guardada en Drift: una es lo que se ve ahora, la otra lo que quedo en
/// disco.
///
/// ## Por que vive aca y no dentro del dialogo
///
/// Antes la lista de mensajes era estado del widget `AiChatView`. Eso tenia dos
/// consecuencias que se vieron en vivo contra el S24 el 9-sep-2026:
///
/// 1. **Lo que se escribe desde el telefono no aparecia en la PC.** La lista
///    solo crecia por dos caminos: lo que se tecleaba en ese dialogo y los
///    eventos del motor. Un mensaje que entra por `AiMessageRequested` no pasa
///    por ninguno de los dos, asi que la pregunta del telefono no se veia en
///    ningun lado y la respuesta aparecia sin contexto.
/// 2. **Cerrar el dialogo borraba la conversacion.** El modelo seguia
///    recordandola (su historial vive en memoria del lado Rust), pero la
///    pantalla no: se volvia a abrir vacia sobre una charla que continuaba.
///
/// Con la conversacion en un provider, la suscripcion vive mientras viva la
/// app: **se sigue anotando aunque el dialogo este cerrado**, venga de donde
/// venga el mensaje.
class ChatTranscript {
  const ChatTranscript({this.entries = const [], this.busy = false});

  final List<ChatEntry> entries;

  /// Hay un turno en curso de un **modelo**. El corresponsal no bloquea: tarda
  /// minutos y dejar la entrada inerte impediria encolar otra pregunta.
  final bool busy;
}

class ChatConversationController extends Notifier<ChatTranscript> {
  final _entries = <ChatEntry>[];
  final _awaitingByAskId = <String, AssistantEntry>{};

  /// Lo que ya esta en la base, por identidad. Sin esto cada volcado
  /// reescribiria la conversacion entera.
  final _persisted = Identity<ChatEntry>();

  /// La conversacion abierta. `null` hasta el primer mensaje: crear una fila
  /// vacia por abrir el dialogo llenaria la lista de charlas sin contenido.
  String? _conversationId;
  int _nextPosition = 0;

  ChatConversationsDao get _dao =>
      ChatConversationsDao(ref.read(databaseProvider));

  StreamSubscription<bridge.AiChatEvent>? _aiEvents;
  StreamSubscription<control_bridge.CorrespondentEvent>? _correspondentEvents;

  AssistantEntry? _streaming;
  bool _busy = false;
  bool _suppressNextAssistantText = false;

  /// Lo pone el dialogo mientras esta abierto. Con el cerrado vale el modo
  /// normal, que es el que no suprime nada.
  AssistantMode mode = AssistantMode.createActions;

  /// Enganche del dialogo para autoejecutar un borrador. **Solo mientras esta
  /// abierto**: con el cerrado no hay donde mostrar la ejecucion ni quien
  /// confirme, asi que el borrador se anota y se queda esperando.
  void Function(DraftEntry entry)? onDraftReady;

  @override
  ChatTranscript build() {
    // Suscripcion DIRECTA a los dos streams, nunca `ref.listen`: Riverpod no
    // vuelve a notificar valores `==` y dos eventos identicos seguidos son
    // perfectamente posibles. Ver "Eventos del bridge" en `CLAUDE.md`.
    _aiEvents = aiChatEventStream(ref).listen(_onAiEvent);
    _correspondentEvents = ref
        .read(controlRepositoryProvider)
        .watchCorrespondent()
        .listen(_onCorrespondentEvent);

    ref.onDispose(() {
      _aiEvents?.cancel();
      _correspondentEvents?.cancel();
    });

    // Retoma la ultima conversacion activa. Es lo que hace que cerrar la app
    // no borre la charla: el historial del modelo se pierde igual (vive en
    // memoria del lado Rust), pero lo dicho sigue en pantalla.
    Future.microtask(resumeLast);
    return const ChatTranscript();
  }

  /// Abre la conversacion activa mas reciente, si hay alguna.
  Future<void> resumeLast() async {
    final activas = await _dao.watchActive().first;
    if (activas.isEmpty) return;
    await open(activas.first.id);
  }

  /// Carga una conversacion guardada.
  ///
  /// **El historial vuelve como transcripcion, no como sesion viva.** Un
  /// borrador de hace un mes se relee como la nota de lo que se propuso, no
  /// como una tarjeta que se pueda ejecutar: el estado del equipo cambio desde
  /// entonces y ofrecer correrlo seria ofrecer algo que ya no se verifico.
  Future<void> open(String conversationId) async {
    final filas = await _dao.messagesOf(conversationId);

    _entries
      ..clear()
      ..addAll(filas.map(_toEntry));
    _persisted
      ..clear()
      ..addAll(_entries);
    _awaitingByAskId.clear();
    _streaming = null;
    _busy = false;
    _conversationId = conversationId;
    _nextPosition = filas.length;
    _publish();
  }

  ChatEntry _toEntry(ChatMessage row) => switch (row.kind) {
    ChatMessageKind.user => UserEntry(
      row.content,
      fromPhone: row.origin == ChatMessageOrigin.phone,
    ),
    ChatMessageKind.assistant => AssistantEntry(
      text: row.content,
      isStreaming: false,
    ),
    ChatMessageKind.tool => ToolEntry(name: row.content, summary: row.content)
      ..done = true
      ..result = row.payload,
    // Ver el comentario de `open`: al releer es una nota, no una tarjeta.
    ChatMessageKind.draft => AssistantEntry(
      text: 'Se propuso un botón: ${row.content}',
      isStreaming: false,
    ),
    ChatMessageKind.error => ErrorEntry(row.content),
  };

  /// Vuelca a la base lo que ya esta terminado.
  ///
  /// Se llama en los puntos en que algo queda firme, no en cada token: a 39
  /// tokens por segundo, escribir por token seria una fila por pulsacion.
  /// **Lo que todavia se esta escribiendo se salta**, y entra en el volcado
  /// siguiente.
  ///
  /// **Se serializa a la fuerza.** Un turno emite `AssistantMessage` y
  /// enseguida `TurnDone`, y los dos volcaban: como marcar una fila como
  /// guardada ocurre DESPUES de su `await`, los dos veian el mismo mensaje sin
  /// guardar y lo escribian dos veces. Se vio en vivo el 9-sep-2026, con la
  /// respuesta del asistente duplicada en la base.
  ///
  /// Marcarla antes del `await` arreglaria el duplicado pero podria **perder**
  /// la fila si la escritura falla, y en este proyecto repetir molesta y
  /// perder no se arregla. Por eso se encola en vez de adelantar la marca.
  Future<void> _flush() async {
    if (_flushing) {
      // Alguien esta escribiendo: se pide otra vuelta al terminar en vez de
      // arrancar una en paralelo.
      _flushAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        await _flushOnce();
      } while (_flushAgain);
    } finally {
      _flushing = false;
    }
  }

  bool _flushing = false;
  bool _flushAgain = false;

  Future<void> _flushOnce() async {
    final pendientes = _entries
        .where((e) => !_persisted.contains(e))
        .where((e) => e is! AssistantEntry || !e.isStreaming)
        .toList();
    if (pendientes.isEmpty) return;

    final id = _conversationId ??= await _createFor(pendientes);

    for (final entry in pendientes) {
      final (kind, content, payload) = _describe(entry);
      if (content.trim().isEmpty) {
        // Una burbuja vacia no es una fila: se marca como guardada para no
        // reintentarla en cada volcado.
        _persisted.add(entry);
        continue;
      }
      await _dao.appendMessage(
        conversationId: id,
        kind: kind,
        content: content,
        origin: entry is UserEntry && entry.fromPhone
            ? ChatMessageOrigin.phone
            : ChatMessageOrigin.local,
        position: _nextPosition++,
        payload: payload,
      );
      _persisted.add(entry);
    }
  }

  /// El titulo sale del primer mensaje del usuario. Es lo unico que hace
  /// reconocible una charla en una lista de treinta.
  Future<String> _createFor(List<ChatEntry> pendientes) async {
    final primero = pendientes.whereType<UserEntry>().firstOrNull;
    final crudo = (primero?.text ?? 'Conversación').trim().replaceAll('\n', ' ');
    final titulo = crudo.length > 60 ? '${crudo.substring(0, 57)}...' : crudo;
    final fila = await _dao.create(titulo.isEmpty ? 'Conversación' : titulo);
    return fila.id;
  }

  (ChatMessageKind, String, String?) _describe(ChatEntry entry) => switch (entry) {
    UserEntry(:final text) => (ChatMessageKind.user, text, null),
    AssistantEntry(:final text) => (ChatMessageKind.assistant, text, null),
    ToolEntry(:final summary, :final result) => (
      ChatMessageKind.tool,
      summary,
      result,
    ),
    DraftEntry(:final draft) => (ChatMessageKind.draft, draft.name, null),
    ErrorEntry(:final detail) => (ChatMessageKind.error, detail, null),
  };

  /// Publica el estado. Se emite una lista **nueva** cada vez: el widget
  /// compara por identidad, y mutar la de dentro no lo despertaria.
  void _publish() {
    state = ChatTranscript(entries: List.of(_entries), busy: _busy);
  }

  /// Lo escribio el usuario, en la PC o en el telefono. **Las dos puntas entran
  /// por aca**, que es lo que hace que la conversacion sea una sola.
  void addUserMessage(String text, {bool fromPhone = false}) {
    _entries.add(UserEntry(text, fromPhone: fromPhone));
    _publish();
    unawaited(_flush());
  }

  void setBusy(bool busy) {
    _busy = busy;
    _publish();
  }

  void addError(String detail) {
    _entries.add(ErrorEntry(detail));
    _busy = false;
    _publish();
    unawaited(_flush());
  }

  /// Anota la espera de una pregunta al corresponsal, por su id.
  void addCorrespondentWaiting(String askId, String text) {
    final waiting = AssistantEntry(text: text, isStreaming: true);
    _entries.add(waiting);
    _awaitingByAskId[askId] = waiting;
    _publish();
  }

  /// Re-emite el estado tras mutar una entrada desde fuera (un borrador que
  /// cambio de resultado). Las entradas son mutables a proposito, asi que hace
  /// falta avisar de que cambiaron.
  void touch() => _publish();

  /// Empieza una conversacion nueva.
  ///
  /// **No borra la anterior**: queda guardada y se puede volver a abrir desde
  /// la lista. "Empezar de nuevo" significa eso, no "tirar lo de antes".
  void clear() {
    _entries.clear();
    _awaitingByAskId.clear();
    _persisted.clear();
    _streaming = null;
    _busy = false;
    _suppressNextAssistantText = false;
    _conversationId = null;
    _nextPosition = 0;
    _publish();
  }

  // ------------------------------------------------------------------
  // Eventos del motor
  // ------------------------------------------------------------------

  void _onAiEvent(bridge.AiChatEvent event) {
    // Los tokens llegan cada 15-30 ms. Se separan del resto porque son el
    // camino caliente: solo hacen crecer la burbuja.
    if (event case bridge.AiChatEvent_AssistantToken(:final delta)) {
      if (_suppressNextAssistantText) return;
      final target = _streaming ??= _appendStreaming();
      target.text += delta;
      _publish();
      return;
    }

    DraftEntry? autoRunCandidate;

    switch (event) {
      case bridge.AiChatEvent_AssistantToken():
        break; // manejado arriba

      case bridge.AiChatEvent_Thinking():
        // No se muestra el monologo interno: que este pensando ya se ve por el
        // indicador de ocupado.
        break;

      case bridge.AiChatEvent_AssistantMessage(:final text):
        if (_suppressNextAssistantText) {
          _suppressNextAssistantText = false;
          _streaming = null;
          break;
        }
        final target = _streaming;
        if (target != null) {
          // El mensaje completo gana sobre lo acumulado: puede venir recortado
          // o normalizado del lado Rust.
          target.text = text;
          target.isStreaming = false;
        } else if (text.trim().isNotEmpty) {
          _entries.add(AssistantEntry(text: text, isStreaming: false));
        }
        _streaming = null;

      case bridge.AiChatEvent_ToolStarted(:final name, :final summary):
        _closeStreaming();
        _entries.add(ToolEntry(name: name, summary: summary));

      case bridge.AiChatEvent_ToolFinished(
        :final name,
        :final ok,
        :final summary,
      ):
        final pending = _entries.whereType<ToolEntry>().lastWhere(
          (entry) => entry.name == name && !entry.done,
          orElse: () {
            final entry = ToolEntry(name: name, summary: name);
            _entries.add(entry);
            return entry;
          },
        );
        pending
          ..done = true
          ..ok = ok
          ..result = summary;

      case bridge.AiChatEvent_DraftReady(:final draft):
        _closeStreaming();
        final entry = DraftEntry(ActionDraft.fromBridge(draft));
        _entries.add(entry);
        autoRunCandidate = entry;
        // El texto que sigue es ruido en vivo: la explicacion que importa es
        // el resumen posterior, que lee la salida real en vez de adivinarla.
        if (mode == AssistantMode.liveExecution) {
          _suppressNextAssistantText = true;
        }

      case bridge.AiChatEvent_TurnDone():
        _closeStreaming();
        _busy = false;

      case bridge.AiChatEvent_Failed(:final detail):
        _closeStreaming();
        _entries.add(ErrorEntry(detail));
        _busy = false;
    }

    _publish();
    unawaited(_flush());

    // Fuera del bloque de arriba: correr un borrador es asincrono y vuelve a
    // tocar la conversacion.
    final candidate = autoRunCandidate;
    if (candidate != null) onDraftReady?.call(candidate);
  }

  // ------------------------------------------------------------------
  // Eventos del corresponsal
  // ------------------------------------------------------------------

  void _onCorrespondentEvent(control_bridge.CorrespondentEvent event) {
    switch (event) {
      case control_bridge.CorrespondentEvent_Delivered(:final id):
        // Solo cambia el texto de la espera. Que ya no este esperando (una
        // respuesta que le gano la carrera al acuse) significa que no hay nada
        // que decir: retroceder a "lo recibio" mentiria.
        _settle(
          id,
          correspondentWaitingMessage(
            CorrespondentAskStatus.delivered,
            listenerEverSeen: true,
          ),
          streaming: true,
        );
      case control_bridge.CorrespondentEvent_Replied(:final id, :final text):
        _settle(id, text, streaming: false);
      case control_bridge.CorrespondentEvent_TimedOut(:final id, :final reason):
        // El motivo viene del servidor y se muestra tal cual: "nadie contesto a
        // tiempo" y "esa terminal se cerro" se arreglan distinto, y un texto
        // generico obligaria al usuario a adivinar cual de los dos fue.
        _settle(id, 'Sin respuesta: $reason.', streaming: false);
      case control_bridge.CorrespondentEvent_Posted(:final text, :final from):
        // Sin pregunta previa: entra como mensaje suelto al final. La firma es
        // cooperativa y puede faltar, asi que solo se antepone si vino.
        _entries.add(
          AssistantEntry(
            text: from == null ? text : '[$from] $text',
            isStreaming: false,
          ),
        );
        _publish();
        unawaited(_flush());
      case control_bridge.CorrespondentEvent_SessionsChanged():
        // No toca la conversacion: quien se redibuja es el selector de
        // destinos, que lo escucha por su cuenta.
        break;
    }
  }

  /// Coloca lo que llegue **en la burbuja de SU pregunta**, por id.
  ///
  /// Correlacionar por "la ultima que espera" funciona con una sola pregunta y
  /// miente con dos, y con el corresponsal se pueden encolar varias porque no
  /// bloquea la entrada.
  void _settle(String askId, String text, {required bool streaming}) {
    final waiting = _awaitingByAskId[askId];

    if (waiting == null) {
      // Si esa burbuja ya no existe (el chat se reinicio), una respuesta entra
      // al final en vez de perderse: perder lo que contesto Claude Code por no
      // encontrar donde ponerlo seria el peor de los dos males.
      if (!streaming) {
        _entries.add(AssistantEntry(text: text, isStreaming: false));
      }
    } else {
      waiting.text = text;
      waiting.isStreaming = streaming;
      if (!streaming) _awaitingByAskId.remove(askId);
    }

    // El campo solo se desbloquea si no queda nada esperando: con varias
    // preguntas encoladas, la primera respuesta no puede dar por terminado el
    // turno de las otras.
    if (!streaming && _awaitingByAskId.isEmpty) _busy = false;
    _publish();
    if (!streaming) unawaited(_flush());
  }

  // ------------------------------------------------------------------

  AssistantEntry _appendStreaming() {
    final entry = AssistantEntry();
    _entries.add(entry);
    return entry;
  }

  void _closeStreaming() {
    final target = _streaming;
    if (target == null) return;
    target.isStreaming = false;
    // Una burbuja que quedo vacia no aporta nada y ocupa una fila.
    if (target.isEmpty) _entries.remove(target);
    _streaming = null;
  }
}

/// Conjunto **por identidad**, no por igualdad.
///
/// Dos mensajes con el mismo texto son entradas distintas de la conversacion, y
/// un `Set` normal trataria al segundo como ya guardado.
class Identity<T extends Object> {
  final _items = HashSet<T>(
    equals: identical,
    hashCode: identityHashCode,
  );

  bool contains(T item) => _items.contains(item);
  void add(T item) => _items.add(item);
  void addAll(Iterable<T> items) => _items.addAll(items);
  void clear() => _items.clear();
}

final chatConversationProvider =
    NotifierProvider<ChatConversationController, ChatTranscript>(
      ChatConversationController.new,
    );
