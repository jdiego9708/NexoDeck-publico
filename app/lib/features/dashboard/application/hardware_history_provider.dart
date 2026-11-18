import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/hardware_history_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/di/database_provider.dart';
import '../data/hardware_history_repository.dart';

final hardwareHistoryRepositoryProvider = Provider<HardwareHistoryRepository>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return HardwareHistoryRepository(HardwareHistoryDao(db));
});

/// Rango seleccionado en la pantalla de historial.
final historyRangeProvider = StateProvider<HistoryRange>(
  (ref) => HistoryRange.lastHour,
);

final hardwareHistoryProvider =
    StreamProvider.autoDispose<List<HardwareHistoryData>>((ref) {
      final range = ref.watch(historyRangeProvider);
      return ref.watch(hardwareHistoryRepositoryProvider).watchRange(range);
    });
