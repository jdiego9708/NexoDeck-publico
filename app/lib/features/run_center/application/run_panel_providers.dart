import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// La ejecucion cuya salida se esta mirando. `null` = la primera activa (o la
/// mas reciente si no hay ninguna corriendo), que lo resuelve el panel.
///
/// Guardar el id y no el objeto es lo que hace que la seleccion sobreviva a
/// que el run cambie de estado dos veces por segundo.
final selectedRunProvider = StateProvider<String?>((ref) => null);

final runPanelControllerProvider = Provider<RunPanelController>(
  (ref) => RunPanelController(ref),
);

/// El unico estado que le queda al panel de ejecuciones: **que run se mira**.
///
/// Antes abria/cerraba y anclaba un panel acoplado (con su provider de "abierto"
/// y de "anclaje"); desde F4 el panel se abre como **dialogo**
/// (`showRunPanelDialog`) y su cierre es el `pop`, asi que nada de eso hace
/// falta.
class RunPanelController {
  RunPanelController(this._ref);

  final Ref _ref;

  void select(String? runId) =>
      _ref.read(selectedRunProvider.notifier).state = runId;
}
