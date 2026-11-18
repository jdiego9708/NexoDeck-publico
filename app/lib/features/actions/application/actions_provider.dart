import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/daos/action_parameters_dao.dart';
import 'package:nexodeck/data/local/daos/actions_dao.dart';
import 'package:nexodeck/data/local/daos/macro_steps_dao.dart';

import '../../../core/di/database_provider.dart';
import '../../hub_subscriptions/application/hub_subscriptions_provider.dart';
import '../data/actions_repository.dart';
import '../data/deck_transfer_repository.dart';
import '../domain/deck_action.dart';
import 'action_groups_provider.dart';

final actionsRepositoryProvider = Provider<ActionsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ActionsRepository(
    db,
    ActionsDao(db),
    ActionParametersDao(db),
    MacroStepsDao(db),
    ref.watch(hubSubscriptionsRepositoryProvider),
  );
});

final actionsListProvider = StreamProvider.autoDispose<List<DeckAction>>((
  ref,
) {
  final repository = ref.watch(actionsRepositoryProvider);
  return repository.watchAll();
});

final deckTransferRepositoryProvider = Provider<DeckTransferRepository>((ref) {
  return DeckTransferRepository(
    ref.watch(actionsRepositoryProvider),
    ref.watch(actionGroupsRepositoryProvider),
  );
});
