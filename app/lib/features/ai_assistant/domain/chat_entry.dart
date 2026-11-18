import 'action_draft.dart';

/// Una fila de la conversacion.
///
/// Sellada para que agregar un tipo nuevo rompa el `switch` del renderizador en
/// vez de caer en un `default` silencioso.
sealed class ChatEntry {
  const ChatEntry();
}

class UserEntry extends ChatEntry {
  const UserEntry(this.text, {this.fromPhone = false});
  final String text;

  /// Se escribio en el telefono, no en la PC.
  ///
  /// La conversacion es **una sola** y esto no cambia nada de como se procesa
  /// el mensaje: solo se marca, para que al releer una charla se entienda
  /// desde donde se dijo cada cosa.
  final bool fromPhone;
}

/// Mensaje del asistente. `text` crece token a token mientras
/// [isStreaming] es `true`.
class AssistantEntry extends ChatEntry {
  AssistantEntry({this.text = '', this.isStreaming = true});

  String text;
  bool isStreaming;

  bool get isEmpty => text.trim().isEmpty;
}

/// Una llamada a herramienta, con su resultado cuando llega.
///
/// Se muestra colapsada y en tono secundario: es contexto de "que esta
/// haciendo", no parte de la respuesta. Ocultarla del todo seria peor —
/// mientras el asistente revisa el disco durante varios segundos, sin esto la
/// pantalla parece congelada.
class ToolEntry extends ChatEntry {
  ToolEntry({required this.name, required this.summary});

  final String name;

  /// Que esta haciendo, en presente: "Buscando el proyecto".
  final String summary;

  /// Como salio, cuando termino: "E:/Proyectos/ExampleApp".
  String? result;

  bool done = false;
  bool ok = true;
}

/// Que paso con un [DraftEntry] despues de mostrarse. `null` significa
/// "todavia nada" — las acciones de la tarjeta siguen habilitadas.
enum DraftOutcome {
  /// Se abrio en el editor (modo crear botones) o se creo la cadena.
  saved,

  /// Se disparo "Ejecutar ahora" (modo en vivo). El detalle de los pasos
  /// que corren vive en [DraftEntry.liveSteps].
  running,

  discarded,
}

/// El borrador propuesto. Es la unica entrada accionable de la conversacion.
///
/// Colapsado por defecto (`expanded = false`): igual que una llamada a
/// herramienta, es "una fase" de la conversacion — el usuario tiene que
/// tocarla para ver la tarjeta completa y decidir. Ver `draft_trace_tile.dart`.
class DraftEntry extends ChatEntry {
  DraftEntry(this.draft, {this.outcome});

  final ActionDraft draft;

  /// `null` mientras nadie toco ninguno de los botones de la tarjeta. Evita
  /// que el usuario dispare el mismo borrador dos veces tocando un mensaje
  /// viejo.
  DraftOutcome? outcome;

  /// **Abierto por defecto**: la tarjeta con Aprobar/Rechazar tiene que verse
  /// sin un clic. Colapsarla es una eleccion del usuario, no un paso previo.
  bool expanded = true;

  /// `true` mientras `runDraftLive` sigue corriendo. Separado de [outcome]
  /// (que solo dice QUE decision se tomo) porque el encabezado colapsado
  /// necesita distinguir "todavia ejecutando" de "ya termino" sin tener que
  /// mirar el estado de cada paso en `runCenterProvider`.
  bool isExecuting = false;

  /// Pasos que corrieron en vivo para ESTE borrador, en orden. Viven aca (no
  /// como entradas sueltas de `_entries`) para que un solo toggle controle a
  /// la vez la tarjeta y su ejecucion — "Ejecutando..." expandido muestra
  /// exactamente esto.
  final List<LiveRunEntry> liveSteps = [];
}

/// Como aparece un paso ejecutado en vivo, dentro de [DraftEntry.liveSteps].
///
/// `.captured` es el unico con salida en vivo — el estado real (lineas,
/// codigo de salida) vive en `runCenterProvider`, esto solo ata el `runId`
/// al nombre del paso para que el widget lo pueda mirar. `.clipboard` no
/// pasa por el runner (no ejecuta nada, solo copia), asi que lleva un
/// mensaje fijo. No hay un tercer caso para una ventana de terminal aparte:
/// `ai_live_runner.dart` corre TODO paso de terminal capturado, nunca en
/// una ventana — ver el comentario ahi sobre por que.
class LiveRunEntry {
  // `runId` (el campo) es nullable porque `.clipboard` no lo usa, pero este
  // parametro tiene que seguir siendo obligatorio y no nulo -- por eso no
  // se puede usar el atajo `this.runId` (initializing formal).
  LiveRunEntry.captured({required this.stepName, required String runId})
    // ignore: prefer_initializing_formals
    : runId = runId,
      staticMessage = null;

  LiveRunEntry.clipboard({required this.stepName})
    : runId = null,
      staticMessage = 'Copiado al portapapeles';

  final String stepName;
  final String? runId;
  final String? staticMessage;
}

class ErrorEntry extends ChatEntry {
  const ErrorEntry(this.detail);
  final String detail;
}
