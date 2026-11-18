// La paleta de comandos (Ctrl+P): un buscador para acciones y para saltar a
// otra nota sin soltar el teclado.

import { rankItems } from './markdownText';

export interface PaletteItem {
  label: string;
  hint?: string;
  keywords?: string;
  icon: SVGElement;
  run(): void;
}

export class Palette {
  private readonly backdrop: HTMLDivElement;
  private readonly input: HTMLInputElement;
  private readonly list: HTMLDivElement;
  private items: PaletteItem[] = [];
  private shown: PaletteItem[] = [];
  private selected = 0;
  private restoreFocus: (() => void) | null = null;

  constructor(
    host: HTMLElement,
    private readonly source: () => PaletteItem[],
  ) {
    this.backdrop = document.createElement('div');
    this.backdrop.className = 'palette-backdrop';
    this.backdrop.hidden = true;

    const panel = document.createElement('div');
    panel.className = 'palette';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Paleta de comandos');

    this.input = document.createElement('input');
    this.input.className = 'palette-input';
    this.input.placeholder = 'Busca un comando o una nota…';
    this.input.setAttribute('aria-label', 'Buscar');
    this.input.spellcheck = false;

    this.list = document.createElement('div');
    this.list.className = 'palette-list';
    this.list.setAttribute('role', 'listbox');

    panel.append(this.input, this.list);
    this.backdrop.append(panel);
    host.append(this.backdrop);

    this.backdrop.addEventListener('mousedown', (event) => {
      if (event.target === this.backdrop) {
        this.close();
      }
    });
    this.input.addEventListener('input', () => this.render());
    this.input.addEventListener('keydown', (event) => this.onKey(event));
  }

  get isOpen(): boolean {
    return !this.backdrop.hidden;
  }

  open(restoreFocus: () => void): void {
    this.restoreFocus = restoreFocus;
    this.items = this.source();
    this.input.value = '';
    this.backdrop.hidden = false;
    this.backdrop.classList.remove('closing');
    this.render();
    this.input.focus();
  }

  close(): void {
    if (!this.isOpen) {
      return;
    }
    this.backdrop.classList.add('closing');
    window.setTimeout(() => {
      this.backdrop.hidden = true;
      this.backdrop.classList.remove('closing');
    }, 140);
    this.restoreFocus?.();
  }

  private render(): void {
    this.shown = rankItems(this.input.value, this.items, 60);
    this.selected = 0;
    this.list.replaceChildren(
      ...this.shown.map((item, index) => {
        const row = document.createElement('div');
        row.className = 'palette-item';
        row.setAttribute('role', 'option');
        row.style.setProperty('--i', String(Math.min(index, 12)));
        const icon = item.icon.cloneNode(true) as SVGElement;
        const label = document.createElement('span');
        label.className = 'palette-label';
        label.textContent = item.label;
        row.append(icon, label);
        if (item.hint) {
          const hint = document.createElement('span');
          hint.className = 'palette-hint';
          hint.textContent = item.hint;
          row.append(hint);
        }
        row.addEventListener('mousemove', () => this.select(index));
        row.addEventListener('mousedown', (event) => {
          event.preventDefault();
          this.run(index);
        });
        return row;
      }),
    );
    if (this.shown.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'palette-empty';
      empty.textContent = 'Nada coincide';
      this.list.append(empty);
    }
    this.select(0);
  }

  private select(index: number): void {
    const rows = this.list.querySelectorAll<HTMLElement>('.palette-item');
    if (rows.length === 0) {
      return;
    }
    this.selected = (index + rows.length) % rows.length;
    rows.forEach((row, i) => row.setAttribute('aria-selected', String(i === this.selected)));
    rows[this.selected].scrollIntoView({ block: 'nearest' });
  }

  private run(index: number): void {
    const item = this.shown[index];
    if (!item) {
      return;
    }
    this.close();
    item.run();
  }

  private onKey(event: KeyboardEvent): void {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.select(this.selected + 1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.select(this.selected - 1);
        break;
      case 'Enter':
        event.preventDefault();
        this.run(this.selected);
        break;
      case 'Escape':
        event.preventDefault();
        this.close();
        break;
    }
  }
}
