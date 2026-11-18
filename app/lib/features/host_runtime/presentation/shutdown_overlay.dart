import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_brand.dart';
import '../application/shutdown_controller.dart';

/// Pantalla de apagado. Cubre la ventana mientras se detiene lo pesado (el
/// asistente, el servidor de control, el tunel…) para que el cierre no se
/// sienta "colgado": la ventana sigue viva y contando que esta pasando.
class ShutdownOverlay extends ConsumerWidget {
  const ShutdownOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuttingDown = ref.watch(shuttingDownProvider);
    final step = ref.watch(shutdownStepProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (shuttingDown) _ShutdownScene(step: step),
      ],
    );
  }
}

class _ShutdownScene extends StatefulWidget {
  const _ShutdownScene({required this.step});

  final String step;

  @override
  State<_ShutdownScene> createState() => _ShutdownSceneState();
}

class _ShutdownSceneState extends State<_ShutdownScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: AppDuration.entrySlow,
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FadeTransition(
      opacity: _entrance,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ColoredBox(
          color: scheme.surface.withValues(alpha: 0.6),
          child: Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(
                CurvedAnimation(parent: _entrance, curve: AppCurves.emphasized),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NexoDeckWordmark(markSize: 46, showText: false),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Apagando NexoDeck…',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AnimatedSwitcher(
                    duration: AppDuration.selection,
                    switchInCurve: AppCurves.emphasized,
                    switchOutCurve: AppCurves.standard,
                    child: Text(
                      widget.step,
                      key: ValueKey(widget.step),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
