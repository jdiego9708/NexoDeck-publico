import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stack/application/stack_controller.dart';
import '../../stack/domain/stack_profile.dart';
import '../data/stack_catalog_repository.dart';
import '../domain/ai_profile.dart';

/// Estado de la pantalla «Configura tus perfiles»: la configuracion guardada,
/// el catalogo de roles del stack y (si se pidio) que hay descargado en WSL2.
class AiProfilesState {
  const AiProfilesState({
    this.config = AiProfilesConfig.defaults,
    this.catalog = const [],
    this.detection = StackDetection.empty,
    this.loading = true,
    this.detecting = false,
    this.detected = false,
  });

  final AiProfilesConfig config;
  final List<StackModel> catalog;
  final StackDetection detection;
  final bool loading;
  final bool detecting;

  /// Si ya se consulto WSL2 alguna vez. Sin esto, antes de detectar se diria
  /// «falta descargar» de todo, que es afirmar algo que no se miro.
  final bool detected;

  /// El modelo del stack con ese rol, si el catalogo lo declara.
  StackModel? stackModelByRole(String? role) {
    if (role == null) return null;
    for (final model in catalog) {
      if (model.role == role && !model.alternative) return model;
    }
    return null;
  }

  bool isStackRoleInstalled(String? role) {
    final model = stackModelByRole(role);
    return model != null && detection.installedDirs.contains(model.dir);
  }

  /// Si el perfil puede arrancar el stack: todos sus slots `stack` tienen el
  /// modelo descargado. Un slot de otro motor (llama.cpp, Ollama, remoto,
  /// Claude Code) no depende de `~/models`, asi que no lo bloquea.
  ///
  /// Solo tiene sentido cuando `detected` (y sin error): antes de mirar WSL2,
  /// `installedDirs` esta vacio y diria que falta todo, que es afirmar algo que
  /// no se comprobo.
  bool isProfileRunnable(String profile) {
    final cfg = config.forProfile(profile);
    for (final slot in [cfg.router, cfg.thinking]) {
      if (slot.isStack && !isStackRoleInstalled(slot.model)) return false;
    }
    return true;
  }

  AiProfilesState copyWith({
    AiProfilesConfig? config,
    List<StackModel>? catalog,
    StackDetection? detection,
    bool? loading,
    bool? detecting,
    bool? detected,
  }) => AiProfilesState(
    config: config ?? this.config,
    catalog: catalog ?? this.catalog,
    detection: detection ?? this.detection,
    loading: loading ?? this.loading,
    detecting: detecting ?? this.detecting,
    detected: detected ?? this.detected,
  );
}

/// Lee y escribe `profiles.json` en la carpeta del stack, y detecta (al abrir
/// la pantalla de perfiles) que modelos hay descargados en WSL2. Ver
/// [StackCatalogRepository].
class AiProfilesController extends Notifier<AiProfilesState> {
  @override
  AiProfilesState build() {
    // Reacciona a que el usuario cambie la carpeta del stack: se relee sola.
    final dir = ref.watch(stackScriptsDirProvider);
    // Cuando una descarga lanzada desde el selector termina, se vuelve a mirar
    // `~/models` para que el tile pase a «Descargado» sin pulsar «Detectar».
    ref.listen(stackDownloadingProvider, (previous, next) {
      if (previous == true && next == false) {
        detectInstalled();
      }
    });
    Future.microtask(() => _load(dir));
    return const AiProfilesState();
  }

  Future<void> _load(String dir) async {
    final repository = StackCatalogRepository(dir);
    final profiles = await repository.readProfiles();
    final catalog = await repository.readCatalog();
    state = state.copyWith(config: profiles, catalog: catalog, loading: false);
  }

  /// Recarga a mano (boton de refrescar).
  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    await _load(ref.read(stackScriptsDirProvider));
  }

  /// Guarda el perfil completo. Devuelve `null` si salio bien o el motivo.
  Future<String?> save(String profile, AiProfileConfig config) async {
    final repository = StackCatalogRepository(
      ref.read(stackScriptsDirProvider),
    );
    final next = state.config.withProfile(profile, config);
    final error = await repository.writeProfiles(next);
    if (error == null) {
      state = state.copyWith(config: next);
    }
    return error;
  }

  /// Consulta WSL2 al abrir la pantalla de perfiles. **No la levanta**: si la
  /// distro esta apagada lo dice, en vez de arrancarla solo por mirar.
  Future<void> detectInstalled() async {
    state = state.copyWith(detecting: true);
    final repository = StackCatalogRepository(
      ref.read(stackScriptsDirProvider),
    );
    final detection = await repository.detectInstalled(
      distro: ref.read(stackDistroProvider),
    );
    state = state.copyWith(
      detection: detection,
      detecting: false,
      detected: true,
    );
  }
}

final aiProfilesProvider =
    NotifierProvider<AiProfilesController, AiProfilesState>(
      AiProfilesController.new,
    );

/// Texto con los **modelos elegidos** por un perfil, para el menu de modo del
/// chat. Se recalcula con la config, asi que refleja los cambios al instante:
/// un perfil con los dos slots en la nube dice «Router: DeepSeek · Pensamiento:
/// DeepSeek», y uno local, el nombre de sus modelos. Para «Apagado» no hay
/// perfil y lo dice.
String describeProfileModels(AiProfilesState state, StackProfile profile) {
  final name = profile.profileName;
  if (name == null) return 'Se libera la GPU';

  final config = state.config.forProfile(name);
  String slotText(ProfileSlot slot) {
    if (slot.isStack) {
      final model = state.stackModelByRole(slot.model);
      return model?.label ?? slot.model ?? 'sin modelo';
    }
    if (slot.isRemote) {
      return slot.remoteDisplayName ??
          slot.remoteModel ??
          'Servicio por internet';
    }
    return slot.label;
  }

  return 'Router: ${slotText(config.router)} · '
      'Pensamiento: ${slotText(config.thinking)}';
}
