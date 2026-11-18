import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'actions_table.dart';

enum ParamInputType { text, number, select }

/// Relacion uno-a-muchos: una accion puede pedir cero o mas datos de
/// entrada al usuario antes de ejecutarse (ej. "nombre de migracion").
@TableIndex(name: 'idx_action_parameters_action_id', columns: {#actionId})
class ActionParameters extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get actionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();

  /// Nombre usado en el template: migration_name
  TextColumn get key => text()();

  /// Texto mostrado al usuario: "Nombre de migracion"
  TextColumn get label => text()();

  TextColumn get inputType =>
      textEnum<ParamInputType>().withDefault(const Constant('text'))();

  TextColumn get defaultValue => text().nullable()();

  /// Solo si inputType = select. JSON: ["Opcion A", "Opcion B"]
  TextColumn get optionsJson => text().nullable()();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
