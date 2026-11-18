import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/widgets/app_brand.dart';
import '../../application/window_mode_controller.dart';

/// Barra minima para el modo compacto (sin decoracion nativa de ventana):
/// arrastrar para mover, y un boton para volver a pantalla completa.
class CompactTitleBar extends ConsumerWidget {
  const CompactTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: AppSizes.compactTitleBarHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: Border(bottom: AppSurface.hairline(scheme)),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            // El mismo lockup que el AppBar de pantalla completa, en chico:
            // los dos modos son la misma app y tienen que verse asi.
            const NexoDeckWordmark(markSize: 16),
            const Spacer(),
            IconButton(
              iconSize: 16,
              tooltip: 'Pantalla completa',
              icon: const Icon(Icons.open_in_full),
              onPressed: () => ref
                  .read(windowModeControllerProvider)
                  .switchTo(WindowMode.fullscreen),
            ),
            IconButton(
              iconSize: 16,
              tooltip: 'Cerrar',
              // Hover rojo, convencion de Windows. Sin esto los dos botones
              // son indistinguibles y cerrar la ventana por error es facil.
              style: IconButton.styleFrom(
                hoverColor: scheme.error.withValues(alpha: 0.14),
              ),
              icon: const Icon(Icons.close),
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}
