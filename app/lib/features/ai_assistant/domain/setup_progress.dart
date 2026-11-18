import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

/// Traduce un evento de setup a lo que muestra el wizard.
///
/// Funcion pura y testeada aparte: la logica de "en que paso estamos y cuanto
/// falta" es justo la que se rompe en silencio (una barra que se queda en 99 %,
/// un paso que nunca cambia de texto), y verificarla en un widget test completo
/// es mucho mas caro que verificarla aca.

enum SetupPhase { idle, probing, downloading, verifying, extracting, starting, ready, failed }

class SetupProgress {
  const SetupProgress({
    required this.phase,
    required this.title,
    this.detail,
    this.fraction,
    this.speedLabel,
  });

  static const idle = SetupProgress(phase: SetupPhase.idle, title: 'Sin iniciar');

  final SetupPhase phase;
  final String title;
  final String? detail;

  /// `0..1`, o `null` cuando el paso no tiene progreso medible (verificar,
  /// descomprimir, arrancar). La UI muestra una barra indeterminada en ese
  /// caso, que es honesto: fingir un porcentaje inventado es peor.
  final double? fraction;

  final String? speedLabel;

  bool get isTerminal => phase == SetupPhase.ready || phase == SetupPhase.failed;
  bool get isRunning => !isTerminal && phase != SetupPhase.idle;
}

SetupProgress progressFor(bridge.AiSetupEvent event) => switch (event) {
  bridge.AiSetupEvent_Probing() => const SetupProgress(
    phase: SetupPhase.probing,
    title: 'Revisando tu equipo',
    detail: 'Detectando GPU, memoria y espacio libre',
  ),
  bridge.AiSetupEvent_Downloading(
    :final asset,
    :final downloaded,
    :final totalBytes,
    :final bytesPerSec,
  ) =>
    SetupProgress(
      phase: SetupPhase.downloading,
      title: 'Descargando $asset',
      detail: '${formatBytes(downloaded)} de ${formatBytes(totalBytes)}',
      // Sin tamano total conocido no se inventa un porcentaje.
      fraction: totalBytes > BigInt.zero
          ? (downloaded / totalBytes).clamp(0.0, 1.0)
          : null,
      speedLabel: bytesPerSec > BigInt.zero ? '${formatBytes(bytesPerSec)}/s' : null,
    ),
  bridge.AiSetupEvent_Verifying(:final asset) => SetupProgress(
    phase: SetupPhase.verifying,
    title: 'Verificando $asset',
    // Se explica por que tarda: en un modelo de varios GB son 30-60 s de
    // silencio que sin este texto parecen un cuelgue.
    detail: 'Comprobando que el archivo bajo entero y sin corromperse',
  ),
  bridge.AiSetupEvent_Extracting(:final asset) => SetupProgress(
    phase: SetupPhase.extracting,
    title: 'Descomprimiendo $asset',
  ),
  bridge.AiSetupEvent_StartingServer() => const SetupProgress(
    phase: SetupPhase.starting,
    title: 'Cargando el modelo',
    detail: 'La primera vez puede tardar un rato',
  ),
  bridge.AiSetupEvent_Ready(:final providerLabel, :final gpuLayers) => SetupProgress(
    phase: SetupPhase.ready,
    title: 'Listo',
    detail: gpuLayers > 0
        ? '$providerLabel · $gpuLayers capas en la GPU'
        : providerLabel,
  ),
  bridge.AiSetupEvent_Failed(:final detail) => SetupProgress(
    phase: SetupPhase.failed,
    title: 'No se pudo preparar el asistente',
    detail: detail,
  ),
};

/// Bytes legibles. Vive aca y no en el widget para que el test de progreso
/// verifique el texto exacto que el usuario ve.
String formatBytes(BigInt bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;

  final value = bytes.toDouble();
  if (value >= gb) return '${(value / gb).toStringAsFixed(1)} GB';
  if (value >= mb) return '${(value / mb).toStringAsFixed(0)} MB';
  if (value >= kb) return '${(value / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
