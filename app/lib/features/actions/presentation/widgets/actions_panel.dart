import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../profiles/application/visible_actions_provider.dart';
import '../../application/actions_panel_controller.dart';
import '../../domain/deck_action.dart';
import '../run_action.dart';
import 'action_icons.dart';
import 'deck_grid_layout.dart';

/// Panel de acciones **compacto** del centro de control.
///
/// Son los mismos comandos que el deck (filtrados por el perfil activo, ver
/// `visibleActionsProvider`), pero en tiles chicas de icono + etiqueta en una
/// sola linea, en 1 o 2 columnas segun el ancho. Reemplaza a
/// `ActionsDeckGrid` en esta pantalla: el deck grande se reserva para los otros
/// layouts.
class ActionsPanel extends ConsumerWidget {
  const ActionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(actionsPanelCollapsedProvider);
    if (collapsed) return const _CollapsedBar();

    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_Header(), Expanded(child: _ActionsGrid())],
    );
  }
}

/// Barrita que queda cuando el panel esta plegado, con el boton para volver a
/// mostrarlo. El chevron apunta hacia adentro (el panel vive contra el borde
/// derecho).
class _CollapsedBar extends ConsumerWidget {
  const _CollapsedBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: AppSizes.collapsedMetricsExtent,
      child: Center(
        child: IconButton(
          tooltip: 'Mostrar acciones',
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: () =>
              ref.read(actionsPanelControllerProvider).setCollapsed(false),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Acciones',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ocultar acciones',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: () =>
                ref.read(actionsPanelControllerProvider).setCollapsed(true),
          ),
        ],
      ),
    );
  }
}

class _ActionsGrid extends ConsumerWidget {
  const _ActionsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(visibleActionsProvider);
    return actions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.bolt_outlined,
            title: 'Sin acciones',
            message: 'Crea acciones para lanzarlas desde aca.',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            const padding = AppSpacing.sm;
            final columns = actionsPanelColumnsFor(
              constraints.maxWidth - padding * 2,
            );
            return GridView.builder(
              padding: const EdgeInsets.all(padding),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.xs,
                crossAxisSpacing: AppSpacing.xs,
                // Alto exacto y fijo: estas tiles no se estiran como las del
                // deck. Todas entran en una linea.
                mainAxisExtent: AppSizes.compactActionTileHeight,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) => _CompactActionTile(
                action: list[index],
                onTap: () => runDeckAction(context, ref, list[index]),
              ),
            );
          },
        );
      },
    );
  }
}

/// Tile chica: icono con el color de la accion + nombre, en una linea. Un solo
/// toque la ejecuta, igual que la tarjeta del deck.
class _CompactActionTile extends StatelessWidget {
  const _CompactActionTile({required this.action, required this.onTap});

  final DeckAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFromHex(action.colorHex);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadius.badge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Icon(iconForName(action.icon), size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  action.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
