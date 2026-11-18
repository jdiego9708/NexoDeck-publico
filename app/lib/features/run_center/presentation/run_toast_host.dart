import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/run_center_controller.dart';
import '../domain/command_run.dart';
import 'run_toast.dart';

/// Cuantos toasts se apilan a la vez. Pasado ese numero los mas viejos se
/// dejan de dibujar (siguen en el historial): una pila de 9 tarjetas tapa la
/// pantalla entera y deja de ser una notificacion.
const _kMaxStacked = 4;

/// Cada cuanto late el cronometro. 200 ms alcanza para que se vea fluido sin
/// reconstruir la pila 60 veces por segundo.
const _kTick = Duration(milliseconds: 200);

/// Capa que dibuja las notificaciones de ejecucion sobre toda la app.
///
/// Va instalada en `MaterialApp.builder`, no adentro de un `Scaffold`, por dos
/// razones: hay dos `Scaffold` disjuntos en escritorio (pantalla completa y
/// modo compacto) y ninguno de los dos esta vivo cuando el telefono pide
/// ejecutar una accion -- ese camino corre en `HostRuntime`, fuera del arbol
/// y sin `BuildContext`. Colgando de la raiz, una ejecucion remota aparece
/// igual.
///
/// Es **solo visual**: en modo solo telefono no se monta, y no pasa nada,
/// porque `runCenterProvider` lo enciende `main()` desde el arranque.
///
/// **Un solo `Timer` para toda la pila.** Un ticker por tarjeta significaria
/// un timer por notificacion, y son varias a la vez.
class RunToastHost extends ConsumerStatefulWidget {
  const RunToastHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RunToastHost> createState() => _RunToastHostState();
}

class _RunToastHostState extends ConsumerState<RunToastHost> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  /// Ids que ya tienen programado su auto-cierre, para no encolar dos.
  final Set<String> _scheduledDismiss = {};

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// El timer solo corre mientras hay algo vivo que cronometrar. Dejarlo
  /// siempre encendido reconstruiria la app 5 veces por segundo para siempre.
  void _syncTicker(bool needed) {
    if (needed && _ticker == null) {
      _ticker = Timer.periodic(_kTick, (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!needed && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  /// Programa el cierre automatico. Un **fallo nunca se auto-cierra**: es el
  /// unico caso en el que el usuario tiene algo que leer o que hacer.
  void _scheduleDismiss(CommandRun run) {
    if (_scheduledDismiss.contains(run.id)) return;
    final linger = switch (run.status) {
      RunStatus.succeeded => kSuccessToastLinger,
      RunStatus.launched => kLaunchedToastLinger,
      RunStatus.cancelled => kSuccessToastLinger,
      _ => null,
    };
    if (linger == null) return;
    _scheduledDismiss.add(run.id);
    Timer(linger, () {
      if (!mounted) return;
      ref.read(runCenterProvider.notifier).dismiss(run.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(runCenterProvider);
    final visible = state.visible;

    _syncTicker(state.hasActive);
    for (final run in visible) {
      if (!run.isActive) _scheduleDismiss(run);
    }

    final stacked = visible.take(_kMaxStacked).toList();

    return Stack(
      children: [
        widget.child,
        if (stacked.isNotEmpty)
          Positioned(
            right: AppSpacing.gutter,
            bottom: AppSpacing.gutter,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final run in stacked.reversed)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: _AnimatedToast(
                        key: ValueKey(run.id),
                        child: RunToast(
                          run: run,
                          now: _now,
                          onDismiss: () => ref
                              .read(runCenterProvider.notifier)
                              .dismiss(run.id),
                          onCancel: () =>
                              ref.read(runCenterProvider.notifier).cancel(run.id),
                          loadOutput: () => ref
                              .read(runCenterProvider.notifier)
                              .fullOutput(run.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Entrada de la tarjeta: desliza desde la derecha y aparece. Sale del
/// arbol de una, sin animacion de salida -- animar la salida obligaria a
/// mantener viva una fila que el estado ya descarto.
class _AnimatedToast extends StatefulWidget {
  const _AnimatedToast({super.key, required this.child});

  final Widget child;

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDuration.entry,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppCurves.emphasized,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
