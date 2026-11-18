// Lo que hizo el asistente con una nota, con su traza: en que quedo, con que
// modelo, que busco Rust y que hizo cada agente.
//
// Existe para poder creer la propuesta: "esto ya se hablo el 3-sep" solo vale si
// se ve de donde sale.

import {
  CircleAlert,
  CircleCheck,
  CircleSlash,
  Clock,
  FilePenLine,
  Hourglass,
  type IconNode,
  Inbox,
  LoaderCircle,
} from 'lucide';

import { button, el, icon } from './dom';
import { agentLabel, digestStateLabel, shortDateTime, triggerLabel } from './labels';
import type { DigestDto } from './protocol';

const STATE_ICONS: Record<string, IconNode> = {
  queued: Clock,
  running: LoaderCircle,
  proposed: FilePenLine,
  skipped: CircleSlash,
  failed: CircleAlert,
  waiting_model: Hourglass,
};

export interface DigestActions {
  /** Titulo de la nota, en la lista general; sin el, la tarjeta no la nombra. */
  noteTitle?: string;
  onOpenNote?: () => void;
  onShowInbox: () => void;
}

export function renderDigest(digest: DigestDto, actions: DigestActions): HTMLElement {
  const card = el('article', 'digest');
  card.dataset.state = digest.state;

  card.append(
    el(
      'div',
      'digest-head',
      icon(STATE_ICONS[digest.state] ?? CircleAlert, 'digest-icon'),
      el('span', 'digest-state', `${digestStateLabel(digest.state)} · ${triggerLabel(digest.trigger)}`),
      el('span', 'digest-date', shortDateTime(digest.createdAt)),
    ),
  );

  if (actions.noteTitle) {
    const link = button('link digest-note', actions.noteTitle);
    link.addEventListener('click', () => actions.onOpenNote?.());
    card.append(link);
  }
  if (digest.stateDetail) {
    card.append(el('p', 'digest-detail', digest.stateDetail));
  }

  const meta = [
    `Modelo: ${digest.modelLabel || '—'}`,
    digest.hub ? `nota de proyecto: ${digest.hub}` : '',
    digest.requeried ? 'el crítico pidió buscar otra vez' : '',
  ].filter(Boolean);
  card.append(el('p', 'digest-meta', meta.join(' · ')));
  if (digest.redactions > 0) {
    card.append(el('p', 'digest-meta', `Se quitaron ${digest.redactions} secretos antes de mandar nada al modelo.`));
  }
  if (digest.discardedIds.length > 0) {
    card.append(el('p', 'digest-meta warn', `Citas descartadas por no existir: ${digest.discardedIds.join(', ')}`));
  }

  if (digest.steps.length > 0) {
    const section = el('details', 'digest-section', el('summary', undefined, `Qué hizo cada agente (${digest.steps.length})`));
    for (const step of digest.steps) {
      section.append(
        el(
          'div',
          step.ok ? 'step ok' : 'step failed',
          icon(step.ok ? CircleCheck : CircleAlert),
          el('span', 'step-name', agentLabel(step.agent)),
          el('span', 'step-time', `${step.millis} ms`),
        ),
      );
      if (step.detail) {
        section.append(el('p', 'step-detail', step.detail));
      }
      if (step.output) {
        section.append(el('pre', 'step-output', step.output));
      }
    }
    card.append(section);
  }

  if (digest.candidates.length > 0) {
    const section = el(
      'details',
      'digest-section',
      el('summary', undefined, `Lo que encontró Rust (${digest.candidates.length} candidatos)`),
    );
    for (const candidate of digest.candidates) {
      section.append(
        el(
          'div',
          'candidate',
          el('strong', undefined, candidate.date ? `${candidate.title} · ${candidate.date}` : candidate.title),
          el('p', undefined, candidate.snippet),
          el('code', undefined, candidate.id),
        ),
      );
    }
    card.append(section);
  }

  if (digest.proposalId) {
    const inbox = button('chip primary', icon(Inbox), 'Ver la propuesta en el buzón');
    inbox.addEventListener('click', actions.onShowInbox);
    card.append(el('div', 'digest-actions', inbox));
  }
  return card;
}
