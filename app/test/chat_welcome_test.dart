import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/ai_assistant/presentation/widgets/chat_welcome.dart';

/// El estado vacio del chat: la invitacion a conversar y los ejemplos, sobre
/// la red neuronal decorativa. La red anima en bucle, asi que se usa `pump` y
/// no `pumpAndSettle` (que esperaria para siempre).
void main() {
  testWidgets('invita a conversar y ofrece ejemplos que se pueden tocar', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatWelcome(onPick: (text) => picked = text)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Iniciá una conversación'), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets);
    // La red neuronal no puede romper el layout ni capturar los toques.
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ActionChip).first);
    await tester.pump();
    expect(picked, isNotNull);
  });
}
