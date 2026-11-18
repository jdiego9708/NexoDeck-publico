import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/dashboard/presentation/widgets/format_utils.dart';

void main() {
  group('formatMb', () {
    test('escala a TB para los totales de varios discos juntos', () {
      // El caso que motivo el escalon: tres discos suman cuatro cifras en GB.
      expect(formatMb(2394112), '2.3 TB');
      expect(formatMb(1024 * 1024), '1.0 TB');
    });

    test('mantiene GB con un decimal por debajo del TB', () {
      expect(formatMb(32768), '32.0 GB');
      // Justo debajo del escalon: sigue en GB.
      expect(formatMb(1024 * 1024 - 1), '1024.0 GB');
    });

    test('por debajo de 1 GB usa MB sin decimales', () {
      expect(formatMb(512), '512 MB');
    });
  });

  group('formatMbPair', () {
    test('escribe la unidad una sola vez y sin decimales en GB', () {
      expect(formatMbPair(396288, 487424), '387/476 GB');
    });

    test('la unidad la fija el total, no el usado', () {
      // Un disco de 2 TB con 900 GB usados: las dos cifras van en TB para
      // que se puedan comparar de un vistazo.
      expect(formatMbPair(921600, 2097152), '0.9/2.0 TB');
    });

    test('un disco vacio no rompe el formato', () {
      expect(formatMbPair(0, 487424), '0/476 GB');
    });
  });

  group('formatBytesPerSec', () {
    test('escala de B/s a KB/s y MB/s', () {
      expect(formatBytesPerSec(512), '512 B/s');
      expect(formatBytesPerSec(2048), '2.0 KB/s');
      expect(formatBytesPerSec(3 * 1024 * 1024), '3.0 MB/s');
    });
  });
}
