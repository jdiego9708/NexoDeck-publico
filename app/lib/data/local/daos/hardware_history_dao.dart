import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/hardware_history_table.dart';

part 'hardware_history_dao.g.dart';

@DriftAccessor(tables: [HardwareHistory])
class HardwareHistoryDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$HardwareHistoryDaoMixin {
  HardwareHistoryDao(super.db);

  Future<int> record(HardwareHistoryCompanion entry) =>
      into(hardwareHistory).insert(entry);

  Stream<List<HardwareHistoryData>> watchSince(DateTime cutoff) =>
      (select(hardwareHistory)
            ..where((h) => h.timestamp.isBiggerOrEqualValue(cutoff))
            ..orderBy([(h) => OrderingTerm.asc(h.timestamp)]))
          .watch();

  /// Estrategia de retencion: solo se conserva historial reciente a
  /// resolucion completa (ver seccion 2.8 del esquema). El umbral concreto
  /// (cuantos minutos/horas) se lee de `app_settings` en la capa de
  /// repositorio, no se hardcodea aqui.
  Future<int> purgeOlderThan(DateTime cutoff) =>
      (delete(hardwareHistory)..where((h) => h.timestamp.isSmallerThanValue(cutoff))).go();
}
