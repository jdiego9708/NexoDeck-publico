import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/actions_table.dart';
import '../tables/profile_actions_table.dart';

part 'profile_actions_dao.g.dart';

@DriftAccessor(tables: [ProfileActions, ActionsTable])
class ProfileActionsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ProfileActionsDaoMixin {
  ProfileActionsDao(super.db);

  /// El grid de acciones de un perfil, ya ordenado -- une `profileActions`
  /// con `actionsTable` para devolver las acciones completas, no solo los
  /// ids de la tabla de union.
  Stream<List<ActionsTableData>> watchActionsForProfile(String profileId) {
    final query =
        select(actionsTable).join([
            innerJoin(
              profileActions,
              profileActions.actionId.equalsExp(actionsTable.id),
            ),
          ])
          ..where(profileActions.profileId.equals(profileId))
          ..orderBy([OrderingTerm.asc(profileActions.orderIndex)]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(actionsTable)).toList(),
    );
  }

  /// Solo los ids, para filtrar el deck sin traer las filas completas (la
  /// grilla ya tiene las acciones cargadas por `actionsListProvider`).
  Stream<Set<String>> watchActionIdsForProfile(String profileId) =>
      (select(profileActions)
            ..where((p) => p.profileId.equals(profileId))
            ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]))
          .watch()
          .map((rows) => rows.map((r) => r.actionId).toSet());

  /// Reemplaza de una la composicion del perfil (mismo patron que
  /// `replaceSteps`/`replaceForAction`): el editor entrega la lista final,
  /// no un diff.
  Future<void> replaceActionsForProfile(
    String profileId,
    List<String> actionIds,
  ) async {
    await transaction(() async {
      await (delete(
        profileActions,
      )..where((p) => p.profileId.equals(profileId))).go();
      for (var i = 0; i < actionIds.length; i++) {
        await into(profileActions).insert(
          ProfileActionsCompanion.insert(
            profileId: profileId,
            actionId: actionIds[i],
            orderIndex: Value(i),
          ),
        );
      }
    });
  }

  Future<void> addActionToProfile(
    String profileId,
    String actionId, {
    int orderIndex = 0,
  }) => into(profileActions).insert(
    ProfileActionsCompanion.insert(
      profileId: profileId,
      actionId: actionId,
      orderIndex: Value(orderIndex),
    ),
  );

  Future<int> removeActionFromProfile(String profileId, String actionId) =>
      (delete(profileActions)..where(
            (p) => p.profileId.equals(profileId) & p.actionId.equals(actionId),
          ))
          .go();
}
