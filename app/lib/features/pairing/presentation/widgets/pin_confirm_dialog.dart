import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import 'pin_display.dart';

/// Rol Android: muestra el PIN que la PC contesto, para compararlo
/// visualmente con el que aparece en la PC antes de confirmar.
///
/// Toma `pin` y `hostName` sueltos y no el evento del bridge a proposito: asi
/// este archivo queda 100% puro y se puede montar en un widget test sin
/// inicializar RustLib.
Future<bool> showPinConfirmDialog(
  BuildContext context, {
  required String pin,
  required String hostName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Confirmar emparejamiento'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.pairingContentMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Compara este PIN con el que se ve en "$hostName"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.gutter),
            PinDisplay(pin: pin),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Coincide, confirmar'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
