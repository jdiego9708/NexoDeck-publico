import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/ai_assistant/domain/conversation_when.dart';

/// La etiqueta de fecha de las listas de conversaciones. Es logica pura: una
/// fecha exacta no dice nada util en una lista ordenada por reciente, asi que
/// se prueba el texto y sus escalones.
void main() {
  group('conversationWhenLabel', () {
    test('antepone el estado de conservar y archivar', () {
      final cuando = DateTime.now().subtract(const Duration(minutes: 5));
      expect(
        conversationWhenLabel(
          updatedAt: cuando,
          keepForever: true,
          archived: false,
        ),
        'Se conserva · hace 5 min',
      );
      expect(
        conversationWhenLabel(
          updatedAt: cuando,
          keepForever: false,
          archived: true,
        ),
        'Archivada · hace 5 min',
      );
      expect(
        conversationWhenLabel(
          updatedAt: cuando,
          keepForever: false,
          archived: false,
        ),
        'hace 5 min',
      );
    });

    test('los escalones de tiempo', () {
      String at(Duration ago) => conversationWhenLabel(
        updatedAt: DateTime.now().subtract(ago),
        keepForever: false,
        archived: false,
      );
      expect(at(const Duration(seconds: 30)), 'hace un momento');
      expect(at(const Duration(hours: 3)), 'hace 3 h');
      expect(at(const Duration(days: 1)), 'ayer');
      expect(at(const Duration(days: 5)), 'hace 5 días');
      expect(at(const Duration(days: 40)), 'hace un mes');
      expect(at(const Duration(days: 95)), 'hace 3 meses');
    });
  });
}
