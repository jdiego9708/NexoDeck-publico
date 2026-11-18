import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/features/actions/presentation/widgets/deck_grid_layout.dart';

void main() {
  group('bestColumnCountForAspect', () {
    test('un solo item siempre es una columna', () {
      expect(
        bestColumnCountForAspect(
          itemCount: 1,
          availableWidth: 1000,
          availableHeight: 500,
          spacing: 8,
        ),
        1,
      );
    });

    test('reparte en dos filas cuando eso acerca la celda al target', () {
      // 4 items en un area ancha y baja: 4 columnas darian celdas muy
      // apaisadas, 2x2 se acerca mas a 1.6.
      final columns = bestColumnCountForAspect(
        itemCount: 4,
        availableWidth: 640,
        availableHeight: 300,
        spacing: 8,
      );
      expect(columns, inInclusiveRange(2, 3));
    });
  });

  group('resolveDeckGrid', () {
    test(
      'con pocas acciones en horizontal llena la pantalla y no scrollea',
      () {
        // El caso que se veia mal en el S24 Ultra apaisado: 4 acciones
        // dejaban media pantalla vacia.
        final layout = resolveDeckGrid(
          itemCount: 4,
          availableWidth: 616,
          availableHeight: 306,
        );

        expect(layout.scrolls, isFalse);
        expect(layout.tileWidth, greaterThanOrEqualTo(AppSizes.minActionTileWidth));
        expect(
          layout.tileHeight,
          greaterThanOrEqualTo(AppSizes.minActionTileHeight),
        );

        // Las filas cubren exactamente el alto disponible.
        final rows = (4 / layout.columns).ceil();
        final used = layout.tileHeight * rows + AppSpacing.sm * (rows - 1);
        expect(used, closeTo(306, 0.01));
      },
    );

    test('con muchas acciones scrollea en vez de achicarlas sin limite', () {
      final layout = resolveDeckGrid(
        itemCount: 40,
        availableWidth: 336,
        availableHeight: 560,
      );

      expect(layout.scrolls, isTrue);
      expect(layout.tileWidth, greaterThanOrEqualTo(AppSizes.minActionTileWidth));
      expect(
        layout.aspectRatio,
        closeTo(AppSizes.actionTileAspectRatio, 0.001),
      );
    });

    test('un telefono vertical con pocas acciones da 2 columnas', () {
      final layout = resolveDeckGrid(
        itemCount: 4,
        availableWidth: 336,
        availableHeight: 500,
      );
      expect(layout.columns, 2);
      expect(layout.scrolls, isFalse);
    });

    test('una lista vacia no rompe la division', () {
      final layout = resolveDeckGrid(
        itemCount: 0,
        availableWidth: 336,
        availableHeight: 500,
      );
      expect(layout.columns, greaterThanOrEqualTo(1));
      expect(layout.aspectRatio.isFinite, isTrue);
    });
  });

  group('actionsPanelColumnsFor', () {
    test('angosto: una sola columna', () {
      expect(actionsPanelColumnsFor(180), 1);
    });

    test('ancho: dos columnas', () {
      expect(actionsPanelColumnsFor(340), 2);
    });

    test('el umbral son dos tiles minimos mas el separador', () {
      final threshold = AppSizes.minCompactActionTileWidth * 2 + AppSpacing.sm;
      expect(actionsPanelColumnsFor(threshold), 2);
      expect(actionsPanelColumnsFor(threshold - 1), 1);
    });
  });
}
