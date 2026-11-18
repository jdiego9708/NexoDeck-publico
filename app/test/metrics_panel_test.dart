import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/core/widgets/interactive_card.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/capacity_bar.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/cpu_chip_chart.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/thermometer_chart.dart';
import 'package:nexodeck/features/dashboard/domain/hardware_snapshot.dart';
import 'package:nexodeck/features/dashboard/domain/metric_kind.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/disk_usage_list.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_specs.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_tile.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metrics_panel.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/ram_module_chart.dart';

/// Snapshot con TODOS los campos opcionales presentes, para poder afirmar
/// que el movil muestra los mismos datos secundarios que la PC (MHz, °C,
/// VRAM, totales) y no solo el porcentaje.
const _snapshot = HardwareSnapshot(
  cpuUsage: 62,
  cpuFreqMhz: 4200,
  cpuTempC: 56,
  ramUsedMb: 9216,
  ramTotalMb: 32768,
  diskUsedMb: 2167808,
  diskTotalMb: 2394112,
  disks: _disks,
  netRxBytesPerSec: 2048,
  netTxBytesPerSec: 1024,
  gpuUsage: 13,
  gpuTempC: 61,
  gpuVramUsedMb: 2534,
  gpuVramTotalMb: 16311,
  gpuPowerWatts: 68,
  gpuPowerLimitWatts: 198,
);

/// Tres discos, que es lo que tiene el equipo principal: dos SSD y un HDD.
/// Las cifras suman exactamente `diskUsedMb`/`diskTotalMb` del snapshot, que
/// es la invariante que sostiene Rust (`disks::totals`).
const _diskC = DiskUsage(
  mountPoint: 'C:',
  label: '',
  kind: DiskMediaKind.ssd,
  usedMb: 396288,
  totalMb: 487424,
  tempC: 44,
  tempAgeSecs: 3,
);
const _diskD = DiskUsage(
  mountPoint: 'D:',
  label: 'Secundario',
  kind: DiskMediaKind.hdd,
  usedMb: 933888,
  totalMb: 953344,
  // Por encima de los 50 del plato: es el caso que tiene que pintarse de
  // alerta mientras el SSD de al lado, mas caliente, no.
  tempC: 52,
  tempAgeSecs: 5,
);
const _diskE = DiskUsage(
  mountPoint: 'E:',
  label: 'SSD',
  kind: DiskMediaKind.ssd,
  usedMb: 837632,
  totalMb: 953344,
  // 63 y no 61: el 61 es la temperatura de GPU de este mismo fixture, y los
  // finders por texto no sabrian de cual de las dos hablan.
  tempC: 63,
  // Dormido: la ultima lectura es de hace media hora. Es el caso que
  // ejercita la atenuacion, y va en el SSD porque a 63 no cruza su umbral
  // -- un disco en alerta se pinta de rojo y la antiguedad no se le nota.
  tempAgeSecs: 1800,
);
const _disks = [_diskC, _diskD, _diskE];

/// El mismo snapshot pero con un solo disco: ahi la lista no aporta nada
/// sobre el agregado y la tile no tiene que pedir ancho de mas.
final _singleDiskSnapshot = HardwareSnapshot(
  cpuUsage: _snapshot.cpuUsage,
  cpuFreqMhz: _snapshot.cpuFreqMhz,
  cpuTempC: _snapshot.cpuTempC,
  ramUsedMb: _snapshot.ramUsedMb,
  ramTotalMb: _snapshot.ramTotalMb,
  diskUsedMb: 396288,
  diskTotalMb: 487424,
  disks: const [_diskC],
  netRxBytesPerSec: _snapshot.netRxBytesPerSec,
  netTxBytesPerSec: _snapshot.netTxBytesPerSec,
  gpuUsage: _snapshot.gpuUsage,
  gpuTempC: _snapshot.gpuTempC,
  gpuVramUsedMb: _snapshot.gpuVramUsedMb,
  gpuVramTotalMb: _snapshot.gpuVramTotalMb,
  gpuPowerWatts: _snapshot.gpuPowerWatts,
  gpuPowerLimitWatts: _snapshot.gpuPowerLimitWatts,
);

/// Los mismos tres discos pero sin ninguna lectura de temperatura: es lo que
/// llega fuera de Windows y de un binario viejo del otro lado del cable.
final _noDiskTempSnapshot = HardwareSnapshot(
  cpuUsage: _snapshot.cpuUsage,
  cpuFreqMhz: _snapshot.cpuFreqMhz,
  cpuTempC: _snapshot.cpuTempC,
  ramUsedMb: _snapshot.ramUsedMb,
  ramTotalMb: _snapshot.ramTotalMb,
  diskUsedMb: _snapshot.diskUsedMb,
  diskTotalMb: _snapshot.diskTotalMb,
  disks: _disks
      .map(
        (disk) => DiskUsage(
          mountPoint: disk.mountPoint,
          label: disk.label,
          kind: disk.kind,
          usedMb: disk.usedMb,
          totalMb: disk.totalMb,
        ),
      )
      .toList(growable: false),
  netRxBytesPerSec: _snapshot.netRxBytesPerSec,
  netTxBytesPerSec: _snapshot.netTxBytesPerSec,
  gpuUsage: _snapshot.gpuUsage,
  gpuTempC: _snapshot.gpuTempC,
  gpuVramUsedMb: _snapshot.gpuVramUsedMb,
  gpuVramTotalMb: _snapshot.gpuVramTotalMb,
);

void main() {
  group('microMetricRowsFor', () {
    test('las 5 metricas entran en una fila en la ventana compacta', () {
      // 320 dp de ventana menos los paddings laterales y el chevron.
      expect(microMetricRowsFor(availableWidth: 276, count: 5), 1);
    });

    test('pasa a dos filas antes de dejar las tiles ilegibles', () {
      // A 5 tiles quedarian ~34 dp cada una, por debajo del minimo.
      expect(microMetricRowsFor(availableWidth: 190, count: 5), 2);
    });

    test('sin metricas no hay filas', () {
      expect(microMetricRowsFor(availableWidth: 276, count: 0), 0);
    });
  });

  group('metricColumnsFor', () {
    test('reparte una sola columna en un telefono muy angosto', () {
      expect(metricColumnsFor(availableWidth: 260, count: 5), 1);
    });

    test('entran dos columnas en un telefono tipico de 360 dp', () {
      // 360 menos los paddings del `Column` y el ancho del chevron.
      expect(metricColumnsFor(availableWidth: 308, count: 5), 2);
    });

    test('las 5 metricas entran en una fila en escritorio', () {
      expect(metricColumnsFor(availableWidth: 1100, count: 5), 5);
    });

    test('nunca devuelve mas columnas que metricas', () {
      expect(metricColumnsFor(availableWidth: 4000, count: 5), 5);
      expect(metricColumnsFor(availableWidth: 4000, count: 2), 2);
    });

    test('nunca baja de una columna aunque el ancho sea absurdo', () {
      expect(metricColumnsFor(availableWidth: 10, count: 5), 1);
    });

    test('respeta el ancho minimo por tile en el limite', () {
      // Justo el ancho para 2 tiles + separador.
      final exact = AppSizes.minMetricTileWidth * 2 + AppSpacing.sm;
      expect(metricColumnsFor(availableWidth: exact, count: 5), 2);
      expect(metricColumnsFor(availableWidth: exact - 1, count: 5), 1);
    });
  });

  group('metricStripLayoutFor', () {
    // 5 metricas de las que una pide ancho doble: 6 unidades en total.
    MetricStripLayout layout({
      required double width,
      double? height = 200,
      int units = 6,
    }) => metricStripLayoutFor(
      availableWidth: width,
      availableHeight: height,
      tileCount: 5,
      unitCount: units,
    );

    test('en escritorio ancho concede el ancho doble', () {
      final result = layout(width: 1100);
      expect(result.expandWideTiles, isTrue);
      expect(result.columns, 6);
      expect(result.rows, 1);
    });

    test('no lo concede si las unidades no entran en una sola fila', () {
      // Alcanza para las 5 tiles sueltas, no para las 6 unidades.
      final result = layout(width: AppSizes.minMetricTileWidth * 5.5);
      expect(result.expandWideTiles, isFalse);
      expect(result.columns, 5);
    });

    test('no lo concede si el alto no da para la densidad completa', () {
      // La lista de discos necesita el alto de `MetricDensity.full`; a 60 dp
      // la tile ya esta en compacta y el ancho de mas no mostraria nada.
      final result = layout(width: 1100, height: 60);
      expect(result.expandWideTiles, isFalse);
      expect(result.columns, 5);
    });

    test('con alto no acotado supone el minimo de la densidad completa', () {
      final result = layout(width: 1100, height: null);
      expect(result.tileHeight, AppSizes.minFullMetricTileHeight);
      expect(result.expandWideTiles, isTrue);
    });

    test('sin unidades extra se comporta igual que el reparto de siempre', () {
      final result = layout(width: 1100, units: 5);
      expect(result.expandWideTiles, isFalse);
      expect(result.columns, metricColumnsFor(availableWidth: 1100, count: 5));
    });

    test('las unidades que no se conceden no dejan huecos en la fila', () {
      // Reconstruye el reparto real: la suma de los anchos mas los
      // separadores tiene que llenar el ancho disponible exactamente.
      const width = 1100.0;
      final result = layout(width: width);
      final total =
          result.unitWidth * result.columns +
          AppSpacing.sm * (result.columns - 1);
      expect(total, closeTo(width, 0.001));
    });

    test(
      'en un telefono angosto la tile ancha se gana una fila propia',
      () {
        // 360 dp: no entran las 6 unidades en una fila (la condicion de
        // "escritorio ancho" de arriba), pero si hay alto para 3 filas a
        // densidad completa -- la tile ancha (indice 2 de 5) se expande
        // igual, en su propia fila.
        final result = metricStripLayoutFor(
          availableWidth: 360,
          availableHeight: 800,
          tileCount: 5,
          unitCount: 6,
          wideTileIndex: 2,
        );
        expect(result.expandWideTiles, isTrue);
        expect(result.columns, 2);
        expect(result.rows, 3);
      },
    );

    test(
      'sin wideTileIndex no se concede la fila propia',
      () {
        // Mismo ancho/alto que el caso de arriba, pero sin decir donde cae
        // la tile ancha (`wideTileIndex` en su default de -1): sin eso no
        // hay forma segura de saber que fila le toca, asi que se queda en
        // el reparto parejo -- mismo comportamiento que antes de que este
        // camino existiera.
        final result = metricStripLayoutFor(
          availableWidth: 360,
          availableHeight: 800,
          tileCount: 5,
          unitCount: 6,
        );
        expect(result.expandWideTiles, isFalse);
      },
    );

    test(
      'sin alto de sobra tampoco se concede la fila propia',
      () {
        final result = metricStripLayoutFor(
          availableWidth: 360,
          availableHeight: 260,
          tileCount: 5,
          unitCount: 6,
          wideTileIndex: 2,
        );
        expect(result.expandWideTiles, isFalse);
        expect(result.columns, 2);
      },
    );

    test(
      'con una sola columna no hay nada que ganar expandiendo',
      () {
        final result = metricStripLayoutFor(
          availableWidth: AppSizes.minMetricTileWidth * 1.2,
          availableHeight: 2000,
          tileCount: 5,
          unitCount: 6,
          wideTileIndex: 2,
        );
        expect(result.expandWideTiles, isFalse);
        expect(result.columns, 1);
      },
    );
  });

  group('rowsWithDedicatedWideRow', () {
    test('la tile ancha en el medio no comparte fila con nada', () {
      // cpu, ram | disco (fila propia) | gpu, red -- 3 filas con 2 columnas.
      expect(
        rowsWithDedicatedWideRow(tileCount: 5, columns: 2, wideIndex: 2),
        3,
      );
    });

    test('la tile ancha al principio abre su propia fila primero', () {
      expect(
        rowsWithDedicatedWideRow(tileCount: 5, columns: 2, wideIndex: 0),
        3,
      );
    });

    test('la tile ancha al final cierra su propia fila', () {
      expect(
        rowsWithDedicatedWideRow(tileCount: 5, columns: 2, wideIndex: 4),
        3,
      );
    });

    test('sin tile ancha (-1) es el reparto parejo de siempre', () {
      expect(
        rowsWithDedicatedWideRow(tileCount: 5, columns: 2, wideIndex: -1),
        3,
      );
    });

    test('con mas columnas el resto se acomoda distinto', () {
      // cpu, ram, (hueco) | disco (fila propia) | gpu, red, (hueco).
      expect(
        rowsWithDedicatedWideRow(tileCount: 5, columns: 3, wideIndex: 2),
        3,
      );
    });
  });

  group('MetricsPanel', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required Size surface,
      required MetricsPanelAxis axis,
      required bool collapsed,
      VoidCallback? onToggle,
      HardwareSnapshot snapshot = _snapshot,
      ValueChanged<MetricKind>? onSelectMetric,
      MetricKind? selectedMetric,
    }) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => MetricsPanel(
                specs: buildMetricSpecs(
                  snapshot: snapshot,
                  scheme: Theme.of(context).colorScheme,
                  cpuHistory: const [10, 20, 30],
                  netRxHistoryKb: const [1, 2, 3],
                  netTxHistoryKb: const [1, 1, 2],
                ),
                axis: axis,
                collapsed: collapsed,
                onToggleCollapsed: onToggle ?? () {},
                onSelectMetric: onSelectMetric,
                selectedMetric: selectedMetric,
              ),
            ),
          ),
        ),
      );
      // Las tiles entran con `flutter_animate` escalonado.
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('en vertical muestra las 5 metricas con sus badges', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(360, 800),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(find.byType(MetricTile), findsNWidgets(5));
      // Los datos secundarios que el modo compacto viejo descartaba.
      expect(find.text('4.20 GHz'), findsOneWidget);
      expect(find.text('56°C'), findsOneWidget);
      expect(find.text('de 32.0 GB'), findsOneWidget);
      // La VRAM ya no es un badge de texto: vive dentro de la barra de
      // capacidad, con la cifra sobre el relleno.
      expect(find.byType(CapacityBar), findsOneWidget);
      expect(find.text('2.5 GB / 15.9 GB'), findsOneWidget);
    });

    testWidgets('en horizontal el riel ocupa una franja acotada del ancho', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(800, 360),
        axis: MetricsPanelAxis.vertical,
        collapsed: false,
      );

      expect(find.byType(MetricTile), findsNWidgets(5));

      final railWidth = tester.getSize(find.byType(MetricsPanel)).width;
      expect(railWidth, lessThanOrEqualTo(AppSizes.metricRailMaxWidth));
      expect(railWidth, greaterThanOrEqualTo(AppSizes.metricRailMinWidth));
      // Le deja al deck la mayor parte del ancho.
      expect(railWidth, lessThan(800 * 0.4));
    });

    testWidgets('colapsado esconde las tiles y deja solo el chevron', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(800, 360),
        axis: MetricsPanelAxis.vertical,
        collapsed: true,
      );

      expect(find.byType(MetricTile), findsNothing);
      expect(find.byTooltip('Mostrar métricas'), findsOneWidget);
      expect(
        tester.getSize(find.byType(MetricsPanel)).width,
        AppSizes.collapsedMetricsExtent,
      );
    });

    testWidgets('el chevron dispara el toggle', (tester) async {
      var toggles = 0;
      await pumpPanel(
        tester,
        surface: const Size(1100, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        onToggle: () => toggles++,
      );

      await tester.tap(find.byTooltip('Ocultar métricas'));
      await tester.pump();
      expect(toggles, 1);
    });

    testWidgets(
      'las 5 tiles del riel entran en un telefono apaisado, con badges',
      (tester) async {
        // Alto real que le queda al riel en un S24 Ultra apaisado debajo del
        // AppBar. Gracias a la densidad compacta (titulo y valor en la misma
        // linea) las 5 entran sin scroll y sin perder MHz/°C/VRAM.
        await pumpPanel(
          tester,
          surface: const Size(891, 309),
          axis: MetricsPanelAxis.vertical,
          collapsed: false,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(MetricTile), findsNWidgets(5));
        // En el riel de un telefono la tile queda en densidad compacta y no
        // hay alto para la barra de capacidad: la VRAM vuelve a ser un badge
        // --con su formato compacto-- en vez de desaparecer.
        expect(find.byType(CapacityBar), findsNothing);
        expect(find.text('2.5 GB/15.9 GB'), findsOneWidget);
        expect(find.text('4.20 GHz'), findsOneWidget);
        expect(find.text('56°C'), findsOneWidget);
      },
    );

    testWidgets('en escritorio la tile de disco muestra la lista completa', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DiskUsageList), findsOneWidget);
      // Titulo propio del modo expandido y una fila por disco.
      expect(find.text('Almacenamiento'), findsOneWidget);
      expect(find.text('C:'), findsOneWidget);
      expect(find.text('387/476 GB'), findsOneWidget);
      expect(find.text('912/931 GB'), findsOneWidget);
      expect(find.text('818/931 GB'), findsOneWidget);

      // La tile ancha mide el doble que una normal (mas el separador que se
      // come al fusionar las dos unidades).
      final widths = tester
          .widgetList<MetricTile>(find.byType(MetricTile))
          .map((tile) => tester.getSize(find.byWidget(tile)).width)
          .toList();
      final wide = widths.reduce((a, b) => a > b ? a : b);
      final narrow = widths.reduce((a, b) => a < b ? a : b);
      expect(wide, closeTo(narrow * 2 + AppSpacing.sm, 0.5));
    });

    testWidgets('con un solo disco la tile no pide ancho de mas', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        snapshot: _singleDiskSnapshot,
      );

      expect(find.byType(DiskUsageList), findsNothing);
      expect(find.text('Disco'), findsOneWidget);

      final widths = tester
          .widgetList<MetricTile>(find.byType(MetricTile))
          .map((tile) => tester.getSize(find.byWidget(tile)).width)
          .toSet();
      expect(widths, hasLength(1));
    });

    testWidgets(
      'en un telefono vertical la tile de disco se gana su propia fila',
      (tester) async {
        // 360 de ancho no alcanza para las 6 unidades en una sola fila (el
        // camino de escritorio), pero la de disco igual se expande: se gana
        // una fila propia entre CPU/RAM y GPU/Red, sin compartirla con nada.
        await pumpPanel(
          tester,
          surface: const Size(360, 800),
          axis: MetricsPanelAxis.horizontal,
          collapsed: false,
        );

        expect(find.byType(DiskUsageList), findsOneWidget);
        expect(find.text('Almacenamiento'), findsOneWidget);
      },
    );

    testWidgets(
      'en un telefono vertical bajo vuelve al agregado',
      (tester) async {
        // Mismo ancho angosto, pero sin alto de sobra para la densidad
        // completa: ni el camino de escritorio ni el de fila propia se
        // conceden, y la tile vuelve al agregado de siempre.
        await pumpPanel(
          tester,
          surface: const Size(360, 260),
          axis: MetricsPanelAxis.horizontal,
          collapsed: false,
        );

        expect(find.byType(DiskUsageList), findsNothing);
        expect(find.text('Disco'), findsOneWidget);
        // El agregado sigue diciendo lo mismo que la suma de los discos.
        expect(find.text('de 2.3 TB'), findsOneWidget);
      },
    );

    testWidgets('en una pantalla aun mas baja el riel scrollea', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(740, 180),
        axis: MetricsPanelAxis.vertical,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });

    /// Sin callback NINGUNA tile es clicable. Es lo que deja al espejo del
    /// telefono y a la ventana compacta exactamente como estaban, sin ningun
    /// `Platform.is...` dentro de un widget compartido.
    testWidgets('sin onSelectMetric ninguna tile responde al clic', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      final cards = tester.widgetList<InteractiveCard>(
        find.byType(InteractiveCard),
      );
      expect(cards, isNotEmpty);
      expect(cards.every((card) => card.onTap == null), isTrue);
    });

    testWidgets('tocar CPU pide su desglose una sola vez', (tester) async {
      final selected = <MetricKind>[];
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        onSelectMetric: selected.add,
      );

      await tester.tap(find.text('CPU'));
      await tester.pump();
      expect(selected, [MetricKind.cpu]);
    });

    /// Disco y Red no se pueden desglosar por proceso en Windows sin ETW:
    /// ofrecerlas clicables para despues no mostrar nada seria peor que no
    /// ofrecerlas.
    testWidgets('las metricas sin desglose no son clicables', (tester) async {
      final selected = <MetricKind>[];
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        onSelectMetric: selected.add,
      );

      await tester.tap(find.text('Red'));
      await tester.pump();
      expect(selected, isEmpty);
    });

    testWidgets('la tile elegida se marca como seleccionada', (tester) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        onSelectMetric: (_) {},
        selectedMetric: MetricKind.ram,
      );

      final selected = tester
          .widgetList<InteractiveCard>(find.byType(InteractiveCard))
          .where((card) => card.selected);
      expect(selected.length, 1);
    });

    /// El pedido concreto: en el riel lateral la metrica de Disco mostraba
    /// solo el agregado ("2.1 TB de 2.3 TB"), que no dice cual de los tres
    /// discos se esta llenando. Ahora se expande igual que en la franja.
    testWidgets('el riel tambien muestra los discos uno por uno', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(400, 900),
        axis: MetricsPanelAxis.vertical,
        collapsed: false,
      );

      expect(find.byType(DiskUsageList), findsOneWidget);
      // Cada unidad con su letra; la etiqueta cuando el volumen tiene una.
      expect(find.text('C:'), findsOneWidget);
      expect(find.text('D:'), findsOneWidget);
      expect(find.text('E:'), findsOneWidget);
      expect(find.text('Secundario'), findsOneWidget);
      expect(find.text('SSD'), findsOneWidget);
    });

    /// Cada fila trae la temperatura de SU disco fisico, y el color depende
    /// del medio: el plato a 52 grados alerta, el SSD a 63 --mas caliente--
    /// no, porque la flash aguanta mucho mas.
    ///
    /// Los finders van acotados a `DiskUsageList` porque las fichas de CPU y
    /// GPU tambien dibujan grados en la misma pantalla.
    testWidgets('cada disco muestra su temperatura, coloreada por medio', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      Finder inList(String text) => find.descendant(
        of: find.byType(DiskUsageList),
        matching: find.text(text),
      );
      for (final text in ['44°C', '52°C', '63°C']) {
        expect(inList(text), findsOneWidget, reason: text);
      }

      final scheme = Theme.of(
        tester.element(find.byType(DiskUsageList)),
      ).colorScheme;
      Color? colorOf(String text) =>
          tester.widget<Text>(inList(text)).style?.color;
      expect(colorOf('52°C'), scheme.error);
      expect(colorOf('63°C'), isNot(scheme.error));
      expect(colorOf('44°C'), isNot(scheme.error));
    });

    /// Una lectura vieja se atenua en vez de desaparecer: un disco dormido no
    /// contesta la consulta, pero tampoco se calienta, asi que su ultima
    /// lectura sigue siendo la mejor verdad disponible. Presentarla igual que
    /// una recien medida seria mentir.
    testWidgets('la temperatura de un disco dormido se ve atenuada', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      Color? colorOf(String text) => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(DiskUsageList),
              matching: find.text(text),
            ),
          )
          .style
          ?.color;

      // El de 52 grados es un HDD por encima de su umbral: alerta, y la
      // antiguedad no se la saca. La atenuacion es para el resto.
      final fresca = colorOf('44°C');
      final vieja = colorOf('63°C');
      expect(fresca, isNotNull);
      expect(vieja, isNotNull);
      expect(
        vieja!.a,
        lessThan(fresca!.a),
        reason: 'la lectura vieja tiene que verse mas tenue',
      );
    });

    /// Un disco sin lectura no dibuja nada: "no se pudo leer" no es "frio".
    testWidgets('un disco sin temperatura no muestra el dato', (tester) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
        snapshot: _noDiskTempSnapshot,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(DiskUsageList),
          matching: find.textContaining('°C'),
        ),
        findsNothing,
      );
    });

    /// El titulo largo entra siempre porque tiene la fila para el solo: el
    /// agregado se movio al pie justamente para no competir con el. Antes,
    /// compartiendo linea, se cortaba en "Almacenami…".
    testWidgets('la tile de disco siempre se llama Almacenamiento', (
      tester,
    ) async {
      for (final caso in [
        (const Size(400, 900), MetricsPanelAxis.vertical),
        (const Size(1200, 200), MetricsPanelAxis.horizontal),
      ]) {
        await pumpPanel(
          tester,
          surface: caso.$1,
          axis: caso.$2,
          collapsed: false,
        );

        expect(find.text('Almacenamiento'), findsOneWidget);
        expect(find.text('Disco'), findsNothing);
      }
    });

    /// El total resume lo que esta arriba, asi que se lee despues: va al pie
    /// de la tarjeta, debajo de las filas de cada disco.
    testWidgets('el total de almacenamiento va al pie', (tester) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      final lista = tester.getRect(find.byType(DiskUsageList));
      final total = tester.getRect(find.text('2.1 TB'));
      expect(total.top, greaterThan(lista.top));
      expect(find.text('Almacenamiento'), findsOneWidget);
    });

    /// La RAM se dibuja como dos modulos que se llenan, con su porcentaje en
    /// el centro de cada uno: es la unica metrica cuyo grafico dibuja la cosa
    /// que mide.
    testWidgets('la RAM usa los modulos y no un donut', (tester) async {
      await pumpPanel(
        tester,
        surface: const Size(1200, 200),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(find.byType(RamModuleChart), findsOneWidget);
      // Titulo, valor y badges siguen ahi, apilados bajo el grafico.
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('9.0 GB'), findsOneWidget);
      expect(find.text('de 32.0 GB'), findsOneWidget);
    });

    /// El caso que desbordaba en el S24: la franja de un telefono da tiles de
    /// ~100 dp, que entran en densidad completa pero no en las cuatro filas
    /// del layout apilado. La tile de GPU se pasaba 7 dp --con banda amarilla
    /// y todo-- y ahi vuelve al reparto lateral.
    testWidgets('en la franja de un telefono ninguna tile desborda', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(360, 800),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MetricTile), findsNWidgets(5));
    });

    /// Los watts comparten el hueco del centro con la temperatura, que hasta
    /// ahora era el unico badge centrado. Sin el separador entre badges
    /// `center` las dos cajas quedaban pegadas.
    testWidgets('la GPU muestra los watts al lado de la temperatura', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1400, 220),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('68 W'), findsOneWidget);
      final temp = tester.getRect(find.text('61°C'));
      final power = tester.getRect(find.text('68 W'));
      expect(power.left, greaterThan(temp.right));
      // Y comparten fila: los watts son un badge mas de la linea de valor,
      // no algo que empuje la tile hacia abajo.
      expect(power.center.dy, closeTo(temp.center.dy, 1));
    });

    /// La tile de CPU reparte su grafico entre las cifras, el chip y el
    /// termometro **solo si tiene ancho**. En el riel de un telefono el
    /// grafico mide 36 dp: ahi el chip se queda con toda la caja y la
    /// temperatura y la frecuencia vuelven a ser badges, en vez de quedar
    /// escaladas hasta no leerse (que es como se veian en el telefono real).
    testWidgets('en el riel del telefono la CPU no parte su grafico en tres', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(800, 360),
        axis: MetricsPanelAxis.vertical,
        collapsed: false,
      );

      expect(find.byType(ThermometerChart), findsNothing);
      expect(find.byType(CpuChipChart), findsOneWidget);
      // Los dos datos siguen visibles, ahora como badges.
      expect(find.text('56°C'), findsOneWidget);
      expect(find.text('4.20 GHz'), findsOneWidget);
      // El chip se queda con la caja entera del grafico. Repartida en tres
      // columnas le quedaban ~10 dp, que es el sintoma que se reporto.
      expect(
        tester.getSize(find.byType(CpuChipChart)).width,
        greaterThan(24),
      );
    });

    /// Y el caso opuesto: con ancho de sobra se dibujan las tres cosas, y
    /// entonces los badges NO se repiten -- las cifras ya estan junto al chip.
    testWidgets('con ancho de sobra la CPU muestra su termometro', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1400, 220),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(find.byType(ThermometerChart), findsOneWidget);
      expect(find.text('56°C'), findsOneWidget);
      expect(find.text('4.20 GHz'), findsOneWidget);
    });

    testWidgets('en una franja alta de escritorio si se apila', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        surface: const Size(1400, 220),
        axis: MetricsPanelAxis.horizontal,
        collapsed: false,
      );

      expect(tester.takeException(), isNull);
      // Con alto de sobra, la GPU muestra su barra de capacidad.
      expect(find.byType(CapacityBar), findsOneWidget);
    });
  });

  group('ramModuleFill', () {
    /// Los modulos se llenan en orden, como se ocuparia la memoria real.
    test('el primer modulo se llena antes que el segundo', () {
      // 25% del total: el primero (que cubre 0-50%) va por la mitad.
      expect(ramModuleFill(0.25, 0, 2), 0.5);
      expect(ramModuleFill(0.25, 1, 2), 0.0);

      // 74%: el primero lleno, el segundo a 48%.
      expect(ramModuleFill(0.74, 0, 2), 1.0);
      expect(ramModuleFill(0.74, 1, 2), closeTo(0.48, 0.001));
    });

    test('lleno y vacio son los extremos exactos', () {
      expect(ramModuleFill(1.0, 0, 2), 1.0);
      expect(ramModuleFill(1.0, 1, 2), 1.0);
      expect(ramModuleFill(0.0, 0, 2), 0.0);
      expect(ramModuleFill(0.0, 1, 2), 0.0);
    });

    /// Un dato roto no puede pintar fuera del modulo ni dar un porcentaje
    /// imposible en el centro.
    test('un valor fuera de rango se clampea', () {
      expect(ramModuleFill(1.8, 0, 2), 1.0);
      expect(ramModuleFill(-0.3, 0, 2), 0.0);
    });
  });
}
