import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/action_groups_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:uuid/uuid.dart';

/// Wrapper fino sobre `ActionGroupsDao` -- los grupos son un dato plano
/// sin logica de dominio propia, a diferencia de `DeckAction`.
class ActionGroupsRepository {
  ActionGroupsRepository(this._dao);

  final ActionGroupsDao _dao;

  Stream<List<ActionGroup>> watchAll() => _dao.watchAll();

  Future<String> createGroup({
    required String name,
    String icon = 'folder',
    String colorHex = '#6366F1',
  }) {
    const uuid = Uuid();
    return _dao.createGroup(
      ActionGroupsCompanion.insert(
        id: Value(uuid.v4()),
        name: name,
        icon: Value(icon),
        colorHex: Value(colorHex),
      ),
    );
  }

  Future<void> renameGroup(
    ActionGroup group, {
    required String name,
    required String icon,
    required String colorHex,
  }) {
    return _dao.updateGroup(
      ActionGroupsCompanion(
        id: Value(group.id),
        name: Value(name),
        icon: Value(icon),
        colorHex: Value(colorHex),
        orderIndex: Value(group.orderIndex),
        createdAt: Value(group.createdAt),
      ),
    );
  }

  Future<void> deleteGroup(String id) => _dao.deleteGroup(id);
}
