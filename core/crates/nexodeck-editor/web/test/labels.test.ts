import { describe, expect, it } from 'vitest';

import {
  agentLabel,
  digestStateLabel,
  isDigestActive,
  isOverdue,
  relativeDay,
  roleLabel,
  shortDateTime,
  sortTasks,
  triggerLabel,
} from '../src/labels';

describe('labels', () => {
  it('names roles, states, agents and triggers in Spanish', () => {
    expect(roleLabel('daily')).toBe('Diario');
    expect(roleLabel('algo_nuevo')).toBe('Nota');
    expect(digestStateLabel('waiting_model')).toBe('Esperando un modelo');
    expect(isDigestActive('waiting_model')).toBe(true);
    expect(isDigestActive('proposed')).toBe(false);
    expect(agentLabel('memory#2')).toBe('Memoria (segunda vuelta)');
    expect(agentLabel('otro')).toBe('otro');
    expect(triggerLabel('mcp')).toBe('desde Claude Code');
  });
});

describe('dates', () => {
  const today = new Date(2026, 8, 15, 12, 0);

  it('a task is overdue only from the day after its date', () => {
    expect(isOverdue('2026-09-10', today)).toBe(true);
    expect(isOverdue('2026-09-15', today)).toBe(false);
    expect(isOverdue(null, today)).toBe(false);
    expect(isOverdue('mañana', today)).toBe(false);
  });

  it('sorts overdue tasks first and undated ones last', () => {
    const tasks = [
      { text: 'sin fecha', due: null },
      { text: 'luego', due: '2026-09-20' },
      { text: 'vencida', due: '2026-09-01' },
      { text: 'pronto', due: '2026-09-16' },
    ];
    expect(sortTasks(tasks, today).map((t) => t.text)).toEqual(['vencida', 'pronto', 'luego', 'sin fecha']);
  });

  it('speaks of recent days and falls back to the date', () => {
    expect(relativeDay(new Date(2026, 8, 15, 8).toISOString(), today)).toBe('hoy - 08:00 am');
    expect(relativeDay('2026-09-14', today)).toBe('ayer');
    expect(relativeDay('2026-09-12', today)).toBe('hace 3 días');
    expect(relativeDay('2026-09-05', today)).toBe('5/9');
    expect(relativeDay(null, today)).toBe('');
    expect(relativeDay('no es fecha', today)).toBe('');
  });

  it('writes a short date and time', () => {
    expect(shortDateTime(new Date(2026, 8, 15, 14, 5).toISOString())).toBe('15/9 14:05');
    expect(shortDateTime('roto')).toBe('');
  });

  it('gives today and yesterday the hour, and leaves a bare date alone', () => {
    expect(relativeDay(new Date(2026, 8, 15, 19, 5).toISOString(), today)).toBe('hoy - 07:05 pm');
    expect(relativeDay(new Date(2026, 8, 14, 18, 16).toISOString(), today)).toBe('ayer - 06:16 pm');
    // Medianoche y mediodia son las dos horas que un reloj de 12 se come.
    expect(relativeDay(new Date(2026, 8, 15, 0, 30).toISOString(), today)).toBe('hoy - 12:30 am');
    expect(relativeDay(new Date(2026, 8, 15, 12, 0).toISOString(), today)).toBe('hoy - 12:00 pm');
    // La del diario no trae hora: no se inventa la medianoche.
    expect(relativeDay('2026-09-15', today)).toBe('hoy');
  });
});
