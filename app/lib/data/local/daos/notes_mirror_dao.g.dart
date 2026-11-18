// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_mirror_dao.dart';

// ignore_for_file: type=lint
mixin _$NotesMirrorDaoMixin on DatabaseAccessor<NexoDeckDatabase> {
  $NoteMirrorTable get noteMirror => attachedDatabase.noteMirror;
  $NoteOutboxTable get noteOutbox => attachedDatabase.noteOutbox;
  NotesMirrorDaoManager get managers => NotesMirrorDaoManager(this);
}

class NotesMirrorDaoManager {
  final _$NotesMirrorDaoMixin _db;
  NotesMirrorDaoManager(this._db);
  $$NoteMirrorTableTableManager get noteMirror =>
      $$NoteMirrorTableTableManager(_db.attachedDatabase, _db.noteMirror);
  $$NoteOutboxTableTableManager get noteOutbox =>
      $$NoteOutboxTableTableManager(_db.attachedDatabase, _db.noteOutbox);
}
