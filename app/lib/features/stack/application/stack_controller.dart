import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge;

import '../../../core/di/database_provider.dart';
import '../../run_center/application/run_center_controller.dart';
import '../domain/stack_profile.dart';

const _kStackScriptsDirKey = 'stack_scripts_dir';
const _kStackProfileKey = 'stack_profile';
const _kStackDistroKey = 'stack_distro';

/// Nombre de la distro de WSL2 donde vive el stack. Es configurable porque el
/// usuario puede haberle puesto otro nombre al instalar Ubuntu.
const kDefaultStackDistro = 'Ubuntu';

/// Carpeta con los scripts del stack (`Start-Stack.ps1`, `Stop-Stack.ps1`).
///
/// Es configurable porque no vive junto a la app: en la maquina de desarrollo
/// esta en el repo, y en otra instalacion el usuario la apunta donde tenga el
/// stack. El default es el del repo --el unico que se conoce-- y se puede
/// cambiar desde el engranaje del switch.
const kDefaultStackScriptsDir = r'D:\Repositorios\NexoDeck\llm-stack\scripts';

/// Prefijo de la etiqueta con la que el switch lanza el comando del stack en el
/// panel de ejecuciones. **Una sola definicion**: de aca sale el texto que ve
/// el usuario y el filtro que decide si el stack esta arrancando.
const kStackRunLabelPrefix = 'Stack: ';

/// Prefijo de la etiqueta de una **descarga** de modelo del stack. Distinto del
/// de arranque a proposito: bajar un modelo no pelea por la GPU, asi que no
/// tiene que bloquear el switch de perfil (ver `stackStartingProvider`).
const kModelDownloadLabelPrefix = 'Descarga: ';

/// Preferencias del stack. Viven en `app_settings` (clave/valor), sin
/// migracion de Drift, mismo patron que el tema y el layout.
final stackScriptsDirProvider = StateProvider<String>(
  (ref) => kDefaultStackScriptsDir,
);

/// Nombre de la distro de WSL2 del stack (`Ubuntu` por defecto).
final stackDistroProvider = StateProvider<String>((ref) => kDefaultStackDistro);

/// El ultimo perfil elegido. **Ojo:** es la eleccion del usuario, no lo que
/// esta corriendo; lo que de verdad hay levantado lo dice `stackHealthProvider`
/// (la pasarela). Ausente = `apagado`.
final selectedStackProfileProvider = StateProvider<StackProfile>(
  (ref) => StackProfile.apagado,
);

final stackControllerProvider = Provider<StackController>((ref) {
  final db = ref.watch(databaseProvider);
  return StackController(ref, AppSettingsDao(db));
});

class StackController {
  StackController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  /// Arranca o para el perfil: guarda la eleccion y lanza el script por el
  /// **runner de comandos capturados**, que es el mismo que usa el deck. El
  /// progreso y la salida salen por el Panel de Ejecuciones y el aviso, sin
  /// maquinaria nueva.
  ///
  /// Devuelve el motivo si no se pudo lanzar (carpeta sin configurar), o
  /// `null` si el run quedo en marcha.
  Future<String?> select(StackProfile profile) async {
    _ref.read(selectedStackProfileProvider.notifier).state = profile;
    await _dao.setValue(_kStackProfileKey, profile.name);

    final dir = _ref.read(stackScriptsDirProvider).trim();
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      return 'No encuentro la carpeta del stack: "$dir". '
          'Configurala con el engranaje del switch.';
    }

    try {
      await bridge.startCapturedCommand(
        label: '$kStackRunLabelPrefix${profile.label}',
        command: stackCommandFor(profile, dir),
        terminalType: bridge.TerminalType.powerShell,
        requiresAdmin: false,
      );
    } catch (error) {
      return 'No se pudo lanzar el stack: $error';
    }
    return null;
  }

  /// Para el stack **sin** poner el MODO en «Apagado».
  ///
  /// Se usa cuando el perfil elegido no tiene ningun rol local (todo
  /// nube/Ollama/Claude): no hay vLLM que arrancar, pero si que **liberar** la
  /// GPU y la RAM de WSL2 de un perfil local anterior. El MODO sigue mostrando
  /// `profile`, para que elegir «Perfil C» no acabe diciendo «Apagado».
  Future<String?> stopStackKeeping(StackProfile profile) async {
    _ref.read(selectedStackProfileProvider.notifier).state = profile;
    await _dao.setValue(_kStackProfileKey, profile.name);

    final dir = _ref.read(stackScriptsDirProvider).trim();
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      return 'No encuentro la carpeta del stack: "$dir". '
          'Configurala con el engranaje del switch.';
    }

    try {
      await bridge.startCapturedCommand(
        label: '$kStackRunLabelPrefix${profile.label}',
        command: stackCommandFor(StackProfile.apagado, dir),
        terminalType: bridge.TerminalType.powerShell,
        requiresAdmin: false,
      );
    } catch (error) {
      return 'No se pudo parar el stack: $error';
    }
    return null;
  }

  /// Descarga un modelo del stack (baja los pesos que falten para ese rol).
  ///
  /// Lo lanza el selector de modelos cuando un rol del stack sale «Falta
  /// descargar». Va por el **runner de comandos capturados**, asi que el
  /// progreso sale en el panel de Ejecuciones, igual que el arranque del stack.
  /// Devuelve el motivo si no se pudo lanzar, o `null` si el run quedo en marcha.
  Future<String?> download(String role) async {
    final dir = _ref.read(stackScriptsDirProvider).trim();
    if (dir.isEmpty || !Directory(dir).existsSync()) {
      return 'No encuentro la carpeta del stack: "$dir". '
          'Configurala con el engranaje del switch.';
    }

    try {
      await bridge.startCapturedCommand(
        label: '$kModelDownloadLabelPrefix$role',
        command: stackDownloadCommandFor(role, dir),
        terminalType: bridge.TerminalType.powerShell,
        requiresAdmin: false,
      );
    } catch (error) {
      return 'No se pudo lanzar la descarga: $error';
    }
    return null;
  }

  Future<void> setScriptsDir(String dir) async {
    final clean = dir.trim();
    _ref.read(stackScriptsDirProvider.notifier).state = clean;
    await _dao.setValue(_kStackScriptsDirKey, clean);
  }

  Future<void> setDistro(String distro) async {
    final clean = distro.trim();
    _ref.read(stackDistroProvider.notifier).state = clean;
    await _dao.setValue(_kStackDistroKey, clean);
  }
}

/// Lee el nombre de la distro guardado, antes de `runApp`.
Future<String> readInitialStackDistro(AppSettingsDao dao) async {
  final distro = await dao.getValue(_kStackDistroKey);
  return (distro == null || distro.trim().isEmpty)
      ? kDefaultStackDistro
      : distro.trim();
}

/// Lee lo guardado antes de `runApp`.
Future<(String dir, StackProfile profile)> readInitialStackPreferences(
  AppSettingsDao dao,
) async {
  final dir = await dao.getValue(_kStackScriptsDirKey);
  final profile = await dao.getValue(_kStackProfileKey);
  return (
    (dir == null || dir.trim().isEmpty) ? kDefaultStackScriptsDir : dir,
    StackProfile.fromName(profile),
  );
}

/// **El stack esta arrancando o parando**: hay un comando del stack corriendo
/// en el centro de ejecuciones.
///
/// `Start-Stack.ps1` no vuelve hasta que los modelos estan cargados (2-6 min),
/// asi que mientras ese run siga vivo no se puede ni preguntar al asistente ni
/// cambiar de perfil: lo primero daria un 503 y lo segundo dos arranques
/// peleandose por la GPU.
///
/// Es el estado REAL (el run), no la eleccion del usuario: elegir «Perfil A»
/// guarda la preferencia al instante, pero el bloqueo dura lo que dura el
/// proceso.
final stackStartingProvider = Provider<bool>((ref) {
  return ref.watch(
    runCenterProvider.select(
      (state) => state.runs.any(
        (run) => run.isActive && run.label.startsWith(kStackRunLabelPrefix),
      ),
    ),
  );
});

/// Hay una **descarga** de modelo del stack en marcha. Lo usa el selector para
/// poner «Descargando…» y para volver a mirar WSL2 cuando la descarga termina.
final stackDownloadingProvider = Provider<bool>((ref) {
  return ref.watch(
    runCenterProvider.select(
      (state) => state.runs.any(
        (run) =>
            run.isActive && run.label.startsWith(kModelDownloadLabelPrefix),
      ),
    ),
  );
});

/// El **rol** del modelo que se esta descargando ahora mismo, o `null`.
///
/// El selector lo usa para que la barra de progreso sobreviva a cerrar y
/// reabrir la hoja: al montarse, si el rol activo es el suyo, arranca el sondeo
/// sin haber pulsado nada en esta sesion de la hoja.
final activeStackDownloadRoleProvider = Provider<String?>((ref) {
  return ref.watch(
    runCenterProvider.select((state) {
      for (final run in state.runs) {
        if (run.isActive && run.label.startsWith(kModelDownloadLabelPrefix)) {
          return run.label.substring(kModelDownloadLabelPrefix.length);
        }
      }
      return null;
    }),
  );
});
