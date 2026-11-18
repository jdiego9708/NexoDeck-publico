import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/control.dart' as bridge;

import 'control_settings_controller.dart';

/// Cuantas entradas del registro se guardan. Es el panel de "que le pidieron a
/// mi maquina", no un log de auditoria: con las ultimas se ve lo que hace falta
/// y no crece sin limite en una sesion larga.
const _kMaxEntries = 100;

enum ControlActivityKind { started, stopped, toolCall, rejected }

/// Una linea del registro de actividad.
class ControlActivity {
  ControlActivity({
    required this.kind,
    required this.text,
    required this.at,
    this.ok = true,
  });

  final ControlActivityKind kind;
  final String text;
  final DateTime at;

  /// `false` pinta la linea como problema. Un rechazo o una herramienta que
  /// fallo tienen que verse distinto de una que salio bien.
  final bool ok;
}

class ControlActivityState {
  const ControlActivityState({this.entries = const []});

  /// De la mas reciente a la mas vieja.
  final List<ControlActivity> entries;

  /// Cuantos rechazos hay en el registro. Si algo esta golpeando el puerto, la
  /// UI tiene que poder decirlo de un vistazo.
  int get rejectionCount =>
      entries.where((e) => e.kind == ControlActivityKind.rejected).length;
}

/// Registro de lo que pasa en el servidor de control.
///
/// **Se suscribe DIRECTO al `Stream` del puente, nunca con `ref.listen`.**
/// Riverpod no vuelve a notificar cuando el valor nuevo es `==` al anterior, y
/// dos rechazos identicos seguidos (alguien reintentando con el mismo token
/// equivocado) son exactamente el caso que hay que ver. Con `ref.listen` el
/// segundo desapareceria en silencio. Ver "Eventos del bridge" en `CLAUDE.md`.
class ControlActivityController extends Notifier<ControlActivityState> {
  StreamSubscription<bridge.ControlEvent>? _subscription;

  @override
  ControlActivityState build() {
    _subscription = bridge.watchControlEvents().listen(_onEvent);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return const ControlActivityState();
  }

  void _onEvent(bridge.ControlEvent event) {
    final activity = switch (event) {
      bridge.ControlEvent_Started(:final port) => ControlActivity(
        kind: ControlActivityKind.started,
        text: 'Servidor escuchando en 127.0.0.1:$port',
        at: DateTime.now(),
      ),
      bridge.ControlEvent_Stopped() => ControlActivity(
        kind: ControlActivityKind.stopped,
        text: 'Servidor detenido',
        at: DateTime.now(),
      ),
      bridge.ControlEvent_ToolCalled(:final tool, :final summary, :final ok) =>
        ControlActivity(
          kind: ControlActivityKind.toolCall,
          text: summary.isEmpty ? tool : summary,
          at: DateTime.now(),
          ok: ok,
        ),
      bridge.ControlEvent_Rejected(:final reason) => ControlActivity(
        kind: ControlActivityKind.rejected,
        text: 'Peticion rechazada: $reason',
        at: DateTime.now(),
        ok: false,
      ),
    };

    // El estado del servidor se refleja aca tambien: `Started` puede venir de
    // un arranque que no paso por el controlador de ajustes.
    if (event is bridge.ControlEvent_Started) {
      ref.read(controlServerStatusProvider.notifier).state =
          ControlServerStatus(port: event.port);
    }

    final entries = [activity, ...state.entries];
    state = ControlActivityState(
      entries: entries.length > _kMaxEntries
          ? entries.sublist(0, _kMaxEntries)
          : entries,
    );
  }
}

final controlActivityProvider =
    NotifierProvider<ControlActivityController, ControlActivityState>(
      ControlActivityController.new,
    );
