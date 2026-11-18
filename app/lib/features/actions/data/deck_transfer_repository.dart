import 'package:nexodeck/data/local/tables/actions_table.dart';

import '../domain/deck_export.dart';
import 'action_groups_repository.dart';
import 'actions_repository.dart';

/// Resultado de una importacion, para poder decir exactamente que entro.
class DeckImportResult {
  const DeckImportResult({
    required this.actions,
    required this.groups,
    required this.droppedSteps,
  });

  final int actions;
  final int groups;

  /// Pasos de macro descartados porque apuntaban a una accion que no venia
  /// en el archivo. No es un error fatal (la macro entra igual, mas corta),
  /// pero **hay que decirlo**: una macro que silenciosamente pierde pasos
  /// es peor que una que no se importa.
  final int droppedSteps;
}

/// Exportar e importar el deck como archivo.
///
/// Vive aparte de `ActionsRepository` porque necesita tambien los grupos, y
/// porque la importacion tiene una regla propia que no es CRUD: **remapear
/// ids**.
class DeckTransferRepository {
  DeckTransferRepository(this._actions, this._groups);

  final ActionsRepository _actions;
  final ActionGroupsRepository _groups;

  Future<String> exportToJson({DateTime? at}) async {
    final actions = await _actions.watchAll().first;
    final groups = await _groups.watchAll().first;
    return encodeDeckExport(
      actions: actions,
      groups: [
        for (final g in groups)
          DeckExportGroup(
            id: g.id,
            name: g.name,
            icon: g.icon,
            colorHex: g.colorHex,
          ),
      ],
      exportedAt: at ?? DateTime.now(),
    );
  }

  /// Importa un deck **agregando**, nunca reemplazando: todo entra con ids
  /// nuevos, asi que importar dos veces el mismo archivo da dos copias en
  /// vez de pisar lo que ya habia. Es la opcion segura por defecto -- nadie
  /// espera que abrir un deck compartido le borre el suyo.
  Future<DeckImportResult> importFromJson(String content) async {
    final parsed = parseDeckExport(content);

    // 1) Grupos primero: las acciones los referencian.
    final groupIdMap = <String, String>{};
    for (final group in parsed.groups) {
      groupIdMap[group.id] = await _groups.createGroup(
        name: group.name,
        icon: group.icon,
        colorHex: group.colorHex,
      );
    }

    // 2) Todas las acciones SIN sus pasos, para tener el mapa completo de
    // ids antes de resolver referencias. Hace falta hacerlo en dos pasadas
    // porque una macro puede referenciar una accion que aparece despues en
    // el archivo, y porque los pasos deben apuntar a los ids NUEVOS.
    final actionIdMap = <String, String>{};
    for (final action in parsed.actions) {
      actionIdMap[action.sourceId] = await _actions.createAction(
        name: action.name,
        description: action.description,
        icon: action.icon,
        colorHex: action.colorHex,
        actionType: action.actionType,
        commandTemplate: action.commandTemplate,
        requiresAdmin: action.requiresAdmin,
        terminalType: action.terminalType,
        showTerminalWindow: action.showTerminalWindow,
        pasteToActiveWindow: action.pasteToActiveWindow,
        groupId: action.sourceGroupId == null
            ? null
            : groupIdMap[action.sourceGroupId],
        parameters: [
          for (final p in action.parameters)
            ActionParamDraft(
              key: p.key,
              label: p.label,
              inputType: p.inputType,
              defaultValue: p.defaultValue,
              options: p.options,
            ),
        ],
      );
    }

    // 3) Recien ahora los pasos, ya con el mapa completo.
    final typeBySourceId = {
      for (final a in parsed.actions) a.sourceId: a.actionType,
    };
    var dropped = 0;
    for (final action in parsed.actions) {
      if (action.steps.isEmpty) continue;
      final drafts = <MacroStepDraft>[];
      for (final step in action.steps) {
        final target = actionIdMap[step.stepActionId];
        if (target == null) {
          // El archivo referencia una accion que no trae (deck editado a
          // mano, o exportado parcialmente).
          dropped++;
          continue;
        }
        // Un archivo editado a mano podria traer una macro dentro de otra.
        // Se descarta aca (contandolo) en vez de dejar que el repositorio
        // lance a mitad de la importacion y quede todo por la mitad.
        if (typeBySourceId[step.stepActionId] == ActionType.macro) {
          dropped++;
          continue;
        }
        drafts.add(
          MacroStepDraft(stepActionId: target, delayMsAfter: step.delayMsAfter),
        );
      }
      if (drafts.isEmpty) continue;

      final created = actionIdMap[action.sourceId];
      if (created == null) continue;
      await _actions.replaceMacroSteps(created, drafts);
    }

    return DeckImportResult(
      actions: parsed.actions.length,
      groups: parsed.groups.length,
      droppedSteps: dropped,
    );
  }
}
