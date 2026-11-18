import 'dart:typed_data';

import 'package:nexodeck/src/rust/api/processes.dart' as bridge;

import '../../dashboard/domain/metric_kind.dart';
import '../../dashboard/presentation/widgets/format_utils.dart';

/// Una aplicacion y lo que consume: todos los procesos que comparten nombre
/// de ejecutable, sumados.
///
/// Mismo criterio de separacion que `HardwareSnapshot`: el tipo del bridge no
/// llega a los widgets.
class ProcessGroup {
  const ProcessGroup({
    required this.name,
    required this.pids,
    required this.cpuPercent,
    required this.memoryMb,
    required this.gpuPercent,
    required this.diskBytesPerSec,
    required this.runTimeSecs,
    required this.isSelf,
  });

  factory ProcessGroup.fromBridge(bridge.ProcessGroup g) => ProcessGroup(
    name: g.name,
    pids: g.pids,
    cpuPercent: g.cpuPercent,
    memoryMb: g.memoryMb,
    gpuPercent: g.gpuPercent,
    diskBytesPerSec: g.diskBytesPerSec,
    runTimeSecs: g.runTimeSecs,
    isSelf: g.isSelf,
  );

  /// Para mandarlo por el cable (`AiAskAboutProcess`, telefono -> PC): el
  /// grupo tal cual lo tiene el telefono en pantalla.
  bridge.ProcessGroup toBridge() => bridge.ProcessGroup(
    name: name,
    pids: Uint32List.fromList(pids),
    cpuPercent: cpuPercent,
    memoryMb: memoryMb,
    gpuPercent: gpuPercent,
    diskBytesPerSec: diskBytesPerSec,
    runTimeSecs: runTimeSecs,
    isSelf: isSelf,
  );

  final String name;

  /// Todos los pids del grupo. Se mandan enteros al cerrar: Rust cierra por
  /// pid **y** nombre, porque Windows reutiliza los pids rapido y estos
  /// vienen de una muestra de hasta dos segundos atras.
  final List<int> pids;

  final double cpuPercent;
  final double memoryMb;

  /// `null` cuando esta maquina no informa uso de GPU por proceso.
  final double? gpuPercent;

  /// Bytes/segundo de lectura + escritura combinadas, sumado del grupo.
  final double diskBytesPerSec;

  /// Segundos que lleva corriendo el proceso mas viejo del grupo. **`0`
  /// significa desconocido**, no recien arrancado: Windows no deja leer el
  /// tiempo de arranque de los procesos del sistema.
  final int runTimeSecs;

  /// El grupo de NexoDeck. Se muestra igual --esconderlo seria deshonesto--
  /// pero no se deja cerrar.
  final bool isSelf;

  int get processCount => pids.length;
}

/// Las tres listas de una misma muestra, ya ordenadas por Rust.
class TopProcesses {
  const TopProcesses({
    required this.byCpu,
    required this.byMemory,
    required this.byGpu,
    required this.byDisk,
    required this.gpuAvailable,
    required this.sampledProcessCount,
  });

  factory TopProcesses.fromBridge(bridge.TopProcesses t) => TopProcesses(
    byCpu: t.byCpu.map(ProcessGroup.fromBridge).toList(growable: false),
    byMemory: t.byMemory.map(ProcessGroup.fromBridge).toList(growable: false),
    byGpu: t.byGpu.map(ProcessGroup.fromBridge).toList(growable: false),
    byDisk: t.byDisk.map(ProcessGroup.fromBridge).toList(growable: false),
    gpuAvailable: t.gpuAvailable,
    sampledProcessCount: t.sampledProcessCount,
  );

  final List<ProcessGroup> byCpu;
  final List<ProcessGroup> byMemory;
  final List<ProcessGroup> byGpu;
  final List<ProcessGroup> byDisk;

  /// Si esta maquina puede medir GPU por proceso. Sin este dato, "aca no se
  /// puede medir" y "nadie esta usando la GPU" son la misma lista vacia.
  final bool gpuAvailable;

  final int sampledProcessCount;

  /// La lista que le corresponde a una metrica. Las tres vienen en cada
  /// muestra justamente para que cambiar de metrica no cueste nada.
  List<ProcessGroup> forMetric(MetricKind kind) => switch (kind) {
    MetricKind.cpu => byCpu,
    MetricKind.ram => byMemory,
    MetricKind.gpu => byGpu,
    MetricKind.disk => byDisk,
    // La Red no se desglosa (ver `supportsProcessBreakdown`); el panel no se
    // abre para ella, pero devolver vacio es mas sano que tirar.
    MetricKind.network => const [],
  };
}

/// El consumo de un grupo en la metrica elegida, ya formateado.
///
/// Un solo decimal en los porcentajes, y no cero como en la tile: con
/// `toStringAsFixed(0)` dos tercios de la lista dirian `0%` y no se podria
/// distinguir el que consume algo del que no consume nada.
String formatMetricValue(ProcessGroup group, MetricKind kind) {
  return switch (kind) {
    MetricKind.cpu => '${group.cpuPercent.toStringAsFixed(1)}%',
    MetricKind.gpu => group.gpuPercent == null
        ? '—'
        : '${group.gpuPercent!.toStringAsFixed(1)}%',
    MetricKind.ram => _formatMemory(group.memoryMb),
    MetricKind.disk => formatBytesPerSec(group.diskBytesPerSec.round()),
    MetricKind.network => '—',
  };
}

String _formatMemory(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(0)} MB';
}

/// Hace cuanto corre el proceso, en la unidad mas grande que aplique.
///
/// `0` es **desconocido** y se dibuja como `—`: Windows no deja leer el
/// tiempo de arranque de los procesos del sistema, y ahi `run_time` daba el
/// epoch entero (`dwm.exe` aparecia con 20691 dias, o sea desde 1970).
String formatRunTime(int seconds) {
  if (seconds <= 0) return '—';
  if (seconds < 60) return '$seconds s';
  if (seconds < 3600) return '${seconds ~/ 60} min';
  if (seconds < 86400) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  return hours == 0 ? '$days d' : '$days d $hours h';
}
