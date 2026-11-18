import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/action_draft.dart';

/// Confirmacion extra antes de ejecutar en vivo un borrador `Dangerous`, o
/// que pida permisos de administrador en alguno de sus pasos.
///
/// A diferencia de "Guardar como boton" (que no hace nada hasta que alguien
/// lo toque despues), tocar "Ejecutar ahora" corre el comando ya mismo — la
/// friccion extra es a proposito. Mismo patron visual que
/// `showConfirmKillDialog` (`features/processes/presentation/`): Cancelar
/// tiene el foco por defecto, el boton destructivo va en el color de error.
Future<bool> showConfirmDangerousRunDialog(
  BuildContext context,
  ActionDraft draft,
) async {
  final scheme = Theme.of(context).colorScheme;
  final notes = [for (final step in draft.steps) ...step.riskNotes];
  final adminSteps = draft.steps.where((step) => step.requiresAdmin).toList();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Ejecutar "${draft.name}" ahora?'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Esto corre de verdad, no es una simulacion.'),
              if (adminSteps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  adminSteps.length == 1
                      ? 'El paso "${adminSteps.first.name}" pide permisos de administrador.'
                      : '${adminSteps.length} pasos piden permisos de administrador.',
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text('· $note'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          // Igual que en `confirm_kill_dialog.dart`: Cancelar responde a
          // Enter, no el boton que ejecuta.
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Ejecutar'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
