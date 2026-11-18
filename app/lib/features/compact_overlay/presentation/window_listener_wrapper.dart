import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../application/window_mode_controller.dart';

/// Persiste posicion/tamano cuando el usuario termina de mover o
/// redimensionar la ventana a mano (no en cada tick de `onWindowMove` /
/// `onWindowResize`, que dispara demasiado seguido para escribir a Drift
/// en cada evento -- `onWindowMoved`/`onWindowResized` ya llegan una sola
/// vez al final del gesto).
class WindowListenerWrapper extends ConsumerStatefulWidget {
  const WindowListenerWrapper({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowListenerWrapper> createState() =>
      _WindowListenerWrapperState();
}

class _WindowListenerWrapperState extends ConsumerState<WindowListenerWrapper>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    if (isDesktopWindowPlatform) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (isDesktopWindowPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMoved() {
    ref.read(windowModeControllerProvider).persistCurrentBounds();
  }

  @override
  void onWindowResized() {
    ref.read(windowModeControllerProvider).persistCurrentBounds();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
