import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/theme/app_theme.dart';
import 'package:nexodeck/features/pairing/domain/host_name.dart';
import 'package:nexodeck/features/pairing/presentation/widgets/pin_confirm_dialog.dart';
import 'package:nexodeck/features/pairing/presentation/widgets/pin_display.dart';

void main() {
  group('pinGroups', () {
    test('parte un PIN de 6 digitos en dos grupos', () {
      expect(pinGroups('061169'), ['061', '169']);
    });

    test('conserva los ceros a la izquierda', () {
      // El PIN se genera con `format!("{:06}")` del lado Rust, asi que
      // `004821` es un valor real y frecuente. Cualquier paso por `int` lo
      // convertiria en `4821` y el usuario compararia contra otra cosa.
      expect(pinGroups('004821'), ['004', '821']);
      expect(formatPin('004821'), '004 821');
    });

    test('un largo inesperado no rompe: devuelve el PIN entero', () {
      // Viene de la red (`HostPinReceived`): una pantalla de emparejamiento
      // que explota es peor que una fea.
      expect(pinGroups('12345'), ['12345']);
      expect(pinGroups(''), ['']);
    });
  });

  group('spellPin', () {
    test('deletrea digito por digito para los lectores de pantalla', () {
      // Sin esto TalkBack lee "cuatro mil ochocientos veintiuno".
      expect(spellPin('004821'), '0 0 4 8 2 1');
    });
  });

  group('hostDisplayName', () {
    test('saca el sufijo del servicio mDNS', () {
      // `DiscoveredHost.name` es el fullname de mDNS: al usuario se le
      // mostraba la PC llamada "JUANDIEGO-PC._nexodeck._tcp.local.".
      expect(
        hostDisplayName('JUANDIEGO-PC._nexodeck._tcp.local.'),
        'JUANDIEGO-PC',
      );
    });

    test('deja intacto un nombre que no trae el sufijo', () {
      expect(hostDisplayName('JUANDIEGO-PC'), 'JUANDIEGO-PC');
    });
  });

  group('PinDisplay', () {
    testWidgets('muestra los grupos separados', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PinDisplay(pin: '004821'))),
      );

      expect(find.text('004'), findsOneWidget);
      expect(find.text('821'), findsOneWidget);
      // Y NO como un solo bloque pegado.
      expect(find.text('004821'), findsNothing);
    });

    testWidgets('el tracking es positivo y las cifras son tabulares', (
      tester,
    ) async {
      // Este es el test que mas vale del archivo. Los estilos grandes del
      // tema llevan `letterSpacing` NEGATIVO (`_tighten` en app_theme), que
      // sobre un PIN que hay que comparar digito por digito es exactamente al
      // reves. Sin este test, que alguien reintroduzca ese tracking solo se
      // detecta mirando una captura con lupa.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: PinDisplay(pin: '004821')),
        ),
      );

      final digits = tester.widget<Text>(find.text('004'));
      final style = digits.style!;
      expect(style.letterSpacing, isNotNull);
      expect(
        style.letterSpacing!,
        greaterThan(0),
        reason: 'el PIN necesita aire entre digitos, no menos',
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('showPinConfirmDialog', () {
    testWidgets('muestra el PIN agrupado y las dos acciones', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPinConfirmDialog(
                  context,
                  pin: '004821',
                  hostName: 'JUANDIEGO-PC',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('004'), findsOneWidget);
      expect(find.text('821'), findsOneWidget);
      expect(find.textContaining('JUANDIEGO-PC'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Coincide, confirmar'), findsOneWidget);
    });
  });
}
