// Los comandos de la barra de herramientas y de los atajos.

import { startCompletion } from '@codemirror/autocomplete';
import { syntaxTree } from '@codemirror/language';
import { EditorSelection, type EditorState } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';

import { toggleTaskAt } from './livePreview';
import {
  applyLinePrefix,
  headingLevelOf,
  type LinePrefixKind,
  setHeadingLevel,
  toggleWrap,
} from './markdownText';

function finish(view: EditorView): boolean {
  view.focus();
  return true;
}

/** Negrita, cursiva, tachado o codigo: envuelve la seleccion, o la desenvuelve. */
export function toggleInline(view: EditorView, marker: string): boolean {
  const { state } = view;
  const transaction = state.changeByRange((range) => {
    const before = state.sliceDoc(range.from - marker.length, range.from);
    const after = state.sliceDoc(range.to, range.to + marker.length);
    if (before === marker && after === marker) {
      return {
        changes: [
          { from: range.from - marker.length, to: range.from },
          { from: range.to, to: range.to + marker.length },
        ],
        range: EditorSelection.range(range.from - marker.length, range.to - marker.length),
      };
    }
    const result = toggleWrap(state.sliceDoc(range.from, range.to), marker);
    return {
      changes: { from: range.from, to: range.to, insert: result.text },
      range: EditorSelection.range(range.from + result.selectFrom, range.from + result.selectTo),
    };
  });
  view.dispatch(state.update(transaction, { scrollIntoView: true, userEvent: 'input.format' }));
  return finish(view);
}

function selectedLineSpan(state: EditorState): { from: number; to: number; lines: string[] } {
  const selection = state.selection.main;
  const first = state.doc.lineAt(selection.from);
  const last = state.doc.lineAt(selection.to);
  const lines: string[] = [];
  for (let number = first.number; number <= last.number; number++) {
    lines.push(state.doc.line(number).text);
  }
  return { from: first.from, to: last.to, lines };
}

export function setHeading(view: EditorView, level: number): boolean {
  const { from, to, lines } = selectedLineSpan(view.state);
  const insert = lines.map((line) => setHeadingLevel(line, level)).join('\n');
  view.dispatch({
    changes: { from, to, insert },
    selection: { anchor: from + insert.length },
    userEvent: 'input.format',
  });
  return finish(view);
}

export function toggleLinePrefix(view: EditorView, kind: LinePrefixKind): boolean {
  const { from, to, lines } = selectedLineSpan(view.state);
  const insert = applyLinePrefix(lines, kind).join('\n');
  view.dispatch({
    changes: { from, to, insert },
    selection: { anchor: from + insert.length },
    userEvent: 'input.format',
  });
  return finish(view);
}

/** Inserta un bloque en su propia linea, con el cursor donde indica `cursorAt`. */
function insertBlock(view: EditorView, block: string, cursorAt: number): boolean {
  const { state } = view;
  const selection = state.selection.main;
  const line = state.doc.lineAt(selection.from);
  const needsBreakBefore = line.text.trim() !== '' && selection.from !== line.from;
  const prefix = needsBreakBefore ? '\n\n' : '';
  view.dispatch({
    changes: { from: selection.from, to: selection.to, insert: prefix + block },
    selection: { anchor: selection.from + prefix.length + cursorAt },
    scrollIntoView: true,
    userEvent: 'input.format',
  });
  return finish(view);
}

export function insertCodeBlock(view: EditorView): boolean {
  const selected = view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to);
  return insertBlock(view, '```\n' + selected + '\n```\n', 4 + selected.length);
}

export function insertTable(view: EditorView): boolean {
  const table = '| Columna | Columna |\n| --- | --- |\n|  |  |\n';
  return insertBlock(view, table, 2);
}

export function insertRule(view: EditorView): boolean {
  return insertBlock(view, '---\n', 4);
}

export function insertLink(view: EditorView): boolean {
  const { state } = view;
  const selection = state.selection.main;
  const text = state.sliceDoc(selection.from, selection.to) || 'texto';
  const insert = `[${text}](https://)`;
  const urlFrom = selection.from + text.length + 3;
  view.dispatch({
    changes: { from: selection.from, to: selection.to, insert },
    selection: { anchor: urlFrom, head: urlFrom + 8 },
    userEvent: 'input.format',
  });
  return finish(view);
}

export function insertWikiLink(view: EditorView): boolean {
  const selection = view.state.selection.main;
  const text = view.state.sliceDoc(selection.from, selection.to);
  view.dispatch({
    changes: { from: selection.from, to: selection.to, insert: `[[${text}]]` },
    selection: { anchor: selection.from + 2 + text.length },
    userEvent: 'input.format',
  });
  finish(view);
  startCompletion(view);
  return true;
}

/** Marca o desmarca la tarea de la linea del cursor (Ctrl+Enter). */
export function toggleTaskUnderCursor(view: EditorView): boolean {
  return toggleTaskAt(view, view.state.doc.lineAt(view.state.selection.main.head).from);
}

export type Format =
  | 'bold'
  | 'italic'
  | 'strike'
  | 'code'
  | 'h1'
  | 'h2'
  | 'h3'
  | 'bullet'
  | 'ordered'
  | 'task'
  | 'quote'
  | 'link';

/** Los formatos activos en el cursor, para iluminar los botones de la barra. */
export function activeFormats(state: EditorState): Set<Format> {
  const formats = new Set<Format>();
  const head = state.selection.main.head;
  const level = headingLevelOf(state.doc.lineAt(head).text);
  if (level >= 1 && level <= 3) {
    formats.add(`h${level}` as Format);
  }
  for (let node = syntaxTree(state).resolveInner(head, -1); node; node = node.parent!) {
    switch (node.name) {
      case 'StrongEmphasis':
        formats.add('bold');
        break;
      case 'Emphasis':
        formats.add('italic');
        break;
      case 'Strikethrough':
        formats.add('strike');
        break;
      case 'InlineCode':
        formats.add('code');
        break;
      case 'Link':
        formats.add('link');
        break;
      case 'Blockquote':
        formats.add('quote');
        break;
      case 'Task':
        formats.add('task');
        break;
      case 'BulletList':
        if (!formats.has('task')) {
          formats.add('bullet');
        }
        break;
      case 'OrderedList':
        formats.add('ordered');
        break;
    }
    if (!node.parent) {
      break;
    }
  }
  return formats;
}
