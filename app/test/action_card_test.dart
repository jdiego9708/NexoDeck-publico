import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/actions/presentation/widgets/action_card.dart';

/// La tarjeta desbordaba cuando el deck se achicaba de mas (el riel de
/// metricas creciendo, o cualquier otro achique real): con nombre + dos
/// lineas de descripcion + dos insignias, la suma no entraba en una tarjeta
/// angosta y baja, y `mainAxisAlignment: spaceBetween` no la achicaba, solo
/// desbordaba. Encontrado en vivo, en la app real.
void main() {
  DeckAction action({String? description, bool requiresAdmin = false}) =>
      DeckAction(
        id: '1',
        name: 'Archivar fotos y liberar disco',
        description: description,
        icon: 'folder',
        colorHex: '#6C5CE7',
        actionType: ActionType.clipboard,
        commandTemplate: 'echo hola',
        requiresAdmin: requiresAdmin,
        terminalType: null,
        isFavorite: false,
        parameters: const [],
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required DeckAction action,
    int promptParamCount = 0,
    required Size size,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ActionCard(
                action: action,
                promptParamCount: promptParamCount,
                onExecute: () {},
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'con nombre, descripcion larga y dos insignias no desborda en una '
    'tarjeta angosta y baja',
    (tester) async {
      await pumpCard(
        tester,
        action: action(
          description:
              'Sube las fotos originales a S3 y despues limpia lo ya '
              'verificado, dejando solo lo que todavia falta procesar',
          requiresAdmin: true,
        ),
        promptParamCount: 2,
        // Angosta y baja a proposito: es el tamano al que cae una tarjeta
        // cuando el deck pasa a 2 columnas en una ventana no muy alta.
        size: const Size(220, 130),
      );

      expect(tester.takeException(), isNull);
      // El nombre tiene que seguir entero y legible, pase lo que pase con
      // el resto -- es lo que la tarjeta nunca puede recortar.
      expect(find.text('Archivar fotos y liberar disco'), findsOneWidget);
    },
  );

  testWidgets(
    'con una fila muy baja (muchas acciones apretando filas en una ventana '
    'chica) tampoco desborda',
    (tester) async {
      // Repro real: 20 acciones en 3 columnas, 7 filas, en una ventana de
      // 811x979 -- la celda resultante quedaba en ~104px de alto, por debajo
      // de lo que pide un nombre + descripcion de dos lineas + una insignia
      // (~140px). `Align` (el fix anterior) seguia marcando el desborde
      // porque el `maxHeight` que le llega a la Column de adentro seguia
      // siendo finito; `OverflowBox` con `maxHeight: infinity` es lo que lo
      // saca de verdad.
      await pumpCard(
        tester,
        action: action(
          description:
              'GET training/runs -- entrenamientos, del mas reciente al mas '
              'antiguo',
          requiresAdmin: true,
        ),
        promptParamCount: 3,
        size: const Size(259, 104),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Archivar fotos y liberar disco'), findsOneWidget);
    },
  );

  testWidgets(
    'con una celda por debajo del minimo del icono+nombre tampoco desborda',
    (tester) async {
      // Repro real: panel de procesos + ventana angosta + 20+ acciones
      // dejaba celdas de ~68px de alto, por debajo de lo que necesitan el
      // icono y el nombre solos (~80px) -- ahi ni el fix de `OverflowBox`
      // (solo protegia la descripcion) alcanzaba, y la tarjeta entera
      // desbordaba. El `FittedBox` que envuelve toda la tarjeta es lo que
      // la salva: se achica entera en vez de desbordar.
      await pumpCard(
        tester,
        action: action(
          description: 'GET training/runs -- entrenamientos',
          requiresAdmin: true,
        ),
        promptParamCount: 3,
        size: const Size(160, 68),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Archivar fotos y liberar disco'), findsOneWidget);
    },
  );

  testWidgets('sin descripcion ni insignias tampoco desborda en el mismo tamano', (
    tester,
  ) async {
    await pumpCard(
      tester,
      action: action(),
      size: const Size(220, 130),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'con espacio de sobra, sigue mostrando nombre, descripcion e insignias',
    (tester) async {
      await pumpCard(
        tester,
        action: action(
          description: 'Pega una plantilla de titulo para el stream',
          requiresAdmin: true,
        ),
        promptParamCount: 1,
        size: const Size(360, 220),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Archivar fotos y liberar disco'), findsOneWidget);
      expect(
        find.text('Pega una plantilla de titulo para el stream'),
        findsOneWidget,
      );
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('1 dato'), findsOneWidget);
    },
  );
}
