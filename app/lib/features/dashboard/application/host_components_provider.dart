import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/src/rust/api/components.dart' as bridge;

import '../domain/host_components.dart';

/// Las piezas del equipo, leidas una sola vez.
///
/// **Sin `autoDispose` a proposito**, al reves que casi todo lo demas: el dato
/// no cambia mientras la app corre, y las consultas que hay detras (WMI para
/// los modulos de memoria, NVML para la GPU) son caras. Que sobreviva a que
/// nadie lo mire es justamente lo que evita repetirlas cada vez que se cambia
/// de layout o se pliegan las metricas.
///
/// El telefono no lo usa para leer las suyas (no tiene WMI/NVML de la PC):
/// ve las de la PC por red, en `remoteHostComponentsProvider`.
final hostComponentsProvider = FutureProvider<HostComponents>((ref) async {
  return HostComponents.fromBridge(await bridge.hostComponents());
});

/// Rol Android: piezas de la PC, recibidas por
/// `ConnectionEvent.hostComponentsReceived` -- ver
/// `connected_device_screen.dart`. `null` hasta que llega (una sola vez por
/// sesion, justo despues de conectar). Mismo patron que
/// `remoteTopProcessesProvider`.
final remoteHostComponentsProvider = StateProvider<HostComponents?>(
  (ref) => null,
);
