import 'package:nexodeck/src/rust/api/actions.dart' as bridge;

/// Estado en el que la UI dibuja una ejecucion.
enum RunStatus {
  /// Se pidio la ejecucion pero el proceso todavia no arranco. Es una ventana
  /// de milisegundos y hoy no se usa: la fila la crea el evento `Started`,
  /// que ya significa "arranco".
  starting,

  /// En curso. **No** se espera a la primera linea de salida para llegar
  /// aca: `flutter analyze` tarda 104 s en imprimir algo, y hasta entonces
  /// decir "Iniciando" es enganoso.
  running,

  /// Seguia viva y muda pasado el umbral: era una app, no un comando.
  launched,
  succeeded,
  failed,
  cancelled,
}

/// De donde salio el disparo. La PC ejecuta tanto lo que se toca en su propio
/// deck como lo que pide el telefono, y la notificacion tiene que poder
/// decirlo -- si no, aparece un comando corriendo "solo".
enum RunOrigin { local, remote }

/// Una linea de salida, con su origen para poder pintarla distinto.
class RunLine {
  const RunLine(this.text, {required this.isError});

  final String text;
  final bool isError;
}

/// Una ejecucion de comando vista desde la UI.
///
/// Es inmutable y se reemplaza entera en cada evento: el controller vive de
/// un stream y copiar una lista de a lo sumo unos cientos de lineas por lote
/// (no por linea, ver el agrupado del lado Rust) es irrelevante al lado de la
/// simplicidad de no tener estado mutable compartido.
class CommandRun {
  const CommandRun({
    required this.id,
    required this.label,
    required this.command,
    required this.status,
    required this.startedAt,
    required this.origin,
    required this.cancellable,
    this.lines = const [],
    this.finishedAt,
    this.exitCode,
    this.elapsedMs,
    this.droppedLines = 0,
    this.afterLaunch = false,
    this.error,
    this.dismissed = false,
  });

  final String id;
  final String label;
  final String command;
  final RunStatus status;
  final DateTime startedAt;
  final RunOrigin origin;

  /// `false` para las ejecuciones elevadas: un proceso de integridad media no
  /// puede matar a uno de integridad alta, asi que ofrecer "Cancelar" seria
  /// ofrecer un boton que no hace nada.
  final bool cancellable;

  final List<RunLine> lines;
  final DateTime? finishedAt;
  final int? exitCode;

  /// Duracion medida del lado Rust. Se prefiere a restar los `DateTime` de
  /// aca: incluye el arranque del proceso y no depende del reloj de la UI.
  final int? elapsedMs;

  final int droppedLines;

  /// Ya se habia dado por "Lanzada" cuando termino. Solo importa si ademas
  /// fallo: significa que no habia ninguna notificacion viva y hay que
  /// levantar una nueva.
  final bool afterLaunch;

  final String? error;

  /// El usuario la cerro a mano. Sale de la pila de toasts pero **queda en el
  /// historial**.
  final bool dismissed;

  bool get isActive =>
      status == RunStatus.starting || status == RunStatus.running;

  bool get isFailure => status == RunStatus.failed;

  /// Ultima linea, para el resumen de una linea del toast contraido.
  String? get lastLine => lines.isEmpty ? null : lines.last.text;

  /// Cuanto lleva/llevo corriendo. Mientras esta viva se calcula contra
  /// `now`, que es lo que hace latir el cronometro.
  Duration elapsed(DateTime now) {
    final ms = elapsedMs;
    if (ms != null) return Duration(milliseconds: ms);
    return now.difference(startedAt);
  }

  CommandRun copyWith({
    RunStatus? status,
    List<RunLine>? lines,
    DateTime? finishedAt,
    int? exitCode,
    int? elapsedMs,
    int? droppedLines,
    bool? afterLaunch,
    String? error,
    bool? dismissed,
    RunOrigin? origin,
  }) {
    return CommandRun(
      id: id,
      label: label,
      command: command,
      status: status ?? this.status,
      startedAt: startedAt,
      origin: origin ?? this.origin,
      cancellable: cancellable,
      lines: lines ?? this.lines,
      finishedAt: finishedAt ?? this.finishedAt,
      exitCode: exitCode ?? this.exitCode,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      droppedLines: droppedLines ?? this.droppedLines,
      afterLaunch: afterLaunch ?? this.afterLaunch,
      error: error ?? this.error,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}

/// A partir de cuanto una ejecucion se considera lenta.
///
/// Se decide **en Dart**, contra `startedAt`, y no con un evento extra desde
/// Rust: el cronometro ya esta latiendo en la UI, asi que cruzar el umbral no
/// necesita ningun mensaje por el puente.
const kSlowRunThreshold = Duration(seconds: 10);

/// Cuanto queda visible un toast que salio bien antes de cerrarse solo. Un
/// fallo **no** se auto-cierra: es el unico caso en el que el usuario tiene
/// algo que hacer.
const kSuccessToastLinger = Duration(seconds: 4);
const kLaunchedToastLinger = Duration(seconds: 2);

/// Cuantas ejecuciones se recuerdan en el historial de la sesion. El anillo de
/// salida real vive del lado Rust (`commandRunOutput`), aca solo queda lo que
/// se recibio en vivo.
const kRunHistoryLimit = 50;

/// Techo de lineas que la UI guarda por ejecucion. El anillo de Rust ya corta
/// en 2000; esto evita que una lista de widgets crezca sin control si alguna
/// vez ese numero sube.
const kUiLineLimit = 2000;

extension CommandRunStatusLabel on CommandRun {
  /// Texto de estado que se muestra en el toast.
  String get statusLabel => switch (status) {
    RunStatus.starting => 'Iniciando',
    RunStatus.running => 'Ejecutando',
    RunStatus.launched => 'Lanzada',
    RunStatus.succeeded => 'Completada',
    RunStatus.cancelled => 'Cancelada',
    RunStatus.failed => exitCode != null ? 'Error (codigo $exitCode)' : 'Error',
  };
}

/// Convierte una linea del puente al modelo de la UI.
RunLine runLineFrom(String text, bridge.CommandOutputStream stream) =>
    RunLine(text, isError: stream == bridge.CommandOutputStream.stderr);
