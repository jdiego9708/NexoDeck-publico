import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/theme/app_text.dart';

/// Parte el PIN en grupos de 3 para que se pueda comparar de un vistazo.
///
/// Si el largo no es multiplo de 3 devuelve el PIN entero en un solo grupo en
/// vez de romper: el PIN de un `HostPinReceived` es dato que llega por red, y
/// una pantalla de emparejamiento que explota es peor que una fea.
List<String> pinGroups(String pin) {
  if (pin.isEmpty || pin.length % 3 != 0) return [pin];
  return [
    for (var i = 0; i < pin.length; i += 3) pin.substring(i, i + 3),
  ];
}

/// `'004821'` -> `'004 821'`. Para titulos y logs.
String formatPin(String pin) => pinGroups(pin).join(' ');

/// `'004821'` -> `'0 0 4 8 2 1'`, **solo para `Semantics`**.
///
/// Sin esto TalkBack lee "cuatro mil ochocientos veintiuno", que es
/// exactamente lo contrario de lo que necesita alguien que tiene que
/// comparar digito por digito contra otra pantalla.
String spellPin(String pin) => pin.split('').join(' ');

/// El PIN de emparejamiento, identico en las dos puntas.
///
/// Existe como widget compartido justamente para que la PC y el telefono NO
/// puedan divergir: agrupacion, tracking, cifras tabulares, peso, pozo y
/// semantica viven en un solo lugar. Lo unico que cambia en cada lado es la
/// frase de instruccion, que va afuera.
class PinDisplay extends StatelessWidget {
  const PinDisplay({
    super.key,
    required this.pin,
    this.label = 'PIN DE EMPAREJAMIENTO',
  });

  final String pin;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = pinGroups(pin);

    return Semantics(
      label: '$label: ${spellPin(pin)}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                // Tinte primario y no `AppSurface.cardDecoration()`: esa pinta
                // `surfaceContainer`, que contra el `surfaceContainerLow` del
                // bottom sheet de la PC y el `surfaceContainerHigh` del dialogo
                // del telefono da DOS contrastes distintos -- justo lo que hay
                // que evitar cuando el trabajo del usuario es comparar las dos
                // pantallas.
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.fromBorderSide(AppSurface.hairline(scheme)),
              ),
              child: FittedBox(
                // En un telefono de 360 dp el AlertDialog deja ~248 dp utiles,
                // y con la escala de texto alta del sistema se desbordaria.
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, group) in groups.indexed) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.lg),
                      Text(
                        group,
                        style: AppText.pin(
                          theme.textTheme.displaySmall,
                        )?.copyWith(color: scheme.onSurface),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
