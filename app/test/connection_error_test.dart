import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/pairing/domain/connection_error.dart';

/// Un error con el `toString()` que queramos, para no arrastrar el bridge.
class _Raw implements Exception {
  const _Raw(this.text);
  final String text;
  @override
  String toString() => text;
}

void main() {
  group('describeConnectionError', () {
    test('traduce el fallo de DNS del sistema', () {
      // Es el caso que se veia en pantalla tal cual: ingles del sistema
      // operativo adentro del Display de Rust.
      expect(
        describeConnectionError(
          const _Raw(
            "AnyhowException(io: Failed host lookup: 'relay.example.com' "
            '(OS Error: No address associated with hostname, errno = 7))',
          ),
        ),
        'No encontramos la PC. Revisa que este encendida y con internet.',
      );
    });

    test('traduce un SocketException de Dart', () {
      expect(
        describeConnectionError(
          const _Raw(
            "SocketException: Failed host lookup: 'mi-pc.tail1234.ts.net' "
            '(OS Error: Name or service not known, errno = -2)',
          ),
        ),
        'No encontramos la PC. Revisa que este encendida y con internet.',
      );
    });

    test('traduce conexion rechazada y tiempo agotado', () {
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(io: Connection refused (os error 111))'),
        ),
        'La PC rechazo la conexion.',
      );
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(io: connection timed out)'),
        ),
        'La PC no respondio a tiempo.',
      );
    });

    test('traduce red inalcanzable', () {
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(io: Network is unreachable (os error 101))'),
        ),
        'No hay red o no se llega a la PC.',
      );
    });

    test('el certificado que no coincide sugiere re-emparejar', () {
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(tls: invalid peer certificate: UnknownIssuer)'),
        ),
        'El certificado de la PC no coincide. Vuelve a emparejar.',
      );
    });

    test('respeta los mensajes que ya vienen en castellano del protocolo', () {
      // Este texto es informacion util: no se puede perder con un generico.
      expect(
        describeConnectionError(
          const _Raw(
            'AnyhowException(protocolo invalido: la PC no esta conectada al tunel)',
          ),
        ),
        'la PC no esta conectada al tunel',
      );
    });

    test('traduce la direccion manual invalida', () {
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(protocolo invalido: host invalido: mi pc)'),
        ),
        'La direccion escrita no es valida.',
      );
    });

    test('un error tecnico no reconocido cae a un generico, nunca al crudo', () {
      expect(
        describeConnectionError(
          const _Raw('AnyhowException(io: wacky socket failure #42)'),
        ),
        'No se pudo conectar con la PC.',
      );
    });

    test('un texto sin jerga tecnica se deja tal cual', () {
      expect(
        describeConnectionError(const _Raw('algo raro pero en castellano')),
        'algo raro pero en castellano',
      );
    });
  });
}
