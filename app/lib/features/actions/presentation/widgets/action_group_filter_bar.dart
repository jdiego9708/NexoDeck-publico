import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../application/action_groups_provider.dart';
import '../action_group_editor_dialog.dart';
import 'action_icons.dart';

/// Barra horizontal de chips para filtrar la grilla de acciones por grupo:
/// "Todas" + un chip por grupo + boton para crear uno nuevo. Long-press en
/// un chip de grupo abre el editor (renombrar/cambiar color/eliminar).
class ActionGroupFilterBar extends ConsumerWidget {
  const ActionGroupFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(actionGroupsListProvider).value ?? const <ActionGroup>[];
    final selected = ref.watch(selectedActionGroupProvider);

    // Si el grupo seleccionado fue borrado, vuelve a "Todas" en vez de
    // quedar filtrando por un id que ya no existe.
    ref.listen(actionGroupsListProvider, (previous, next) {
      final list = next.value;
      if (list == null) return;
      final current = ref.read(selectedActionGroupProvider);
      if (current != null && !list.any((g) => g.id == current)) {
        ref.read(selectedActionGroupProvider.notifier).state = null;
      }
    });

    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: AppSizes.groupFilterBarHeight,
      // Fade en el borde derecho: sin esto, con muchos grupos la lista se
      // corta a filo contra el borde y no hay ninguna pista de que hay mas
      // para scrollear.
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: const [0.0, 0.92, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: const Text('Todas'),
                selected: selected == null,
                onSelected: (_) =>
                    ref.read(selectedActionGroupProvider.notifier).state = null,
              ),
            ),
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onLongPress: () =>
                        showActionGroupEditorDialog(context, existing: group),
                    // En escritorio nadie descubre un long-press: el click
                    // derecho es la forma natural de llegar al editor.
                    onSecondaryTap: () =>
                        showActionGroupEditorDialog(context, existing: group),
                    child: ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: colorFromHex(group.colorHex),
                        radius: AppSizes.groupDotRadius,
                      ),
                      label: Text(group.name),
                      selected: selected == group.id,
                      onSelected: (_) => ref
                          .read(selectedActionGroupProvider.notifier)
                          .state = group.id,
                    ),
                  ),
                ),
              ),
            // "Crear" no es un filtro mas: va en estilo outline (sin
            // relleno) para que se lea distinto de los chips que si filtran.
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Grupo'),
              backgroundColor: Colors.transparent,
              side: BorderSide(
                color: scheme.outlineVariant,
                style: BorderStyle.solid,
              ),
              onPressed: () => showActionGroupEditorDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
