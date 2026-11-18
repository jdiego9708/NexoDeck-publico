import 'package:flutter_riverpod/legacy.dart';

/// Verdadero mientras NexoDeck se esta apagando. La UI lo mira para mostrar el
/// overlay "Apagando NexoDeck…" en vez de dejar la ventana muerta mientras se
/// detiene lo pesado.
final shuttingDownProvider = StateProvider<bool>((ref) => false);

/// El paso del apagado en curso (detener el asistente, el servidor de control,
/// el tunel…). Vive aparte del booleano para que el overlay diga **que** se
/// esta apagando, no solo que se esta apagando.
final shutdownStepProvider = StateProvider<String>((ref) => '');
