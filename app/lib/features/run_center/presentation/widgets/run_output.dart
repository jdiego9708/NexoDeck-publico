import 'package:flutter/material.dart';

/// Una linea de salida de un comando, en monoespaciada.
///
/// Vive aca y no dentro del toast porque la dibujan **los dos**: el toast de
/// la esquina y el panel acoplado. Que la salida se vea distinta en cada uno
/// seria el mismo problema que tenia el PIN de emparejamiento dibujado en dos
/// lugares.
///
/// `Text` y no `SelectableText`: el toast cuelga de `MaterialApp.builder`, o
/// sea fuera del `Navigator`, y ahi `SelectableText` explota con "No Overlay
/// widget found" en cada frame. Para copiar esta el boton.
class RunOutputLine extends StatelessWidget {
  const RunOutputLine({super.key, required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
          height: 1.35,
          color: isError ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// `120ms`, `1.2s`, `48s`, `2:05`, `1:23:45`.
///
/// Sin milisegundos arriba del segundo: un cronometro con centesimas a los
/// 30 s es ruido. Y **con escalon de horas**, que no es cosmetico: una cadena
/// de ODM corre 3-4 horas, y sin el se veria `214:07` -- un numero que hay
/// que dividir mentalmente para saber que son tres horas y media.
String formatRunElapsed(Duration elapsed) {
  final ms = elapsed.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s';

  final seconds = elapsed.inSeconds % 60;
  final minutes = elapsed.inMinutes % 60;
  if (elapsed.inHours == 0) {
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  return '${elapsed.inHours}:${minutes.toString().padLeft(2, '0')}'
      ':${seconds.toString().padLeft(2, '0')}';
}
