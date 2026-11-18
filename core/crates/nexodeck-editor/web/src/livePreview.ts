// Vista previa en vivo: el markdown se ve formateado y las marcas (`#`, `**`,
// `[]()`, `- [ ]`) solo aparecen en la linea donde esta el cursor.
//
// Todo son decoraciones de vista. El documento no cambia: lo que se guarda es
// markdown byte a byte, igual que si se hubiera escrito en un bloc de notas.

import { syntaxTree } from '@codemirror/language';
import type { EditorState, Range } from '@codemirror/state';
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
} from '@codemirror/view';
import type { SyntaxNode } from '@lezer/common';

import { findWikiLinks, taskCheckIndex } from './markdownText';

const hiddenMark = Decoration.replace({});
const lineClass = (className: string) => Decoration.line({ class: className });

/** La nota abierta: hace falta para resolver una imagen relativa (`![]()`). */
let currentNote: string | null = null;

/** La fija `main.ts` al cargar una nota. */
export function setCurrentNote(path: string | null): void {
  currentNote = path;
}

/** La URL con la que el WebView pide un adjunto de la boveda. Lo absoluto
 * (data:, https:, ya-nexodeck:) pasa tal cual; lo demas es relativo a la nota. */
function attachmentUrl(src: string): string {
  if (/^(?:data:|https?:|blob:|nexodeck:|file:)/i.test(src)) {
    return src;
  }
  const note = currentNote ?? '';
  return `nexodeck://localhost/attachment?note=${encodeURIComponent(note)}&src=${encodeURIComponent(src)}`;
}

class CheckboxWidget extends WidgetType {
  constructor(
    private readonly checked: boolean,
    private readonly lineFrom: number,
  ) {
    super();
  }

  eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked && other.lineFrom === this.lineFrom;
  }

  toDOM(view: EditorView): HTMLElement {
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.className = 'cm-task';
    box.checked = this.checked;
    box.tabIndex = -1;
    box.setAttribute('aria-label', this.checked ? 'Tarea hecha' : 'Tarea pendiente');
    box.addEventListener('mousedown', (event) => {
      event.preventDefault();
      toggleTaskAt(view, this.lineFrom);
    });
    return box;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class RuleWidget extends WidgetType {
  eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const rule = document.createElement('span');
    rule.className = 'cm-hr-widget';
    return rule;
  }
}

/** La fila de guiones de una tabla (`|---|`), como una linea fina. */
class TableDividerWidget extends WidgetType {
  eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const divider = document.createElement('span');
    divider.className = 'cm-table-divider';
    return divider;
  }
}

/** Una imagen `![alt](src)`, incrustada en el texto. Si no se puede cargar se
 * esconde en vez de dejar el icono roto del navegador. */
class ImageWidget extends WidgetType {
  constructor(
    private readonly src: string,
    private readonly alt: string,
  ) {
    super();
  }

  eq(other: ImageWidget): boolean {
    return other.src === this.src && other.alt === this.alt;
  }

  toDOM(): HTMLElement {
    const image = document.createElement('img');
    image.className = 'cm-image';
    image.src = attachmentUrl(this.src);
    image.alt = this.alt;
    image.loading = 'lazy';
    image.addEventListener('error', () => image.classList.add('cm-image-failed'));
    return image;
  }
}

/** Marca o desmarca la tarea de la linea que empieza en `lineFrom`. */
export function toggleTaskAt(view: EditorView, lineFrom: number): boolean {
  const line = view.state.doc.lineAt(lineFrom);
  const index = taskCheckIndex(line.text);
  if (index === null) {
    return false;
  }
  const next = line.text[index] === ' ' ? 'x' : ' ';
  view.dispatch({
    changes: { from: line.from + index, to: line.from + index + 1, insert: next },
    userEvent: 'input.toggle-task',
  });
  return true;
}

/** Lineas donde esta el cursor o la seleccion: ahi se enseña el markdown crudo. */
function activeLines(state: EditorState, focused: boolean): Set<number> {
  const lines = new Set<number>();
  if (!focused) {
    return lines;
  }
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let number = first; number <= last; number++) {
      lines.add(number);
    }
  }
  return lines;
}

/** Donde termina el frontmatter YAML (posicion final de su `---`), o -1. */
export function frontmatterEnd(state: EditorState): number {
  const doc = state.doc;
  if (doc.lines < 2 || doc.line(1).text.trim() !== '---') {
    return -1;
  }
  const limit = Math.min(doc.lines, 200);
  for (let number = 2; number <= limit; number++) {
    if (doc.line(number).text.trim() === '---') {
      return doc.line(number).to;
    }
  }
  return -1;
}

function buildDecorations(view: EditorView): DecorationSet {
  const { state } = view;
  const doc = state.doc;
  const active = activeLines(state, view.hasFocus);
  const isActive = (position: number) => active.has(doc.lineAt(position).number);
  const out: Range<Decoration>[] = [];
  const hide = (from: number, to: number) => {
    if (to > from) {
      out.push(hiddenMark.range(from, to));
    }
  };
  const mark = (className: string, from: number, to: number, attributes?: Record<string, string>) => {
    if (to > from) {
      out.push(Decoration.mark({ class: className, attributes }).range(from, to));
    }
  };
  const eachLine = (from: number, to: number, className: (number: number, first: number, last: number) => string) => {
    const first = doc.lineAt(from).number;
    const last = doc.lineAt(to).number;
    for (let number = first; number <= last; number++) {
      out.push(lineClass(className(number, first, last)).range(doc.line(number).from));
    }
  };

  const fmEnd = frontmatterEnd(state);
  if (fmEnd >= 0) {
    eachLine(0, fmEnd, () => 'cm-frontmatter-line');
  }

  const codeRanges: Array<[number, number]> = [];
  const hideMarkAndSpace = (node: { from: number; to: number }) => {
    const after = doc.sliceString(node.to, node.to + 1);
    hide(node.from, after === ' ' ? node.to + 1 : node.to);
  };

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (node) => {
        if (node.to <= fmEnd) {
          return false;
        }
        const name = node.name;
        const heading = /^(?:ATX|Setext)Heading([1-6])$/.exec(name);
        if (heading) {
          out.push(lineClass(`cm-h${heading[1]}`).range(doc.lineAt(node.from).from));
          return undefined;
        }
        const parent: SyntaxNode | null = node.node.parent;
        switch (name) {
          case 'HeaderMark':
            if (parent?.name.startsWith('ATXHeading') && !isActive(node.from)) {
              hideMarkAndSpace(node);
            }
            return undefined;
          case 'StrongEmphasis':
            mark('cm-strong', node.from, node.to);
            return undefined;
          case 'Emphasis':
            mark('cm-em', node.from, node.to);
            return undefined;
          case 'Strikethrough':
            mark('cm-strike', node.from, node.to);
            return undefined;
          case 'InlineCode':
            mark('cm-inline-code', node.from, node.to);
            codeRanges.push([node.from, node.to]);
            return undefined;
          case 'EmphasisMark':
          case 'StrikethroughMark':
            if (!isActive(node.from)) {
              hide(node.from, node.to);
            }
            return undefined;
          case 'CodeMark':
            if (parent?.name === 'InlineCode') {
              if (!isActive(node.from)) {
                hide(node.from, node.to);
              }
            } else if (parent?.name === 'FencedCode') {
              mark('cm-code-fence', node.from, node.to);
            }
            return undefined;
          case 'CodeInfo':
            mark('cm-code-info', node.from, node.to);
            return undefined;
          case 'FencedCode':
          case 'CodeBlock':
            codeRanges.push([node.from, node.to]);
            eachLine(node.from, node.to, (number, first, last) =>
              [
                'cm-codeblock-line',
                number === first ? 'cm-codeblock-first' : '',
                number === last ? 'cm-codeblock-last' : '',
              ]
                .filter(Boolean)
                .join(' '),
            );
            return undefined;
          case 'Blockquote':
            eachLine(node.from, node.to, () => 'cm-quote-line');
            return undefined;
          case 'QuoteMark':
            if (!isActive(node.from)) {
              hideMarkAndSpace(node);
            }
            return undefined;
          case 'HorizontalRule':
            if (!isActive(node.from)) {
              out.push(Decoration.replace({ widget: new RuleWidget() }).range(node.from, node.to));
            }
            return undefined;
          case 'Table':
            eachLine(node.from, node.to, (number, first, last) =>
              [
                'cm-table-line',
                number === first ? 'cm-table-first' : '',
                number === last ? 'cm-table-last' : '',
              ]
                .filter(Boolean)
                .join(' '),
            );
            return undefined;
          case 'TableCell':
            if (parent?.name === 'TableHeader') {
              mark('cm-table-header', node.from, node.to);
            }
            return undefined;
          case 'TableDelimiter': {
            // Dos clases de nodo comparten el nombre: el `|` dentro de una fila
            // (hijo de TableHeader/TableRow) y la fila de guiones entera (hija
            // de Table). El pipe se esconde; los guiones pasan a ser una linea.
            const isPipe = parent?.name === 'TableHeader' || parent?.name === 'TableRow';
            if (isPipe) {
              if (!isActive(node.from)) {
                hide(node.from, node.to);
              }
            } else if (!isActive(node.from)) {
              out.push(Decoration.replace({ widget: new TableDividerWidget() }).range(node.from, node.to));
            }
            return undefined;
          }
          case 'Link': {
            if (isActive(node.from)) {
              return false;
            }
            const marks = node.node.getChildren('LinkMark');
            const url = node.node.getChild('URL');
            if (marks.length >= 2 && url) {
              const href = doc.sliceString(url.from, url.to);
              mark('cm-link', marks[0].to, marks[1].from, { title: `Ctrl+clic para abrir ${href}` });
              hide(marks[0].from, marks[0].to);
              hide(marks[1].from, node.to);
            }
            return false;
          }
          case 'Image': {
            // `![alt](src)`: se pinta la imagen y se esconden las marcas. Al
            // editar la linea, vuelve el markdown crudo como en el resto.
            if (isActive(node.from)) {
              return false;
            }
            const marks = node.node.getChildren('LinkMark');
            const url = node.node.getChild('URL');
            if (marks.length >= 2 && url) {
              const src = doc.sliceString(url.from, url.to);
              const alt = doc.sliceString(marks[0].to, url.from);
              out.push(Decoration.replace({ widget: new ImageWidget(src, alt) }).range(node.from, node.to));
            }
            return false;
          }
          case 'ListMark':
            if (!parent?.getChild('Task')) {
              mark('cm-list-mark', node.from, node.to);
            }
            return undefined;
          case 'Task': {
            const marker = node.node.getChild('TaskMarker');
            if (!marker) {
              return undefined;
            }
            const line = doc.lineAt(node.from);
            const checked = /x/i.test(doc.sliceString(marker.from, marker.to));
            const listMark = parent?.getChild('ListMark');
            const textFrom = Math.min(marker.to + 1, line.to);
            if (!isActive(node.from)) {
              out.push(
                Decoration.replace({ widget: new CheckboxWidget(checked, line.from) }).range(
                  listMark ? listMark.from : marker.from,
                  textFrom,
                ),
              );
            }
            out.push(lineClass(checked ? 'cm-task-line cm-task-line-done' : 'cm-task-line').range(line.from));
            if (checked) {
              mark('cm-task-done', textFrom, node.to);
            }
            return undefined;
          }
          default:
            return undefined;
        }
      },
    });

    const text = doc.sliceString(from, to);
    for (const link of findWikiLinks(text, from)) {
      if (codeRanges.some(([start, end]) => link.from >= start && link.to <= end)) {
        continue;
      }
      if (isActive(link.from)) {
        mark('cm-wikilink-raw', link.from, link.to);
        continue;
      }
      hide(link.from, link.labelFrom);
      mark('cm-wikilink', link.labelFrom, link.labelTo, {
        title: `Ctrl+clic para abrir ${link.target}`,
        'data-target': link.target,
      });
      hide(link.labelTo, link.to);
    }
  }

  return Decoration.set(out, true);
}

export const livePreview = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }

    update(update: ViewUpdate): void {
      if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

export interface LinkOpeners {
  wiki(target: string): void;
  url(href: string): void;
}

/** Ctrl+clic abre un `[[enlace]]` en el editor o un enlace web en el navegador. */
export function linkClicks(open: LinkOpeners) {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      if (!(event.ctrlKey || event.metaKey) || event.button !== 0) {
        return false;
      }
      const position = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (position === null) {
        return false;
      }
      const line = view.state.doc.lineAt(position);
      const wiki = findWikiLinks(line.text, line.from).find(
        (link) => position >= link.from && position <= link.to,
      );
      if (wiki) {
        event.preventDefault();
        open.wiki(wiki.target);
        return true;
      }
      for (let node: SyntaxNode | null = syntaxTree(view.state).resolveInner(position, 1); node; node = node.parent) {
        if (node.name === 'Link' || node.name === 'Autolink' || node.name === 'URL') {
          const url = node.name === 'URL' ? node : node.getChild('URL');
          if (url) {
            event.preventDefault();
            open.url(view.state.sliceDoc(url.from, url.to));
            return true;
          }
        }
      }
      return false;
    },
  });
}
