import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/domain/hardware_snapshot.dart';
import 'package:nexodeck/features/dashboard/domain/metric_kind.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/capacity_bar.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/metric_specs.dart';

/// Los colores por umbral no se pueden probar contra hardware real caliente
/// desde un test -- esto verifica la logica de `buildMetricSpecs` con
/// snapshots sinteticos en vez de eso: que la tile ENTERA quede en el color
/// de alerta cuando el dato cruza el umbral, y no cuando no lo cruza.
void main() {
  const scheme = ColorScheme.light();

  HardwareSnapshot snapshot({
    double cpuTempC = 50,
    double ramUsedMb = 8000,
    double ramTotalMb = 32000,
    double? gpuUsage = 10,
    double? gpuTempC = 50,
    int? gpuClockMhz = 1200,
    double? gpuPowerWatts,
    double? gpuPowerLimitWatts,
    int netRxBytesPerSec = 0,
    int netTxBytesPerSec = 0,
    double? gpuVramUsedMb,
    double? gpuVramTotalMb,
  }) => HardwareSnapshot(
    cpuUsage: 20,
    cpuFreqMhz: 3000,
    cpuTempC: cpuTempC,
    ramUsedMb: ramUsedMb,
    ramTotalMb: ramTotalMb,
    diskUsedMb: 100,
    diskTotalMb: 1000,
    netRxBytesPerSec: netRxBytesPerSec,
    netTxBytesPerSec: netTxBytesPerSec,
    gpuUsage: gpuUsage,
    gpuTempC: gpuTempC,
    gpuClockMhz: gpuClockMhz,
    gpuPowerWatts: gpuPowerWatts,
    gpuPowerLimitWatts: gpuPowerLimitWatts,
    gpuVramUsedMb: gpuVramUsedMb,
    gpuVramTotalMb: gpuVramTotalMb,
  );

  MetricSpec specFor(
    MetricKind kind,
    HardwareSnapshot snapshot, {
    List<double> netRxHistoryKb = const [1],
    List<double> netTxHistoryKb = const [1],
  }) => buildMetricSpecs(
    snapshot: snapshot,
    scheme: scheme,
    cpuHistory: const [10],
    netRxHistoryKb: netRxHistoryKb,
    netTxHistoryKb: netTxHistoryKb,
  ).firstWhere((s) => s.kind == kind);

  group('CPU', () {
    test('tibia usa el color normal', () {
      final spec = specFor(MetricKind.cpu, snapshot(cpuTempC: 79.9));
      expect(spec.accentColor, scheme.primary);
    });

    test('caliente vira toda la tile a error', () {
      final spec = specFor(MetricKind.cpu, snapshot(cpuTempC: 85));
      expect(spec.accentColor, scheme.error);
    });
  });

  group('RAM', () {
    test('el valor pasa a ser un badge', () {
      final spec = specFor(MetricKind.ram, snapshot());
      expect(spec.valueAsBadge, isTrue);
    });

    test('el primer badge (total) queda sin caja', () {
      final spec = specFor(MetricKind.ram, snapshot());
      expect(spec.badges.first.plain, isTrue);
    });

    test('por debajo del 80% ni el valor ni el badge de % alertan', () {
      final spec = specFor(
        MetricKind.ram,
        snapshot(ramUsedMb: 20000, ramTotalMb: 32000), // 62%
      );
      expect(spec.valueColor, isNull);
      expect(spec.badges.last.color, isNull);
    });

    test('al 80% o mas, valor y badge de % alertan juntos', () {
      final spec = specFor(
        MetricKind.ram,
        snapshot(ramUsedMb: 26000, ramTotalMb: 32000), // 81%
      );
      expect(spec.valueColor, scheme.error);
      expect(spec.badges.last.color, scheme.error);
    });
  });

  group('GPU', () {
    test('en reposo usa el color neutro del modo, no rojo fijo', () {
      final spec = specFor(MetricKind.gpu, snapshot(gpuUsage: 5));
      expect(spec.accentColor, scheme.onSurfaceVariant);
    });

    test('con uso alto, toda la tile pasa a rojo', () {
      final spec = specFor(MetricKind.gpu, snapshot(gpuUsage: 85));
      expect(spec.accentColor, scheme.error);
    });

    test('el badge de temperatura alerta independiente del de uso', () {
      // GPU en reposo (no busy) pero con temperatura cruzando su propio
      // umbral: el badge de temperatura tiene que alertar igual.
      final spec = specFor(
        MetricKind.gpu,
        snapshot(gpuUsage: 5, gpuTempC: 82, gpuClockMhz: 1200),
      );
      final tempBadge = spec.badges.firstWhere((b) => b.text.contains('°C'));
      final clockBadge = spec.badges.firstWhere((b) => b.text.contains('MHz'));
      expect(tempBadge.color, scheme.error);
      expect(clockBadge.color, isNull);
    });

    test('el badge de reloj alerta independiente del de temperatura', () {
      final spec = specFor(
        MetricKind.gpu,
        snapshot(gpuUsage: 5, gpuTempC: 50, gpuClockMhz: 2600),
      );
      final tempBadge = spec.badges.firstWhere((b) => b.text.contains('°C'));
      final clockBadge = spec.badges.firstWhere((b) => b.text.contains('MHz'));
      expect(tempBadge.color, isNull);
      expect(clockBadge.color, scheme.error);
    });

    test('sin lectura de potencia no hay badge de watts', () {
      // El caso de una AMD/Intel: NVML es la unica fuente, y sin ella la
      // fila no debe mostrar un "0 W" que seria mentira.
      final spec = specFor(MetricKind.gpu, snapshot(gpuUsage: 5));
      expect(spec.badges.where((b) => b.text.endsWith(' W')), isEmpty);
    });

    test('los watts lejos del techo usan el color normal', () {
      final spec = specFor(
        MetricKind.gpu,
        snapshot(gpuUsage: 5, gpuPowerWatts: 68, gpuPowerLimitWatts: 198),
      );
      final powerBadge = spec.badges.firstWhere((b) => b.text.endsWith(' W'));
      expect(powerBadge.text, '68 W');
      expect(powerBadge.color, isNull);
    });

    test('los watts contra el techo alertan, aunque la GPU no este caliente', () {
      final spec = specFor(
        MetricKind.gpu,
        snapshot(
          gpuUsage: 5,
          gpuTempC: 50,
          gpuPowerWatts: 190,
          gpuPowerLimitWatts: 198,
        ),
      );
      final powerBadge = spec.badges.firstWhere((b) => b.text.endsWith(' W'));
      final tempBadge = spec.badges.firstWhere((b) => b.text.contains('°C'));
      expect(powerBadge.color, scheme.error);
      expect(tempBadge.color, isNull);
    });

    test('sin techo informado los watts se muestran pero nunca alertan', () {
      // 190 W serian "al limite" en una tarjeta de 198 y una nimiedad en una
      // de 450: sin el techo no hay contra que comparar.
      final spec = specFor(
        MetricKind.gpu,
        snapshot(gpuUsage: 5, gpuPowerWatts: 190),
      );
      final powerBadge = spec.badges.firstWhere((b) => b.text.endsWith(' W'));
      expect(powerBadge.color, isNull);
    });

    test('la barra de VRAM usa el color normal por debajo del umbral', () {
      final spec = specFor(
        MetricKind.gpu,
        snapshot(gpuVramUsedMb: 4000, gpuVramTotalMb: 16000), // 25%
      );
      final bar = spec.bottomBar as CapacityBar;
      expect(bar.color, scheme.tertiary);
      expect(bar.labelOnFilled, scheme.onTertiary);
    });

    test('la barra de VRAM alerta independiente del uso y la temperatura', () {
      final spec = specFor(
        MetricKind.gpu,
        snapshot(
          gpuUsage: 5, // no busy
          gpuTempC: 50, // no hot
          gpuVramUsedMb: 13000,
          gpuVramTotalMb: 16000, // 81%
        ),
      );
      final bar = spec.bottomBar as CapacityBar;
      expect(bar.color, scheme.error);
      expect(bar.labelOnFilled, scheme.onError);
      // El resto de la tile no tiene por que alertar solo porque la VRAM si.
      expect(spec.accentColor, scheme.onSurfaceVariant);
    });
  });

  group('Red', () {
    test('tranquila usa los colores de siempre (bajada/subida)', () {
      final spec = specFor(
        MetricKind.network,
        snapshot(netRxBytesPerSec: 1024, netTxBytesPerSec: 1024),
        netRxHistoryKb: const [1, 500, 500],
        netTxHistoryKb: const [1, 1, 1],
      );
      expect(spec.valueColor, scheme.primary);
      expect(spec.badges.single.color, scheme.tertiary);
    });

    test('cargada contra su propio pico reciente vira a error', () {
      // El pico reciente de bajada llego a 500 KB/s; la muestra actual
      // (1024 B/s = 1 KB/s) NO esta cargada. Se fuerza subiendo el rate
      // actual al mismo orden que el pico para simular carga real.
      final spec = specFor(
        MetricKind.network,
        snapshot(
          netRxBytesPerSec: 480 * 1024, // ~480 KB/s
          netTxBytesPerSec: 1024,
        ),
        netRxHistoryKb: const [1, 500, 500],
        netTxHistoryKb: const [1, 1, 1],
      );
      expect(spec.valueColor, scheme.error);
      expect(spec.badges.single.color, scheme.tertiary);
    });
  });
}
