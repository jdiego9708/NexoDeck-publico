import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'actions_table.dart';

/// Modela una macro como una secuencia de otras acciones existentes. Una
/// accion con actionType = macro no tiene commandTemplate propio; sus pasos
/// estan aqui. Prohibir macros anidadas (paso que apunte a otra macro) se
/// valida en la capa de repositorios, no en el esquema.
@TableIndex(
  name: 'idx_macro_steps_macro_action_order',
  columns: {#macroActionId, #orderIndex},
)
class MacroSteps extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// La accion "contenedora" (actionType = macro).
  ///
  /// `@ReferenceName` desambigua esta FK de `stepActionId` -- ambas
  /// apuntan a `ActionsTable`, y sin esto drift_dev no puede generar
  /// nombres distintos para las relaciones inversas.
  @ReferenceName('macroStepsAsContainer')
  TextColumn get macroActionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();

  /// La accion que se ejecuta en este paso.
  @ReferenceName('macroStepsAsStep')
  TextColumn get stepActionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();

  IntColumn get orderIndex => integer()();
  IntColumn get delayMsAfter => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
