import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/src/rust/api/connection.dart' as bridge_connection;
import 'package:nexodeck/src/rust/api/processes.dart' as bridge;

import '../../dashboard/domain/metric_kind.dart';
import '../domain/process_group.dart';

/// La metrica cuyo desglose se esta viendo, o `null` con el panel cerrado.
///
/// No se persiste a proposito: el panel es una consulta puntual ("quien me
/// esta comiendo la CPU"), no una preferencia. Que la app abriera sola un
/// panel de procesos en cada arranque seria molesto.
///
/// En escritorio (F4) el desglose se abre como **dialogo**
/// (`showProcessPanelDialog`) y el dialogo se cierra solo; en el **movil** este
/// provider es el que abre y cierra la hoja (`ConnectedDeviceScreen`), asi que
/// `close` sigue siendo la salida por defecto del panel.
final selectedMetricProvider = StateProvider<MetricKind?>((ref) => null);

/// Muestras de procesos **de la maquina local**, mientras el panel este
/// abierto.
///
/// `autoDispose` no es un detalle: cuando el ultimo oyente se va, Rust corta
/// el loop y **deja de recorrer los ~370 procesos de la maquina**. Con el
/// panel cerrado esta funcionalidad cuesta exactamente cero.
///
/// Aca **si** corresponde un `StreamProvider`, a diferencia de los eventos de
/// conexion y pairing que el proyecto obliga a escuchar con una suscripcion
/// directa. La diferencia es que esto es *estado*, no una secuencia de
/// eventos: si Riverpod se come una emision por ser `==` a la anterior, no se
/// pierde nada, porque volver a dibujar la misma lista no cambia la pantalla.
///
/// **El telefono no lo usa**: sus procesos no le interesan a nadie -- lo que
/// mira son los de la PC, que llegan por `ConnectionEvent` y los publica
/// `remoteTopProcessesProvider`.
final topProcessesProvider = StreamProvider.autoDispose<TopProcesses>((ref) {
  return bridge.watchProcessUsage().map(TopProcesses.fromBridge);
});

/// Procesos **de la PC** recibidos por red (rol Android).
///
/// Lo alimenta `ConnectedDeviceScreen`, que ya escucha el stream de eventos de
/// conexion **directo** --y no con `ref.listen`-- por la regla de siempre:
/// Riverpod no re-notifica valores `==` y estos son value types de freezed.
final remoteTopProcessesProvider = StateProvider<TopProcesses?>((ref) => null);

final processPanelControllerProvider = Provider<ProcessPanelController>(
  (ref) => ProcessPanelController(ref),
);

class ProcessPanelController {
  ProcessPanelController(this._ref);

  final Ref _ref;

  /// Cierra el desglose. Es la salida por defecto del panel: en el movil
  /// limpia la metrica y la hoja se va; en escritorio el dialogo lo pisa con
  /// su `pop`.
  void close() => _ref.read(selectedMetricProvider.notifier).state = null;
}

/// Cierra un grupo de procesos **de esta maquina**. Devuelve el reporte para
/// que la UI pueda decir cuantos se cerraron de verdad.
Future<bridge.KillReport> terminateProcessGroup(ProcessGroup group) {
  return bridge.terminateProcessGroup(name: group.name, pids: group.pids);
}

/// Rol Android: pide (o corta) el envio de la lista de procesos de la PC.
///
/// Es una suscripcion, no un push permanente: mientras el panel este cerrado,
/// la PC no recorre nada y el telefono no recibe nada.
Future<void> watchRemoteProcesses(bool enabled) {
  return bridge_connection.sendWatchProcesses(enabled: enabled);
}

/// Rol Android: pide cerrar una aplicacion **en la PC**. La respuesta llega
/// despues, como evento de conexion.
Future<void> sendTerminateProcessGroup(ProcessGroup group) {
  return bridge_connection.sendTerminateProcessGroup(
    name: group.name,
    pids: group.pids,
  );
}

/// Rol Android: pide que la IA de la PC explique este proceso. La respuesta
/// llega como un mensaje normal del chat, por el reenvio persistente de
/// `main.dart` -- no hay un evento de vuelta especifico para esto.
Future<void> sendAiAskAboutProcess(ProcessGroup group) {
  return bridge_connection.sendAiAskAboutProcess(group: group.toBridge());
}
