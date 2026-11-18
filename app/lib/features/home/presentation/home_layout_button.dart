import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/home_layout_controller.dart';
import '../domain/home_layout.dart';

/// Boton de la barra que rota entre los cuatro [HomeLayout] con un clic.
///
/// Muestra el icono del layout **actual**, no el del siguiente: el boton es
/// antes que nada un indicador de donde estas parado, y el tooltip es el que
/// dice a donde te lleva el proximo clic.
class HomeLayoutButton extends ConsumerWidget {
  const HomeLayoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);

    return IconButton(
      tooltip: 'Disposición: ${layout.label}\nClic para ${layout.next.label}',
      onPressed: () => ref.read(homeLayoutControllerProvider).cycle(),
      icon: _LayoutIcon(layout: layout),
    );
  }
}

/// El icono cambia con una transicion corta en vez de saltar: son cuatro
/// estados y el cambio es la unica confirmacion visual de que el clic hizo
/// algo cuando el layout nuevo se parece al anterior (izquierda -> derecha).
class _LayoutIcon extends StatelessWidget {
  const _LayoutIcon({required this.layout});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(layout.icon, key: ValueKey(layout));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      // `metricsLeft` y `metricsRight` comparten icono: sin el volteo, el
      // boton se veria identico en los dos y el clic parecería no hacer nada.
      child: layout.flipIcon
          ? Transform.flip(key: ValueKey(layout), flipX: true, child: icon)
          : icon,
    );
  }
}
