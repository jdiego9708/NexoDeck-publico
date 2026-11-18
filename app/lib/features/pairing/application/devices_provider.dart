import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/daos/devices_dao.dart';

import '../../../core/di/database_provider.dart';
import '../data/devices_repository.dart';
import '../domain/paired_device.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DevicesRepository(DevicesDao(db));
});

final pairedDevicesListProvider = StreamProvider.autoDispose<List<PairedDevice>>((
  ref,
) {
  final repository = ref.watch(devicesRepositoryProvider);
  return repository.watchAll();
});
