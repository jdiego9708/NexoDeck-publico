import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/stack/application/stack_health.dart';
import 'package:nexodeck/features/stack/domain/stack_profile.dart';

void main() {
  group('stackCommandFor', () {
    test('el perfil A lanza -Profile A', () {
      expect(
        stackCommandFor(StackProfile.rapido, r'D:\stack\scripts'),
        r"& 'D:\stack\scripts\Start-Stack.ps1' -Profile A",
      );
    });

    test('el perfil B lanza -Profile B', () {
      expect(
        stackCommandFor(StackProfile.contextoLargo, r'D:\stack\scripts'),
        r"& 'D:\stack\scripts\Start-Stack.ps1' -Profile B",
      );
    });

    test('Texto arranca el perfil C', () {
      expect(
        stackCommandFor(StackProfile.texto, r'D:\stack\scripts'),
        r"& 'D:\stack\scripts\Start-Stack.ps1' -Profile C",
      );
    });

    test('Apagado para el stack y libera WSL', () {
      expect(
        stackCommandFor(StackProfile.apagado, r'D:\stack\scripts'),
        r"& 'D:\stack\scripts\Stop-Stack.ps1' -ReleaseWsl",
      );
    });

    test('tolera una barra final en la carpeta', () {
      expect(
        stackCommandFor(StackProfile.rapido, r'D:\stack\scripts\'),
        stackCommandFor(StackProfile.rapido, r'D:\stack\scripts'),
      );
    });
  });

  group('stackDownloadCommandFor', () {
    test('descarga un rol del stack', () {
      expect(
        stackDownloadCommandFor('writer', r'D:\stack\scripts'),
        r"& 'D:\stack\scripts\Download-Model.ps1' -Role writer",
      );
    });

    test('tolera una barra final en la carpeta', () {
      expect(
        stackDownloadCommandFor('writer', r'D:\stack\scripts\'),
        stackDownloadCommandFor('writer', r'D:\stack\scripts'),
      );
    });
  });

  group('downloadRateMbps', () {
    test('calcula MB/s entre dos medidas', () {
      expect(
        downloadRateMbps(
          previousBytes: 0,
          bytes: 10 * 1024 * 1024,
          elapsed: const Duration(seconds: 2),
        ),
        closeTo(5.0, 1e-9),
      );
    });

    test('sin ventana de tiempo no inventa un numero', () {
      expect(
        downloadRateMbps(
          previousBytes: 0,
          bytes: 10 * 1024 * 1024,
          elapsed: Duration.zero,
        ),
        isNull,
      );
    });

    test('un directorio que encoge no da una tasa negativa', () {
      expect(
        downloadRateMbps(
          previousBytes: 20 * 1024 * 1024,
          bytes: 10 * 1024 * 1024,
          elapsed: const Duration(seconds: 2),
        ),
        isNull,
      );
    });
  });

  group('stackRolesStarted', () {
    test('esta iniciado cuando todos sus roles estan up', () {
      const health = StackHealth(reachable: true, router: 'up', fast: 'up');
      expect(stackRolesStarted({'router', 'fast'}, health), isTrue);
      // B necesita el complejo, que no esta.
      expect(stackRolesStarted({'router', 'complex'}, health), isFalse);
    });

    test('sin pasarela, o sin roles locales, no esta iniciado', () {
      expect(
        stackRolesStarted({'router'}, const StackHealth.unreachable()),
        isFalse,
      );
      expect(
        stackRolesStarted(
          const <String>{},
          const StackHealth(reachable: true, router: 'up'),
        ),
        isFalse,
      );
    });
  });

  group('StackProfile.fromName', () {
    test('lee lo guardado y cae a apagado si no existe', () {
      expect(
        StackProfile.fromName('contextoLargo'),
        StackProfile.contextoLargo,
      );
      expect(StackProfile.fromName('lo_que_sea'), StackProfile.apagado);
      expect(StackProfile.fromName(null), StackProfile.apagado);
    });

    test('el nombre viejo «carrera» sigue leyendo el perfil C', () {
      expect(StackProfile.fromName('carrera'), StackProfile.texto);
    });
  });
}
