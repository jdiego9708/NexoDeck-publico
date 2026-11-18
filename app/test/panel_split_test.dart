import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_spacing.dart';
import 'package:nexodeck/features/home/domain/panel_split.dart';

void main() {
  group('extentFor sin nada guardado', () {
    /// El reparto automatico tiene que seguir siendo **exactamente** el que
    /// habia antes de que los divisores se pudieran arrastrar: quien nunca
    /// toca uno no deberia notar que existen.
    test('la franja de metricas toma ~20% del alto, acotado', () {
      final extent = PanelSlot.metricsStrip.extentFor(available: 800);
      expect(extent, 160); // 800 * 0.2, dentro del clamp 96-168
    });

    test('en una ventana muy alta la franja se clampea', () {
      expect(
        PanelSlot.metricsStrip.extentFor(available: 2000),
        AppSizes.metricStripPreferredMaxHeight,
      );
    });

    test('el riel usa su factor y su clamp de siempre', () {
      // 1100 * 0.26 = 286, por encima del maximo automatico.
      expect(
        PanelSlot.metricsRail.extentFor(available: 1100),
        AppSizes.metricRailMaxWidth,
      );
    });

    /// La franja micro **es** su minimo: el layout "Deck al maximo" existe
    /// justamente para mostrar lo menos posible.
    test('la franja micro arranca en su alto natural', () {
      expect(
        PanelSlot.metricsMicroStrip.extentFor(available: 900),
        AppSizes.microMetricStripHeight,
      );
    });
  });

  group('extentFor con un reparto guardado', () {
    test('respeta la fraccion que dejo el usuario', () {
      expect(
        PanelSlot.metricsStrip.extentFor(available: 1000, fraction: 0.25),
        250,
      );
    });

    /// El tope de arrastre es mas ancho que el del calculo automatico: es lo
    /// que permite estirar el riel hasta que la lista de discos entre en una
    /// fila por unidad.
    test('el arrastre puede pasar del maximo automatico del riel', () {
      final extent = PanelSlot.metricsRail.extentFor(
        available: 1400,
        fraction: 0.2, // 280 px, por encima de metricRailMaxWidth (220)
      );
      expect(extent, 280);
      expect(extent, greaterThan(AppSizes.metricRailMaxWidth));
    });

    /// El riel no tiene techo propio (`metricRailDragMaxWidth` es
    /// `double.infinity`, ver `app_spacing.dart`): el usuario pidio poder
    /// seguir agrandandolo mientras el deck de acciones tuviera de sobra
    /// para ceder, asi que lo unico que puede cortarlo es
    /// `minDeckWidthWithPanel`.
    test('una fraccion desmedida se corta en lo que le queda al deck', () {
      expect(
        PanelSlot.metricsRail.extentFor(available: 2000, fraction: 0.9),
        2000 - AppSizes.minDeckWidthWithPanel,
      );
    });

    test('una fraccion minuscula se levanta hasta el minimo', () {
      expect(
        PanelSlot.metricsRail.extentFor(available: 1200, fraction: 0.01),
        AppSizes.metricRailMinWidth,
      );
    });

    /// El techo real no es solo [PanelSlot.max]: tambien es lo que le queda al
    /// deck. Sin esto, arrastrar el riel en una ventana angosta lo dejaria sin
    /// espacio para una sola tarjeta.
    test('el deck nunca baja de su minimo, aunque la fraccion lo pida', () {
      final extent = PanelSlot.metricsRail.extentFor(
        available: 560,
        fraction: 0.8,
      );
      // El riel no tiene techo propio: el que manda aca es el minimo del
      // deck (560 - 260 = 300), que es lo que este test comprueba.
      expect(extent, 560 - AppSizes.minDeckWidthWithPanel);
      expect(extent, lessThan(AppSizes.metricRailDragMaxWidth));
    });
  });

  group('extentFor cuando no entra', () {
    /// `null` = no hay reparto posible; el llamador dibuja el panel en su
    /// minimo (el riel de metricas) o lo deja como este.
    test('devuelve null si el panel no entra ni en su minimo', () {
      expect(PanelSlot.actionsPanel.extentFor(available: 300), isNull);
      expect(PanelSlot.metricsRail.extentFor(available: 100), isNull);
    });

    test('en una ventana de escritorio los dos paneles entran', () {
      expect(PanelSlot.actionsPanel.extentFor(available: 1100), isNotNull);
      expect(PanelSlot.metricsRail.extentFor(available: 1100), isNotNull);
    });
  });

  group('fractionAfterDrag', () {
    test('arrastrar hacia adelante agranda el panel', () {
      final fraction = PanelSlot.metricsStrip.fractionAfterDrag(
        available: 1000,
        currentExtent: 200,
        delta: 40,
      );
      expect(fraction * 1000, closeTo(240, 0.001));
    });

    /// El delta llega **ya con el signo que agranda**: quien lo invierte es el
    /// widget del divisor, segun contra que borde este apoyado el panel.
    test('un delta negativo lo achica', () {
      final fraction = PanelSlot.metricsStrip.fractionAfterDrag(
        available: 1000,
        currentExtent: 200,
        delta: -40,
      );
      expect(fraction * 1000, closeTo(160, 0.001));
    });

    /// Se clampea en px y recien despues se pasa a fraccion. Al reves, el
    /// panel se iria un instante mas alla del tope antes de volver.
    test('no deja pasar del tope de arrastre por mucho que se empuje', () {
      final fraction = PanelSlot.metricsStrip.fractionAfterDrag(
        available: 1000,
        currentExtent: 300,
        delta: 5000,
      );
      expect(
        fraction * 1000,
        closeTo(AppSizes.metricStripDragMaxHeight, 0.001),
      );
    });

    test('no deja bajar del minimo por mucho que se empuje', () {
      final fraction = PanelSlot.metricsStrip.fractionAfterDrag(
        available: 1000,
        currentExtent: 100,
        delta: -5000,
      );
      expect(
        fraction * 1000,
        closeTo(AppSizes.metricStripDragMinHeight, 0.001),
      );
    });

    /// La franja micro solo se agranda: su minimo es su alto natural.
    test('la franja micro no se puede achicar', () {
      final fraction = PanelSlot.metricsMicroStrip.fractionAfterDrag(
        available: 800,
        currentExtent: AppSizes.microMetricStripHeight,
        delta: -100,
      );
      expect(fraction * 800, closeTo(AppSizes.microMetricStripHeight, 0.001));
    });

    /// Un ancho de cero llega en el primer frame de algunos layouts; dividir
    /// por el daria `NaN` y el reparto quedaria roto para siempre.
    test('sin espacio disponible no se guarda ninguna fraccion rara', () {
      expect(
        PanelSlot.metricsStrip.fractionAfterDrag(
          available: 0,
          currentExtent: 0,
          delta: 10,
        ),
        0,
      );
    });
  });

  group('claves de persistencia', () {
    test('cada panel guarda en su propia clave y ninguna se repite', () {
      final keys = PanelSlot.values.map((slot) => slot.settingKey).toList();
      expect(keys.toSet().length, keys.length);
      for (final key in keys) {
        expect(key, startsWith('split_'));
      }
    });

    /// Izquierda y derecha son el mismo riel cambiado de borde: el ancho que
    /// necesita no depende de contra que lado este apoyado.
    test('el riel tiene una sola clave para los dos lados', () {
      expect(PanelSlot.metricsRail.settingKey, 'split_metrics_rail');
    });
  });
}
