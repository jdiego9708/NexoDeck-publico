import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/features/dashboard/domain/hardware_snapshot.dart';
import 'package:nexodeck/features/dashboard/domain/host_components.dart';
import 'package:nexodeck/features/dashboard/domain/metric_kind.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_specs.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_tile.dart';

/// El subtitulo (el nombre de la pieza) se come una linea entera de la tile.
/// En la franja de un telefono vertical la tile mide justo
/// [AppSizes.minFullMetricTileHeight], y ahi el subtitulo empujaba la fila de
/// valores fuera de la tile: Flutter dibujaba la banda de overflow en RAM y en
/// Red. El contrato del subtitulo es que nunca puede desplazar al valor, asi
/// que se omite cuando no hay alto -- y sigue apareciendo cuando lo hay.
void main() {
  const tileWidth = 160.0;

  HardwareSnapshot snapshot() => HardwareSnapshot(
    cpuUsage: 11,
    cpuFreqMhz: 4350,
    cpuTempC: 65,
    cpuThreadsBusy: 2,
    cpuThreadsTotal: 16,
    ramUsedMb: 19251,
    ramTotalMb: 32672,
    diskUsedMb: 2441000,
    diskTotalMb: 4700000,
    netRxBytesPerSec: 99328,
    netTxBytesPerSec: 4096,
    gpuUsage: 5,
    gpuTempC: 54,
    gpuClockMhz: 1402,
    gpuPowerWatts: 24,
    gpuPowerLimitWatts: 198,
    gpuVramUsedMb: 2560,
    gpuVramTotalMb: 16311,
  );

  const components = HostComponents(
    cpuName: 'AMD Ryzen 7 5700X 8-Core Processor',
    ramVendor: 'Corsair',
    ramPartNumber: 'CM4X16GD3600C18K2D',
    ramSpeedMts: 3600,
    ramModuleCount: 2,
    gpuName: 'NVIDIA GeForce RTX 5060 Ti',
    gpuVramTotalMb: 16311,
    networkAdapter: 'Ethernet',
  );

  List<MetricSpec> specs() => buildMetricSpecs(
    snapshot: snapshot(),
    scheme: const ColorScheme.light(),
    components: components,
    cpuHistory: const [10, 20, 11],
    netRxHistoryKb: const [1, 500, 97],
    netTxHistoryKb: const [1, 1, 4],
  );

  Future<void> pumpTile(
    WidgetTester tester,
    MetricKind kind,
    double height,
  ) async {
    final spec = specs().firstWhere((s) => s.kind == kind);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: tileWidth,
              height: height,
              child: MetricTile(spec: spec, density: MetricDensity.full),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('en el alto minimo ninguna tile desborda', (tester) async {
    for (final kind in MetricKind.values) {
      await pumpTile(tester, kind, AppSizes.minFullMetricTileHeight);
      expect(tester.takeException(), isNull, reason: 'desbordo ${kind.name}');
    }
  });

  testWidgets('en el alto minimo el subtitulo no aparece (no hay lugar)', (
    tester,
  ) async {
    await pumpTile(tester, MetricKind.network, AppSizes.minFullMetricTileHeight);
    expect(find.text('Ethernet'), findsNothing);

    await pumpTile(tester, MetricKind.cpu, AppSizes.minFullMetricTileHeight);
    expect(find.text('AMD Ryzen 7 5700X'), findsNothing);
  });

  testWidgets('con alto de sobra el subtitulo sigue apareciendo', (tester) async {
    await pumpTile(
      tester,
      MetricKind.network,
      AppSizes.minFullMetricTileWithSubtitleHeight + 24,
    );
    expect(find.text('Ethernet'), findsOneWidget);

    await pumpTile(
      tester,
      MetricKind.cpu,
      AppSizes.minFullMetricTileWithSubtitleHeight + 24,
    );
    expect(find.text('AMD Ryzen 7 5700X'), findsOneWidget);
  });
}
