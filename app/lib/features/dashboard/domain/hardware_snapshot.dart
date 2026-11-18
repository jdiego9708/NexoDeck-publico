import 'package:nexodeck/src/rust/api/hardware.dart' as bridge;

/// Snapshot de hardware del dominio de la app. Deliberadamente separado del
/// tipo generado por el bridge (`bridge.HardwareSnapshot`): esta capa no
/// depende de Flutter ni de Drift, y no queremos que un cambio en el bridge
/// (ej. u64 -> BigInt) se propague directo a los widgets.
class HardwareSnapshot {
  const HardwareSnapshot({
    required this.cpuUsage,
    required this.cpuFreqMhz,
    required this.cpuTempC,
    this.cpuThreadsTotal = 0,
    this.cpuThreadsBusy = 0,
    required this.ramUsedMb,
    required this.ramTotalMb,
    required this.diskUsedMb,
    required this.diskTotalMb,
    this.disks = const [],
    required this.netRxBytesPerSec,
    required this.netTxBytesPerSec,
    required this.gpuUsage,
    required this.gpuTempC,
    required this.gpuVramUsedMb,
    required this.gpuVramTotalMb,
    this.gpuClockMhz,
    this.gpuPowerWatts,
    this.gpuPowerLimitWatts,
  });

  factory HardwareSnapshot.fromBridge(bridge.HardwareSnapshot s) => HardwareSnapshot(
    cpuUsage: s.cpuUsage,
    cpuFreqMhz: s.cpuFreqMhz?.toInt(),
    cpuTempC: s.cpuTemp,
    cpuThreadsTotal: s.cpuThreadsTotal,
    cpuThreadsBusy: s.cpuThreadsBusy,
    ramUsedMb: s.ramUsedMb,
    ramTotalMb: s.ramTotalMb,
    diskUsedMb: s.diskUsedMb,
    diskTotalMb: s.diskTotalMb,
    disks: s.disks.map(DiskUsage.fromBridge).toList(growable: false),
    netRxBytesPerSec: s.netRxBytes.toInt(),
    netTxBytesPerSec: s.netTxBytes.toInt(),
    gpuUsage: s.gpuUsage,
    gpuTempC: s.gpuTemp,
    gpuVramUsedMb: s.gpuVramUsedMb,
    gpuVramTotalMb: s.gpuVramTotalMb,
    gpuClockMhz: s.gpuClockMhz,
    gpuPowerWatts: s.gpuPowerWatts,
    gpuPowerLimitWatts: s.gpuPowerLimitWatts,
  );

  /// Porcentaje 0-100.
  final double cpuUsage;
  final int? cpuFreqMhz;
  final double? cpuTempC;

  /// Hilos logicos del procesador y cuantos estan trabajando ahora. Dice algo
  /// que el porcentaje solo no dice: 4 hilos al 100% y 12 dormidos dan el
  /// mismo 25% que 16 hilos al 25%, y son cargas muy distintas.
  final int cpuThreadsTotal;
  final int cpuThreadsBusy;

  final double ramUsedMb;
  final double ramTotalMb;

  /// Agregado de [disks]: las unidades de nube y de red no entran (el filtro
  /// vive en Rust, `nexodeck-hardware/src/disks.rs`).
  final double diskUsedMb;
  final double diskTotalMb;

  /// Un elemento por disco fisico montado, ya ordenado por punto de montaje.
  /// Puede venir vacia: es lo que llega de un binario viejo del otro lado del
  /// cable, y tambien lo que se usa en los tests que no la necesitan.
  final List<DiskUsage> disks;

  final int netRxBytesPerSec;
  final int netTxBytesPerSec;

  /// `null` cuando no hay GPU NVIDIA o el driver/NVML no esta disponible.
  final double? gpuUsage;
  final double? gpuTempC;
  final double? gpuVramUsedMb;
  final double? gpuVramTotalMb;

  /// Reloj grafico actual en MHz. Dato vivo --sube y baja con la carga-- y por
  /// eso viaja en el snapshot y no con las piezas del equipo, que se leen una
  /// sola vez. `null` fuera de NVIDIA: no hay ruta vendor-agnostica.
  final int? gpuClockMhz;

  /// Potencia que esta consumiendo la GPU ahora mismo, en watts, y el techo
  /// efectivo que le impone el driver. Dato vivo, igual que [gpuClockMhz], y
  /// `null` por el mismo motivo fuera de NVIDIA. El techo viaja al lado del
  /// consumo porque es lo que lo vuelve interpretable: 180 W son "tranquila"
  /// en una tarjeta de 450 W y "al limite" en una de 200 W.
  final double? gpuPowerWatts;
  final double? gpuPowerLimitWatts;

  /// 0.0-1.0 de VRAM ocupada, o `null` si la maquina no informa alguna de las
  /// dos cifras.
  double? get gpuVramFraction {
    final used = gpuVramUsedMb;
    final total = gpuVramTotalMb;
    if (used == null || total == null || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  /// 0.0-1.0 del techo de potencia que la GPU esta usando, o `null` si falta
  /// alguna de las dos cifras. Mismo criterio que [gpuVramFraction]: la
  /// proporcion es lo que se puede comparar entre maquinas distintas, el
  /// numero suelto no.
  double? get gpuPowerFraction {
    final watts = gpuPowerWatts;
    final limit = gpuPowerLimitWatts;
    if (watts == null || limit == null || limit <= 0) return null;
    return (watts / limit).clamp(0.0, 1.0);
  }
}

/// Un disco fisico con su capacidad y su ocupacion. Mismo criterio de
/// separacion que [HardwareSnapshot]: el tipo del bridge no llega a los
/// widgets.
class DiskUsage {
  const DiskUsage({
    required this.mountPoint,
    required this.label,
    required this.kind,
    required this.usedMb,
    required this.totalMb,
    this.readBytesPerSec,
    this.writeBytesPerSec,
    this.tempC,
    this.tempAgeSecs,
  });

  factory DiskUsage.fromBridge(bridge.DiskUsage d) => DiskUsage(
    mountPoint: d.mountPoint,
    label: d.label,
    kind: switch (d.kind) {
      bridge.DiskMediaKind.ssd => DiskMediaKind.ssd,
      bridge.DiskMediaKind.hdd => DiskMediaKind.hdd,
      bridge.DiskMediaKind.unknown => DiskMediaKind.unknown,
    },
    usedMb: d.usedMb,
    totalMb: d.totalMb,
    readBytesPerSec: d.readBytesPerSec,
    writeBytesPerSec: d.writeBytesPerSec,
    tempC: d.tempC,
    tempAgeSecs: d.tempAgeSecs?.toInt(),
  );

  /// `C:` en Windows, punto de montaje en Unix. Es lo que identifica al disco
  /// en la lista, porque siempre esta (a diferencia de [label]).
  final String mountPoint;

  /// Etiqueta del volumen. Puede estar vacia -- un `C:` recien instalado no
  /// tiene ninguna.
  final String label;

  final DiskMediaKind kind;
  final double usedMb;
  final double totalMb;

  /// Bytes/segundo de lectura y escritura, para la senal de vida de la UI.
  /// `null` cuando la PC no sabe medirlo (fuera de Windows, o un volumen sin
  /// letra de unidad) -- distinto de "0", que es reposo real.
  final double? readBytesPerSec;
  final double? writeBytesPerSec;

  /// Temperatura del disco **fisico**, en grados Celsius. Dos particiones del
  /// mismo disco traen el mismo numero: hay un solo sensor, el del disco.
  /// `null` cuando la PC no sabe leerla o el disco no la publica.
  final double? tempC;

  /// Hace cuantos segundos se tomo [tempC]. Un disco dormido no contesta la
  /// consulta y conserva su ultima lectura, asi que sin esto no habria forma
  /// de distinguir un dato recien medido de uno de hace horas.
  final int? tempAgeSecs;

  /// Si [tempC] es una lectura vieja, de un disco que ya se durmio.
  ///
  /// El umbral es mayor que la cadencia de sondeo (30 s) con margen: a los 30
  /// justos, una lectura perfectamente fresca parpadearia entre fresca y vieja
  /// segun el momento del ciclo en que se dibuje.
  bool get isTempStale => (tempAgeSecs ?? 0) > 90;

  /// 0.0-1.0. Un disco de capacidad cero no llega hasta aca (Rust lo
  /// descarta), pero el clamp evita que un dato roto pinte una barra
  /// desbordada.
  double get usedFraction =>
      totalMb == 0 ? 0 : (usedMb / totalMb).clamp(0.0, 1.0);
}

enum DiskMediaKind { ssd, hdd, unknown }
