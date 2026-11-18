import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

import '../data/connection_repository.dart';

final connectionRepositoryProvider = Provider<ConnectionRepository>(
  (ref) => const ConnectionRepository(),
);

/// Rol PC: ids de los dispositivos con sesion abierta ahora mismo.
///
/// `HostRuntime` es quien lo mantiene al dia (el bridge solo avisa altas y
/// bajas, no expone la lista), fuera del arbol de widgets, asi que sigue
/// vigente en modo compacto y sin interfaz. Cualquier otra parte que necesite
/// reenviarle algo a los dispositivos conectados (el eco del chat, el tooltip
/// de la bandeja) lo lee de aca.
final connectedDeviceIdsProvider = StateProvider<Set<String>>((ref) => const {});

final connectionEventsProvider = StreamProvider.autoDispose<bridge.ConnectionEvent>((
  ref,
) {
  final repository = ref.watch(connectionRepositoryProvider);
  return repository.watchConnectionEvents();
});

/// Suscripcion directa al stream de eventos, para efectos secundarios que
/// tienen que correr **una vez por evento**.
///
/// No uses `ref.listen(connectionEventsProvider, ...)` para eso: Riverpod no
/// vuelve a notificar cuando el valor nuevo es `==` al anterior, y los
/// eventos que genera flutter_rust_bridge son value types (freezed). Dos
/// `ExecuteAction` seguidos de la MISMA accion son identicos, asi que el
/// segundo se descartaba en silencio: tocar dos veces el mismo boton del
/// deck desde el celular ejecutaba una sola vez. Verificado en un E2E real
/// (tap A -> corre, tap A otra vez -> nada, tap B, tap A -> vuelve a
/// correr).
///
/// Quien lo use se queda con la `StreamSubscription` y la cancela al
/// desmontarse (ver `_HomeShell`).
Stream<bridge.ConnectionEvent> connectionEventStream(WidgetRef ref) =>
    ref.read(connectionRepositoryProvider).watchConnectionEvents();
