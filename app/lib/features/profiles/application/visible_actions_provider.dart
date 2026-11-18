import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/application/actions_provider.dart';
import '../../actions/domain/deck_action.dart';
import 'active_profile_controller.dart';
import 'profiles_provider.dart';

/// Las acciones que componen el deck **segun el perfil activo**.
///
/// Unica definicion de ese filtro: lo consumen el deck de pantalla completa
/// y el modo compacto. Tenerlo en cada widget garantizaba que en algun
/// momento uno de los dos dejara de respetar el perfil.
///
/// El filtro por *grupo* NO se aplica aca: es otra cosa (categoria visual
/// dentro del deck, con su barra de chips) y solo existe en la pantalla
/// completa.
///
/// **Un perfil sin acciones asignadas no filtra nada**: devuelve el deck
/// completo. Activar un perfil recien creado no puede dejar la pantalla
/// vacia sin explicacion -- el editor lo dice explicitamente al crearlo.
final visibleActionsProvider = Provider<AsyncValue<List<DeckAction>>>((ref) {
  final actions = ref.watch(actionsListProvider);
  final active = ref.watch(activeProfileProvider);
  if (active == null) return actions;

  final ids = ref.watch(profileActionIdsProvider(active.id)).value;
  if (ids == null || ids.isEmpty) return actions;

  return actions.whenData(
    (all) => all.where((a) => ids.contains(a.id)).toList(),
  );
});
