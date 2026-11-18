import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/profile_actions_dao.dart';
import 'package:nexodeck/data/local/daos/profiles_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:uuid/uuid.dart';

import '../domain/deck_profile.dart';

class ProfilesRepository {
  ProfilesRepository(this._profilesDao, this._profileActionsDao);

  final ProfilesDao _profilesDao;
  final ProfileActionsDao _profileActionsDao;

  Stream<List<DeckProfile>> watchAll() =>
      _profilesDao.watchAll().map((rows) => rows.map(DeckProfile.fromRow).toList());

  /// Ids de las acciones que componen [profileId].
  Stream<Set<String>> watchActionIds(String profileId) =>
      _profileActionsDao.watchActionIdsForProfile(profileId);

  Future<String> createProfile({
    required String name,
    String icon = 'folder',
    String colorHex = '#22C55E',
    String? autoDetectProcess,
    List<String> actionIds = const [],
  }) async {
    final id = const Uuid().v4();
    await _profilesDao.createProfile(
      ProfilesCompanion.insert(
        id: Value(id),
        name: name,
        icon: Value(icon),
        colorHex: Value(colorHex),
        autoDetectProcess: Value(_normalizeProcess(autoDetectProcess)),
      ),
    );
    await _profileActionsDao.replaceActionsForProfile(id, actionIds);
    return id;
  }

  Future<void> updateProfile(
    DeckProfile existing, {
    required String name,
    required String icon,
    required String colorHex,
    String? autoDetectProcess,
    List<String> actionIds = const [],
  }) async {
    await _profilesDao.updateProfile(
      ProfilesCompanion(
        id: Value(existing.id),
        name: Value(name),
        icon: Value(icon),
        colorHex: Value(colorHex),
        isDefault: Value(existing.isDefault),
        autoDetectProcess: Value(_normalizeProcess(autoDetectProcess)),
      ),
    );
    await _profileActionsDao.replaceActionsForProfile(existing.id, actionIds);
  }

  Future<void> deleteProfile(String id) => _profilesDao.deleteProfile(id);

  /// Un campo de texto vacio (o con espacios) significa "sin auto-deteccion",
  /// que en la columna se representa con `null`. Guardar `''` haria que
  /// `hasAutoDetect` y el match tuvieran que defenderse del mismo caso en
  /// dos lugares distintos.
  static String? _normalizeProcess(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
