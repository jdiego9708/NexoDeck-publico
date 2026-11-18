import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';

const _kThemeModeSettingKey = 'theme_mode';

/// Preferencia de modo claro/oscuro. El valor inicial real se decide en
/// `main()` (antes de `runApp`, leyendo la ultima preferencia guardada via
/// [readInitialThemeMode]) y se inyecta via `overrideWith` en el
/// `ProviderScope` -- mismo patron que `windowModeProvider` (ver
/// `window_mode_controller.dart`).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final themeModeControllerProvider = Provider<ThemeModeController>((ref) {
  final db = ref.watch(databaseProvider);
  return ThemeModeController(ref, AppSettingsDao(db));
});

class ThemeModeController {
  ThemeModeController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> toggle() {
    final current = _ref.read(themeModeProvider);
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    return setMode(next);
  }

  Future<void> setMode(ThemeMode mode) async {
    _ref.read(themeModeProvider.notifier).state = mode;
    await _dao.setValue(_kThemeModeSettingKey, mode.name);
  }
}

/// Lee la ultima preferencia guardada antes de `runApp` (mismo momento en
/// que `main()` lee `getLastActiveMode()` para la ventana), para no
/// mostrar un flash del tema equivocado en el primer frame.
Future<ThemeMode> readInitialThemeMode(AppSettingsDao dao) async {
  final stored = await dao.getValue(_kThemeModeSettingKey);
  return ThemeMode.values.firstWhere(
    (m) => m.name == stored,
    orElse: () => ThemeMode.system,
  );
}
