import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Elegir un color de una paleta corta: círculos, con el elegido marcado.
///
/// Existe porque este mismo bloque estaba escrito tres veces —el editor de
/// grupos del deck, el de acciones y el de perfiles—, cada copia con un tamaño
/// distinto. Las agrupaciones de notas son la cuarta, y en vez de copiarlo otra
/// vez vive aquí. Pasar las tres anteriores a este widget es aparte: son
/// pantallas que ya funcionan y no tienen por qué cambiar en la misma tanda.
///
/// Recibe los colores en `#RRGGBB` y los convierte él: un widget de `core/` no
/// puede depender de `colorFromHex`, que vive en una feature.
class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({
    super.key,
    required this.palette,
    required this.selected,
    required this.onSelected,
    this.size = 32,
  });

  /// `#RRGGBB`.
  final List<String> palette;

  /// El elegido, en `#RRGGBB`. Se compara sin distinguir mayúsculas: el mismo
  /// color puede venir de un fichero escrito a mano.
  final String selected;
  final ValueChanged<String> onSelected;
  final double size;

  static Color parse(String hex) {
    final clean = hex.trim().replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16);
    // Un color mal escrito en la configuración no puede tumbar la pantalla:
    // se pinta gris y se ve que algo no cuadra.
    if (clean.length != 6 || value == null) return const Color(0xFF9E9E9E);
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final hex in palette)
          Semantics(
            button: true,
            selected: hex.toUpperCase() == selected.toUpperCase(),
            label: 'Color $hex',
            child: GestureDetector(
              onTap: () => onSelected(hex),
              child: AnimatedContainer(
                duration: AppDuration.selection,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: parse(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hex.toUpperCase() == selected.toUpperCase()
                        ? onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: hex.toUpperCase() == selected.toUpperCase()
                    ? Icon(Icons.check, size: size * 0.44, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
