import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:nexodeck/features/compact_overlay/application/window_mode_controller.dart';
import 'package:nexodeck/features/compact_overlay/data/window_layout_repository.dart';

/// Fila con la geometria de una ventana de pantalla completa.
const _fullscreenLike = PersistedWindowLayout(
  posX: 100,
  posY: 100,
  width: 1100,
  height: 720,
);

void main() {
  group('windowSizeFor', () {
    test('el modo compacto ignora el tamano guardado', () {
      // Regresion real: la fila `compact` de una instalacion termino con
      // 1100x720 -- el tamano de pantalla completa -- porque los eventos del
      // WindowListener escribian con el modo viejo todavia activo. Restaurar
      // eso hacia que el modo compacto abriera con la ventana entera.
      final size = windowSizeFor(WindowMode.compact, _fullscreenLike);
      expect(size.width, lessThan(500));
      expect(size.height, lessThan(600));
    });

    test('el modo compacto mide siempre lo mismo, con o sin fila guardada', () {
      expect(
        windowSizeFor(WindowMode.compact, null),
        windowSizeFor(WindowMode.compact, _fullscreenLike),
      );
    });

    test('pantalla completa si restaura lo que el usuario dejo', () {
      final size = windowSizeFor(WindowMode.fullscreen, _fullscreenLike);
      expect(size.width, 1100);
      expect(size.height, 720);
    });

    test('pantalla completa sin fila guardada cae al tamano por defecto', () {
      expect(windowSizeFor(WindowMode.fullscreen, null).width, greaterThan(0));
    });
  });
}
