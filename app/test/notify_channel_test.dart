import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/control/domain/notify_channel.dart';

void main() {
  group('el JSON es un contrato con serde, no un formato libre', () {
    /// Si alguien renombra una clave, el canal deja de existir del lado Rust y
    /// el sintoma es "no hay ningun canal configurado", que no apunta a la
    /// causa. Por eso se fijan los nombres exactos.
    test('the wire keys match what serde expects on the Rust side', () {
      final json = const NotifyChannel(
        id: 'wa',
        label: 'WhatsApp',
        program: 'bash',
        args: ['-lc', 'avisar -'],
        minLevel: NotifyMinLevel.always,
        timeoutSecs: 30,
      ).toJson();

      expect(json.keys, containsAll(<String>['id', 'label', 'program', 'args']));
      expect(json['delivery'], 'stdin');
      expect(json['min_level'], 'always');
      expect(json['timeout_secs'], 30);
      expect(json['enabled'], true);
    });

    test('a channel survives a round trip unchanged', () {
      const original = NotifyChannel(
        id: 'wa',
        label: 'WhatsApp',
        program: r'C:\PROGRA~1\Git\bin\bash.exe',
        args: ['-lc', r'bash "$0" -', '/d/proyecto/scripts/avisar.sh'],
        delivery: NotifyDelivery.stdin,
        minLevel: NotifyMinLevel.always,
        timeoutSecs: 45,
        enabled: false,
      );

      final restored = decodeNotifyChannels(
        encodeNotifyChannels([original]),
      ).single;

      expect(restored.id, original.id);
      expect(restored.program, original.program);
      expect(restored.args, original.args);
      expect(restored.delivery, original.delivery);
      expect(restored.minLevel, original.minLevel);
      expect(restored.timeoutSecs, original.timeoutSecs);
      expect(restored.enabled, original.enabled);
    });

    /// El timeout ausente tiene que seguir ausente: escribir un `null` haria
    /// que serde eligiera `None` igual, pero mandar la clave con `null` es una
    /// diferencia gratuita entre lo que guarda Dart y lo que lee Rust.
    test('an absent timeout does not travel as a null key', () {
      final json = const NotifyChannel(
        id: 'x',
        label: 'X',
        program: 'bash',
      ).toJson();
      expect(json.containsKey('timeout_secs'), isFalse);
    });
  });

  group('leer configuracion rota no puede tumbar el arranque', () {
    test('garbage and empty input yield no channels instead of throwing', () {
      expect(decodeNotifyChannels(null), isEmpty);
      expect(decodeNotifyChannels(''), isEmpty);
      expect(decodeNotifyChannels('no soy json'), isEmpty);
      expect(decodeNotifyChannels('{"no":"una lista"}'), isEmpty);
    });

    /// Mismo criterio que `channels_from_json` en Rust: se descarta lo que no
    /// se entiende y se conserva el resto. Una entrada rota no puede dejar a la
    /// maquina sin ningun aviso.
    test('an unusable entry is dropped but the rest survives', () {
      final raw = jsonEncode([
        {'id': 'ok', 'label': 'Bueno', 'program': 'bash'},
        {'id': 'sin-programa', 'label': 'Malo', 'program': '   '},
        {'label': 'sin id', 'program': 'bash'},
        'ni siquiera un objeto',
      ]);

      final channels = decodeNotifyChannels(raw);
      expect(channels, hasLength(1));
      expect(channels.single.id, 'ok');
    });

    test('an unknown delivery or level falls back instead of failing', () {
      final raw = jsonEncode([
        {
          'id': 'x',
          'label': 'X',
          'program': 'bash',
          'delivery': 'telepatia',
          'min_level': 'urgentisimo',
        },
      ]);

      final channel = decodeNotifyChannels(raw).single;
      expect(channel.delivery, NotifyDelivery.argv);
      expect(channel.minLevel, NotifyMinLevel.milestone);
    });
  });

  group('el atajo de script de bash', () {
    final channel = NotifyChannel.bashScript(
      id: 'wa',
      label: 'WhatsApp',
      scriptPath: '/d/proyecto/scripts/avisar.sh',
    );

    /// `-l` fija `HOME`. Sin eso, un script que haga `ssh` no encuentra su
    /// `~/.ssh/config` y el aviso no sale nunca. Ya costo tiempo antes, en el
    /// grupo ODM del deck.
    test('it uses a login shell so ssh can find its config', () {
      expect(channel.args.first, contains('-l'));
    });

    /// La ruta del script viaja como argumento propio y el script la lee de
    /// `$0`. Interpolarla en la linea obligaria a citarla, y las comillas
    /// quedarian anidadas con las del `-lc`.
    test('the script path travels as its own argument, not interpolated', () {
      expect(channel.args, contains('/d/proyecto/scripts/avisar.sh'));
      expect(channel.args[1], contains(r'$0'));
    });

    /// El texto va por stdin: asi ningun shell lo parsea y no hay nada que
    /// escapar, ni comillas ni acentos ni `$`.
    test('the message goes over stdin, never through a shell', () {
      expect(channel.delivery, NotifyDelivery.stdin);
      expect(channel.args.join(' '), isNot(contains('{{message}}')));
    });

    test('it uses the 8.3 short path for Git Bash to avoid nested quoting', () {
      expect(channel.program, NotifyChannel.gitBashShortPath);
      expect(channel.program, isNot(contains(' ')));
    });
  });
}
