import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/window_mode_controller.dart';

/// Boton para pasar a modo compacto (anclado, always-on-top). Solo se
/// muestra en Windows/Linux -- en Android el modo compacto es un mecanismo
/// distinto (overlay tipo bubble, fuera de alcance de esta feature).
class WindowModeToggleButton extends ConsumerWidget {
  const WindowModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopWindowPlatform) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'Modo compacto',
      icon: const Icon(Icons.picture_in_picture_alt_outlined),
      onPressed: () =>
          ref.read(windowModeControllerProvider).toggle(),
    );
  }
}
