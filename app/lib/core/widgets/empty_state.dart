import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Estado vacio con badge, titulo, mensaje y una accion opcional.
///
/// Reusa deliberadamente el lenguaje visual del badge de
/// `action_error_dialog.dart` (circulo tonal + icono grande): que los
/// estados "no hay nada" y "algo fallo" se vean de la misma familia es lo
/// que hace que la app parezca disenada por una sola mano, en vez de textos
/// pelados distintos en cada pantalla.
///
/// Trae variante compacta automatica: si el alto disponible no alcanza,
/// omite el badge en vez de desbordar. Eso lo hace usable tambien en el
/// telefono apaisado y en la ventana compacta de 320x460.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Reemplaza el badge del icono. Sirve para distinguir "esperando" (con un
  /// indicador de progreso) de "vacio".
  final Widget? leading;

  /// Alto por debajo del cual se omite el badge.
  static const _compactBelow = 160.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < _compactBelow;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    leading ??
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Icon(
                            icon,
                            size: 28,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (action != null && !compact) ...[
                    const SizedBox(height: AppSpacing.gutter),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
