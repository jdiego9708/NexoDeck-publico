import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';
import '../domain/panel_split.dart';

/// Lo que el usuario dejo arrastrado, por panel. Un slot ausente significa
/// "nunca lo movio", y entonces manda el reparto que se calcula solo
/// ([PanelSlot.preferredExtent]).
///
/// Se guarda la **fraccion** y no el tamano en px -- el porque esta en
/// [PanelSlot]. Vive en `app_settings` (clave/valor), asi que no hay migracion
/// de Drift, mismo patron que el tema y el layout del home.
///
/// El valor inicial lo lee `main()` antes de `runApp` y se inyecta con
/// `overrideWith`: sin eso, el primer frame dibujaria el reparto por defecto y
/// los paneles saltarian a su tamano guardado un frame despues.
final panelSplitsProvider = StateProvider<Map<PanelSlot, double>>((ref) {
  return const {};
});

final panelSplitControllerProvider = Provider<PanelSplitController>((ref) {
  final db = ref.watch(databaseProvider);
  return PanelSplitController(ref, AppSettingsDao(db));
});

class PanelSplitController {
  PanelSplitController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  double? fractionOf(PanelSlot slot) => _ref.read(panelSplitsProvider)[slot];

  /// Mueve el divisor **sin escribir en la base**. Se llama en cada frame del
  /// arrastre, que son decenas por segundo: persistir ahi dentro seria una
  /// escritura a disco por frame, y ademas dejaria guardado cualquier punto
  /// intermedio si la app se cierra a mitad del gesto.
  void drag(PanelSlot slot, double fraction) {
    _ref.read(panelSplitsProvider.notifier).state = {
      ..._ref.read(panelSplitsProvider),
      slot: fraction,
    };
  }

  /// Guarda el reparto actual. Se llama al **soltar**, no durante el arrastre.
  Future<void> commit(PanelSlot slot) async {
    final fraction = fractionOf(slot);
    if (fraction == null) return;
    await _dao.setValue(slot.settingKey, fraction.toString());
  }

  /// Devuelve el panel a su reparto automatico. Es lo que hace el doble clic
  /// sobre el divisor: sin esto, un arrastre desafortunado no tendria vuelta
  /// atras salvo volviendo a acertarle al pixel.
  ///
  /// Guarda la cadena vacia en vez de borrar la fila porque
  /// [AppSettingsDao] no expone un borrado, y `double.tryParse('')` devuelve
  /// `null`, que es exactamente "nunca lo movio".
  Future<void> reset(PanelSlot slot) async {
    final next = {..._ref.read(panelSplitsProvider)}..remove(slot);
    _ref.read(panelSplitsProvider.notifier).state = next;
    await _dao.setValue(slot.settingKey, '');
  }
}

/// Lee los repartos guardados antes de `runApp`.
///
/// Un valor ilegible (una version vieja, una fila a medio escribir) se ignora
/// en vez de reventar el arranque, igual que `HomeLayout.fromName`: el panel
/// vuelve a su reparto automatico, que siempre es dibujable.
Future<Map<PanelSlot, double>> readInitialPanelSplits(
  AppSettingsDao dao,
) async {
  final splits = <PanelSlot, double>{};
  for (final slot in PanelSlot.values) {
    final raw = await dao.getValue(slot.settingKey);
    final fraction = raw == null ? null : double.tryParse(raw);
    // Una fraccion fuera de (0, 1) no describe ningun reparto posible.
    if (fraction != null && fraction > 0 && fraction < 1) {
      splits[slot] = fraction;
    }
  }
  return splits;
}
