import 'package:drift/drift.dart';

import 'actions_table.dart';
import 'profiles_table.dart';

/// Tabla de union N:N entre perfiles y acciones. Cascade en ambos lados: si
/// se borra un perfil, sus asociaciones desaparecen (la accion no); si se
/// borra una accion, deja de aparecer en cualquier perfil.
@TableIndex(
  name: 'idx_profile_actions_profile_order',
  columns: {#profileId, #orderIndex},
)
class ProfileActions extends Table {
  TextColumn get profileId =>
      text().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get actionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {profileId, actionId};
}
