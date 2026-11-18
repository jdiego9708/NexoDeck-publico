import 'dart:convert';

import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';

import 'action_param.dart';
import 'deck_action.dart';

/// Version del formato de archivo de deck.
///
/// **No es la version del protocolo de red** (ADR 0001, postcard): esto es
/// un archivo que el usuario guarda, comparte y abre meses despues, asi que
/// aca JSON es lo correcto -- se puede versionar, inspeccionar a mano y
/// perdonar campos ausentes, que es justo lo contrario de lo que necesita
/// el cable.
const kDeckExportVersion = 1;

/// Un grupo tal como viaja en el archivo. Se exporta el grupo entero (no
/// solo su id) para que importar en otra maquina no dependa de que ahi
/// exista un grupo con el mismo id -- que nunca va a pasar, porque los ids
/// son UUID por instalacion.
class DeckExportGroup {
  const DeckExportGroup({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
  });

  final String id;
  final String name;
  final String icon;
  final String colorHex;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'colorHex': colorHex,
  };

  static DeckExportGroup fromJson(Map<String, dynamic> json) => DeckExportGroup(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Grupo',
    icon: json['icon'] as String? ?? 'folder',
    colorHex: json['colorHex'] as String? ?? '#6366F1',
  );
}

/// Contenido completo de un archivo de deck.
class DeckExport {
  const DeckExport({
    required this.version,
    required this.actions,
    required this.groups,
    this.exportedAt,
  });

  final int version;
  final List<DeckAction> actions;
  final List<DeckExportGroup> groups;
  final DateTime? exportedAt;
}

/// Se intento importar un archivo que no es un deck, o que esta corrupto.
class DeckImportException implements Exception {
  const DeckImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serializa el deck a JSON legible.
///
/// **Los ids se exportan tal cual, y sirven solo como referencias INTERNAS
/// del archivo**: los pasos de una macro apuntan a otras acciones por id, y
/// las acciones a su grupo. Al importar se remapean todos a ids nuevos (ver
/// [parseDeckExport] + el repositorio); si se reusaran los originales, una
/// segunda importacion del mismo archivo pisaria las acciones ya
/// existentes.
String encodeDeckExport({
  required List<DeckAction> actions,
  required List<DeckExportGroup> groups,
  required DateTime exportedAt,
}) {
  final json = {
    'version': kDeckExportVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'groups': [for (final g in groups) g.toJson()],
    'actions': [
      for (final a in actions)
        {
          'id': a.id,
          'name': a.name,
          if (a.description != null) 'description': a.description,
          'icon': a.icon,
          'colorHex': a.colorHex,
          'actionType': a.actionType.name,
          if (a.commandTemplate != null) 'commandTemplate': a.commandTemplate,
          'requiresAdmin': a.requiresAdmin,
          if (a.terminalType != null) 'terminalType': a.terminalType!.name,
          'showTerminalWindow': a.showTerminalWindow,
          'pasteToActiveWindow': a.pasteToActiveWindow,
          if (a.groupId != null) 'groupId': a.groupId,
          'parameters': [
            for (final p in a.parameters)
              {
                'key': p.key,
                'label': p.label,
                'inputType': p.inputType.name,
                if (p.defaultValue != null) 'defaultValue': p.defaultValue,
                if (p.options.isNotEmpty) 'options': p.options,
              },
          ],
          'macroSteps': [
            for (final s in a.macroSteps)
              {'stepActionId': s.stepActionId, 'delayMsAfter': s.delayMsAfter},
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// Un paso de macro tal como viene en el archivo (sin resolver todavia).
class ImportedStep {
  const ImportedStep({required this.stepActionId, required this.delayMsAfter});

  final String stepActionId;
  final int delayMsAfter;
}

/// Una accion del archivo, con sus referencias todavia en ids del ORIGEN.
class ImportedAction {
  const ImportedAction({
    required this.sourceId,
    required this.name,
    required this.description,
    required this.icon,
    required this.colorHex,
    required this.actionType,
    required this.commandTemplate,
    required this.requiresAdmin,
    required this.terminalType,
    required this.showTerminalWindow,
    required this.pasteToActiveWindow,
    required this.sourceGroupId,
    required this.parameters,
    required this.steps,
  });

  final String sourceId;
  final String name;
  final String? description;
  final String icon;
  final String colorHex;
  final ActionType actionType;
  final String? commandTemplate;
  final bool requiresAdmin;
  final TerminalType? terminalType;
  final bool showTerminalWindow;
  final bool pasteToActiveWindow;
  final String? sourceGroupId;
  final List<ActionParam> parameters;
  final List<ImportedStep> steps;
}

class ParsedDeck {
  const ParsedDeck({required this.actions, required this.groups});

  final List<ImportedAction> actions;
  final List<DeckExportGroup> groups;
}

/// Parsea un archivo de deck. Lanza [DeckImportException] con un motivo
/// legible si no lo es.
///
/// Es tolerante a campos ausentes (cae a los mismos defaults que el
/// esquema) pero **estricto con la forma**: un archivo que no es JSON, o
/// que no tiene `actions`, no se importa "a medias" dejando la mitad de un
/// deck adentro.
ParsedDeck parseDeckExport(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException catch (e) {
    throw DeckImportException('El archivo no es un JSON válido: ${e.message}');
  }

  if (decoded is! Map<String, dynamic>) {
    throw const DeckImportException(
      'El archivo no tiene la forma de un deck de NexoDeck.',
    );
  }

  final version = decoded['version'];
  if (version is! int) {
    throw const DeckImportException(
      'Al archivo le falta el campo "version": no parece un deck exportado '
      'por NexoDeck.',
    );
  }
  if (version > kDeckExportVersion) {
    throw DeckImportException(
      'El archivo es de una versión más nueva de NexoDeck (formato '
      '$version, esta versión entiende hasta $kDeckExportVersion).',
    );
  }

  final rawActions = decoded['actions'];
  if (rawActions is! List) {
    throw const DeckImportException(
      'El archivo no trae ninguna lista de acciones.',
    );
  }

  final groups = <DeckExportGroup>[];
  final rawGroups = decoded['groups'];
  if (rawGroups is List) {
    for (final g in rawGroups) {
      if (g is Map<String, dynamic> && g['id'] is String) {
        groups.add(DeckExportGroup.fromJson(g));
      }
    }
  }

  final actions = <ImportedAction>[];
  for (final raw in rawActions) {
    if (raw is! Map<String, dynamic>) continue;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) continue;

    actions.add(
      ImportedAction(
        sourceId: id,
        name: name,
        description: raw['description'] as String?,
        icon: raw['icon'] as String? ?? 'bolt',
        colorHex: raw['colorHex'] as String? ?? '#6366F1',
        actionType: _enumByName(
          ActionType.values,
          raw['actionType'],
          ActionType.clipboard,
        ),
        commandTemplate: raw['commandTemplate'] as String?,
        requiresAdmin: raw['requiresAdmin'] as bool? ?? false,
        terminalType: raw['terminalType'] == null
            ? null
            : _enumByName(
                TerminalType.values,
                raw['terminalType'],
                TerminalType.defaultShell,
              ),
        showTerminalWindow: raw['showTerminalWindow'] as bool? ?? true,
        // Ausente en los archivos exportados antes de que existiera la
        // opcion: por defecto solo copia, que es lo que hacian.
        pasteToActiveWindow: raw['pasteToActiveWindow'] as bool? ?? false,
        sourceGroupId: raw['groupId'] as String?,
        parameters: _parseParams(raw['parameters']),
        steps: _parseSteps(raw['macroSteps']),
      ),
    );
  }

  if (actions.isEmpty) {
    throw const DeckImportException(
      'El archivo no contiene ninguna acción válida.',
    );
  }

  return ParsedDeck(actions: actions, groups: groups);
}

List<ActionParam> _parseParams(Object? raw) {
  if (raw is! List) return const [];
  final result = <ActionParam>[];
  for (final (index, p) in raw.indexed) {
    if (p is! Map<String, dynamic>) continue;
    final key = p['key'];
    if (key is! String || key.isEmpty) continue;
    result.add(
      ActionParam(
        // El id no viaja: es de la fila de origen y no significa nada aca.
        id: 'imported-$index-$key',
        key: key,
        label: p['label'] as String? ?? key,
        inputType: _enumByName(
          ParamInputType.values,
          p['inputType'],
          ParamInputType.text,
        ),
        defaultValue: p['defaultValue'] as String?,
        options: [
          if (p['options'] is List)
            for (final o in p['options'] as List) '$o',
        ],
        orderIndex: index,
      ),
    );
  }
  return result;
}

List<ImportedStep> _parseSteps(Object? raw) {
  if (raw is! List) return const [];
  final result = <ImportedStep>[];
  for (final s in raw) {
    if (s is! Map<String, dynamic>) continue;
    final target = s['stepActionId'];
    if (target is! String) continue;
    result.add(
      ImportedStep(
        stepActionId: target,
        delayMsAfter: (s['delayMsAfter'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return result;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  // Un valor desconocido (archivo de una version futura, o editado a mano)
  // cae al default en vez de tumbar la importacion entera.
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
