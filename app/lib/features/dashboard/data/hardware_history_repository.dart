import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/hardware_history_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../domain/hardware_snapshot.dart';

/// Ventana de tiempo que se puede mirar en el historial.
///
/// La retencion (`HardwareHistoryRepository.retention`) tiene que cubrir la
/// mas larga, si no el rango de 7 dias mostraria una linea recortada sin
/// decir por que.
enum HistoryRange {
  lastHour(Duration(hours: 1), '1 hora'),
  lastDay(Duration(days: 1), '24 horas'),
  lastWeek(Duration(days: 7), '7 días');

  const HistoryRange(this.span, this.label);

  final Duration span;
  final String label;
}

class HardwareHistoryRepository {
  HardwareHistoryRepository(this._dao);

  final HardwareHistoryDao _dao;

  /// Cada cuanto se persiste una muestra.
  ///
  /// El stream de metricas emite 1/s, pero guardar a esa frecuencia son
  /// 86.400 filas por dia para un grafico que nunca va a mostrar mas de
  /// unos cientos de puntos. Con 15 s son ~5.760/dia y ~40.000 en la
  /// semana de retencion: una tabla que SQLite maneja sin despeinarse y
  /// que sigue dando resolucion de sobra para ver un pico.
  static const sampleEvery = Duration(seconds: 15);

  /// Cuanto historial se conserva. Coincide con el rango mas largo que la
  /// UI ofrece.
  static const retention = Duration(days: 7);

  /// Cada cuantas muestras se purga lo viejo. Purgar en cada escritura
  /// seria un DELETE cada 15 s para borrar, casi siempre, cero filas.
  /// Cada 240 muestras es una vez por hora.
  static const _purgeEveryNSamples = 240;

  int _samplesSincePurge = 0;

  Future<void> record(HardwareSnapshot snapshot, {DateTime? at}) async {
    await _dao.record(
      HardwareHistoryCompanion.insert(
        timestamp: Value(at ?? DateTime.now()),
        cpuUsage: snapshot.cpuUsage,
        cpuTemp: Value(snapshot.cpuTempC),
        cpuFreqMhz: Value(snapshot.cpuFreqMhz?.toDouble()),
        gpuUsage: Value(snapshot.gpuUsage),
        gpuTemp: Value(snapshot.gpuTempC),
        gpuVramUsedMb: Value(snapshot.gpuVramUsedMb),
        ramUsedMb: snapshot.ramUsedMb,
        ramTotalMb: snapshot.ramTotalMb,
        netRxBytesPerSec: Value(snapshot.netRxBytesPerSec),
        netTxBytesPerSec: Value(snapshot.netTxBytesPerSec),
      ),
    );

    _samplesSincePurge++;
    if (_samplesSincePurge >= _purgeEveryNSamples) {
      _samplesSincePurge = 0;
      await purgeOld();
    }
  }

  Future<int> purgeOld() =>
      _dao.purgeOlderThan(DateTime.now().subtract(retention));

  Stream<List<HardwareHistoryData>> watchRange(HistoryRange range) =>
      _dao.watchSince(DateTime.now().subtract(range.span));
}
