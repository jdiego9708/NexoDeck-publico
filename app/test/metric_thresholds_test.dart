import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/domain/hardware_snapshot.dart';
import 'package:nexodeck/features/dashboard/domain/metric_thresholds.dart';

void main() {
  group('isCpuHot', () {
    test('sin dato nunca alerta', () => expect(isCpuHot(null), isFalse));
    test('justo debajo del umbral no alerta', () {
      expect(isCpuHot(kCpuHotTempC - 0.1), isFalse);
    });
    test('en el umbral y por encima si alerta', () {
      expect(isCpuHot(kCpuHotTempC), isTrue);
      expect(isCpuHot(kCpuHotTempC + 5), isTrue);
    });
  });

  group('isGpuHot', () {
    test('sin dato nunca alerta', () => expect(isGpuHot(null), isFalse));
    test('respeta el umbral de GPU', () {
      expect(isGpuHot(kGpuHotTempC - 1), isFalse);
      expect(isGpuHot(kGpuHotTempC), isTrue);
    });
  });

  group('isGpuFast', () {
    test('sin dato nunca alerta', () => expect(isGpuFast(null), isFalse));
    test('respeta el umbral de reloj', () {
      expect(isGpuFast(kGpuFastClockMhz - 1), isFalse);
      expect(isGpuFast(kGpuFastClockMhz), isTrue);
    });
  });

  group('isDiskHot', () {
    test('sin dato nunca alerta', () {
      for (final kind in DiskMediaKind.values) {
        expect(isDiskHot(kind, null), isFalse, reason: kind.name);
      }
    });

    /// El punto de tener umbrales por medio: la MISMA temperatura alerta en
    /// un plato y no en una memoria flash. Con un solo numero, o se callaba
    /// un HDD a 65 grados o se pintaba de rojo un NVMe que esta perfecto.
    test('55 grados alertan en un HDD pero no en un SSD', () {
      expect(isDiskHot(DiskMediaKind.hdd, 55), isTrue);
      expect(isDiskHot(DiskMediaKind.ssd, 55), isFalse);
    });

    test('cada medio respeta su propio umbral', () {
      expect(isDiskHot(DiskMediaKind.hdd, kHddHotTempC - 0.1), isFalse);
      expect(isDiskHot(DiskMediaKind.hdd, kHddHotTempC), isTrue);
      expect(isDiskHot(DiskMediaKind.ssd, kSsdHotTempC - 0.1), isFalse);
      expect(isDiskHot(DiskMediaKind.ssd, kSsdHotTempC), isTrue);
    });

    /// El medio desconocido queda en el medio a proposito: no puede ser tan
    /// permisivo como el SSD ni tan estricto como el plato.
    test('el medio desconocido cae entre los otros dos', () {
      expect(kUnknownDiskHotTempC, greaterThan(kHddHotTempC));
      expect(kUnknownDiskHotTempC, lessThan(kSsdHotTempC));
      expect(isDiskHot(DiskMediaKind.unknown, kUnknownDiskHotTempC), isTrue);
    });
  });

  group('isGpuBusy', () {
    test('sin dato nunca alerta', () => expect(isGpuBusy(null), isFalse));
    test('compara contra el 80% de USO, no de fraccion', () {
      // El umbral se expresa en fraccion (0.8) pero la funcion recibe
      // porcentaje (0-100), como llega `snapshot.gpuUsage`.
      expect(isGpuBusy(79.9), isFalse);
      expect(isGpuBusy(80.0), isTrue);
    });
  });

  group('isRamModuleHot', () {
    test('respeta el umbral por modulo', () {
      expect(isRamModuleHot(kRamModuleHotFraction - 0.01), isFalse);
      expect(isRamModuleHot(kRamModuleHotFraction), isTrue);
      expect(isRamModuleHot(1.0), isTrue);
    });
  });

  group('isNetworkBusy', () {
    test('sin pico reciente nunca alerta', () {
      // Un pico en 0 (todavia sin historial) no puede servir de referencia.
      expect(isNetworkBusy(500, 0), isFalse);
    });
    test('compara contra el propio pico reciente, no un KB/s fijo', () {
      // 50 KB/s es "mucho" contra un pico de 60, pero nada contra uno de
      // 5000 -- no hay un numero absoluto que sirva para las dos redes.
      expect(isNetworkBusy(50, 60), isTrue);
      expect(isNetworkBusy(50, 5000), isFalse);
    });
    test('el umbral es una fraccion del pico, no el pico exacto', () {
      final peak = 1000.0;
      expect(isNetworkBusy(peak * kNetworkBusyFractionOfPeak - 1, peak), isFalse);
      expect(isNetworkBusy(peak * kNetworkBusyFractionOfPeak, peak), isTrue);
    });
  });
}
