import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as connection;

import '../domain/command_run.dart';

/// Estado del centro de ejecuciones: las vivas y el historial de la sesion,
/// en una sola lista ordenada de mas nueva a mas vieja.
class RunCenterState {
  const RunCenterState({this.runs = const []});

  final List<CommandRun> runs;

  /// Lo que se dibuja como toast: activas y las que terminaron hace poco y el
  /// usuario todavia no cerro.
  List<CommandRun> get visible => runs.where((r) => !r.dismissed).toList();

  bool get hasActive => runs.any((r) => r.isActive);
}

/// Mantiene el estado de todas las ejecuciones de comandos.
///
/// **Se suscribe DIRECTO al `Stream` del puente, nunca con `ref.listen`.**
/// Riverpod no vuelve a notificar cuando el valor nuevo es `==` al anterior,
/// y dos eventos `Output` con las mismas lineas seguidos son perfectamente
/// posibles (un comando que imprime la misma linea dos veces). Con
/// `ref.listen` el segundo desaparecia en silencio. Es la misma regla que ya
/// costo dos bugs en el proyecto -- ver "Eventos del bridge" en `CLAUDE.md`.
class RunCenterController extends Notifier<RunCenterState> {
  StreamSubscription<bridge.CommandRunEvent>? _subscription;

  /// Origen declarado por quien dispara, antes de que llegue el `Started`.
  /// El evento no lo puede saber: para Rust las dos puntas son iguales.
  final Map<String, RunOrigin> _pendingOrigins = {};

  @override
  RunCenterState build() {
    _subscription = bridge.watchCommandRuns().listen(_onEvent);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return const RunCenterState();
  }

  /// Declara de donde va a venir la proxima ejecucion con ese id. Se llama
  /// justo despues de `startCapturedCommand`, que devuelve el id.
  void declareOrigin(String runId, RunOrigin origin) {
    _pendingOrigins[runId] = origin;
    // El `Started` puede haber ganado la carrera (el evento sale del puente
    // antes de que `startCapturedCommand` resuelva): si la fila ya existe, se
    // corrige en vez de quedar marcada como local.
    _update(runId, (run) => run.copyWith(origin: origin));
  }

  void _onEvent(bridge.CommandRunEvent event) {
    switch (event) {
      case bridge.CommandRunEvent_Started(
        :final runId,
        :final label,
        :final command,
        :final cancellable,
      ):
        _insert(
          CommandRun(
            id: runId,
            label: label,
            command: command,
            // Directo a "Ejecutando", no a "Iniciando": la fila la crea este
            // mismo evento, o sea que el proceso YA arranco. Esperar a la
            // primera linea de salida para promoverla dejaba un
            // `flutter analyze` diciendo "Iniciando" durante los 104 s que
            // tarda en imprimir algo.
            status: RunStatus.running,
            startedAt: DateTime.now(),
            origin: _pendingOrigins.remove(runId) ?? RunOrigin.local,
            cancellable: cancellable,
          ),
        );

      case bridge.CommandRunEvent_Output(
        :final runId,
        :final stream,
        :final lines,
      ):
        _update(runId, (run) {
          final merged = [
            ...run.lines,
            ...lines.map((text) => runLineFrom(text, stream)),
          ];
          return run.copyWith(
            lines: merged.length > kUiLineLimit
                ? merged.sublist(merged.length - kUiLineLimit)
                : merged,
          );
        });

      case bridge.CommandRunEvent_Detached(:final runId, :final elapsedMs):
        _update(
          runId,
          (run) => run.copyWith(
            status: RunStatus.launched,
            elapsedMs: elapsedMs,
            finishedAt: DateTime.now(),
          ),
        );

      case bridge.CommandRunEvent_Finished(
        :final runId,
        :final exitCode,
        :final elapsedMs,
        :final ok,
        :final afterDetach,
        :final droppedLines,
      ):
        _update(
          runId,
          (run) => run.copyWith(
            status: ok ? RunStatus.succeeded : RunStatus.failed,
            exitCode: exitCode,
            elapsedMs: elapsedMs,
            finishedAt: DateTime.now(),
            afterLaunch: afterDetach,
            droppedLines: droppedLines,
            // Una app que ya se habia dado por lanzada y despues revienta no
            // tiene ninguna notificacion viva: se vuelve a mostrar.
            dismissed: afterDetach && !ok ? false : null,
          ),
        );

      case bridge.CommandRunEvent_Cancelled(:final runId, :final elapsedMs):
        _update(
          runId,
          (run) => run.copyWith(
            status: RunStatus.cancelled,
            elapsedMs: elapsedMs,
            finishedAt: DateTime.now(),
          ),
        );

      case bridge.CommandRunEvent_Failed(:final runId, :final detail):
        _update(
          runId,
          (run) => run.copyWith(
            status: RunStatus.failed,
            error: detail,
            finishedAt: DateTime.now(),
          ),
        );
    }
  }

  void _insert(CommandRun run) {
    final runs = [run, ...state.runs.where((r) => r.id != run.id)];
    state = RunCenterState(
      runs: runs.length > kRunHistoryLimit
          ? runs.sublist(0, kRunHistoryLimit)
          : runs,
    );
  }

  void _update(String runId, CommandRun Function(CommandRun) transform) {
    final index = state.runs.indexWhere((r) => r.id == runId);
    // Puede no existir si el evento llego antes que el `Started` (imposible
    // hoy) o si el historial ya lo descarto: se ignora en vez de inventar una
    // fila sin nombre ni comando.
    if (index == -1) return;
    final updated = [...state.runs];
    updated[index] = transform(updated[index]);
    state = RunCenterState(runs: updated);
  }

  /// Ingresa un update que llego **por red**, desde la PC, para una accion
  /// que este dispositivo mando ejecutar.
  ///
  /// El telefono no tiene el stream de eventos del runner (el comando corre
  /// en la PC): recibe solo el arranque y el cierre con el final de la
  /// salida. Por eso las lineas llegan de una sola vez y no hay cronometro
  /// vivo -- la duracion viene medida del otro lado.
  void applyRemoteUpdate({
    required String runId,
    required String actionLabel,
    required connection.RunPhase phase,
    required int elapsedMs,
    int? exitCode,
    String outputTail = '',
  }) {
    final status = switch (phase) {
      connection.RunPhase.started => RunStatus.running,
      connection.RunPhase.launched => RunStatus.launched,
      connection.RunPhase.succeeded => RunStatus.succeeded,
      connection.RunPhase.failed => RunStatus.failed,
      connection.RunPhase.cancelled => RunStatus.cancelled,
    };
    final lines = outputTail.isEmpty
        ? const <RunLine>[]
        : [
            for (final line in outputTail.trimRight().split('\n'))
              RunLine(line, isError: status == RunStatus.failed),
          ];

    final index = state.runs.indexWhere((r) => r.id == runId);
    if (index == -1) {
      _insert(
        CommandRun(
          id: runId,
          label: actionLabel,
          command: '',
          status: status,
          startedAt: DateTime.now().subtract(Duration(milliseconds: elapsedMs)),
          // La accion corre en la PC pero la disparo ESTE dispositivo, asi
          // que para el telefono es local: el icono de "remota" senala "la
          // pidio otro", y aca el otro seria uno mismo.
          origin: RunOrigin.local,
          cancellable: false,
          lines: lines,
          exitCode: exitCode,
          elapsedMs: phase == connection.RunPhase.started ? null : elapsedMs,
        ),
      );
      return;
    }
    _update(
      runId,
      (run) => run.copyWith(
        status: status,
        lines: lines.isEmpty ? null : lines,
        exitCode: exitCode,
        elapsedMs: phase == connection.RunPhase.started ? null : elapsedMs,
        finishedAt: phase == connection.RunPhase.started ? null : DateTime.now(),
      ),
    );
  }

  /// Saca el toast de la pila. La ejecucion queda en el historial.
  void dismiss(String runId) {
    _update(runId, (run) => run.copyWith(dismissed: true));
  }

  void dismissAllFinished() {
    state = RunCenterState(
      runs: [
        for (final run in state.runs)
          run.isActive ? run : run.copyWith(dismissed: true),
      ],
    );
  }

  /// Como [dismissAllFinished], pero **deja los fallos a la vista**.
  ///
  /// Lo usa la vuelta del modo solo telefono: lo que termino bien mientras no
  /// habia interfaz ya no es noticia, y sin esto aparecerian de golpe todos
  /// los toasts acumulados. Un fallo si es algo que el usuario tiene que
  /// leer, igual que un toast de fallo nunca se auto-cierra.
  void dismissFinishedSuccesses() {
    state = RunCenterState(
      runs: [
        for (final run in state.runs)
          run.isActive || run.isFailure ? run : run.copyWith(dismissed: true),
      ],
    );
  }

  Future<void> cancel(String runId) async {
    await bridge.cancelCommandRun(runId: runId);
  }

  /// Salida completa desde el anillo de Rust. Se pide al expandir el detalle
  /// porque la UI puede no tener todo (se suscribio tarde, o el historial
  /// recorto).
  Future<List<String>> fullOutput(String runId) =>
      bridge.commandRunOutput(runId: runId);
}

final runCenterProvider =
    NotifierProvider<RunCenterController, RunCenterState>(
      RunCenterController.new,
    );
