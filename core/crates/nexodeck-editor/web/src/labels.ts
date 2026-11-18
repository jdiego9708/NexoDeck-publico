// Textos para el usuario a partir de lo que manda Rust, que llega en ingles y
// sin formato. Funciones puras: se prueban sin DOM.

export function roleLabel(role: string): string {
  switch (role) {
    case 'daily':
      return 'Diario';
    case 'hub':
      return 'Proyecto';
    default:
      return 'Nota';
  }
}

export function digestStateLabel(state: string): string {
  switch (state) {
    case 'queued':
      return 'En cola';
    case 'running':
      return 'Procesándose';
    case 'proposed':
      return 'Con propuesta';
    case 'skipped':
      return 'Sin nada que hacer';
    case 'failed':
      return 'Falló';
    case 'waiting_model':
      return 'Esperando un modelo';
    default:
      return 'Desconocido';
  }
}

/** Todavia puede acabar en una propuesta: pedir otro no tiene sentido. */
export function isDigestActive(state: string): boolean {
  return state === 'queued' || state === 'running' || state === 'waiting_model';
}

export function agentLabel(agent: string): string {
  const [name, round] = agent.split('#');
  const label =
    { reader: 'Lector', memory: 'Memoria', code: 'Código', critic: 'Crítico', synthesizer: 'Redactor' }[name] ?? name;
  return round ? `${label} (segunda vuelta)` : label;
}

export function triggerLabel(trigger: string): string {
  return { manual: 'pedido a mano', idle: 'automático', mcp: 'desde Claude Code' }[trigger] ?? trigger;
}

export function hitKindLabel(kind: string): string {
  return { note: 'Nota', finding: 'Hallazgo', commit: 'Commit' }[kind] ?? kind;
}

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function parseDay(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null;
}

/** Vencida: con fecha anterior a hoy. Se compara por dia: la de hoy no lo esta. */
export function isOverdue(due: string | null | undefined, today: Date): boolean {
  const date = due ? parseDay(due) : null;
  return date !== null && date.getTime() < startOfDay(today);
}

/** Primero las vencidas, despues por fecha, y las que no tienen fecha al final. */
export function sortTasks<T extends { due: string | null }>(tasks: readonly T[], today: Date): T[] {
  const rank = (task: T) => (isOverdue(task.due, today) ? 0 : task.due ? 1 : 2);
  return [...tasks].sort((a, b) => rank(a) - rank(b) || (a.due ?? '').localeCompare(b.due ?? ''));
}

function two(value: number): string {
  return String(value).padStart(2, '0');
}

/** `15/9 14:05`. Corto a proposito: va al lado de un titulo. */
export function shortDateTime(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return `${date.getDate()}/${date.getMonth() + 1} ${two(date.getHours())}:${two(date.getMinutes())}`;
}

/** `07:05 pm`, la hora como la lee el usuario. */
export function clockTime(date: Date): string {
  const hours = date.getHours();
  const hour = hours % 12 === 0 ? 12 : hours % 12;
  return `${two(hour)}:${two(date.getMinutes())} ${hours < 12 ? 'am' : 'pm'}`;
}

/** "hoy - 07:05 pm", "ayer - 06:16 pm", "hace 3 días" o `15/9`. Acepta
 * RFC 3339 o `AAAA-MM-DD`.
 *
 * Hoy y ayer llevan la hora porque son los dias en los que el usuario toca
 * varias notas: "hoy" a secas no dice cual acaba de dejar, que es justo lo que
 * se busca al ordenar por recientes. Mas atras la hora ya no distingue nada y
 * solo alarga la fila. Una fecha suelta (`AAAA-MM-DD`, la del diario) no trae
 * hora, y no se inventa la medianoche. */
export function relativeDay(value: string | null | undefined, now: Date): string {
  if (!value) {
    return '';
  }
  const day = parseDay(value);
  const date = day ?? new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const days = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);
  const at = day === null ? ` - ${clockTime(date)}` : '';
  if (days <= 0) {
    return `hoy${at}`;
  }
  if (days === 1) {
    return `ayer${at}`;
  }
  if (days < 7) {
    return `hace ${days} días`;
  }
  return `${date.getDate()}/${date.getMonth() + 1}`;
}
