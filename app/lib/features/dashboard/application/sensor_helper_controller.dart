import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../src/rust/api/sensors.dart' as bridge;

export '../../../src/rust/api/sensors.dart' show SensorHelperStatus;

/// Estado del ayudante que mide la temperatura del procesador.
///
/// **Por que la app necesita saber esto.** En Windows la temperatura del CPU
/// no se puede leer desde espacio de usuario, asi que la mide un servicio que
/// NexoDeck instala. Registrar un servicio pide permisos de administrador, y
/// NexoDeck se puede instalar **por usuario** --el modo por defecto del
/// instalador-- sin pasar nunca por una elevacion. En ese caso el servicio no
/// queda registrado, la temperatura no aparece **y nada lo explica**: pasa en
/// una instalacion real, verificado.
///
/// Con este provider la UI puede decir que falta y ofrecer instalarlo.
///
/// Es un `FutureProvider` y no un stream porque el dato cambia solo cuando
/// alguien instala o para el servicio: se relee a pedido con `ref.invalidate`,
/// no una vez por segundo.
final sensorHelperStatusProvider = FutureProvider<bridge.SensorHelperStatus>((
  ref,
) async {
  return bridge.sensorHelperStatus();
});

/// Cuanto se espera antes de releer el estado despues de aceptar el UAC.
///
/// `installSensorHelper` vuelve cuando el usuario respondio al dialogo de
/// elevacion, **no** cuando el servicio quedo arrancado: registrar el servicio
/// y abrir los sensores lleva un par de segundos mas.
const kSensorHelperInstallGrace = Duration(seconds: 5);

/// Instala el ayudante y devuelve el estado que quedo.
///
/// El `Err` de Rust incluye que el usuario **cancele** el UAC, que no es un
/// fallo del programa sino una decision suya: quien llama lo distingue por el
/// mensaje, no por que haya excepcion.
class SensorHelperController {
  SensorHelperController(this._ref);

  final Ref _ref;

  Future<SensorHelperInstallResult> install() async {
    try {
      await bridge.installSensorHelper();
    } catch (error) {
      return SensorHelperInstallResult.failed(error.toString());
    }

    await Future<void>.delayed(kSensorHelperInstallGrace);
    _ref.invalidate(sensorHelperStatusProvider);
    final status = await _ref.read(sensorHelperStatusProvider.future);
    return SensorHelperInstallResult(status: status);
  }
}

final sensorHelperControllerProvider = Provider(SensorHelperController.new);

/// Como termino un intento de instalacion.
class SensorHelperInstallResult {
  const SensorHelperInstallResult({required this.status}) : error = null;

  const SensorHelperInstallResult.failed(String this.error)
    : status = bridge.SensorHelperStatus.notInstalled;

  final bridge.SensorHelperStatus status;

  /// `null` cuando el lanzamiento no fallo. Que el estado siga siendo
  /// `notInstalled` con `error` en `null` es un caso real: el usuario acepto
  /// el UAC pero el registro no prospero.
  final String? error;

  bool get succeeded => status == bridge.SensorHelperStatus.running;
}
