import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/widgets/color_palette_picker.dart';
import 'package:nexodeck/features/notes/domain/notes.dart';
import 'package:nexodeck/features/notes/presentation/note_groups.dart';
import 'package:nexodeck/src/rust/api/notes.dart' as bridge;

const _odm = NoteGroup(
  id: 'odm',
  name: 'Tandas de ODM',
  colorHex: '#10B981',
  order: 0,
  notes: 1,
);

const _overview = NotesOverview(
  configured: true,
  digestOnIdle: false,
  notes: [
    NoteSummary(
      path: 'odm/vuelo-27.md',
      group: 'odm',
      title: 'Vuelo 27',
      role: NoteRole.note,
      tags: [],
      openTasks: 0,
      aiExcluded: false,
    ),
    NoteSummary(
      path: 'inbox/suelta.md',
      title: 'Suelta',
      role: NoteRole.note,
      tags: [],
      openTasks: 0,
      aiExcluded: false,
    ),
  ],
  groups: [_odm],
  openTasks: [],
  commits: 0,
);

void main() {
  group('la agrupacion de una nota', () {
    test('resolves the group of a note by its folder id', () {
      expect(_overview.group(_overview.notes.first.group)?.name, 'Tandas de ODM');
    });

    test('a note in the inbox has no group', () {
      expect(_overview.group(_overview.notes.last.group), isNull);
    });

    /// Una carpeta que se borró por fuera entre dos fotos: la nota todavía la
    /// nombra, pero la agrupación ya no está. No puede romper la lista.
    test('an id that no longer exists resolves to nothing', () {
      expect(_overview.group('borrada'), isNull);
    });
  });

  group('lo que llega del puente', () {
    test('carries the group of each note and the list of groups', () {
      final overview = NotesOverview.fromBridge(
        const bridge.NotesOverviewItem(
          configured: true,
          digestOnIdle: false,
          folders: [],
          notes: [
            bridge.NoteSummaryItem(
              path: 'odm/a.md',
              group: 'odm',
              title: 'A',
              role: 'note',
              tags: [],
              openTasks: 0,
              aiExcluded: false,
            ),
          ],
          groups: [
            bridge.NoteGroupItem(
              id: 'odm',
              name: 'Tandas de ODM',
              colorHex: '#10B981',
              order: 0,
              notes: 1,
            ),
          ],
          openTasks: [],
          commits: 0,
        ),
      );

      expect(overview.notes.single.group, 'odm');
      expect(overview.groups.single.name, 'Tandas de ODM');
    });

    /// Lo que Rust reescribió al mover es lo único que dice qué notas del
    /// usuario cambiaron sin que él las tocara.
    test('a move keeps the notes whose links were rewritten', () {
      final move = NoteMove.fromBridge(
        const bridge.NoteMoveItem(
          from: 'inbox/malla.md',
          to: 'odm/malla.md',
          relinked: [bridge.NoteRelinkItem(path: 'temas/indice.md', links: 2)],
          digests: 1,
        ),
      );

      expect(move.to, 'odm/malla.md');
      expect(move.relinked.single.path, 'temas/indice.md');
      expect(move.relinked.single.links, 2);
    });
  });

  group('la carpeta de una agrupacion', () {
    test('a main vault group has no folder and its slug is its id', () {
      expect(noteGroupFolder(_odm), isNull);
      expect(noteGroupSlug(_odm), 'odm');
    });

    /// El id de una agrupación de una carpeta local lleva su prefijo; para
    /// mover una nota a ella se pasa solo el nombre de la carpeta.
    test('a local group names its folder and its slug', () {
      const local = NoteGroup(
        id: '@apuntes/clientes',
        name: 'Clientes',
        colorHex: '#10B981',
        order: 0,
        notes: 2,
      );
      expect(noteGroupFolder(local), 'apuntes');
      expect(noteGroupSlug(local), 'clientes');
    });
  });

  group('el color', () {
    test('a group color is its hex', () {
      expect(noteGroupColor(_odm), const Color(0xFF10B981));
    });

    /// Llega de un fichero que se puede editar a mano: mal escrito se pinta
    /// gris en vez de tumbar la pantalla.
    test('a broken hex paints grey instead of throwing', () {
      expect(ColorPalettePicker.parse('verde'), const Color(0xFF9E9E9E));
      expect(ColorPalettePicker.parse('#12'), const Color(0xFF9E9E9E));
    });
  });
}
