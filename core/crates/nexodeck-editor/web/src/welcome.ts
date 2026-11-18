// Lo que se ve con la ventana abierta y ninguna nota: por donde empezar.

import { CalendarPlus, Command, FilePlus, NotebookPen } from 'lucide';

import { button, el, icon } from './dom';
import type { OverviewDto } from './protocol';
import { groupFor, noteRow } from './sidebar';

/** Cuantas notas recientes se enseñan. */
const RECENT = 6;

export interface WelcomeActions {
  openDaily(): void;
  newNote(): void;
  palette(): void;
  openNote(path: string): void;
}

export class WelcomeView {
  readonly element: HTMLElement;
  private readonly root: HTMLElement;
  private readonly heading: HTMLElement;
  private readonly recent: HTMLElement;

  constructor(private readonly actions: WelcomeActions) {
    this.root = el('p', 'welcome-root', 'Leyendo la bóveda…');
    const daily = button('chip primary', icon(CalendarPlus), 'Nota de hoy');
    daily.addEventListener('click', () => actions.openDaily());
    const create = button('chip', icon(FilePlus), 'Nota nueva');
    create.addEventListener('click', () => actions.newNote());
    const palette = button('chip', icon(Command), 'Comandos', el('kbd', undefined, 'Ctrl P'));
    palette.addEventListener('click', () => actions.palette());

    this.heading = el('p', 'side-heading', 'Recientes');
    this.heading.hidden = true;
    this.recent = el('div', 'welcome-recent');
    this.element = el(
      'section',
      'welcome',
      el(
        'div',
        'welcome-card',
        el('div', 'welcome-badge', icon(NotebookPen)),
        el('h1', undefined, 'Tus notas de trabajo'),
        this.root,
        el('div', 'welcome-actions', daily, create, palette),
        this.heading,
        this.recent,
      ),
    );
  }

  setOverview(overview: OverviewDto): void {
    if (!overview.configured) {
      // El camino es el menú de esta misma ventana. Antes mandaba a un botón
      // del diálogo de la app que, con esta ventana disponible, no se ve nunca.
      this.root.textContent =
        'No hay ninguna carpeta de notas. Pulsa ⋮ junto al buscador y elige «Importar espacio de NexoDeck…».';
      this.heading.hidden = true;
      this.recent.replaceChildren();
      return;
    }
    this.root.textContent = overview.root ?? '';
    const notes = overview.notes.slice(0, RECENT);
    this.heading.hidden = notes.length === 0;
    this.recent.replaceChildren(
      ...notes.map((note, index) =>
        noteRow(note, index, (path) => this.actions.openNote(path), groupFor(overview, note)),
      ),
    );
  }
}
