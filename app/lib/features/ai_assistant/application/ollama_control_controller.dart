import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'ai_providers.dart';

/// Estado de Ollama para el interruptor del menu "Mas".
///
/// No se persiste: encendido o apagado no es una preferencia de NexoDeck, es
/// el estado real de un servicio de la maquina que puede cambiar por fuera
/// (el arranque de Windows, la bandeja del sistema, el propio usuario). Por eso
/// se consulta al abrir el menu en vez de guardarse.
class OllamaControlStatus {
  const OllamaControlStatus({
    this.running = false,
    this.binaryPath,
    this.busy = false,
    this.error,
  });

  /// Responde en `127.0.0.1:11434`.
  final bool running;

  /// Ruta del ejecutable si se encontro la instalacion. `null` = no hay Ollama.
  final String? binaryPath;

  /// Hay un arranque o una parada en curso.
  final bool busy;

  /// El motivo del ultimo fallo, si lo hubo.
  final String? error;

  bool get installed => binaryPath != null;

  static const initial = OllamaControlStatus();
}

/// Estado de Ollama, para que la UI pueda decir por que no arranco en vez de
/// limitarse a no hacer nada. Mismo patron que `controlServerStatusProvider`.
final ollamaControlStatusProvider = StateProvider<OllamaControlStatus>(
  (ref) => OllamaControlStatus.initial,
);

final ollamaControlControllerProvider = Provider<OllamaControlController>(
  (ref) => OllamaControlController(ref),
);

/// Enciende y apaga el Ollama instalado. La logica vive aqui y no en el widget
/// del menu, igual que en `ControlSettingsController`.
class OllamaControlController {
  OllamaControlController(this._ref);

  final Ref _ref;

  /// Consulta el estado sin tocar nada. Lo llama el menu al abrirse.
  Future<void> refresh() async {
    try {
      final status = await _ref.read(aiRepositoryProvider).ollamaControlStatus();
      _ref.read(ollamaControlStatusProvider.notifier).state = OllamaControlStatus(
        running: status.running,
        binaryPath: status.binaryPath,
      );
    } catch (e) {
      // En Android el bridge devuelve "no soportado": que falle la consulta no
      // puede tumbar el menu, solo dejar el estado con su motivo.
      _ref.read(ollamaControlStatusProvider.notifier).state = OllamaControlStatus(
        error: e.toString(),
      );
    }
  }

  /// Enciende o apaga. **Primero refresca** para no invertir un estado viejo:
  /// Ollama puede haber arrancado o parado por fuera desde la ultima consulta.
  Future<void> toggle() async {
    await refresh();
    await setRunning(!_ref.read(ollamaControlStatusProvider).running);
  }

  Future<void> setRunning(bool running) async {
    final before = _ref.read(ollamaControlStatusProvider);
    _ref.read(ollamaControlStatusProvider.notifier).state = OllamaControlStatus(
      running: before.running,
      binaryPath: before.binaryPath,
      busy: true,
    );

    try {
      final repository = _ref.read(aiRepositoryProvider);
      final status = running
          ? await repository.startOllama()
          : await repository.stopOllama();
      _ref.read(ollamaControlStatusProvider.notifier).state = OllamaControlStatus(
        running: status.running,
        binaryPath: status.binaryPath,
      );
    } catch (e) {
      _ref.read(ollamaControlStatusProvider.notifier).state = OllamaControlStatus(
        running: before.running,
        binaryPath: before.binaryPath,
        error: e.toString(),
      );
    }
  }
}

/// Texto del subtitulo del item del menu. Fuera del widget para poder
/// reutilizarlo y para que el `build` quede legible.
String ollamaControlSubtitle(OllamaControlStatus status) {
  if (status.busy) {
    return status.running ? 'Apagando…' : 'Encendiendo…';
  }
  if (status.error != null) {
    return status.error!;
  }
  if (!status.installed) {
    return 'No se encontró Ollama instalado';
  }
  return status.running
      ? 'Encendido — se apaga para toda la máquina'
      : 'Apagado — enciéndelo para usar tus modelos';
}
