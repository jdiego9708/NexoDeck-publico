import { describe, expect, it } from 'vitest';

import { exportFileName, inFolder, linkForm, splitVirtual } from '../src/notePaths';
import { buildNoteTree, compareNatural, sortNotes } from '../src/noteTree';
import type { NoteSummaryDto, OverviewDto } from '../src/protocol';

function note(path: string): NoteSummaryDto {
  return {
    path,
    folder: splitVirtual(path)[0],
    group: null,
    title: path,
    role: 'note',
    date: null,
    tags: [],
    openTasks: 0,
    aiExcluded: false,
    modified: null,
  };
}

function overview(paths: string[]): OverviewDto {
  return {
    configured: true,
    root: 'D:\\Notas',
    folders: [
      { id: 'notas', name: 'Notas', path: 'D:\\Notas', local: false, available: true },
      { id: 'apuntes', name: 'Apuntes', path: 'D:\\Apuntes', local: true, available: true },
    ],
    groups: [],
    notes: paths.map(note),
    tasks: [],
    digests: [],
    error: null,
  };
}

describe('note tree', () => {
  it('puts each note under its folder, with the inner path', () => {
    const [main, local] = buildNoteTree(overview(['temas/malla.md', '@apuntes/clientes/acme.md', 'suelta.md']));
    expect(main.tree.folders.map((f) => f.name)).toEqual(['temas']);
    expect(main.tree.notes.map((n) => n.path)).toEqual(['suelta.md']);
    expect(local.tree.folders[0].path).toBe('clientes');
    expect(local.tree.folders[0].notes[0].path).toBe('@apuntes/clientes/acme.md');
    expect(local.tree.count).toBe(1);
  });

  // El orden del Explorador: carpetas primero, natural y sin mayusculas.
  it('orders folders first, naturally and ignoring case', () => {
    const [main] = buildNoteTree(overview(['nota 10.md', 'b/x.md', 'Nota 2.md', 'A/y.md']));
    expect(main.tree.folders.map((f) => f.name)).toEqual(['A', 'b']);
    expect(main.tree.notes.map((n) => n.path)).toEqual(['Nota 2.md', 'nota 10.md']);
    expect(main.tree.count).toBe(4);
  });

  it('a snapshot without folders puts everything in the main one', () => {
    const old = overview(['a.md']);
    delete old.folders;
    const roots = buildNoteTree(old);
    expect(roots).toHaveLength(1);
    expect(roots[0].tree.notes).toHaveLength(1);
  });

  it('compares numbers by value', () => {
    expect(compareNatural('v2', 'v10')).toBeLessThan(0);
    expect(compareNatural('Acme', 'acme')).toBe(0);
  });

  it('sorts by recency when asked, and keeps notes without a date at the end', () => {
    const dated = (path: string, modified: string | null): NoteSummaryDto => ({ ...note(path), modified });
    const snapshot = overview(['a.md', 'b.md', 'c.md']);
    snapshot.notes = [
      dated('a.md', '2026-09-10T10:00:00Z'),
      dated('b.md', '2026-09-12T10:00:00Z'),
      dated('c.md', null),
    ];

    expect(buildNoteTree(snapshot, 'newest')[0].tree.notes.map((n) => n.path)).toEqual(['b.md', 'a.md', 'c.md']);
    expect(buildNoteTree(snapshot, 'oldest')[0].tree.notes.map((n) => n.path)).toEqual(['a.md', 'b.md', 'c.md']);
    expect(sortNotes(snapshot.notes, 'newest').map((n) => n.path)).toEqual(['b.md', 'a.md', 'c.md']);
  });

  it('reorders folders by the recency of the notes they hold', () => {
    const dated = (path: string, modified: string | null): NoteSummaryDto => ({ ...note(path), modified });
    const snapshot = overview([]);
    snapshot.notes = [
      dated('vieja/x.md', '2026-09-01T10:00:00Z'),
      dated('media/x.md', '2026-09-10T10:00:00Z'),
      // La mas reciente de todas esta dos niveles abajo: su carpeta madre tiene
      // que subir igual.
      dated('nueva/dentro/x.md', '2026-09-20T10:00:00Z'),
      dated('nueva/y.md', '2026-09-02T10:00:00Z'),
      dated('sinfecha/x.md', null),
    ];

    const byName = buildNoteTree(snapshot, 'name')[0].tree;
    expect(byName.folders.map((f) => f.name)).toEqual(['media', 'nueva', 'sinfecha', 'vieja']);

    const newest = buildNoteTree(snapshot, 'newest')[0].tree;
    expect(newest.folders.map((f) => f.name)).toEqual(['nueva', 'media', 'vieja', 'sinfecha']);
    expect(newest.folders[0].folders.map((f) => f.name)).toEqual(['dentro']);

    const oldest = buildNoteTree(snapshot, 'oldest')[0].tree;
    expect(oldest.folders.map((f) => f.name)).toEqual(['vieja', 'nueva', 'media', 'sinfecha']);

    // Reordenar no pierde ni duplica notas.
    expect(newest.count).toBe(5);
  });
});

describe('export', () => {
  // Con la fecha local: pasada la medianoche en UTC seguiria siendo "hoy".
  it('suggests a dated zip name', () => {
    expect(exportFileName(new Date(2026, 8, 6, 23, 30))).toBe('notas-2026-09-06.zip');
  });
});

describe('virtual paths', () => {
  it('splits and joins a local folder prefix', () => {
    expect(splitVirtual('@apuntes/clientes/acme.md')).toEqual(['apuntes', 'clientes/acme.md']);
    expect(splitVirtual('temas/malla.md')).toEqual([null, 'temas/malla.md']);
    expect(inFolder('inbox/x', 'apuntes')).toBe('@apuntes/inbox/x');
    expect(inFolder('inbox/x', null)).toBe('inbox/x');
  });

  // Como `link_form` en Rust: dentro de la misma carpeta, relativo a ella.
  it('writes a link relative inside the same folder and virtual across', () => {
    expect(linkForm('@apuntes/clientes/acme', '@apuntes/indice.md')).toBe('clientes/acme');
    expect(linkForm('@apuntes/clientes/acme', 'temas/malla.md')).toBe('@apuntes/clientes/acme');
    expect(linkForm('temas/malla', '@apuntes/indice.md')).toBe('temas/malla');
    expect(linkForm('temas/malla', null)).toBe('temas/malla');
  });
});
