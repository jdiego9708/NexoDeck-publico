import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/daos/profile_actions_dao.dart';
import 'package:nexodeck/data/local/daos/profiles_dao.dart';
import 'package:nexodeck/src/rust/api/foreground.dart' as bridge;

import '../../../core/di/database_provider.dart';
import '../data/profiles_repository.dart';
import '../domain/deck_profile.dart';

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ProfilesRepository(ProfilesDao(db), ProfileActionsDao(db));
});

final profilesListProvider = StreamProvider<List<DeckProfile>>((ref) {
  return ref.watch(profilesRepositoryProvider).watchAll();
});

/// Ids de las acciones que componen un perfil. Familia por id de perfil:
/// lo usan tanto el filtro del deck (para el perfil activo) como el editor
/// (para el perfil que se esta editando).
final profileActionIdsProvider = StreamProvider.family<Set<String>, String>((
  ref,
  profileId,
) {
  return ref.watch(profilesRepositoryProvider).watchActionIds(profileId);
});

/// Aplicacion en primer plano de la PC. Rust emite **solo cuando cambia**
/// (ver `watch_foreground_app`), asi que el dedupe por `==` de Riverpod no
/// se come nada util: aca el valor ES un estado, no una secuencia de
/// eventos que haya que contar.
///
/// En Android este stream no aplica (la deteccion es del proceso de la PC);
/// no se monta ahi.
final foregroundAppProvider = StreamProvider<bridge.ForegroundApp?>((ref) {
  return bridge.watchForegroundApp();
});
