// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'secrets_refs_dao.dart';

// ignore_for_file: type=lint
mixin _$SecretsRefsDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $SecretsRefsTable get secretsRefs => attachedDatabase.secretsRefs;
  SecretsRefsDaoManager get managers => SecretsRefsDaoManager(this);
}

class SecretsRefsDaoManager {
  final _$SecretsRefsDaoMixin _db;
  SecretsRefsDaoManager(this._db);
  $$SecretsRefsTableTableManager get secretsRefs =>
      $$SecretsRefsTableTableManager(_db.attachedDatabase, _db.secretsRefs);
}
