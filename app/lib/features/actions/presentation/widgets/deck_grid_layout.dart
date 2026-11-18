import 'dart:math' as math;

import '../../../../core/theme/app_spacing.dart';

/// Como queda repartida la grilla del deck en un espacio concreto.
class DeckGridLayout {
  const DeckGridLayout({
    required this.columns,
    required this.tileWidth,
    required this.tileHeight,
    required this.scrolls,
  });

  final int columns;
  final double tileWidth;
  final double tileHeight;

  /// `true` cuando las tarjetas no entran todas a un tamano usable y la
  /// grilla tiene que scrollear en vez de seguir achicandolas.
  final bool scrolls;

  double get aspectRatio => tileWidth / tileHeight;
}

/// Elige la cantidad de columnas que hace que, al repartir [itemCount]
/// tarjetas en `columns` columnas (y por lo tanto `ceil(itemCount/columns)`
/// filas), la celda resultante quede lo mas cerca posible de
/// [targetAspectRatio] (ancho/alto) llenando todo el espacio.
///
/// Funcion pura y compartida: la usan el deck de escritorio
/// (`ActionsDeckGrid`) y el de movil (`ConnectedDeviceScreen`).
int bestColumnCountForAspect({
  required int itemCount,
  required double availableWidth,
  required double availableHeight,
  required double spacing,
  double targetAspectRatio = 1.6,
}) {
  if (itemCount <= 1) return 1;

  var bestColumns = 1;
  var bestScore = double.infinity;
  for (var columns = 1; columns <= itemCount; columns++) {
    final rows = (itemCount / columns).ceil();
    final cellWidth = (availableWidth - spacing * (columns - 1)) / columns;
    final cellHeight = (availableHeight - spacing * (rows - 1)) / rows;
    if (cellWidth <= 0 || cellHeight <= 0) continue;

    final score = (cellWidth / cellHeight - targetAspectRatio).abs();
    if (score < bestScore) {
      bestScore = score;
      bestColumns = columns;
    }
  }
  return bestColumns;
}

/// Cuantas columnas entran en el panel de acciones **compacto** del centro de
/// control: una o dos, nunca mas.
///
/// A diferencia del deck, este panel es angosto (180-320 dp), asi que repartir
/// en mas de dos columnas no tiene sentido. Pura y testeada directo, igual que
/// `metricColumnsFor`.
int actionsPanelColumnsFor(
  double availableWidth, {
  double spacing = AppSpacing.sm,
}) {
  final twoColumnsWidth = (availableWidth - spacing) / 2;
  return twoColumnsWidth >= AppSizes.minCompactActionTileWidth ? 2 : 1;
}

/// Layout del deck en MOVIL, donde hay dos regimenes distintos:///
/// - Si las acciones entran a un tamano usable, se estiran para llenar toda
///   la pantalla (con 4 acciones en horizontal, una grilla de extent fijo
///   dejaba media pantalla vacia).
/// - Si no entran, se cae a un ancho maximo por tarjeta y la grilla
///   scrollea. Seguir achicandolas —como hace el deck de escritorio— las
///   vuelve intocables en un telefono.
DeckGridLayout resolveDeckGrid({
  required int itemCount,
  required double availableWidth,
  required double availableHeight,
  double spacing = AppSpacing.sm,
  double targetAspectRatio = 1.4,
}) {
  final safeCount = math.max(1, itemCount);

  final fillColumns = bestColumnCountForAspect(
    itemCount: safeCount,
    availableWidth: availableWidth,
    availableHeight: availableHeight,
    spacing: spacing,
    targetAspectRatio: targetAspectRatio,
  );
  final fillRows = (safeCount / fillColumns).ceil();
  final fillWidth =
      (availableWidth - spacing * (fillColumns - 1)) / fillColumns;
  final fillHeight = (availableHeight - spacing * (fillRows - 1)) / fillRows;

  if (fillWidth >= AppSizes.minActionTileWidth &&
      fillHeight >= AppSizes.minActionTileHeight) {
    return DeckGridLayout(
      columns: fillColumns,
      tileWidth: fillWidth,
      tileHeight: fillHeight,
      scrolls: false,
    );
  }

  final columns = math.max(
    1,
    (availableWidth / AppSizes.maxActionTileExtent).ceil(),
  );
  final tileWidth = (availableWidth - spacing * (columns - 1)) / columns;
  return DeckGridLayout(
    columns: columns,
    tileWidth: tileWidth,
    tileHeight: tileWidth / AppSizes.actionTileAspectRatio,
    scrolls: true,
  );
}
