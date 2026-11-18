import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/metric_kind.dart';
import 'metric_specs.dart';
import 'metric_tile.dart';

/// Retraso entre la entrada animada de cada tile consecutiva.
const _kStaggerStep = AppDuration.staggerSlow;

/// Como se acomodan las metricas.
enum MetricsPanelAxis {
  /// Franja: las tiles se reparten a lo ancho, arriba del deck. Es el modo
  /// de escritorio y el de un telefono en vertical.
  horizontal,

  /// Riel: las tiles se apilan en una columna a la izquierda, y el deck
  /// ocupa el resto del ancho. Es el modo de telefono/tablet en horizontal,
  /// donde el alto es el recurso escaso.
  vertical,

  /// Franja micro: una sola fila de tiles **siempre** en
  /// [MetricDensity.micro] (grafico chico + valor, sin titulo ni badges).
  ///
  /// Es el modo de la ventana compacta, donde el ancho util son ~300 dp:
  /// ahi la franja normal cae a 2 columnas x 3 filas y se come media
  /// ventana, y el riel vertical se lleva un tercio del ancho. La densidad
  /// no se decide midiendo como en los otros dos modos -- este layout ES la
  /// decision de mostrar lo minimo.
  microStrip,
}

/// Cuantas filas necesita la franja micro para [count] metricas en
/// [availableWidth]: una sola mientras cada tile no baje de
/// [AppSizes.minMicroMetricTileWidth], y dos si no entran.
///
/// Pura y publica por el mismo motivo que [metricColumnsFor]: es la regla
/// que decide como se ve la franja del modo compacto, y se testea sin
/// montar widgets.
int microMetricRowsFor({
  required double availableWidth,
  required int count,
  double spacing = AppSpacing.xs,
}) {
  if (count <= 0) return 0;
  final tileWidth = (availableWidth - spacing * (count - 1)) / count;
  return tileWidth >= AppSizes.minMicroMetricTileWidth ? 1 : 2;
}

/// Cuantas columnas de metricas entran en [availableWidth] respetando
/// [AppSizes.minMetricTileWidth], acotado a [count].
///
/// Funcion pura y publica a proposito: es la regla que decide como se ve la
/// franja en cada tamano de pantalla, y se testea directamente sin montar
/// widgets (ver `test/metrics_panel_test.dart`).
int metricColumnsFor({
  required double availableWidth,
  required int count,
  double spacing = AppSpacing.sm,
}) {
  if (count <= 0) return 0;
  // Se busca el mayor n <= count tal que el ancho por tile, ya descontados
  // los separadores, no baje del minimo.
  for (var columns = math.min(count, 8); columns >= 1; columns--) {
    final tileWidth = (availableWidth - spacing * (columns - 1)) / columns;
    if (tileWidth >= AppSizes.minMetricTileWidth) return columns;
  }
  return 1;
}

/// Como queda repartida la franja horizontal.
///
/// [columns] se cuenta en **unidades**, no en tiles: una metrica puede pedir
/// mas de una (`MetricSpec.widthUnits`). [expandWideTiles] dice si ese pedido
/// se concedio; cuando es `false`, toda tile ocupa una unidad y el resultado
/// es identico al de antes de que existieran las tiles anchas.
typedef MetricStripLayout = ({
  int columns,
  int rows,
  double unitWidth,
  double tileHeight,
  bool expandWideTiles,
});

/// Cuantas filas hacen falta si la tile en [wideIndex] (si la hay, `-1` si
/// no) se gana una fila PROPIA en el medio de las demas -- nunca comparte
/// fila con nada, para no repetir el hueco/desalineacion que dejaba una tile
/// ancha que no entraba del todo. Las tiles antes y despues se reparten en
/// [columns] columnas, como siempre.
///
/// Pura y testeada por el mismo motivo que el resto de estas funciones.
int rowsWithDedicatedWideRow({
  required int tileCount,
  required int columns,
  required int wideIndex,
}) {
  if (tileCount <= 0) return 0;
  if (wideIndex < 0 || wideIndex >= tileCount) {
    return (tileCount / columns).ceil();
  }
  final before = wideIndex;
  final after = tileCount - wideIndex - 1;
  final beforeRows = before == 0 ? 0 : (before / columns).ceil();
  final afterRows = after == 0 ? 0 : (after / columns).ceil();
  return beforeRows + 1 + afterRows;
}

/// Reparte la franja entre [tileCount] tiles que suman [unitCount] unidades.
///
/// Pura y publica por el mismo motivo que [metricColumnsFor]: decide como se
/// ve la franja en cada tamano de ventana y se testea sin montar widgets.
///
/// El ancho doble se concede de dos formas posibles, en este orden:
///
/// 1. **Todo entra en una sola fila junto con el resto.** El reparto de
///    siempre: todas las unidades (las sueltas mas las de la tile ancha)
///    caben en una unica fila de la franja.
/// 2. **La tile ancha se gana una fila propia**, sin compartir con nada --
///    esto es lo que permite el desglose de discos en el riel vertical de un
///    telefono, donde las 5 metricas ya necesitan mas de una fila: en vez de
///    exigir que TODO entre en una sola fila, alcanza con que la tile ancha
///    quepa sola en la suya. Necesita [wideTileIndex] (la posicion de esa
///    tile, `-1` si no hay ninguna) para saber donde cae esa fila propia.
///
/// Las dos formas exigen ademas que **sobre alto para la densidad
/// completa**: el cuerpo expandido (la lista de discos) necesita el alto de
/// [MetricDensity.full]; mas apretado que eso, una tile mas ancha mostrando
/// el mismo agregado solo gastaria espacio.
MetricStripLayout metricStripLayoutFor({
  required double availableWidth,
  required double? availableHeight,
  required int tileCount,
  required int unitCount,
  int wideTileIndex = -1,
  double spacing = AppSpacing.sm,
}) {
  double widthFor(int columns) =>
      (availableWidth - spacing * (columns - 1)) / columns;
  double heightFor(int rows) => availableHeight == null
      ? AppSizes.minFullMetricTileHeight
      : (availableHeight - spacing * (rows - 1)) / rows;

  final hasWideTile = unitCount > tileCount && wideTileIndex >= 0;

  // Camino 1: todo entra en una sola fila.
  final allUnitsFitOneRow =
      unitCount > tileCount &&
      metricColumnsFor(
            availableWidth: availableWidth,
            count: unitCount,
            spacing: spacing,
          ) >=
          unitCount;
  if (allUnitsFitOneRow) {
    final tileHeight = heightFor(1);
    if (metricDensityFor(tileHeight) == MetricDensity.full) {
      return (
        columns: unitCount,
        rows: 1,
        unitWidth: widthFor(unitCount),
        tileHeight: tileHeight,
        expandWideTiles: true,
      );
    }
  }

  // Camino 2: la tile ancha se gana una fila propia (>=2 columnas para que
  // valga la pena: con una sola columna no hay nada que ganar ocupando dos).
  if (hasWideTile) {
    final columns = metricColumnsFor(
      availableWidth: availableWidth,
      count: tileCount,
      spacing: spacing,
    );
    if (columns >= 2) {
      final rows = rowsWithDedicatedWideRow(
        tileCount: tileCount,
        columns: columns,
        wideIndex: wideTileIndex,
      );
      final tileHeight = heightFor(rows);
      if (metricDensityFor(tileHeight) == MetricDensity.full) {
        return (
          columns: columns,
          rows: rows,
          unitWidth: widthFor(columns),
          tileHeight: tileHeight,
          expandWideTiles: true,
        );
      }
    }
  }

  // Reparto parejo: cada tile (incluida la ancha) ocupa una sola unidad.
  final columns = metricColumnsFor(
    availableWidth: availableWidth,
    count: tileCount,
    spacing: spacing,
  );
  final rows = (tileCount / columns).ceil();
  return (
    columns: columns,
    rows: rows,
    unitWidth: widthFor(columns),
    tileHeight: heightFor(rows),
    expandWideTiles: false,
  );
}

/// El riel y la franja comparten el mismo criterio: la densidad la manda el
/// alto por tile, no la plataforma ni la orientacion.
MetricDensity metricDensityFor(double tileHeight) {
  if (tileHeight >= AppSizes.minFullMetricTileHeight) {
    return MetricDensity.full;
  }
  if (tileHeight >= AppSizes.minCompactMetricTileHeight) {
    return MetricDensity.compact;
  }
  return MetricDensity.micro;
}

/// Panel de metricas responsive y colapsable. No sabe de donde salen los
/// datos: recibe las [MetricSpec] ya armadas (ver `buildMetricSpecs`), asi
/// que sirve igual al dashboard local de la PC y al espejo remoto del
/// telefono.
class MetricsPanel extends StatelessWidget {
  const MetricsPanel({
    super.key,
    required this.specs,
    required this.axis,
    required this.collapsed,
    required this.onToggleCollapsed,
    this.mirrored = false,
    this.selectedMetric,
    this.onSelectMetric,
    this.railWidth,
  });

  final List<MetricSpec> specs;
  final MetricsPanelAxis axis;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  /// El panel esta anclado al borde OPUESTO al habitual: derecha en el riel
  /// vertical, abajo en las dos franjas horizontales.
  ///
  /// Es un solo bool y no un `enum Side` porque cada eje solo tiene dos
  /// posiciones posibles, y lo unico que cambia es de que lado queda el
  /// chevron y hacia donde apunta. Lo usan los layouts de la pantalla
  /// principal (`HomeLayout`); el espejo remoto del telefono nunca lo pasa.
  final bool mirrored;

  /// La metrica cuyo desglose de procesos se esta viendo, si hay alguno.
  final MetricKind? selectedMetric;

  /// Abre el desglose de una metrica. **En `null`, ninguna tile es
  /// clicable**: asi es como el espejo del telefono y la ventana compacta
  /// quedan exactamente igual que antes sin necesitar ningun `Platform.is...`
  /// dentro de un widget compartido.
  final ValueChanged<MetricKind>? onSelectMetric;

  /// Ancho del riel vertical impuesto por el padre, o `null` para que lo
  /// calcule el propio panel.
  ///
  /// Existe porque en el escritorio ese ancho **lo reparte el usuario**
  /// arrastrando el divisor (`PanelSlot.metricsRail`), y el panel no puede
  /// deducirlo: el calculo automatico sale de `MediaQuery`, que devuelve el
  /// ancho de la ventana entera y no el trozo que le toco al riel.
  ///
  /// El telefono (`ConnectedDeviceScreen`) lo deja en `null` y sigue con el
  /// calculo de siempre: ahi no hay divisores arrastrables porque en touch no
  /// hay hover, o sea que no habria forma de descubrirlos.
  final double? railWidth;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppDuration.collapse,
      curve: AppCurves.standard,
      // Crece desde el borde al que esta anclado: si no, la franja de abajo
      // se despegaria del borde inferior mientras dura la animacion.
      alignment: axis == MetricsPanelAxis.vertical
          ? (mirrored ? Alignment.centerRight : Alignment.centerLeft)
          : (mirrored ? Alignment.bottomCenter : Alignment.topCenter),
      child: collapsed ? _buildCollapsed(context) : _buildExpanded(context),
    );
  }

  /// El `onTap` que le toca a una tile. Ademas de que el host haya pasado un
  /// callback, la metrica tiene que poder desglosarse: Disco y Red no pueden
  /// (ver `MetricKind.supportsProcessBreakdown`), y ofrecerlas clicables para
  /// despues no mostrar nada es peor que no ofrecerlas.
  VoidCallback? _tapFor(MetricSpec spec) {
    if (onSelectMetric == null || !spec.kind.supportsProcessBreakdown) {
      return null;
    }
    return () => onSelectMetric!(spec.kind);
  }

  // --- colapsado --------------------------------------------------------

  Widget _buildCollapsed(BuildContext context) {
    final horizontal = axis != MetricsPanelAxis.vertical;
    // El chevron apunta hacia donde se va a abrir el panel, que es hacia
    // adentro de la pantalla: un panel anclado abajo se abre hacia arriba.
    final button = _CollapseButton(
      icon: horizontal
          ? (mirrored ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down)
          : (mirrored ? Icons.keyboard_arrow_left : Icons.keyboard_arrow_right),
      tooltip: 'Mostrar métricas',
      onPressed: onToggleCollapsed,
    );

    return SizedBox(
      width: horizontal ? double.infinity : AppSizes.collapsedMetricsExtent,
      height: horizontal ? AppSizes.collapsedMetricsExtent : double.infinity,
      child: Align(
        alignment: horizontal ? Alignment.centerRight : Alignment.center,
        child: button,
      ),
    );
  }

  // --- expandido --------------------------------------------------------

  Widget _buildExpanded(BuildContext context) {
    // Sin metricas no hay nada que repartir (y las divisiones por cantidad
    // de columnas darian NaN).
    if (specs.isEmpty) return const SizedBox.shrink();
    return switch (axis) {
      MetricsPanelAxis.horizontal => _buildStrip(context),
      MetricsPanelAxis.vertical => _buildRail(context),
      MetricsPanelAxis.microStrip => _buildMicroStrip(context),
    };
  }

  /// Franja micro (ventana compacta): grafico chico + valor, repartidos a lo
  /// ancho. Comparte el chevron con los otros dos modos -- plegar aca pliega
  /// tambien en pantalla completa, porque "mostrar metricas" es una sola
  /// preferencia (`metrics_collapsed`), no una por ventana.
  Widget _buildMicroStrip(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tilesWidth =
            constraints.maxWidth - AppSizes.collapsedMetricsExtent;
        final rows = microMetricRowsFor(
          availableWidth: tilesWidth,
          count: specs.length,
        );
        final columns = (specs.length / rows).ceil();
        final tileWidth =
            (tilesWidth - AppSpacing.xs * (columns - 1)) / columns;
        // La tile micro pone el chart en un `Expanded`, asi que necesita
        // alto acotado si o si: sin esto el `Wrap` le pasa alto infinito y
        // revienta el layout.
        final tileHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - AppSpacing.xs * (rows - 1)) / rows
            : AppSizes.microMetricStripHeight;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (index, spec) in specs.indexed)
                    SizedBox(
                      width: tileWidth,
                      height: tileHeight,
                      child: MetricTile(
                        spec: spec,
                        density: MetricDensity.micro,
                        entryDelay: _kStaggerStep * index,
                        onTap: _tapFor(spec),
                        selected: selectedMetric == spec.kind,
                      ),
                    ),
                ],
              ),
            ),
            _CollapseButton(
              icon: mirrored
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              tooltip: 'Ocultar métricas',
              onPressed: onToggleCollapsed,
            ),
          ],
        );
      },
    );
  }

  /// Franja horizontal: las tiles llenan el ancho de borde a borde (el ancho
  /// se calcula, no se hardcodea), y bajan de densidad si el alto no alcanza.
  Widget _buildStrip(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // El chevron va al final de la franja, asi que su ancho sale del
        // presupuesto de las tiles.
        final tilesWidth =
            constraints.maxWidth - AppSizes.collapsedMetricsExtent;
        final layout = metricStripLayoutFor(
          availableWidth: tilesWidth,
          availableHeight: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null,
          tileCount: specs.length,
          unitCount: specs.fold(0, (sum, spec) => sum + spec.widthUnits),
          wideTileIndex: specs.indexWhere((spec) => spec.widthUnits > 1),
        );
        final density = metricDensityFor(layout.tileHeight);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (index, spec) in specs.indexed)
                    SizedBox(
                      width: _tileWidthFor(spec, layout),
                      height: layout.tileHeight,
                      child: MetricTile(
                        spec: spec,
                        density: density,
                        expanded: layout.expandWideTiles && spec.widthUnits > 1,
                        entryDelay: _kStaggerStep * index,
                        onTap: _tapFor(spec),
                        selected: selectedMetric == spec.kind,
                      ),
                    ),
                ],
              ),
            ),
            _CollapseButton(
              icon: mirrored
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              tooltip: 'Ocultar métricas',
              onPressed: onToggleCollapsed,
            ),
          ],
        );
      },
    );
  }

  /// Riel vertical: columna angosta a la izquierda con las tiles apiladas y
  /// el chevron pegado al borde derecho. Scrollea en vez de desbordar si el
  /// telefono es muy bajo.
  Widget _buildRail(BuildContext context) {
    // Sin ancho impuesto, sale de `MediaQuery` y no de las constraints: el
    // riel vive como hijo no-flex de un `Row`, que le pasa ancho NO ACOTADO,
    // asi que `constraints.maxWidth` seria infinito y el factor proporcional
    // no haria nada (siempre daria el maximo del clamp).
    final width =
        railWidth ??
        (MediaQuery.sizeOf(context).width * AppSizes.metricRailWidthFactor)
            .clamp(AppSizes.metricRailMinWidth, AppSizes.metricRailMaxWidth);
    // El chevron de plegado se lleva su franja fija del ancho; lo que queda
    // es para las tiles. Nunca negativo: con un riel arrastrado hasta el
    // minimo, restar la franja del chevron podria pasarse de cero y un ancho
    // negativo revienta el `SizedBox` en tiempo de ejecucion.
    final tilesWidth = math.max(0.0, width - AppSizes.collapsedMetricsExtent);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : AppSizes.minFullMetricTileHeight * specs.length;
        // Reparte el alto entre las 5 tiles, pero nunca por debajo del alto
        // que necesitan para seguir mostrando titulo/valor/badges: si no
        // entran, el `ListView` scrollea en vez de bajar de densidad.
        final tileHeight = math.max(
          AppSizes.railPreferredTileHeight,
          (availableHeight - AppSpacing.sm * (specs.length - 1)) / specs.length,
        );
        final density = metricDensityFor(tileHeight);

        final tiles = SizedBox(
          width: tilesWidth,
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: specs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => SizedBox(
              height: tileHeight,
              child: MetricTile(
                spec: specs[index],
                density: density,
                // El riel tambien expande la tile que tenga cuerpo propio
                // --hoy solo almacenamiento-- si le queda alto para la
                // densidad completa. Sin esto, en los layouts de riel la
                // metrica de Disco solo podia mostrar el agregado, y "2.1 TB
                // de 2.3 TB" no dice cual de los tres discos se esta
                // llenando, que es justo lo que uno quiere saber.
                expanded: density == MetricDensity.full,
                entryDelay: _kStaggerStep * index,
                onTap: _tapFor(specs[index]),
                selected: selectedMetric == specs[index].kind,
              ),
            ),
          ),
        );
        // El chevron va SIEMPRE del lado de adentro de la pantalla, o sea
        // pegado al deck: es la frontera entre los dos, y del lado de afuera
        // quedaria contra el borde de la ventana, lejos de lo que separa.
        final collapse = _CollapseButton(
          icon: mirrored
              ? Icons.keyboard_arrow_right
              : Icons.keyboard_arrow_left,
          tooltip: 'Ocultar métricas',
          onPressed: onToggleCollapsed,
        );

        return SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: mirrored ? [collapse, tiles] : [tiles, collapse],
          ),
        );
      },
    );
  }

  /// Una tile ancha ocupa sus unidades MAS los separadores que se come al
  /// fusionarlas: sin ese termino la tile queda corta y la fila no llega al
  /// borde.
  ///
  /// Acotado a `layout.columns`: en el camino de la fila propia (ver
  /// `rowsWithDedicatedWideRow`), `layout.columns` son las columnas de las
  /// tiles SUELTAS, no la unidad fina del camino de una sola fila -- pedir
  /// mas que eso desbordaria la franja.
  static double _tileWidthFor(MetricSpec spec, MetricStripLayout layout) {
    final units = layout.expandWideTiles
        ? math.min(spec.widthUnits, layout.columns)
        : 1;
    return layout.unitWidth * units + AppSpacing.sm * (units - 1);
  }
}

/// Chevron de baja emfasis: tiene que estar ahi sin competir con las
/// metricas ni con el deck.
class _CollapseButton extends StatelessWidget {
  const _CollapseButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: AppSizes.collapsedMetricsExtent,
      child: Center(
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: AppSizes.collapsedMetricsExtent,
            minHeight: AppSizes.collapsedMetricsExtent,
          ),
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
