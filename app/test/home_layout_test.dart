import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/domain/hardware_snapshot.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_specs.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metrics_panel.dart';
import 'package:nexodeck/features/home/domain/home_layout.dart';

const _snapshot = HardwareSnapshot(
  cpuUsage: 62,
  cpuFreqMhz: 4200,
  cpuTempC: 56,
  ramUsedMb: 9216,
  ramTotalMb: 32768,
  diskUsedMb: 396288,
  diskTotalMb: 487424,
  netRxBytesPerSec: 2048,
  netTxBytesPerSec: 1024,
  gpuUsage: 13,
  gpuTempC: 61,
  gpuVramUsedMb: 2534,
  gpuVramTotalMb: 16311,
);

void main() {
  group('HomeLayout', () {
    test('el boton recorre todos y vuelve al primero', () {
      var layout = HomeLayout.metricsTop;
      final recorridos = <HomeLayout>[];
      for (var i = 0; i < HomeLayout.values.length; i++) {
        layout = layout.next;
        recorridos.add(layout);
      }

      // Pasa por todos exactamente una vez y termina donde empezo: con un
      // clic por layout el usuario tiene que volver a lo que tenia, no quedar
      // en un estado que no eligio.
      expect(recorridos.toSet().length, HomeLayout.values.length);
      expect(layout, HomeLayout.metricsTop);
    });

    test('un valor guardado que ya no existe cae al centro de control', () {
      // Pasa al bajar de version o al renombrar el enum. Preferimos arrancar
      // con la disposicion por defecto --el centro de control-- antes que
      // reventar en `main()`.
      expect(
        HomeLayout.fromName('un_layout_que_no_existe'),
        HomeLayout.controlCenter,
      );
      expect(HomeLayout.fromName(null), HomeLayout.controlCenter);
      expect(HomeLayout.fromName('deckFocus'), HomeLayout.deckFocus);
    });

    test('los dos rieles laterales se distinguen por el volteo del icono', () {
      // Comparten `IconData`: si `flipIcon` no los separara, el boton se
      // veria identico en los dos y el clic parecería no hacer nada.
      expect(HomeLayout.metricsLeft.icon, HomeLayout.metricsRight.icon);
      expect(HomeLayout.metricsLeft.flipIcon, isFalse);
      expect(HomeLayout.metricsRight.flipIcon, isTrue);
      // La franja de abajo tambien esta espejada, pero su icono no se voltea:
      // no comparte icono con nadie.
      expect(HomeLayout.deckFocus.flipIcon, isFalse);
    });

    test('solo los rieles reparten ancho', () {
      expect(HomeLayout.metricsLeft.isSideRail, isTrue);
      expect(HomeLayout.metricsRight.isSideRail, isTrue);
      expect(HomeLayout.metricsTop.isSideRail, isFalse);
      expect(HomeLayout.deckFocus.isSideRail, isFalse);
    });
  });

  group('MetricsPanel espejado', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required MetricsPanelAxis axis,
      required bool mirrored,
      required bool collapsed,
      Size surface = const Size(900, 600),
    }) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final panel = MetricsPanel(
                  specs: collapsed
                      ? const []
                      : buildMetricSpecs(
                          snapshot: _snapshot,
                          scheme: Theme.of(context).colorScheme,
                          cpuHistory: const [10, 20, 30],
                          netRxHistoryKb: const [1, 2, 3],
                          netTxHistoryKb: const [1, 1, 2],
                        ),
                  axis: axis,
                  mirrored: mirrored,
                  collapsed: collapsed,
                  onToggleCollapsed: () {},
                );
                // Cada eje se monta en el contenedor en el que vive de
                // verdad: la franja horizontal ocupa todo el ancho, asi que
                // dentro de un `Row` recibiria ancho infinito -- que es
                // exactamente lo que hace `HomeLayoutView` con la `Column`.
                return axis == MetricsPanelAxis.vertical
                    ? Row(
                        children: [
                          panel,
                          const Expanded(child: SizedBox.expand()),
                        ],
                      )
                    : Column(
                        children: [
                          panel,
                          const Expanded(child: SizedBox.expand()),
                        ],
                      );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('el riel deja el chevron pegado al deck, no al borde', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.vertical,
        mirrored: false,
        collapsed: false,
      );
      final panel = tester.getRect(find.byType(MetricsPanel));
      final chevron = tester.getCenter(find.byType(IconButton));
      // Riel a la izquierda: el deck queda a su derecha, y ahi va el chevron.
      expect(chevron.dx, greaterThan(panel.center.dx));

      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.vertical,
        mirrored: true,
        collapsed: false,
      );
      final panelMirrored = tester.getRect(find.byType(MetricsPanel));
      final chevronMirrored = tester.getCenter(find.byType(IconButton));
      expect(chevronMirrored.dx, lessThan(panelMirrored.center.dx));
    });

    testWidgets('el chevron apunta hacia donde se abre el panel', (
      tester,
    ) async {
      // Riel derecho plegado: se abre hacia la izquierda.
      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.vertical,
        mirrored: true,
        collapsed: true,
      );
      expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

      // Riel izquierdo plegado: hacia la derecha.
      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.vertical,
        mirrored: false,
        collapsed: true,
      );
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);

      // Franja de abajo plegada: hacia arriba.
      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.microStrip,
        mirrored: true,
        collapsed: true,
      );
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

      // Franja de arriba plegada: hacia abajo, que es el comportamiento de
      // siempre y el que no hay que romper.
      await pumpPanel(
        tester,
        axis: MetricsPanelAxis.horizontal,
        mirrored: false,
        collapsed: true,
      );
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });
  });
}
