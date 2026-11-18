import 'dart:convert';

import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';

/// Un dato que la accion pide al usuario antes de ejecutarse (ej. "nombre
/// de migracion"), usado para reemplazar `{{key}}` en el `commandTemplate`.
class ActionParam {
  const ActionParam({
    required this.id,
    required this.key,
    required this.label,
    required this.inputType,
    required this.defaultValue,
    required this.options,
    required this.orderIndex,
  });

  factory ActionParam.fromRow(ActionParameter row) => ActionParam(
    id: row.id,
    key: row.key,
    label: row.label,
    inputType: row.inputType,
    defaultValue: row.defaultValue,
    options: parseOptionsJson(row.optionsJson),
    orderIndex: row.orderIndex,
  );

  final String id;
  final String key;
  final String label;
  final ParamInputType inputType;
  final String? defaultValue;

  /// Opciones ya parseadas -- solo relevante si [inputType] es
  /// [ParamInputType.select].
  ///
  /// El dominio NO carga el JSON crudo de la columna `options_json`: se
  /// parsea una sola vez en [fromRow]. Que fuera texto JSON obligaba a
  /// cada consumidor a parsearlo (y al catalogo hacia Android, que manda
  /// una lista de strings por el ADR 0001, a re-serializarlo para que la
  /// otra punta lo volviera a parsear).
  final List<String> options;

  final int orderIndex;

  /// Parsea el JSON crudo de `ActionParameters.optionsJson` (`["A","B"]`).
  /// Un JSON invalido o de otra forma degrada a lista vacia: un select sin
  /// opciones se ve raro, pero romper la carga entera del deck por un
  /// campo mal escrito es peor.
  static List<String> parseOptionsJson(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.map((e) => '$e').toList();
    } on FormatException {
      return const [];
    }
  }

  /// Serializa [options] al formato de la columna. `null` si no hay
  /// ninguna, para no guardar un `[]` que no significa nada distinto.
  static String? encodeOptions(List<String> options) =>
      options.isEmpty ? null : jsonEncode(options);
}
