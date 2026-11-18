import 'package:flutter/material.dart';

import '../domain/process_group.dart';

/// Pregunta antes de cerrar una aplicacion.
///
/// Cerrar procesos es irreversible y el deck es una pantalla de clics
/// rapidos, asi que **Cancelar es la accion por defecto**: tiene el foco y es
/// la que responde a Enter. El boton destructivo va en el color de error y
/// dice cuantos procesos se van a cerrar, porque "cerrar chrome.exe" en
/// realidad cierra sus 32 procesos y con ellos todas las pestanas abiertas.
Future<bool> showConfirmKillDialog(
  BuildContext context,
  ProcessGroup group,
) async {
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('¿Cerrar ${group.name}?'),
      content: Text(
        group.processCount > 1
            ? 'Se van a cerrar sus ${group.processCount} procesos. '
                  'Lo que no esté guardado se pierde.'
            : 'Lo que no esté guardado se pierde.',
      ),
      actions: [
        TextButton(
          // `autofocus` en Cancelar, no en Cerrar: si el usuario aprieta Enter
          // por inercia, no mata nada.
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
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
