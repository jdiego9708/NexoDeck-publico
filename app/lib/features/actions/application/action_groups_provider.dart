import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/action_groups_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/di/database_provider.dart';
import '../data/action_groups_repository.dart';

final actionGroupsRepositoryProvider = Provider<ActionGroupsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ActionGroupsRepository(ActionGroupsDao(db));
});

final actionGroupsListProvider = StreamProvider.autoDispose<List<ActionGroup>>((
  ref,
) {
  return ref.watch(actionGroupsRepositoryProvider).watchAll();
});

/// Grupo activo para filtrar la grilla de acciones. `null` = "Todas".
final selectedActionGroupProvider = StateProvider<String?>((ref) => null);
