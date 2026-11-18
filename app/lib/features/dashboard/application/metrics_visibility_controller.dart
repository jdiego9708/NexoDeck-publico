import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';

const _kMetricsCollapsedSettingKey = 'metrics_collapsed';

/// Si el panel de metricas esta plegado. Es preferencia de usuario, no
/// layout, asi que vive en `app_settings` (clave/valor) igual que el tema y
/// el modo de ventana -- no necesita tabla ni migracion propia.
///
/// El valor inicial real lo decide `main()` antes de `runApp` y se inyecta
/// con `overrideWith` en el `ProviderScope`, mismo patron que
/// `themeModeProvider` (ver `theme_mode_controller.dart`).
final metricsCollapsedProvider = StateProvider<bool>((ref) => false);

final metricsVisibilityControllerProvider =
    Provider<MetricsVisibilityController>((ref) {
      final db = ref.watch(databaseProvider);
      return MetricsVisibilityController(ref, AppSettingsDao(db));
    });

class MetricsVisibilityController {
  MetricsVisibilityController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> toggle() => setCollapsed(!_ref.read(metricsCollapsedProvider));

  Future<void> setCollapsed(bool collapsed) async {
    _ref.read(metricsCollapsedProvider.notifier).state = collapsed;
    await _dao.setValue(_kMetricsCollapsedSettingKey, collapsed.toString());
  }
}

/// Lee la ultima preferencia guardada antes de `runApp`, para no mostrar un
/// frame con las metricas abiertas si el usuario las habia plegado.
Future<bool> readInitialMetricsCollapsed(AppSettingsDao dao) async {
  return await dao.getValue(_kMetricsCollapsedSettingKey) == 'true';
}
