import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/pairing/domain/manual_host.dart';
import 'package:nexodeck/features/pairing/domain/reconnect_target.dart';

// Como lo anuncia mDNS: nombre de instancia sanitizado + tipo de servicio.
DiscoveredEndpoint _announced(String name, {String host = '192.168.1.8'}) =>
    (name: '$name._nexodeck._tcp.local.', host: host, port: 58643);

void main() {
  const manual = ManualHost(host: '100.64.0.5', port: 58643);

  test('con la PC anunciada por mDNS gana la direccion anunciada', () {
    final target = resolveReconnectTarget(
      deviceName: 'JUANDIEGO-PC',
      discovered: [_announced('JUANDIEGO-PC')],
      manual: manual,
      mdnsGraceElapsed: true,
    );
    expect(target, (host: '192.168.1.8', port: 58643));
  });

  // El nombre real puede tener caracteres que mDNS convierte en `-`.
  test('matchea contra el nombre sanitizado, no contra el crudo', () {
    final target = resolveReconnectTarget(
      deviceName: "Juan's PC",
      discovered: [_announced('Juan-s-PC')],
      manual: null,
      mdnsGraceElapsed: true,
    );
    expect(target?.host, '192.168.1.8');
  });

  test('otra PC en la red no se toma por la propia', () {
    final target = resolveReconnectTarget(
      deviceName: 'JUANDIEGO-PC',
      discovered: [_announced('OTRA-PC')],
      manual: null,
      mdnsGraceElapsed: true,
    );
    expect(target, isNull);
  });

  group('sin mDNS', () {
    test('durante la gracia todavia no se usa la direccion manual', () {
      final target = resolveReconnectTarget(
        deviceName: 'JUANDIEGO-PC',
        discovered: const [],
        manual: manual,
        mdnsGraceElapsed: false,
      );
      expect(target, isNull);
    });

    test('vencida la gracia, se usa la direccion manual', () {
      final target = resolveReconnectTarget(
        deviceName: 'JUANDIEGO-PC',
        discovered: const [],
        manual: manual,
        mdnsGraceElapsed: true,
      );
      expect(target, (host: '100.64.0.5', port: 58643));
    });

    test('sin direccion manual no hay a donde ir', () {
      final target = resolveReconnectTarget(
        deviceName: 'JUANDIEGO-PC',
        discovered: const [],
        manual: null,
        mdnsGraceElapsed: true,
      );
      expect(target, isNull);
    });
  });

  // El caso que motiva el orden: la IP de la LAN la reparte el DHCP y
  // cambia, asi que una direccion manual guardada hace meses no puede
  // ganarle a lo que mDNS esta viendo AHORA.
  test('mDNS le gana a la manual aunque la gracia haya vencido', () {
    final target = resolveReconnectTarget(
      deviceName: 'JUANDIEGO-PC',
      discovered: [_announced('JUANDIEGO-PC', host: '192.168.1.44')],
      manual: manual,
      mdnsGraceElapsed: true,
    );
    expect(target?.host, '192.168.1.44');
  });
}
