import { describe, expect, it } from 'vitest';

import {
  isPrivatePath,
  normalizeNewNotePath,
  regroupPath,
  suggestNotePath,
  suggestPathInGroup,
} from '../src/notePaths';

describe('group of a new note', () => {
  // Sin agrupacion va a la bandeja: la misma regla que `save_note` desde Claude Code.
  it('suggests the inbox without a group and the group folder with one', () => {
    expect(suggestPathInGroup('Reunión de soporte', '')).toBe('inbox/reunión-de-soporte');
    expect(suggestPathInGroup('Vuelo 27', 'odm')).toBe('odm/vuelo-27');
    expect(suggestPathInGroup('   ', 'odm')).toBe('');
  });

  it('moves a hand-written path between the inbox and known groups', () => {
    expect(regroupPath('inbox/vuelo-27', 'odm', ['odm'])).toBe('odm/vuelo-27');
    expect(regroupPath('odm/vuelo-27', '', ['odm'])).toBe('inbox/vuelo-27');
  });

  // Una ruta en `privado/` o en una carpeta que no es agrupacion la decidio el
  // usuario: cambiar de grupo no puede sacarla de ahi en silencio.
  it('never touches a folder that is not a group', () => {
    expect(regroupPath('privado/ideas', 'odm', ['odm'])).toBe('privado/ideas');
    expect(regroupPath('diario/2026-09-16', 'odm', ['odm'])).toBe('diario/2026-09-16');
    expect(regroupPath('suelta', 'odm', ['odm'])).toBe('suelta');
  });
});

describe('new note paths', () => {
  it('stays inside the vault', () => {
    expect(normalizeNewNotePath(' temas/reunión soporte ')).toBe('temas/reunión soporte.md');
    expect(normalizeNewNotePath('\\privado\\claves.md')).toBe('privado/claves.md');
    expect(normalizeNewNotePath('../fuera')).toBeNull();
    expect(normalizeNewNotePath('.obsidian/workspace')).toBeNull();
    expect(normalizeNewNotePath('D:\\Notas\\x')).toBeNull();
    expect(normalizeNewNotePath('temas//x')).toBeNull();
    expect(normalizeNewNotePath('')).toBeNull();
  });

  it('suggests a path from the title', () => {
    expect(suggestNotePath('Reunión de soporte: ODM?')).toBe('reunión-de-soporte-odm');
    expect(suggestNotePath('   ')).toBe('');
  });

  it('knows a private note at any depth', () => {
    expect(isPrivatePath('Privado/claves.md')).toBe(true);
    expect(isPrivatePath('proyectos/privado/x.md')).toBe(true);
    expect(isPrivatePath('temas/privados.md')).toBe(false);
  });
});
