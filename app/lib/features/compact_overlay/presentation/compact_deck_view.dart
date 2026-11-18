import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/actions/presentation/run_action.dart';
import 'package:nexodeck/features/actions/presentation/widgets/action_icons.dart';
import 'package:nexodeck/features/profiles/application/visible_actions_provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/interactive_card.dart';
import '../../dashboard/application/metrics_visibility_controller.dart';
import '../../dashboard/presentation/metrics_row.dart';
import '../../dashboard/presentation/widgets/metrics_panel.dart';
import 'widgets/compact_title_bar.dart';

/// Contenido del modo compacto: solo ejecutar acciones con un toque, sin
/// el chrome de edicion/CRUD de `ActionsDeckGrid` (eso vive en pantalla
/// completa). Esta es la vision de "deck" anclado del documento de
/// arquitectura.
class CompactDeckView extends ConsumerWidget {
  const CompactDeckView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Filtradas por el perfil activo, igual que el deck de pantalla
    // completa: el modo compacto es justamente el que se usa mientras se
    // trabaja en otra app, o sea donde mas sentido tiene el auto-cambio.
    final actions = ref.watch(visibleActionsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const CompactTitleBar(),
          // Mismo pipeline de metricas que la pantalla completa y que el
          // telefono (`buildMetricSpecs`), en su forma minima: una fila de
          // grafico + valor. Ver `MetricsPanelAxis.microStrip`.
          //
          // El alto es fijo y no proporcional como en pantalla completa: la
          // ventana compacta mide ~460 dp de alto y un 20% de eso (92 dp)
          // seria mas alto que dos filas de acciones.
          SizedBox(
            height: ref.watch(metricsCollapsedProvider)
                ? AppSizes.collapsedMetricsExtent
                : AppSizes.microMetricStripHeight,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: MetricsRow(axis: MetricsPanelAxis.microStrip),
            ),
          ),
          Expanded(
            child: actions.when(
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.bolt_outlined,
                      title: 'Sin acciones',
                      message: 'Crealas en pantalla completa.',
                    )
                  : GridView.count(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      children: [
                        for (final action in list)
                          _CompactActionTile(action: action),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActionTile extends ConsumerWidget {
  const _CompactActionTile({required this.action});

  final DeckAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = colorFromHex(action.colorHex);
    // Misma reaccion al hover que el deck grande: en una ventana anclada de
    // 320 px, siempre encima del resto, saber que tile esta bajo el cursor
    // importa mas todavia.
    return InteractiveCard(
      accent: color,
      onTap: () => _execute(context, ref),
      semanticLabel: action.name,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              radius: 18,
              child: Icon(iconForName(action.icon), size: 18),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              action.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Mismo flujo que el deck de pantalla completa (prompt de parametros,
  /// progreso de macro y dialogo de error): una sola definicion en
  /// `run_action.dart`. Esta copia local no mostraba errores.
  Future<void> _execute(BuildContext context, WidgetRef ref) =>
      runDeckAction(context, ref, action);
}
