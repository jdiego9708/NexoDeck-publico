import '../../actions/domain/placeholders.dart';
import '../../actions/presentation/widgets/action_icons.dart';
import 'action_draft.dart';

/// Segunda linea de defensa sobre el borrador de la IA.
///
/// Rust ya valida lo mismo (`draft::validate`) y ademas rechaza la propuesta
/// para que el modelo corrija en la misma conversacion. Esto no es duplicacion
/// por las dudas: **son dos usos distintos**. Alla sirve para enseñarle al
/// modelo; aca sirve para no escribir basura en Drift si algo cambio en el
/// medio — el set de iconos y la paleta viven en Dart, y si alguien agrega un
/// icono nuevo del lado Flutter sin tocar Rust, este es el unico lugar que se
/// entera.
///
/// Todo puro: sin `BuildContext`, sin base, sin FFI.

/// Limite de `ActionsTable.name` en Drift (`withLength(min: 1, max: 60)`).
/// Pasarse no da un error legible: falla el insert.
const int kMaxActionNameLength = 60;

class DraftIssue {
  const DraftIssue({required this.field, required this.message, this.stepIndex});

  final String field;
  final String message;

  /// `null` cuando el problema es del borrador entero.
  final int? stepIndex;

  @override
  String toString() => stepIndex == null ? message : 'Paso ${stepIndex! + 1}: $message';
}

/// Revisa el borrador y devuelve lo que hay que arreglar. Lista vacia = se
/// puede abrir en el editor tal cual.
List<DraftIssue> validateDraft(ActionDraft draft) {
  final issues = <DraftIssue>[];

  final name = draft.name.trim();
  if (name.isEmpty) {
    issues.add(const DraftIssue(field: 'name', message: 'El nombre esta vacio'));
  } else if (name.characters > kMaxActionNameLength) {
    issues.add(
      DraftIssue(
        field: 'name',
        message:
            'El nombre tiene ${name.characters} caracteres y el maximo es $kMaxActionNameLength',
      ),
    );
  }

  if (!kActionIcons.containsKey(draft.icon)) {
    issues.add(
      DraftIssue(field: 'icon', message: 'El icono "${draft.icon}" no existe'),
    );
  }

  if (!kActionColorPalette.any(
    (color) => color.toUpperCase() == draft.colorHex.toUpperCase(),
  )) {
    issues.add(
      DraftIssue(
        field: 'colorHex',
        message: 'El color "${draft.colorHex}" no esta en la paleta',
      ),
    );
  }

  if (draft.steps.isEmpty) {
    issues.add(const DraftIssue(field: 'steps', message: 'El borrador no tiene pasos'));
  }

  for (var index = 0; index < draft.steps.length; index++) {
    issues.addAll(_validateStep(draft.steps[index], index));
  }

  return issues;
}

List<DraftIssue> _validateStep(DraftStep step, int index) {
  final issues = <DraftIssue>[];

  if (step.name.trim().isEmpty) {
    issues.add(
      DraftIssue(field: 'name', message: 'El paso no tiene nombre', stepIndex: index),
    );
  }
  if (step.resolvedCommand.trim().isEmpty) {
    issues.add(
      DraftIssue(field: 'command', message: 'El comando esta vacio', stepIndex: index),
    );
  }

  final keys = step.parameters.map((param) => param.key.trim()).toList();
  final seen = <String>{};
  for (final key in keys) {
    if (key.isEmpty) {
      issues.add(
        DraftIssue(
          field: 'parameters',
          message: 'Hay un parametro sin nombre de variable',
          stepIndex: index,
        ),
      );
    } else if (!seen.add(key)) {
      issues.add(
        DraftIssue(
          field: 'parameters',
          message: 'La variable "$key" esta repetida',
          stepIndex: index,
        ),
      );
    }
  }

  // Se valida contra el comando **resuelto**, no contra el original: el
  // `working_directory` puede traer una variable y tambien hay que declararla.
  for (final missing in undeclaredPlaceholders(step.resolvedCommand, keys)) {
    issues.add(
      DraftIssue(
        field: 'parameters',
        message: 'El comando usa {{$missing}} pero no esta declarado',
        stepIndex: index,
      ),
    );
  }

  return issues;
}

extension on String {
  /// Largo en caracteres visibles. `String.length` cuenta unidades UTF-16, asi
  /// que un nombre con emoji o acentos compuestos se pasaria del limite de
  /// Drift antes de lo esperado.
  int get characters => runes.length;
}
