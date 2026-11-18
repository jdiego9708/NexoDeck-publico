import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/secrets_refs_table.dart';

part 'secrets_refs_dao.g.dart';

@DriftAccessor(tables: [SecretsRefs])
class SecretsRefsDao extends DatabaseAccessor<NexoDeckDatabase>
    with _$SecretsRefsDaoMixin {
  SecretsRefsDao(super.db);

  /// Solo metadatos -- el valor cifrado real vive en nexodeck-vault (Rust),
  /// nunca aqui.
  Stream<List<SecretsRef>> watchAll() => select(secretsRefs).watch();

  Future<void> createRef(SecretsRefsCompanion entry) =>
      into(secretsRefs).insert(entry);

  Future<int> deleteRef(String keyName) =>
      (delete(secretsRefs)..where((s) => s.keyName.equals(keyName))).go();
}
