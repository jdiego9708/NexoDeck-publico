import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/pairing/domain/manual_host.dart';

ManualHost _ok(String raw) {
  final parsed = parseManualHost(raw);
  expect(
    parsed,
    isA<ManualHostParsed>(),
    reason: '"$raw" deberia ser una direccion valida',
  );
  return (parsed as ManualHostParsed).value;
}

String _error(String raw) {
  final parsed = parseManualHost(raw);
  expect(parsed, isA<ManualHostInvalid>(), reason: '"$raw" deberia rechazarse');
  return (parsed as ManualHostInvalid).message;
}

void main() {
  group('parseManualHost', () {
    test('una IP sola cae al puerto por defecto del transporte', () {
      final host = _ok('100.101.102.103');
      expect(host.host, '100.101.102.103');
      expect(host.port, kDefaultTransportPort);
    });

    test('acepta el nombre MagicDNS de Tailscale', () {
      expect(_ok('mi-pc.tail1234.ts.net').host, 'mi-pc.tail1234.ts.net');
    });

    test('un puerto explicito gana sobre el default', () {
      final host = _ok('192.168.1.8:9000');
      expect(host.host, '192.168.1.8');
      expect(host.port, 9000);
    });

    test('recorta espacios alrededor', () {
      expect(_ok('  100.64.0.5  ').host, '100.64.0.5');
    });

    test('tolera un pegado con esquema y barra final', () {
      final host = _ok('https://mi-pc.ts.net:1234/');
      expect(host.host, 'mi-pc.ts.net');
      expect(host.port, 1234);
    });

    // Tailscale reparte IPv6 ademas de las 100.x, asi que este caso no es
    // teorico: partir por el ultimo `:` romperia la direccion.
    test('una IPv6 pelada no se confunde con host:puerto', () {
      final host = _ok('fd7a:115c:a1e0::1');
      expect(host.host, 'fd7a:115c:a1e0::1');
      expect(host.port, kDefaultTransportPort);
    });

    test('una IPv6 entre corchetes si admite puerto', () {
      final host = _ok('[fd7a:115c:a1e0::1]:9000');
      expect(host.host, 'fd7a:115c:a1e0::1');
      expect(host.port, 9000);
    });

    test('rechaza vacio, puerto no numerico y puerto fuera de rango', () {
      expect(_error(''), isNotEmpty);
      expect(_error('   '), isNotEmpty);
      expect(_error('192.168.1.8:abc'), contains('puerto'));
      expect(_error('192.168.1.8:0'), contains('1 y 65535'));
      expect(_error('192.168.1.8:70000'), contains('1 y 65535'));
      expect(_error('192.168.1.8:'), contains('puerto'));
    });

    test('rechaza una direccion con espacios en el medio', () {
      expect(_error('mi pc'), isNotEmpty);
    });
  });

  group('ManualHost.display', () {
    // El puerto por defecto se omite: quien nunca lo toco no tiene por que
    // verlo aparecer solo en el campo al volver a editar la direccion.
    test('omite el puerto por defecto y conserva cualquier otro', () {
      const bare = ManualHost(host: '100.64.0.5', port: kDefaultTransportPort);
      expect(bare.display, '100.64.0.5');
      expect(
        const ManualHost(host: '100.64.0.5', port: 9000).display,
        '100.64.0.5:9000',
      );
    });

    test('una IPv6 con puerto se muestra entre corchetes', () {
      expect(
        const ManualHost(host: 'fd7a::1', port: 9000).display,
        '[fd7a::1]:9000',
      );
    });

    test('display vuelve a parsear al mismo valor', () {
      for (final host in const [
        ManualHost(host: '100.64.0.5', port: kDefaultTransportPort),
        ManualHost(host: '100.64.0.5', port: 9000),
        ManualHost(host: 'fd7a::1', port: 9000),
        ManualHost(host: 'mi-pc.ts.net', port: 1234),
      ]) {
        expect(_ok(host.display), host, reason: 'round trip de ${host.display}');
      }
    });
  });
}
