import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Sin esto, un dispositivo sin WiFi (ej. usando datos moviles) se queda
/// mirando un spinner para siempre, sin ninguna pista de por que -- mDNS
/// (descubrimiento y reconexion) no viaja fuera de la red local.
///
/// Mismo tratamiento que el banner de error de transporte de la PC (radio y
/// margen, no una banda a sangre): son el mismo tipo de aviso en las dos
/// puntas y tienen que verse igual.
class NoWifiBanner extends StatelessWidget {
  const NoWifiBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Conecta el WiFi a la misma red que tu PC. Con datos '
              'moviles no es posible descubrir dispositivos en la red '
              'local.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
