import 'package:drift/drift.dart';

/// Tabla de alta frecuencia de escritura (potencialmente un registro por
/// segundo). PK autoincremental (no UUID): evita overhead de indice en una
/// tabla que se purga constantemente, y el orden cronologico natural del
/// autoincremental ya sirve para ordenar sin columna adicional.
@TableIndex(name: 'idx_hardware_history_timestamp', columns: {#timestamp})
class HardwareHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp =>
      dateTime().clientDefault(() => DateTime.now())();

  RealColumn get cpuUsage => real()();
  RealColumn get cpuTemp => real().nullable()();
  RealColumn get cpuFreqMhz => real().nullable()();

  RealColumn get gpuUsage => real().nullable()();
  RealColumn get gpuTemp => real().nullable()();
  RealColumn get gpuVramUsedMb => real().nullable()();

  RealColumn get ramUsedMb => real()();
  RealColumn get ramTotalMb => real()();

  IntColumn get diskReadBytesPerSec => integer().nullable()();
  IntColumn get diskWriteBytesPerSec => integer().nullable()();

  /// Tasas de red del snapshot. Se agregaron en `schemaVersion 4`: la tabla
  /// original preveia E/S de disco (que `HardwareMonitor` todavia no
  /// produce, por eso las dos de arriba quedan siempre en `null`) pero no
  /// red, y la red es una de las 5 metricas que la UI grafica. Sin estas
  /// columnas el historial persistido habria mostrado 4 de 5.
  IntColumn get netRxBytesPerSec => integer().nullable()();
  IntColumn get netTxBytesPerSec => integer().nullable()();

  // Sin `primaryKey` explicito: `autoIncrement()` ya declara `id` como PK,
  // y drift_dev rechaza declarar ambas cosas a la vez.
}
