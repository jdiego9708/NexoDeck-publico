import 'package:nexodeck/data/local/daos/notes_mirror_dao.dart';
import 'package:nexodeck/data/local/database.dart';

import '../application/mobile_notes_host.dart';
import '../application/notes_sync_engine.dart';
import '../domain/mobile_notes_page.dart';

/// La copia local del móvil para la página del editor: lee del espejo de Drift
/// y escribe por el motor de sincronización, que es quien mete cada cambio en la
/// cola hacia la PC.
class DriftMobileNotesStore implements MobileNotesStore {
  const DriftMobileNotesStore(this._dao, this._engine);

  final NotesMirrorDao _dao;
  final NotesSyncEngine _engine;

  static MirrorNote _note(NoteMirrorData row) => MirrorNote(
    path: row.path,
    content: row.content,
    localHash: row.localHash,
    private: row.private,
    updatedAt: row.updatedAt,
    conflictContent: row.conflictContent,
    conflictHash: row.conflictHash,
  );

  @override
  Future<List<MirrorNote>> all() async =>
      (await _dao.all()).map(_note).toList();

  @override
  Future<MirrorNote?> byPath(String path) async {
    final row = await _dao.byPath(path);
    return row == null ? null : _note(row);
  }

  @override
  Stream<void> changes() => _dao.watchAll().map((_) {});

  @override
  Future<void> save(String path, String content) =>
      _engine.saveNote(path, content);

  @override
  Future<void> keepMine(String path) => _engine.keepMine(path);

  @override
  Future<void> takeHost(String path) => _engine.takeHost(path);

  @override
  Future<void> sync() => _engine.sync();
}
