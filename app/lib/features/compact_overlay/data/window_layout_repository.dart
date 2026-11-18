import 'package:drift/drift.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/data/local/daos/window_layouts_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:uuid/uuid.dart';

/// Clave en `app_settings` para recordar que modo estaba activo entre
/// reinicios (la tabla `window_layouts` guarda posicion/tamano *por* modo,
/// pero no cual era el modo activo -- eso es una preferencia global, no
/// datos de layout).
const kWindowModeSettingKey = 'window_mode';

class PersistedWindowLayout {
  const PersistedWindowLayout({
    required this.posX,
    required this.posY,
    required this.width,
    required this.height,
    this.monitorId,
  });

  final double posX;
  final double posY;
  final double width;
  final double height;
  final String? monitorId;
}

class WindowLayoutRepository {
  WindowLayoutRepository(this._layoutsDao, this._settingsDao);

  final WindowLayoutsDao _layoutsDao;
  final AppSettingsDao _settingsDao;

  Future<PersistedWindowLayout?> getLayout(WindowMode mode) async {
    final row = await _layoutsDao.getForMode(mode);
    if (row == null) return null;
    return PersistedWindowLayout(
      posX: row.posX,
      posY: row.posY,
      width: row.width,
      height: row.height,
      monitorId: row.monitorId,
    );
  }

  /// Upsert manual por `mode` -- `WindowLayouts.id` es la PK real (no
  /// `mode`), asi que `insertOnConflictUpdate` por si solo insertaria una
  /// fila nueva cada vez en vez de actualizar. Se reusa el id existente si
  /// ya hay un layout guardado para este modo.
  Future<void> saveLayout(
    WindowMode mode, {
    required double posX,
    required double posY,
    required double width,
    required double height,
    String? monitorId,
    bool alwaysOnTop = false,
  }) async {
    final existing = await _layoutsDao.getForMode(mode);
    await _layoutsDao.saveLayout(
      WindowLayoutsCompanion(
        id: Value(existing?.id ?? const Uuid().v4()),
        mode: Value(mode),
        posX: Value(posX),
        posY: Value(posY),
        width: Value(width),
        height: Value(height),
        monitorId: Value(monitorId),
        alwaysOnTop: Value(alwaysOnTop),
      ),
    );
  }

  Future<WindowMode> getLastActiveMode() async {
    final value = await _settingsDao.getValue(kWindowModeSettingKey);
    return value == WindowMode.compact.name
        ? WindowMode.compact
        : WindowMode.fullscreen;
  }

  Future<void> setLastActiveMode(WindowMode mode) =>
      _settingsDao.setValue(kWindowModeSettingKey, mode.name);
}
