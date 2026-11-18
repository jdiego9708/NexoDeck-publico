import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/provider_reader.dart';
import '../../actions/application/actions_provider.dart';
import '../../actions/data/actions_repository.dart';
import '../../actions/presentation/action_editor_sheet.dart';
import '../domain/action_draft.dart';
import '../domain/draft_to_editor.dart';
import '../domain/draft_validation.dart';

/// Lleva un borrador de la IA hasta el editor de acciones.
///
/// ## La regla que gobierna este archivo
///
/// **Nada se guarda hasta que el usuario confirma.** Para una accion simple es
/// trivial: se abre el editor prellenado y listo. Para una cadena hay un
/// problema real: una macro guarda ids de acciones que **tienen que existir**,
/// asi que las hojas se crean antes de abrir el editor de la macro. Si el
/// usuario cancela ahi, se borran todas — la base nunca queda con botones que
/// nadie pidio.
///
/// Devuelve `true` si el usuario termino guardando algo.
Future<bool> applyDraft(
  BuildContext context,
  WidgetRef ref,
  ActionDraft draft,
) async {
  final issues = validateDraft(draft);
  if (issues.isNotEmpty) {
    // Rust ya valido esto y el modelo tuvo su chance de corregir. Llegar aca
    // significa que algo cambio en el medio (un icono que se saco del set, por
    // ejemplo): se informa en vez de escribir una fila invalida.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El borrador tiene problemas: ${issues.first}'),
        ),
      );
    }
    return false;
  }

  if (!draft.isMacro) {
    return showActionEditorSheet(context, seed: seedForSingleStep(draft));
  }

  return _applyChain(context, ref, draft);
}

Future<bool> _applyChain(
  BuildContext context,
  WidgetRef ref,
  ActionDraft draft,
) async {
  final repository = ref.read(actionsRepositoryProvider);
  final leafIds = <String>[];

  try {
    for (var index = 0; index < draft.steps.length; index++) {
      final step = draft.steps[index];
      leafIds.add(
        await repository.createAction(
          name: step.name,
          description: step.description,
          icon: draft.icon,
          colorHex: draft.colorHex,
          actionType: step.actionType,
          commandTemplate: step.resolvedCommand,
          requiresAdmin: step.requiresAdmin,
          terminalType: step.terminalType,
          showTerminalWindow: step.showTerminalWindow,
          autoSubscribe: autoSubscribeConfigFor(step),
          parameters: paramDraftsFor(step),
        ),
      );
    }
  } catch (error) {
    // Si una hoja falla a mitad de camino, las anteriores quedarian sueltas en
    // el deck sin la macro que les da sentido.
    await _discard(repository, leafIds);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron crear los pasos: $error')),
      );
    }
    return false;
  }

  if (!context.mounted) {
    await _discard(repository, leafIds);
    return false;
  }

  final saved = await showActionEditorSheet(
    context,
    seed: seedForMacro(draft, leafIds),
  );

  if (!saved) {
    await _discard(repository, leafIds);
    return false;
  }

  return true;
}

/// Borra las hojas creadas para una macro que no llego a guardarse.
Future<void> _discard(ActionsRepository repository, List<String> ids) async {
  for (final id in ids) {
    // Un fallo al limpiar no puede tapar el error original que trajo hasta
    // aca, ni dejar la UI colgada.
    try {
      await repository.deleteAction(id);
    } catch (_) {}
  }
}

/// Guarda el borrador tal cual, **sin editor ni confirmacion**.
///
/// Es la mitad de [applyDraft] que no toca `BuildContext`: quien la llama ya
/// obtuvo la confirmacion de un humano en otro lado (hoy, el telefono -- el
/// borrador que le llega a esta funcion ya tiene los `{{parametros}}`
/// resueltos, porque el telefono los junto con su propio dialogo antes de
/// mandarlo). Mismo modelo de confianza que `ExecuteAction`: quien inicia el
/// pedido resuelve, la PC ejecuta sin volver a preguntar.
///
/// Devuelve el id de la accion (o de la macro) creada, o `null` si el
/// borrador no paso validacion o algo fallo al guardar -- silencioso a
/// proposito, igual que el resto de los caminos remotos de este proyecto que
/// no tienen un ack propio (ver `_tryAutoSubscribe`).
Future<String?> applyDraftHeadless(ProviderReader read, ActionDraft draft) async {
  if (validateDraft(draft).isNotEmpty) return null;

  final repository = read(actionsRepositoryProvider);

  if (!draft.isMacro) {
    final seed = seedForSingleStep(draft);
    try {
      return await repository.createAction(
        name: seed.name,
        description: seed.description,
        icon: seed.icon,
        colorHex: seed.colorHex,
        actionType: seed.actionType,
        commandTemplate: seed.commandTemplate,
        requiresAdmin: seed.requiresAdmin,
        terminalType: seed.terminalType,
        showTerminalWindow: seed.showTerminalWindow,
        autoSubscribe: seed.autoSubscribe,
        parameters: seed.parameters,
      );
    } catch (_) {
      return null;
    }
  }

  return _applyChainHeadless(read, draft);
}

Future<String?> _applyChainHeadless(ProviderReader read, ActionDraft draft) async {
  final repository = read(actionsRepositoryProvider);
  final leafIds = <String>[];

  try {
    for (final step in draft.steps) {
      leafIds.add(
        await repository.createAction(
          name: step.name,
          description: step.description,
          icon: draft.icon,
          colorHex: draft.colorHex,
          actionType: step.actionType,
          commandTemplate: step.resolvedCommand,
          requiresAdmin: step.requiresAdmin,
          terminalType: step.terminalType,
          showTerminalWindow: step.showTerminalWindow,
          autoSubscribe: autoSubscribeConfigFor(step),
          parameters: paramDraftsFor(step),
        ),
      );
    }

    final seed = seedForMacro(draft, leafIds);
    return await repository.createAction(
      name: seed.name,
      description: seed.description,
      icon: seed.icon,
      colorHex: seed.colorHex,
      actionType: seed.actionType,
      macroSteps: seed.macroSteps,
    );
  } catch (_) {
    await _discard(repository, leafIds);
    return null;
  }
}
