import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Lockup de marca de NexoDeck.
///
/// Antes el AppBar era un `Text('NexoDeck')` con los defaults de Material.
/// Esto no inventa ningun color: el degradado sale de `primary` y `tertiary`
/// del `ColorScheme`, o sea que sigue derivando del mismo seed violeta y
/// acompana al tema claro/oscuro solo.
///
/// El contraste de peso dentro de la palabra ("Nexo" en w800 + "Deck" en
/// w400) es la firma tipografica tipica de las marcas de herramientas de
/// desarrollo, y es lo que hace que se lea como marca y no como titulo de
/// ventana.
class NexoDeckWordmark extends StatelessWidget {
  const NexoDeckWordmark({super.key, this.markSize = 26, this.showText = true});

  final double markSize;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
            borderRadius: BorderRadius.circular(AppRadius.chip - 4),
          ),
          child: Icon(
            Icons.bolt,
            size: markSize * 0.62,
            color: scheme.onPrimary,
          ),
        ),
        if (showText) ...[
          SizedBox(width: markSize * 0.35),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Nexo',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: 'Deck',
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              letterSpacing: -0.3,
              color: scheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
