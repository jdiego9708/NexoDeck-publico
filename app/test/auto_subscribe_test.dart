import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/actions/domain/auto_subscribe.dart';

/// Tests de `extractAutoSubscribeArgument`, la unica parte de la
/// auto-suscripcion que es pura (`tryAutoSubscribe` necesita
/// `HubSubscriptionsRepository`, ver `hub_subscriptions_dao_test.dart` para
/// lo que ya cubre ese lado).

void main() {
  group('extractAutoSubscribeArgument', () {
    test('JSON valido con el campo presente devuelve su valor', () {
      expect(
        extractAutoSubscribeArgument('{"job_id": "abc123"}', 'job_id'),
        'abc123',
      );
    });

    test('un numero se convierte a string', () {
      expect(extractAutoSubscribeArgument('{"job_id": 42}', 'job_id'), '42');
    });

    test('sin el campo esperado devuelve null', () {
      expect(
        extractAutoSubscribeArgument('{"otro_campo": "x"}', 'job_id'),
        isNull,
      );
    });

    test('JSON invalido devuelve null en vez de lanzar', () {
      expect(extractAutoSubscribeArgument('no es json', 'job_id'), isNull);
    });

    test('un valor vacio cuenta como ausente', () {
      expect(extractAutoSubscribeArgument('{"job_id": ""}', 'job_id'), isNull);
    });

    test('un valor null en el JSON cuenta como ausente', () {
      expect(extractAutoSubscribeArgument('{"job_id": null}', 'job_id'), isNull);
    });

    test('un array de nivel superior (no objeto) devuelve null', () {
      expect(extractAutoSubscribeArgument('["a", "b"]', 'job_id'), isNull);
    });

    test('recorta espacios alrededor de la salida antes de parsear', () {
      expect(
        extractAutoSubscribeArgument('\n  {"job_id": "abc"}  \n', 'job_id'),
        'abc',
      );
    });
  });
}
