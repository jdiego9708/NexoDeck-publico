import { describe, expect, it } from 'vitest';

import {
  applyLinePrefix,
  countWords,
  findWikiLinks,
  headingLevelOf,
  rankItems,
  readingMinutes,
  setHeadingLevel,
  taskCheckIndex,
  toggleTaskLine,
  toggleWrap,
  wikiQueryBefore,
} from '../src/markdownText';

describe('line prefixes', () => {
  it('adds bullets and removes them when every line already has one', () => {
    expect(applyLinePrefix(['uno', '', 'dos'], 'bullet')).toEqual(['- uno', '', '- dos']);
    expect(applyLinePrefix(['- uno', '- dos'], 'bullet')).toEqual(['uno', 'dos']);
  });

  it('numbers ordered lists and replaces a different prefix instead of stacking', () => {
    expect(applyLinePrefix(['- uno', '- dos'], 'ordered')).toEqual(['1. uno', '2. dos']);
    expect(applyLinePrefix(['- uno'], 'task')).toEqual(['- [ ] uno']);
    expect(applyLinePrefix(['- [ ] uno'], 'bullet')).toEqual(['- uno']);
    expect(applyLinePrefix(['- [x] hecha'], 'task')).toEqual(['hecha']);
  });

  it('keeps indentation', () => {
    expect(applyLinePrefix(['  sub'], 'quote')).toEqual(['  > sub']);
  });
});

describe('headings', () => {
  it('sets, changes and removes a heading level', () => {
    expect(setHeadingLevel('Titulo', 2)).toBe('## Titulo');
    expect(setHeadingLevel('## Titulo', 1)).toBe('# Titulo');
    expect(setHeadingLevel('## Titulo', 2)).toBe('Titulo');
    expect(setHeadingLevel('### Titulo', 0)).toBe('Titulo');
    expect(headingLevelOf('### x')).toBe(3);
    expect(headingLevelOf('#sin espacio')).toBe(0);
  });
});

describe('inline wrapping', () => {
  it('wraps and unwraps, reporting the new selection', () => {
    expect(toggleWrap('hola', '**')).toEqual({ text: '**hola**', selectFrom: 2, selectTo: 6 });
    expect(toggleWrap('**hola**', '**')).toEqual({ text: 'hola', selectFrom: 0, selectTo: 4 });
    expect(toggleWrap('', '`')).toEqual({ text: '``', selectFrom: 1, selectTo: 1 });
  });
});

describe('tasks', () => {
  it('finds and toggles the checkbox of a task line', () => {
    expect(taskCheckIndex('  - [ ] algo')).toBe(5);
    expect(toggleTaskLine('- [ ] reprocesar la tanda R')).toBe('- [x] reprocesar la tanda R');
    expect(toggleTaskLine('* [X] hecha')).toBe('* [ ] hecha');
    expect(toggleTaskLine('- no es tarea')).toBeNull();
  });
});

describe('wikilinks', () => {
  it('finds targets, headings and aliases with the visible label range', () => {
    const text = 'ver [[temas/malla]] y [[ODM#decisiones|la decision]]';
    const [plain, aliased] = findWikiLinks(text, 10);
    expect(plain.target).toBe('temas/malla');
    expect(text.slice(plain.labelFrom - 10, plain.labelTo - 10)).toBe('temas/malla');
    expect(aliased.target).toBe('ODM');
    expect(aliased.heading).toBe('decisiones');
    expect(text.slice(aliased.labelFrom - 10, aliased.labelTo - 10)).toBe('la decision');
    expect(aliased.to - 10).toBe(text.length);
  });

  it('knows what is being typed inside an open [[', () => {
    expect(wikiQueryBefore('algo [[tem')).toBe('tem');
    expect(wikiQueryBefore('algo [[')).toBe('');
    expect(wikiQueryBefore('[[cerrado]] y mas')).toBeNull();
  });
});

describe('stats', () => {
  it('counts words in Spanish text and estimates reading time', () => {
    expect(countWords('La ortofoto de la tanda R sale deformada — ¿por qué?')).toBe(10);
    expect(countWords('')).toBe(0);
    expect(readingMinutes(0)).toBe(0);
    expect(readingMinutes(30)).toBe(1);
    expect(readingMinutes(1100)).toBe(5);
  });
});

describe('ranking', () => {
  const items = [
    { label: 'Negrita', keywords: 'bold' },
    { label: 'Ir a: Reunión de soporte', keywords: 'reuniones/soporte' },
    { label: 'Insertar tabla' },
  ];

  it('ignores accents and case and prefers word starts', () => {
    expect(rankItems('reunion', items)[0].label).toBe('Ir a: Reunión de soporte');
    expect(rankItems('TABLA', items)[0].label).toBe('Insertar tabla');
    expect(rankItems('bold', items)[0].label).toBe('Negrita');
  });

  it('matches letters in order and drops what does not match', () => {
    expect(rankItems('ngr', items).map((i) => i.label)).toEqual(['Negrita']);
    expect(rankItems('zzz', items)).toEqual([]);
    expect(rankItems('', items)).toHaveLength(3);
  });
});
