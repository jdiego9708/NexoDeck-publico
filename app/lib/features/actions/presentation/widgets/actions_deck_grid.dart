import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../ai_assistant/application/ai_enabled_controller.dart';
import '../../../ai_assistant/presentation/ai_assistant_dialog.dart';
import '../../../profiles/application/visible_actions_provider.dart';
import '../../application/action_groups_provider.dart';
import '../../application/actions_provider.dart';
import '../../domain/deck_action.dart';
import '../../domain/macro_plan.dart';
import '../action_editor_sheet.dart';
import '../run_action.dart';
import 'action_card.dart';
import 'action_group_filter_bar.dart';
import 'deck_grid_layout.dart';

/// Retraso entre la entrada animada de cada tarjeta consecutiva, acotado
/// para que una grilla grande no tarde en terminar de aparecer.
const _kStaggerStep = AppDuration.staggerFast;
const _kMaxStaggerSteps = AppMotion.maxStaggerSteps;

/// Grilla de acciones ejecutables -- el "deck" propiamente dicho. Sin
/// `Scaffold`/`AppBar` propios para poder incrustarse junto a la fila de
/// metricas en una sola pantalla (ver `main.dart`).
class ActionsDeckGrid extends ConsumerWidget {
  const ActionsDeckGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ya filtradas por el perfil activo (ver `visibleActionsProvider`).
    final actions = ref.watch(visibleActionsProvider);
    final selectedGroup = ref.watch(selectedActionGroupProvider);
    // La IA es opt-in (menu "Mas" > Asistente de IA). Con el flag apagado no
    // se ofrece el atajo: abrirlo dispararia el probe de hardware y, desde el
    // wizard, la descarga del modelo.
    final aiEnabled = ref.watch(aiEnabledProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: ActionGroupFilterBar(),
        ),
        Expanded(
          child: actions.when(
            data: (all) {
              // Segundo filtro, que se compone con el del perfil: los
              // grupos son una categoria visual DENTRO del deck, no
              // deciden que acciones lo componen.
              final list = selectedGroup == null
                  ? all
                  : all.where((a) => a.groupId == selectedGroup).toList();
              if (list.isEmpty) {
                return selectedGroup == null
                    ? EmptyState(
                        icon: Icons.bolt_outlined,
                        title: 'Tu deck esta vacio',
                        message:
                            'Crea tu primera accion para lanzarla desde aca '
                            'o desde el telefono.',
                        // La IA primero: quien tiene el deck vacio es
                        // justamente quien todavia no sabe que comando
                        // escribir, que es el publico al que apunta el
                        // asistente. Si esta desactivada, el estado vacio
                        // vuelve a tener un solo boton.
                        action: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (aiEnabled) ...[
                              FilledButton.icon(
                                onPressed: () => showAiAssistantDialog(context),
                                icon: const Icon(Icons.auto_awesome, size: 18),
                                label: const Text('Crear con IA'),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            FilledButton.tonalIcon(
                              onPressed: () => showActionEditorSheet(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Nueva accion'),
                            ),
                          ],
                        ),
                      )
                    : EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Este grupo esta vacio',
                        message:
                            'Ninguna accion esta asignada a este grupo '
                            'todavia.',
                        action: FilledButton.tonal(
                          onPressed: () => ref
                              .read(selectedActionGroupProvider.notifier)
                              .state = null,
                          child: const Text('Ver todas'),
                        ),
                      );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  const padding = AppSpacing.md;
                  const spacing = AppSpacing.sm;
                  final availableWidth = constraints.maxWidth - padding * 2;
                  final availableHeight = constraints.maxHeight - padding * 2;
                  final columns = bestColumnCountForAspect(
                    itemCount: list.length,
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    spacing: spacing,
                  );
                  final rows = (list.length / columns).ceil();
                  final cellHeight =
                      (availableHeight - spacing * (rows - 1)) / rows;

                  return GridView.builder(
                    padding: const EdgeInsets.all(padding),
                    // `mainAxisExtent` y no `childAspectRatio`: pedir el
                    // alto exacto evita el viaje de ida y vuelta por una
                    // relacion de aspecto (`cellWidth / cellHeight`, y
                    // despues `crossAxisExtent / aspectRatio` adentro del
                    // delegate) donde el redondeo de punto flotante puede
                    // perder una fraccion de pixel. Encontrado en vivo: con
                    // el riel de metricas muy ancho -- el deck cae a 2
                    // columnas -- las tarjetas desbordaban exactamente 0.5 px
                    // abajo, la marca tipica de esa perdida.
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      mainAxisExtent: cellHeight,
                    ),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final action = list[index];
                      return ActionCard(
                        action: action,
                        // Se resuelve contra `all` y no contra `list`: los
                        // pasos de una macro pueden estar en otro grupo, y
                        // `list` viene filtrada.
                        promptParamCount: promptParametersFor(
                          action,
                          all,
                        ).length,
                        entryDelay:
                            _kStaggerStep * index.clamp(0, _kMaxStaggerSteps),
                        onExecute: () => runDeckAction(context, ref, action),
                        onEdit: () =>
                            showActionEditorSheet(context, existing: action),
                        onDelete: () => _confirmDelete(context, ref, action),
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) =>
                Center(child: Text('Error cargando acciones: $error')),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DeckAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar accion'),
        content: Text('¿Eliminar "${action.name}"? Esto no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(actionsRepositoryProvider).deleteAction(action.id);
    }
  }
}
