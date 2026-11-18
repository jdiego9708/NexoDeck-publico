import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/src/rust/api/docs.dart' as docs_bridge;

import '../../../core/di/database_provider.dart';
import 'ai_providers.dart';

const _kAiEnabledSettingKey = 'ai_enabled';

/// Si las funciones de IA estan habilitadas. **Arranca apagado siempre**: el
/// asistente descarga modelos de varios GB y levanta `llama-server` como
/// proceso hijo, asi que no puede ser algo que pase por defecto sin que el
/// usuario lo pida. Mientras esto sea `false` no se llama a ninguna funcion
/// del bridge de IA — ni siquiera al probe de capacidades, que inicializa
/// NVML y una instancia de Vulkan.
///
/// Es preferencia de usuario, no layout, asi que vive en `app_settings`
/// (clave/valor) igual que el tema y el plegado de metricas — sin tabla ni
/// migracion propia. El valor inicial real lo decide `main()` antes de
/// `runApp` y se inyecta con `overrideWith` en el `ProviderScope`, mismo
/// patron que `themeModeProvider` (ver `theme_mode_controller.dart`).
final aiEnabledProvider = StateProvider<bool>((ref) => false);

final aiEnabledControllerProvider = Provider<AiEnabledController>((ref) {
  final db = ref.watch(databaseProvider);
  return AiEnabledController(ref, AppSettingsDao(db));
});

class AiEnabledController {
  AiEnabledController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  Future<void> toggle() => setEnabled(!_ref.read(aiEnabledProvider));

  Future<void> setEnabled(bool enabled) async {
    _ref.read(aiEnabledProvider.notifier).state = enabled;
    await _dao.setValue(_kAiEnabledSettingKey, enabled.toString());

    // El buzon de documentacion usa el modelo local como respaldo, y con la IA
    // apagada no puede ni consultarlo. Se traga el fallo por lo mismo que abajo:
    // en Android el buzon no existe, y sin inicializar no hay nada que avisar.
    try {
      await docs_bridge.docsSetAiEnabled(enabled: enabled);
    } catch (_) {
      // Ignorado: ver arriba.
    }

    if (!enabled) {
      // Apagar el switch tiene que **matar el sidecar**, no solo esconder el
      // boton: si el usuario ya habia levantado el motor en esta sesion,
      // `llama-server` sigue vivo consumiendo VRAM hasta que se cierre la app.
      //
      // El fallo se traga a proposito: en Android el bridge de IA devuelve
      // "no soportado", y que el motor no estuviera corriendo tampoco es un
      // error que el usuario tenga que ver al apagar una preferencia.
      try {
        await _ref.read(aiRepositoryProvider).stop();
      } catch (_) {
        // Ignorado: ver arriba.
      }
    }
  }
}

/// Lee la ultima preferencia guardada antes de `runApp`, para que el primer
/// frame ya no muestre las entradas de IA si estan desactivadas.
///
/// Ausente (instalacion nueva) significa **desactivado**: la IA es opt-in.
Future<bool> readInitialAiEnabled(AppSettingsDao dao) async {
  return await dao.getValue(_kAiEnabledSettingKey) == 'true';
}
