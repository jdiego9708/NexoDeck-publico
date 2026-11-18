import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/profiles_table.dart';

part 'profiles_dao.g.dart';

@DriftAccessor(tables: [Profiles])
class ProfilesDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$ProfilesDaoMixin {
  ProfilesDao(super.db);

  Stream<List<Profile>> watchAll() =>
      (select(profiles)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();

  Future<Profile?> getById(String id) =>
      (select(profiles)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<String> createProfile(ProfilesCompanion entry) async {
    await into(profiles).insert(entry);
    return entry.id.value;
  }

  Future<bool> updateProfile(ProfilesCompanion entry) =>
      update(profiles).replace(entry);

  Future<int> deleteProfile(String id) =>
      (delete(profiles)..where((p) => p.id.equals(id))).go();
}
