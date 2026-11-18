import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/application/action_groups_provider.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/actions/presentation/action_editor_sheet.dart';

/// El campo Comando (3 lineas) se quedaba corto para un `curl` con JSON o
/// una cadena de scripts encadenados: sin forma de verlo entero, editarlo
/// era a ciegas. Se agrego un icono para ampliar (siempre visible) y un
/// aviso "Ver completo" que solo aparece si el comando es largo de verdad.
void main() {
  const longCommand =
      'curl -s -X POST "http://localhost:5242/PlantDetection/training/start" '
      '-H "Content-Type: application/json" '
      '-d "{\\"id_zone_tif\\": 42, \\"run_name\\": \\"\\", \\"epochs\\": '
      'null, \\"register_as\\": \\"\\", \\"detect_when_done\\": false}"';

  DeckAction action({required String commandTemplate}) => DeckAction(
    id: '1',
    name: 'Entrenamiento IA: iniciar',
    description: null,
    icon: 'code',
    colorHex: '#8B5CF6',
    actionType: ActionType.terminal,
    commandTemplate: commandTemplate,
    requiresAdmin: false,
    terminalType: TerminalType.cmd,
    isFavorite: false,
    parameters: const [],
  );

  Future<void> pumpEditor(WidgetTester tester, DeckAction existing) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          actionGroupsListProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showActionEditorSheet(context, existing: existing),
                child: const Text('abrir editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir editor'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'con un comando corto no aparece el aviso de "ver completo"',
    (tester) async {
      await pumpEditor(tester, action(commandTemplate: 'echo hola'));

      expect(find.textContaining('Ver completo'), findsNothing);
      // El icono de ampliar esta siempre, corto o largo.
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    },
  );

  testWidgets(
    'con un comando largo aparece el aviso, y ampliar abre pantalla '
    'completa con el mismo texto',
    (tester) async {
      await pumpEditor(tester, action(commandTemplate: longCommand));

      expect(find.textContaining('Ver completo'), findsOneWidget);
      // Dos iconos "ampliar": el del campo y el del aviso.
      expect(find.byIcon(Icons.open_in_full), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.open_in_full).first);
      await tester.pumpAndSettle();

      // La pantalla completa muestra el comando entero, no recortado.
      expect(find.widgetWithText(TextField, longCommand), findsOneWidget);

      // "Listo" cierra la pantalla completa y vuelve al editor con el
      // mismo texto (mismo controller, nada se pierde).
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();

      expect(find.text('Editar acción'), findsOneWidget);
      expect(find.textContaining('Ver completo'), findsOneWidget);
    },
  );

  testWidgets(
    'editar el comando en pantalla completa se refleja en el campo chico',
    (tester) async {
      await pumpEditor(tester, action(commandTemplate: 'echo hola'));

      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'echo chau');
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'echo chau'), findsOneWidget);
    },
  );
}
