import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/notes/domain/vault_config.dart';

/// Una configuración como la real: dos proyectos de documentación que NO son la
/// bóveda y que no se pueden perder al tocarla.
const _withDocs = '''
{
  "worker_enabled": true,
  "remote": { "provider_id": "deepseek", "model": "deepseek-chat" },
  "projects": [
    { "id": "ia", "name": "IA", "repo_root": "D:\\\\Repositorios\\\\ExampleApi",
      "documents": [ { "path": "docs/estado.md", "role": "journal" } ] }
  ]
}
''';

const _withVault = '''
{
  "projects": [
    { "id": "ia", "name": "IA", "repo_root": "D:\\\\Repositorios\\\\ExampleApi" },
    { "id": "notas", "name": "Notas", "kind": "vault", "repo_root": "D:\\\\Viejo" }
  ],
  "notes": { "vault_project": "notas", "repos": ["D:\\\\Repositorios\\\\NexoDeck"], "digest_on_idle": true }
}
''';

void main() {
  group('leer la boveda de la configuracion', () {
    test('reports no vault when there is none', () {
      expect(readVaultSettings(_withDocs).configured, isFalse);
      expect(readVaultSettings(_withDocs).root, isNull);
    });

    test('reads the folder and the repos', () {
      final settings = readVaultSettings(_withVault);
      expect(settings.projectId, 'notas');
      expect(settings.root, r'D:\Viejo');
      expect(settings.repos, [r'D:\Repositorios\NexoDeck']);
      expect(settings.configured, isTrue);
    });

    /// Una configuración a medias (proyecto de bóveda sin el bloque `notes`) es
    /// justo la que hay que poder arreglar desde la interfaz.
    test('finds a vault project even without the notes block', () {
      const halfway = '''
      { "projects": [ { "id": "n", "kind": "vault", "repo_root": "D:\\\\N" } ] }
      ''';
      expect(readVaultSettings(halfway).root, r'D:\N');
    });

    test('a broken config is just no vault, never a crash', () {
      expect(readVaultSettings('{ esto no es json').configured, isFalse);
      expect(readVaultSettings('').configured, isFalse);
    });
  });

  group('cambiar la carpeta de la boveda', () {
    /// Lo que no se puede romper: la configuración es una sola y la comparten
    /// los proyectos de documentación.
    test('never touches the documentation projects', () {
      final out =
          jsonDecode(writeVaultFolder(_withDocs, r'D:\Notas'))
              as Map<String, dynamic>;
      final projects = out['projects'] as List;

      final ia = projects.firstWhere((p) => p['id'] == 'ia') as Map;
      expect(ia['repo_root'], r'D:\Repositorios\ExampleApi');
      expect((ia['documents'] as List).single['role'], 'journal');
      expect(out['worker_enabled'], true);
      expect((out['remote'] as Map)['model'], 'deepseek-chat');
    });

    test('adds the vault project and the notes block when there was none', () {
      final out =
          jsonDecode(writeVaultFolder(_withDocs, r'D:\Notas'))
              as Map<String, dynamic>;
      final vault =
          (out['projects'] as List).firstWhere((p) => p['kind'] == 'vault')
              as Map;
      expect(vault['repo_root'], r'D:\Notas');
      expect(vault['id'], kVaultProjectId);
      expect((out['notes'] as Map)['vault_project'], kVaultProjectId);
      expect((out['notes'] as Map)['digest_on_idle'], false);
    });

    /// Dos bóvedas en la lista dejarían al usuario eligiendo entre dos cosas que
    /// se llaman igual.
    test('reuses the existing vault instead of adding a second one', () {
      final out =
          jsonDecode(writeVaultFolder(_withVault, r'D:\Notas'))
              as Map<String, dynamic>;
      final vaults = (out['projects'] as List)
          .where((p) => p['kind'] == 'vault')
          .toList();
      expect(vaults, hasLength(1));
      expect(vaults.single['repo_root'], r'D:\Notas');
      expect(vaults.single['id'], 'notas');
      // Y no se pierde lo que el usuario ya había elegido.
      expect((out['notes'] as Map)['digest_on_idle'], true);
      expect((out['notes'] as Map)['repos'], [r'D:\Repositorios\NexoDeck']);
    });

    test('an empty folder is refused instead of writing a broken config', () {
      expect(() => writeVaultFolder(_withVault, '   '), throwsFormatException);
    });

    test('repos are trimmed and empties dropped', () {
      final out =
          jsonDecode(
                writeVaultRepos(_withVault, [r'  D:\Uno  ', '', r'D:\Dos']),
              )
              as Map<String, dynamic>;
      expect((out['notes'] as Map)['repos'], [r'D:\Uno', r'D:\Dos']);
    });
  });

  group('carpetas locales', () {
    test('adds a vault project with a safe id and lists it', () {
      final out = addLocalFolder(_withVault, r'D:\Trabajo\Apuntes Clientes');
      final folder = readLocalFolders(out).single;
      expect(folder.id, 'apuntes-clientes');
      expect(folder.name, 'Apuntes Clientes');
      expect(folder.path, r'D:\Trabajo\Apuntes Clientes');
      // La bóveda y los proyectos del buzón siguen ahí.
      expect(readVaultSettings(out).root, r'D:\Viejo');
      expect(
        (jsonDecode(out)['projects'] as List).map((p) => p['id']),
        containsAll(['ia', 'notas']),
      );
    });

    test('an id already taken gets a suffix', () {
      final out = addLocalFolder(_withVault, r'E:\notas');
      expect(readLocalFolders(out).single.id, 'notas-2');
    });

    test('removing one leaves the vault and the other folders', () {
      final two = addLocalFolder(
        addLocalFolder(_withVault, r'D:\Uno'),
        r'D:\Dos',
      );
      final out = removeLocalFolder(two, 'uno');
      expect(readLocalFolders(out).map((f) => f.id), ['dos']);
      expect(readVaultSettings(out).root, r'D:\Viejo');
    });

    /// Una carpeta local también es de clase `vault`. Sin el bloque `notes`
    /// apuntando a la bóveda —o al cambiarla— no puede confundirse con ella:
    /// cambiar la bóveda acabaría moviendo la carpeta local.
    test('a local folder is never taken for the main vault', () {
      const onlyLocal = '''
{
  "projects": [
    { "id": "apuntes", "name": "Apuntes", "kind": "vault", "repo_root": "D:\\\\Apuntes" }
  ],
  "notes": { "local_folders": ["apuntes"] }
}
''';
      expect(readVaultSettings(onlyLocal).configured, isFalse);

      final out = writeVaultFolder(onlyLocal, r'D:\Notas');
      expect(readVaultSettings(out).root, r'D:\Notas');
      expect(readLocalFolders(out).single.path, r'D:\Apuntes');
    });
  });
}
