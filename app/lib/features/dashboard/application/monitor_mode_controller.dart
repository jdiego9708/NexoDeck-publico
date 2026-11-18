import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';

const _kMonitorModeSettingKey = 'monitor_mode';

/// Modo monitor del telefono: se esconde el deck de acciones y las metricas
/// de la PC se quedan con la pantalla entera.
///
/// Es un **modo de uso**, no un plegado momentaneo: el telefono apoyado al
/// lado del monitor mostrando CPU, RAM, disco, GPU y red. Por eso se persiste
/// en `app_settings` --igual que el tema, el plegado de metricas y el layout
/// del Home-- y no en el `State` de la pantalla: al volver a abrir la app
/// sigue haciendo lo que se le pidio.
///
/// Ausente = apagado: una instalacion nueva arranca con el deck.
///
/// Solo lo mira `ConnectedDeviceScreen` (rol Android). En escritorio no
/// aplica: ahi el reparto entre metricas y deck lo eligen los cuatro
/// `HomeLayout`.
final monitorModeProvider = StateProvider<bool>((ref) => false);

final monitorModeControllerProvider = Provider<MonitorModeController>((ref) {
  final db = ref.watch(databaseProvider);
  return MonitorModeController(ref, AppSettingsDao(db));
});

class MonitorModeController {
  MonitorModeController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> toggle() => setEnabled(!_ref.read(monitorModeProvider));

  Future<void> setEnabled(bool enabled) async {
    _ref.read(monitorModeProvider.notifier).state = enabled;
    await _dao.setValue(_kMonitorModeSettingKey, enabled.toString());
  }
}

/// Lee la ultima preferencia guardada antes de `runApp`, para no mostrar un
/// frame con el deck cuando el telefono habia quedado como monitor.
Future<bool> readInitialMonitorMode(AppSettingsDao dao) async {
  return await dao.getValue(_kMonitorModeSettingKey) == 'true';
}
