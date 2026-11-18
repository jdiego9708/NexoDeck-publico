import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';
import '../domain/deck_profile.dart';
import '../domain/profile_matching.dart';
import 'profiles_provider.dart';

const _kActiveProfileSettingKey = 'active_profile_id';

/// Perfil activo. `null` = "Todas las acciones" (sin filtrar): es el estado
/// por defecto y el que ve alguien que nunca creo un perfil, para que el
/// deck no aparezca vacio de la nada.
///
/// El valor inicial lo inyecta `main()` con [readInitialActiveProfileId],
/// mismo patron que `themeModeProvider` y `windowModeProvider`.
final activeProfileIdProvider = StateProvider<String?>((ref) => null);

/// El perfil activo ya resuelto contra la lista, o `null` si no hay ninguno
/// activo **o si el guardado ya no existe** (se borro entre dos sesiones).
final activeProfileProvider = Provider<DeckProfile?>((ref) {
  final id = ref.watch(activeProfileIdProvider);
  if (id == null) return null;
  final profiles = ref.watch(profilesListProvider).value ?? const [];
  for (final profile in profiles) {
    if (profile.id == id) return profile;
  }
  return null;
});

final activeProfileControllerProvider = Provider<ActiveProfileController>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return ActiveProfileController(ref, AppSettingsDao(db));
});

class ActiveProfileController {
  ActiveProfileController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  /// Cambio explicito del usuario (selector de la barra).
  ///
  /// Marca [_manualOverride], que **apaga la auto-deteccion hasta que el
  /// foco cambie a otra aplicacion**. Sin esto, elegir un perfil a mano con
  /// OBS abierto duraba menos de un segundo: el siguiente tick del detector
  /// volvia a imponer el perfil de OBS y el selector "rebotaba" solo, sin
  /// ninguna explicacion visible.
  Future<void> select(String? profileId) async {
    _manualOverride = true;
    await _apply(profileId);
  }

  /// Cambio automatico por deteccion de proceso. No toca el override.
  Future<void> _applyAutomatic(String? profileId) => _apply(profileId);

  Future<void> _apply(String? profileId) async {
    if (_ref.read(activeProfileIdProvider) == profileId) return;
    _ref.read(activeProfileIdProvider.notifier).state = profileId;
    // Cadena vacia y no `null`: `app_settings` es clave/valor y borrar la
    // clave haria que la proxima sesion no distinga "sin perfil" de "nunca
    // se eligio".
    await _dao.setValue(_kActiveProfileSettingKey, profileId ?? '');
  }

  bool _manualOverride = false;

  /// Ultimo proceso visto, para detectar el cambio de aplicacion que
  /// devuelve el control a la auto-deteccion.
  String? _lastProcess;

  /// Reacciona a un cambio de aplicacion en primer plano.
  ///
  /// El llamador (`HostRuntime`) ya filtro dos casos que NO son
  /// cambios de aplicacion a estos efectos: la propia ventana de NexoDeck y
  /// "no se puede saber". Ver el comentario largo alla.
  Future<void> onForegroundChanged(
    String? processName,
    List<DeckProfile> profiles,
  ) async {
    final changedApp = processName != _lastProcess;
    _lastProcess = processName;
    // Cambiar de ventana es la senal de que el usuario "solto" su eleccion
    // manual: a partir de ahi la auto-deteccion vuelve a mandar.
    if (changedApp) _manualOverride = false;
    if (_manualOverride) return;

    final match = profileForProcess(processName, profiles);
    // Que ninguna app matchee NO desactiva el perfil actual: pasar por el
    // explorador de archivos entre OBS y OBS no tiene por que vaciar el
    // deck. Solo se cambia cuando otro perfil reclama el foco.
    if (match == null) return;
    await _applyAutomatic(match.id);
  }
}

/// Lee el perfil activo guardado antes de `runApp`, para que el primer
/// frame ya muestre el deck correcto en vez de parpadear con todas las
/// acciones.
Future<String?> readInitialActiveProfileId(AppSettingsDao dao) async {
  final stored = await dao.getValue(_kActiveProfileSettingKey);
  if (stored == null || stored.isEmpty) return null;
  return stored;
}
