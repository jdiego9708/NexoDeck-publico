import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';
import '../domain/home_layout.dart';

const _kHomeLayoutSettingKey = 'home_layout';

/// Layout activo de la pantalla principal. Es preferencia de usuario, no
/// estado de ventana, asi que vive en `app_settings` (clave/valor) igual que
/// el tema, el plegado de metricas y el flag de IA -- sin tabla ni migracion
/// propia.
///
/// El valor inicial real lo decide `main()` antes de `runApp` y se inyecta
/// con `overrideWith` en el `ProviderScope`: sin eso la app dibujaria un
/// frame con el layout por defecto antes de leer el guardado, y el salto se
/// ve.
final homeLayoutProvider = StateProvider<HomeLayout>(
  (ref) => HomeLayout.controlCenter,
);

final homeLayoutControllerProvider = Provider<HomeLayoutController>((ref) {
  final db = ref.watch(databaseProvider);
  return HomeLayoutController(ref, AppSettingsDao(db));
});

class HomeLayoutController {
  HomeLayoutController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  /// Avanza al siguiente de la rueda. Es lo que hace el boton de la barra.
  Future<void> cycle() => setLayout(_ref.read(homeLayoutProvider).next);

  Future<void> setLayout(HomeLayout layout) async {
    _ref.read(homeLayoutProvider.notifier).state = layout;
    await _dao.setValue(_kHomeLayoutSettingKey, layout.name);
  }
}

/// Lee el layout guardado antes de `runApp`.
Future<HomeLayout> readInitialHomeLayout(AppSettingsDao dao) async {
  return HomeLayout.fromName(await dao.getValue(_kHomeLayoutSettingKey));
}
