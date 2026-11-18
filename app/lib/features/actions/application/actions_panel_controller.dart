import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';

const _kActionsPanelCollapsedKey = 'actions_panel_collapsed';

/// Si el panel de acciones del centro de control esta plegado.
///
/// Preferencia de usuario en `app_settings` (clave/valor), mismo patron que
/// `metrics_collapsed` y el layout del home: sin tabla ni migracion de Drift.
/// El valor inicial real lo lee `main()` antes de `runApp` y se inyecta con
/// `overrideWith`.
final actionsPanelCollapsedProvider = StateProvider<bool>((ref) => false);

final actionsPanelControllerProvider = Provider<ActionsPanelController>((ref) {
  final db = ref.watch(databaseProvider);
  return ActionsPanelController(ref, AppSettingsDao(db));
});

class ActionsPanelController {
  ActionsPanelController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> toggle() =>
      setCollapsed(!_ref.read(actionsPanelCollapsedProvider));

  Future<void> setCollapsed(bool collapsed) async {
    _ref.read(actionsPanelCollapsedProvider.notifier).state = collapsed;
    await _dao.setValue(_kActionsPanelCollapsedKey, collapsed.toString());
  }
}

/// Lee la ultima preferencia guardada antes de `runApp`.
Future<bool> readInitialActionsPanelCollapsed(AppSettingsDao dao) async {
  return await dao.getValue(_kActionsPanelCollapsedKey) == 'true';
}
