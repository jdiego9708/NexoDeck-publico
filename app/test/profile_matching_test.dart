import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/profiles/domain/deck_profile.dart';
import 'package:nexodeck/features/profiles/domain/profile_matching.dart';

void main() {
  group('matchesProcess', () {
    test('compara sin distinguir mayúsculas', () {
      // Windows no distingue mayúsculas en nombres de archivo, y el campo
      // del editor es texto libre.
      expect(matchesProcess('obs64.exe', 'obs64.exe'), isTrue);
      expect(matchesProcess('Code.exe', 'code.exe'), isTrue);
      expect(matchesProcess('obs64.exe', 'OBS64.EXE'), isTrue);
    });

    test('tolera que el usuario omita la extensión', () {
      expect(matchesProcess('obs64.exe', 'obs64'), isTrue);
      expect(matchesProcess('Code.exe', 'Code'), isTrue);
    });

    test('NO matchea por prefijo', () {
      // Si matcheara, configurar `code` activaría el perfil con cualquier
      // ejecutable que empiece igual.
      expect(matchesProcess('obs64.exe', 'obs'), isFalse);
      expect(matchesProcess('code_helper.exe', 'code'), isFalse);
    });

    test('un valor vacío nunca matchea', () {
      // Vacío significa "solo activación manual", no "cualquier cosa".
      expect(matchesProcess('obs64.exe', null), isFalse);
      expect(matchesProcess('obs64.exe', ''), isFalse);
      expect(matchesProcess('obs64.exe', '   '), isFalse);
    });

    test('ignora espacios alrededor del valor configurado', () {
      expect(matchesProcess('obs64.exe', '  obs64.exe  '), isTrue);
    });
  });

  group('profileForProcess', () {
    final streaming = _profile('s', 'Streaming', 'obs64.exe');
    final dev = _profile('d', 'Desarrollo', 'Code.exe');
    final manual = _profile('m', 'Manual', null);

    test('devuelve el perfil cuyo ejecutable coincide', () {
      final match = profileForProcess('Code.exe', [streaming, dev, manual]);
      expect(match?.id, 'd');
    });

    test('devuelve null si ninguno reclama el proceso', () {
      expect(profileForProcess('explorer.exe', [streaming, dev]), isNull);
    });

    test('devuelve null si no se sabe qué app está en foco', () {
      expect(profileForProcess(null, [streaming, dev]), isNull);
    });

    test('nunca elige un perfil sin auto-detección', () {
      expect(profileForProcess('', [manual]), isNull);
      expect(profileForProcess('manual', [manual]), isNull);
    });

    test('con dos perfiles para el mismo exe gana el primero, y es estable', () {
      // Lo importante no es cuál gana sino que no oscile entre los dos en
      // cada tick del detector de foco.
      final otro = _profile('z', 'Otro', 'obs64.exe');
      final primera = profileForProcess('obs64.exe', [streaming, otro]);
      final segunda = profileForProcess('obs64.exe', [streaming, otro]);
      expect(primera?.id, 's');
      expect(segunda?.id, primera?.id);
    });
  });
}

DeckProfile _profile(String id, String name, String? process) => DeckProfile(
  id: id,
  name: name,
  icon: 'folder',
  colorHex: '#22C55E',
  isDefault: false,
  autoDetectProcess: process,
);
