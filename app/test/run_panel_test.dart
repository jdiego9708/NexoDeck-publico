import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/features/run_center/domain/run_panel_dock.dart';
import 'package:nexodeck/features/run_center/presentation/widgets/run_output.dart';

void main() {
  /// El ancho del panel lo decide `PanelSlot.runPanel` (probado en
  /// `panel_split_test.dart`). Lo que se fija aca es el token, que es la razon
  /// por la que este panel pide mas que el de procesos.
  test('el panel de ejecuciones pide mas ancho que el de procesos', () {
    expect(
      AppSizes.runPanelMinWidth,
      greaterThan(AppSizes.processPanelMinWidth),
    );
  });

  group('RunPanelDock', () {
    test('un valor guardado invalido cae a la derecha', () {
      expect(RunPanelDock.fromName('nope'), RunPanelDock.right);
      expect(RunPanelDock.fromName(null), RunPanelDock.right);
      expect(RunPanelDock.fromName('left'), RunPanelDock.left);
      expect(RunPanelDock.fromName('maximized'), RunPanelDock.maximized);
    });

    test('solo izquierda y derecha son laterales', () {
      expect(RunPanelDock.left.isSide, isTrue);
      expect(RunPanelDock.right.isSide, isTrue);
      expect(RunPanelDock.maximized.isSide, isFalse);
    });
  });

  /// El escalon de horas no es cosmetico: una cadena de ODM corre 3-4 horas y
  /// sin el se veria `214:07`, un numero que hay que dividir mentalmente.
  group('formatRunElapsed', () {
    test('por debajo del segundo, milisegundos', () {
      expect(formatRunElapsed(const Duration(milliseconds: 120)), '120ms');
    });

    test('entre 1 y 10 segundos, una decima', () {
      expect(formatRunElapsed(const Duration(milliseconds: 1234)), '1.2s');
    });

    test('por debajo del minuto, segundos enteros', () {
      expect(formatRunElapsed(const Duration(seconds: 48)), '48s');
    });

    test('por encima del minuto, sin decimas', () {
      expect(formatRunElapsed(const Duration(seconds: 125)), '2:05');
    });

    test('una cadena de ODM se lee en horas, no en minutos', () {
      expect(
        formatRunElapsed(const Duration(hours: 3, minutes: 34, seconds: 7)),
        '3:34:07',
      );
    });
  });
}
