// Import prefijado a proposito: Drift genera una clase `MacroStep` para la
// tabla `macro_steps`, y este es el tipo de DOMINIO con el mismo concepto.
// Mismo criterio que `ActionParam` vs `ActionParameter`.
import 'package:nexodeck/data/local/database.dart' as db;

/// Un paso de una macro: que accion ejecutar y cuanto esperar despues de
/// ejecutarla. Es la fila de `macro_steps` ya en dominio.
///
/// Guarda el `stepActionId` y no la accion entera porque una macro se
/// define por referencia: si despues editas el comando de la accion
/// referenciada, la macro corre el comando nuevo. Resolver el id contra la
/// lista real de acciones es trabajo de `planMacro` (`macro_plan.dart`).
class DeckMacroStep {
  const DeckMacroStep({
    required this.id,
    required this.stepActionId,
    required this.orderIndex,
    required this.delayMsAfter,
  });

  factory DeckMacroStep.fromRow(db.MacroStep row) => DeckMacroStep(
    id: row.id,
    stepActionId: row.stepActionId,
    orderIndex: row.orderIndex,
    delayMsAfter: row.delayMsAfter,
  );

  final String id;
  final String stepActionId;
  final int orderIndex;

  /// Pausa despues de ejecutar este paso. Existe porque encadenar acciones
  /// sin respiro es justamente lo que rompe una macro util: abrir una app y
  /// mandarle un comando en el mismo instante llega antes de que la app
  /// exista.
  final int delayMsAfter;

  Duration get delayAfter => Duration(milliseconds: delayMsAfter);
}
