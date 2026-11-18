import 'package:nexodeck/src/rust/api/processes.dart' as bridge;

import 'process_group.dart';

/// El texto que se manda al chat de IA al preguntar por un proceso.
///
/// Funcion pura, sin bridge ni contexto: la usan los dos lados (PC local y
/// telefono via el evento que llega de la PC) para que la pregunta se vea
/// igual sin importar quien la disparo.
String buildProcessQuestionPrompt(
  ProcessGroup group, {
  bridge.ProcessDetails? details,
}) {
  final buffer = StringBuffer(
    'Explicame el proceso "${group.name}"'
    '${details != null ? ' (PID ${details.pid})' : ''}: '
    'usa ${group.cpuPercent.toStringAsFixed(1)}% de CPU, '
    '${_formatMemory(group.memoryMb)} de RAM',
  );
  if (group.gpuPercent != null) {
    buffer.write(', ${group.gpuPercent!.toStringAsFixed(1)}% de GPU');
  }
  buffer.write(
    ', y lleva corriendo ${formatRunTime(group.runTimeSecs)}.',
  );

  if (details?.parentName != null) {
    buffer.write(' Lo lanzo "${details!.parentName}".');
  }
  if (details?.owner != null) {
    buffer.write(' Corre como el usuario "${details!.owner}".');
  }
  if (details?.commandLine != null) {
    buffer.write(' Linea de comando: ${details!.commandLine}');
  } else if (details?.exePath != null) {
    buffer.write(' Ejecutable: ${details!.exePath}');
  }

  buffer.write(' ¿Que es, que hace, y es normal que este corriendo?');
  return buffer.toString();
}

String _formatMemory(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(0)} MB';
}
