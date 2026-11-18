// El panel de la derecha: lo que rodea a la nota abierta. Su esquema, quien la
// enlaza, que se le parece y lo que hizo el asistente con ella.

import { ArrowUpRight, type IconNode, Link2, List, LoaderCircle, Sparkles } from 'lucide';

import { renderDigest } from './digestView';
import { button, el, icon } from './dom';
import { isDigestActive } from './labels';
import type { DetailsDto, HitDto, NoteDto, NoteSummaryDto, OverviewDto } from './protocol';

export interface ContextActions {
  openNote(path: string): void;
  digest(path: string): void;
  showInbox(): void;
}

function section(iconNode: IconNode, title: string, ...body: Node[]): HTMLElement {
  return el('section', 'panel-section', el('h3', 'panel-title', icon(iconNode), title), ...body);
}

export class ContextPanel {
  readonly element: HTMLElement;
  readonly outlineList: HTMLElement;
  readonly outlineEmpty: HTMLElement;
  private readonly links: HTMLElement;
  private readonly assistant: HTMLElement;
  private note: NoteDto | null = null;
  private details: DetailsDto | null = null;
  private titles = new Map<string, string>();
  private summaries = new Map<string, NoteSummaryDto>();
  private busyNotes = new Set<string>();
  /** Se pidio procesar y todavia no llego la respuesta. */
  private requested = false;

  constructor(private readonly actions: ContextActions) {
    this.outlineList = el('nav', 'outline-list');
    this.outlineEmpty = el('p', 'panel-empty', 'Sin títulos todavía');
    this.links = el('div');
    this.assistant = el('div');
    this.element = el(
      'aside',
      'context',
      section(List, 'Esquema', this.outlineEmpty, this.outlineList),
      section(Link2, 'Enlaces', this.links),
      section(Sparkles, 'Asistente', this.assistant),
    );
  }

  setNote(note: NoteDto): void {
    this.note = note;
    this.details = null;
    this.requested = false;
    this.renderLinks();
    this.renderAssistant();
  }

  setOverview(overview: OverviewDto): void {
    this.titles = new Map(overview.notes.map((note) => [note.path, note.title]));
    this.summaries = new Map(overview.notes.map((note) => [note.path, note]));
    this.busyNotes = new Set(overview.digests.filter((d) => isDigestActive(d.state)).map((d) => d.note));
    if (this.note && this.busyNotes.has(this.note.path)) {
      this.requested = false;
    }
    this.renderLinks();
    this.renderAssistant();
  }

  setDetails(details: DetailsDto): void {
    if (!this.note || details.path !== this.note.path) {
      return;
    }
    this.details = details;
    this.requested = false;
    this.renderLinks();
    this.renderAssistant();
  }

  private renderLinks(): void {
    if (!this.note) {
      this.links.replaceChildren();
      return;
    }
    if (!this.details) {
      this.links.replaceChildren(el('div', 'skeleton small'), el('div', 'skeleton small'));
      return;
    }
    const { backlinks, related } = this.details;
    const nodes: Node[] = [el('p', 'panel-sub', `Enlazan aquí (${backlinks.length})`)];
    if (backlinks.length === 0) {
      nodes.push(el('p', 'panel-empty', this.note.private ? 'Las notas privadas no entran en el índice.' : 'Ninguna nota enlaza a esta todavía.'));
    }
    for (const path of backlinks) {
      const link = button('link-row', icon(ArrowUpRight), el('span', undefined, this.titles.get(path) ?? path));
      link.title = path;
      link.addEventListener('click', () => this.actions.openNote(path));
      nodes.push(link);
    }
    if (related.length > 0) {
      nodes.push(el('p', 'panel-sub', 'Se le parecen'));
      nodes.push(...related.map((hit) => this.hitRow(hit)));
    }
    this.links.replaceChildren(...nodes);
  }

  private hitRow(hit: HitDto): HTMLElement {
    const node = button('link-row stacked', el('strong', undefined, hit.title), el('span', undefined, hit.snippet));
    const path = hit.path;
    if (path) {
      node.addEventListener('click', () => this.actions.openNote(path));
    } else {
      node.disabled = true;
    }
    return node;
  }

  private renderAssistant(): void {
    const note = this.note;
    if (!note) {
      this.assistant.replaceChildren();
      return;
    }
    const digests = this.details?.digests ?? [];
    const busy = this.requested || this.busyNotes.has(note.path) || digests.some((d) => isDigestActive(d.state));
    const blocked = note.private
      ? 'Es privada: ningún agente la lee.'
      : this.summaries.get(note.path)?.aiExcluded
        ? 'Tiene "ai: false": ningún agente la lee.'
        : null;
    const label = busy ? 'El asistente está con ella' : digests.length > 0 ? 'Procesar otra vez' : 'Procesar nota';
    const trigger = button(
      'chip primary digest-trigger',
      icon(busy ? LoaderCircle : Sparkles, busy ? 'spinner' : undefined),
      label,
    );
    trigger.disabled = busy || blocked !== null;
    trigger.addEventListener('click', () => {
      this.requested = true;
      this.actions.digest(note.path);
      this.renderAssistant();
    });

    const nodes: Node[] = [trigger];
    if (blocked) {
      nodes.push(el('p', 'panel-note', blocked));
    } else if (digests.length === 0 && !busy) {
      nodes.push(
        el(
          'p',
          'panel-note',
          'Cinco agentes cruzan la nota con tus otras notas, los hallazgos y los commits, y dejan una propuesta en el buzón.',
        ),
      );
    }
    for (const digest of digests) {
      nodes.push(renderDigest(digest, { onShowInbox: () => this.actions.showInbox() }));
    }
    this.assistant.replaceChildren(...nodes);
  }
}
