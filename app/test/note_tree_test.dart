import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/features/notes/domain/note_tree.dart';
import 'package:nexodeck/features/notes/domain/notes.dart';
import 'package:nexodeck/features/notes/domain/vault_config.dart';

NoteSummary _note(String path, {String? folder}) => NoteSummary(
  path: path,
  folder: folder,
  title: path,
  role: NoteRole.note,
  tags: const [],
  openTasks: 0,
  aiExcluded: false,
);

const _main = NoteFolder(
  id: 'notas',
  name: 'Notas',
  path: r'D:\Notas',
  local: false,
  available: true,
);
const _local = NoteFolder(
  id: 'apuntes',
  name: 'apuntes',
  path: r'D:\Trabajo\apuntes',
  local: true,
  available: true,
);

void main() {
  group('el arbol de notas', () {
    test('splits notes by folder and keeps the path inside each folder', () {
      final roots = buildNoteTree(
        NotesOverview(
          configured: true,
          digestOnIdle: false,
          notes: [
            _note('temas/malla.md'),
            _note('@apuntes/clientes/acme.md', folder: 'apuntes'),
            _note('@apuntes/suelta.md', folder: 'apuntes'),
          ],
          folders: const [_main, _local],
          openTasks: const [],
          commits: 0,
        ),
      );

      expect(roots.map((r) => r.folder.id), ['notas', 'apuntes']);
      expect(roots[0].tree.folders.single.name, 'temas');
      final apuntes = roots[1].tree;
      // Sin el `@apuntes/`: es la estructura que el usuario ve en su disco.
      expect(apuntes.folders.single.name, 'clientes');
      expect(apuntes.folders.single.path, 'clientes');
      expect(apuntes.notes.single.path, '@apuntes/suelta.md');
      expect(apuntes.count, 2);
    });

    /// El orden del Explorador: carpetas primero, natural y sin mayúsculas.
    test('sorts folders first, naturally and ignoring case', () {
      final root = buildNoteTree(
        NotesOverview(
          configured: true,
          digestOnIdle: false,
          notes: [
            _note('nota 10.md'),
            _note('Zeta/a.md'),
            _note('nota 2.md'),
            _note('alfa/b.md'),
            _note('Beta.md'),
          ],
          folders: const [_main],
          openTasks: const [],
          commits: 0,
        ),
      ).single.tree;

      expect(root.folders.map((f) => f.name), ['alfa', 'Zeta']);
      expect(root.notes.map((n) => n.path), ['Beta.md', 'nota 2.md', 'nota 10.md']);
    });

    test('natural order compares numbers as numbers', () {
      expect(compareNatural('nota 2', 'nota 10'), lessThan(0));
      expect(compareNatural('Acme', 'acme'), 0);
    });
  });

  group('las carpetas locales en la configuracion', () {
    const base = '''
{
  "projects": [
    { "id": "ia", "kind": "docs", "repo_root": "D:\\\\Repositorios\\\\ExampleApi" },
    { "id": "notas", "kind": "vault", "repo_root": "D:\\\\Notas" }
  ],
  "notes": { "vault_project": "notas", "digest_on_idle": true }
}
''';

    test('adds a folder as a vault project and lists it', () {
      final json = addLocalFolder(base, r'D:\Trabajo\Año Apuntes');
      final folders = readLocalFolders(json);
      expect(folders.single.id, 'ano-apuntes');
      expect(folders.single.name, 'Año Apuntes');
      expect(folders.single.path, r'D:\Trabajo\Año Apuntes');

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      // El resto queda intacto.
      expect((decoded['notes'] as Map)['digest_on_idle'], true);
      expect((decoded['projects'] as List).first['id'], 'ia');
    });

    test('ids never collide with an existing project', () {
      final json = addLocalFolder(base, r'D:\Otra\notas');
      expect(readLocalFolders(json).single.id, 'notas-2');
    });

    /// Quitar una carpeta no toca el disco ni otros proyectos.
    test('removing a folder keeps the other projects', () {
      final added = addLocalFolder(base, r'D:\Trabajo\apuntes');
      final removed = removeLocalFolder(added, 'apuntes');
      expect(readLocalFolders(removed), isEmpty);
      final ids = [
        for (final p in (jsonDecode(removed)['projects'] as List)) p['id'],
      ];
      expect(ids, ['ia', 'notas']);
    });

    test('ids only use lowercase letters, digits and dashes', () {
      expect(folderId('  Mis Notas (2026)! '), 'mis-notas-2026');
      expect(folderId('***'), 'carpeta');
    });
  });
}
