// Transformaciones de texto puras, sin CodeMirror: se prueban sin navegador.

export type LinePrefixKind = 'bullet' | 'ordered' | 'task' | 'quote';

const ANY_PREFIX = /^(?:[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s?)/;

function hasKind(line: string, kind: LinePrefixKind): boolean {
  const body = line.trimStart();
  switch (kind) {
    case 'task':
      return /^[-*+]\s+\[[ xX]\](\s|$)/.test(body);
    case 'bullet':
      return /^[-*+]\s+/.test(body) && !/^[-*+]\s+\[[ xX]\](\s|$)/.test(body);
    case 'ordered':
      return /^\d+[.)]\s/.test(body);
    case 'quote':
      return body.startsWith('>');
  }
}

/**
 * Pone o quita un tipo de bloque en varias lineas. Si todas las lineas con texto
 * ya lo tienen, se quita; si no, se pone en todas, reemplazando cualquier otro
 * prefijo de lista o cita (pasar de viñetas a tareas no deja "- - [ ]").
 */
export function applyLinePrefix(lines: readonly string[], kind: LinePrefixKind): string[] {
  const withText = lines.filter((line) => line.trim() !== '');
  const remove = withText.length > 0 && withText.every((line) => hasKind(line, kind));
  let counter = 1;
  return lines.map((line) => {
    if (line.trim() === '') {
      return line;
    }
    const indent = line.match(/^\s*/)?.[0] ?? '';
    const body = line.slice(indent.length).replace(ANY_PREFIX, '');
    if (remove) {
      return indent + body;
    }
    const prefix =
      kind === 'bullet' ? '- ' : kind === 'ordered' ? `${counter++}. ` : kind === 'task' ? '- [ ] ' : '> ';
    return indent + prefix + body;
  });
}

/** Nivel de encabezado de una linea; 0 si no lo es. */
export function headingLevelOf(line: string): number {
  const match = line.match(/^(#{1,6})\s/);
  return match ? match[1].length : 0;
}

/** Cambia el encabezado de una linea. 0 es parrafo; repetir el nivel lo quita. */
export function setHeadingLevel(line: string, level: number): string {
  const match = line.match(/^(#{1,6})\s+/);
  const body = match ? line.slice(match[0].length) : line;
  if (level === 0 || (match !== null && match[1].length === level)) {
    return body;
  }
  return `${'#'.repeat(level)} ${body}`;
}

/** Envuelve o desenvuelve un texto con un marcador (`**`, `_`, `` ` ``, `~~`). */
export function toggleWrap(text: string, marker: string): { text: string; selectFrom: number; selectTo: number } {
  if (text.length >= marker.length * 2 && text.startsWith(marker) && text.endsWith(marker)) {
    const inner = text.slice(marker.length, text.length - marker.length);
    return { text: inner, selectFrom: 0, selectTo: inner.length };
  }
  return { text: marker + text + marker, selectFrom: marker.length, selectTo: marker.length + text.length };
}

/** Donde esta la casilla de una tarea en su linea: el indice del caracter entre corchetes. */
export function taskCheckIndex(line: string): number | null {
  const match = line.match(/^(\s*[-*+]\s+\[)[ xX]\]/);
  return match ? match[1].length : null;
}

/** La linea con la casilla cambiada, o null si no es una tarea. */
export function toggleTaskLine(line: string): string | null {
  const index = taskCheckIndex(line);
  if (index === null) {
    return null;
  }
  const next = line[index] === ' ' ? 'x' : ' ';
  return line.slice(0, index) + next + line.slice(index + 1);
}

export function countWords(text: string): number {
  const words = text.match(/[\p{L}\p{N}][\p{L}\p{N}'’_-]*/gu);
  return words ? words.length : 0;
}

/** Minutos de lectura a 220 palabras por minuto, como mínimo 1 si hay texto. */
export function readingMinutes(words: number): number {
  return words === 0 ? 0 : Math.max(1, Math.round(words / 220));
}

export interface WikiLink {
  from: number;
  to: number;
  target: string;
  heading: string | null;
  alias: string | null;
  /** Lo que se ve cuando el enlace se pinta: el alias, o el destino con su sección. */
  labelFrom: number;
  labelTo: number;
}

const WIKILINK = /\[\[([^[\]\n|#]+)(#[^[\]\n|]*)?(?:\|([^[\]\n]*))?\]\]/g;

export function findWikiLinks(text: string, offset = 0): WikiLink[] {
  const links: WikiLink[] = [];
  for (const match of text.matchAll(WIKILINK)) {
    const from = offset + (match.index ?? 0);
    const to = from + match[0].length;
    const rawTarget = match[1];
    const heading = match[2] !== undefined ? match[2].slice(1) : null;
    const alias = match[3] !== undefined ? match[3] : null;
    let labelFrom: number;
    let labelTo: number;
    if (alias !== null && alias.length > 0) {
      labelTo = to - 2;
      labelFrom = labelTo - alias.length;
    } else {
      labelFrom = from + 2;
      labelTo = labelFrom + rawTarget.length + (match[2]?.length ?? 0);
    }
    links.push({ from, to, target: rawTarget.trim(), heading, alias, labelFrom, labelTo });
  }
  return links;
}

/** Lo que se esta escribiendo dentro de un `[[` abierto antes del cursor. */
export function wikiQueryBefore(textBefore: string): string | null {
  const match = textBefore.match(/\[\[([^[\]|#\n]*)$/);
  return match ? match[1] : null;
}

export function normalizeForSearch(text: string): string {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

export interface Rankable {
  label: string;
  keywords?: string;
}

/**
 * Ordena por coincidencia: primero lo que contiene la busqueda tal cual (mejor
 * si empieza en una palabra), despues lo que tiene sus letras en orden. Sin
 * tildes ni mayusculas.
 */
export function rankItems<T extends Rankable>(query: string, items: readonly T[], limit = 50): T[] {
  const needle = normalizeForSearch(query.trim());
  if (needle === '') {
    return items.slice(0, limit);
  }
  const scored: { item: T; score: number; index: number }[] = [];
  items.forEach((item, index) => {
    const haystack = normalizeForSearch(`${item.label} ${item.keywords ?? ''}`);
    const score = matchScore(needle, haystack);
    if (score > 0) {
      scored.push({ item, score, index });
    }
  });
  scored.sort((a, b) => b.score - a.score || a.index - b.index);
  return scored.slice(0, limit).map((entry) => entry.item);
}

function matchScore(needle: string, haystack: string): number {
  const at = haystack.indexOf(needle);
  if (at >= 0) {
    const wordStart = at === 0 || /[\s/_-]/.test(haystack[at - 1]);
    return 1000 + (wordStart ? 500 : 0) - at;
  }
  let position = 0;
  let score = 0;
  let streak = 0;
  for (const char of needle) {
    const found = haystack.indexOf(char, position);
    if (found < 0) {
      return 0;
    }
    streak = found === position ? streak + 1 : 0;
    score += 1 + streak * 2;
    position = found + 1;
  }
  return score;
}
