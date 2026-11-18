import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/action_error_dialog.dart';
import '../application/actions_provider.dart';
import '../data/actions_repository.dart';
import '../domain/deck_action.dart';
import '../domain/macro_plan.dart';
import 'widgets/parameter_prompt_dialog.dart';

/// Ejecuta [action] desde la UI de escritorio: pide los parametros si hace
/// falta, muestra el progreso si es una macro, y reporta el resultado.
///
/// Es la UNICA definicion de ese flujo. Antes estaba duplicado entre el
/// deck (`actions_deck_grid.dart`) y el modo compacto
/// (`compact_deck_view.dart`), con la copia del compacto ya divergida: no
/// mostraba ningun error si la accion fallaba. Sumarle el progreso de macro
/// a dos copias era garantizar que volvieran a separarse.
Future<void> runDeckAction(
  BuildContext context,
  WidgetRef ref,
  DeckAction action,
) async {
  final repository = ref.read(actionsRepositoryProvider);

  // Para una macro los parametros son los de sus pasos, asi que hace falta
  // la lista completa para resolverlos. Para una accion simple no: se evita
  // la query en el camino caliente, que es el 99% de los toques del deck.
  final prompt = action.actionType == ActionType.macro
      ? promptParametersFor(action, await repository.watchAll().first)
      : action.parameters;

  var values = const <String, String>{};
  if (prompt.isNotEmpty) {
    if (!context.mounted) return;
    final entered = await showParameterPromptDialog(
      context,
      title: action.name,
      parameters: prompt,
    );
    if (entered == null) return; // cancelado
    values = entered;
  }
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  // Una macro con pausas tarda segundos; sin esto la UI no da ninguna senal
  // de que algo esta pasando y el usuario vuelve a tocar la tarjeta.
  final progress = action.actionType == ActionType.macro
      ? ValueNotifier<_MacroProgress?>(null)
      : null;
  if (progress != null) {
    messenger.showSnackBar(
      SnackBar(
        // Se cierra a mano al terminar (o al fallar), no por timeout: el
        // tiempo real depende de los delays configurados en la macro.
        duration: const Duration(days: 1),
        content: _MacroProgressBar(name: action.name, progress: progress),
      ),
    );
  }

  try {
    await repository.execute(
      action,
      paramValues: values,
      onStep: progress == null
          ? null
          : (index, total, step) => progress.value = _MacroProgress(
              index: index,
              total: total,
              stepName: step.name,
            ),
    );
    messenger.hideCurrentSnackBar();
    // Una accion de terminal capturada ya tiene su propia notificacion, con
    // cronometro, salida y codigo de salida: un SnackBar diciendo "ejecutada"
    // seria redundante y ademas llegaria despues. El resto (portapapeles,
    // ventana de terminal) no notifica nada por si mismo y si lo necesita.
    if (!_hasOwnNotification(action)) {
      messenger.showSnackBar(
        SnackBar(content: Text('"${action.name}" ejecutada')),
      );
    }
  } on CommandCancelledException {
    // El usuario la corto desde la notificacion: ya sabe lo que hizo, y la
    // tarjeta ya muestra "Cancelada". Un dialogo de error arriba seria
    // reprocharle una decision suya.
    messenger.hideCurrentSnackBar();
  } catch (e) {
    messenger.hideCurrentSnackBar();
    if (!context.mounted) return;
    // Un comando capturado que fallo ya se ve en su notificacion (roja, con
    // el codigo y la salida). Solo se abre el dialogo cuando el toast NO
    // alcanza: una macro, para poder decir en que paso se corto.
    if (e is CommandFailedException && action.actionType != ActionType.macro) {
      return;
    }
    await showActionErrorDialog(
      context,
      actionName: action.name,
      error: e,
      friendlyMessage: friendlyActionError(e, action.actionType),
    );
  } finally {
    progress?.dispose();
  }
}

/// Si la accion se reporta sola con una notificacion del centro de
/// ejecuciones. Solo las de terminal capturadas -- las que abren una ventana
/// real no pasan por el runner.
bool _hasOwnNotification(DeckAction action) =>
    action.actionType == ActionType.terminal && !action.showTerminalWindow;

/// Mensaje humano de entrada para el dialogo de error -- el detalle tecnico
/// real (`e.toString()`) va aparte, detras de "Ver mas".
String friendlyActionError(Object error, ActionType actionType) {
  // Una macro que fallo en el paso 4 de 6 no se explica con "no se pudo
  // copiar al portapapeles": lo primero que hay que decir es CUAL paso
  // rompio, que es justamente lo que `MacroStepException` sabe.
  if (error is MacroStepException) {
    final cause = error.cause;
    // Con la ejecucion capturada, la causa suele traer el codigo de salida
    // real: decirlo aca ahorra tener que abrir "Ver mas".
    final detail = cause is CommandFailedException && cause.exitCode != null
        ? ' El comando termino con codigo ${cause.exitCode}.'
        : '';
    return 'La macro se detuvo en el paso ${error.stepIndex + 1} de '
        '${error.totalSteps} ("${error.stepName}").$detail Los pasos '
        'anteriores ya se ejecutaron.';
  }
  if (error is CommandFailedException) {
    return error.exitCode != null
        ? 'El comando termino con codigo ${error.exitCode}.'
        : 'El comando no se pudo completar.';
  }
  switch (actionType) {
    case ActionType.clipboard:
      return 'No se pudo copiar el contenido al portapapeles.';
    case ActionType.terminal:
      return 'No se pudo abrir la aplicación o ejecutar el comando. '
          'Verifica que exista y que tengas los permisos necesarios.';
    case ActionType.macro:
      return 'No se pudo ejecutar la macro.';
  }
}

class _MacroProgress {
  const _MacroProgress({
    required this.index,
    required this.total,
    required this.stepName,
  });

  final int index;
  final int total;
  final String stepName;
}

class _MacroProgressBar extends StatelessWidget {
  const _MacroProgressBar({required this.name, required this.progress});

  final String name;
  final ValueListenable<_MacroProgress?> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_MacroProgress?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final total = value?.total ?? 0;
        return Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // Indeterminado hasta que arranque el primer paso (hay un
                // instante entre el toque y la resolucion del plan).
                value: value == null || total == 0
                    ? null
                    : (value.index + 1) / total,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                value == null
                    ? 'Ejecutando "$name"...'
                    : 'Paso ${value.index + 1}/$total: ${value.stepName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
