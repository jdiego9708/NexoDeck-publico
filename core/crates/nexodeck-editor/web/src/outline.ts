// El esquema de la nota: sus encabezados, para saltar y para saber donde se esta.

import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import type { EditorState } from '@codemirror/state';

import { frontmatterEnd } from './livePreview';

export interface HeadingItem {
  level: number;
  text: string;
  from: number;
}

export function extractHeadings(state: EditorState): HeadingItem[] {
  const tree = ensureSyntaxTree(state, state.doc.length, 200) ?? syntaxTree(state);
  const items: HeadingItem[] = [];
  // Lezer no sabe de frontmatter: `date: 2026-09-15` seguido del `---` de cierre
  // es para el un encabezado Setext, y salia en el esquema.
  const fmEnd = frontmatterEnd(state);
  tree.iterate({
    enter: (node) => {
      const match = /^(?:ATX|Setext)Heading([1-6])$/.exec(node.name);
      if (!match) {
        return undefined;
      }
      if (node.from <= fmEnd) {
        return false;
      }
      const line = state.doc.lineAt(node.from);
      const text = line.text.replace(/^#{1,6}\s+/, '').replace(/\s+#+\s*$/, '').trim();
      if (text !== '') {
        items.push({ level: Number(match[1]), text, from: line.from });
      }
      return false;
    },
  });
  return items;
}

/** El encabezado bajo el que esta `position`, o null. */
export function currentHeading(items: readonly HeadingItem[], position: number): HeadingItem | null {
  let current: HeadingItem | null = null;
  for (const item of items) {
    if (item.from > position) {
      break;
    }
    current = item;
  }
  return current;
}

export class OutlineView {
  private rendered = '';
  private buttons: HTMLButtonElement[] = [];
  private items: HeadingItem[] = [];

  constructor(
    private readonly list: HTMLElement,
    private readonly empty: HTMLElement,
    private readonly onJump: (from: number) => void,
  ) {}

  update(items: HeadingItem[], position: number): void {
    const signature = JSON.stringify(items.map((item) => [item.level, item.text]));
    if (signature !== this.rendered) {
      this.rendered = signature;
      this.items = items;
      this.list.replaceChildren();
      this.buttons = items.map((item) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'outline-item';
        button.dataset.level = String(Math.min(item.level, 4));
        button.textContent = item.text;
        button.title = item.text;
        button.addEventListener('click', () => this.onJump(this.items[this.buttons.indexOf(button)].from));
        this.list.append(button);
        return button;
      });
      this.empty.hidden = items.length > 0;
    } else {
      this.items = items;
    }
    const current = currentHeading(this.items, position);
    this.buttons.forEach((button, index) => {
      button.classList.toggle('active', current !== null && this.items[index] === current);
    });
  }
}
