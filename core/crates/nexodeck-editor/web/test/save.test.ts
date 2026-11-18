import { describe, expect, it } from 'vitest';

import type { SaveReason } from '../src/protocol';
import { AutoSaver, type SaveStatus, type Timers } from '../src/save';

class FakeTimers implements Timers {
  private next = 1;
  private readonly pending = new Map<number, () => void>();

  set(callback: () => void): unknown {
    const id = this.next++;
    this.pending.set(id, callback);
    return id;
  }

  clear(handle: unknown): void {
    this.pending.delete(handle as number);
  }

  get armed(): number {
    return this.pending.size;
  }

  fire(): void {
    const callbacks = [...this.pending.values()];
    this.pending.clear();
    callbacks.forEach((callback) => callback());
  }
}

function setup() {
  const timers = new FakeTimers();
  const sent: Array<{ text: string; baseHash: string | null; reason: SaveReason }> = [];
  const statuses: SaveStatus[] = [];
  let text = 'hola';
  const saver = new AutoSaver({
    delayMs: 1000,
    getText: () => text,
    send: (value, baseHash, reason) => sent.push({ text: value, baseHash, reason }),
    onStatus: (status) => statuses.push(status),
    timers,
  });
  return {
    saver,
    timers,
    sent,
    statuses,
    type(value: string) {
      text = value;
      saver.edited();
    },
  };
}

describe('AutoSaver', () => {
  it('waits for a pause in typing and sends one save with the base hash', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('hola m');
    s.type('hola mundo');
    expect(s.sent).toHaveLength(0);
    expect(s.timers.armed).toBe(1);

    s.timers.fire();
    expect(s.sent).toEqual([{ text: 'hola mundo', baseHash: 'h1', reason: 'auto' }]);
    expect(s.saver.current).toBe('saving');

    s.saver.saved('h2');
    expect(s.saver.current).toBe('clean');
    expect(s.saver.hash).toBe('h2');
    expect(s.statuses).toEqual(['clean', 'dirty', 'saving', 'clean']);
  });

  it('never sends two saves at once and saves again what was typed meanwhile', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('uno');
    s.saver.flush('manual');
    s.type('uno dos');
    expect(s.saver.flush('manual')).toBe(false);
    expect(s.sent).toHaveLength(1);

    s.saver.saved('h2');
    expect(s.saver.current).toBe('dirty');
    s.timers.fire();
    expect(s.sent[1]).toEqual({ text: 'uno dos', baseHash: 'h2', reason: 'auto' });
  });

  it('stops saving on a conflict until the user chooses', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('mio');
    s.timers.fire();
    s.saver.conflicted({ diskText: 'de obsidian', diskHash: 'h9' });

    s.type('mio y mas');
    expect(s.timers.armed).toBe(0);
    expect(s.saver.flush('manual')).toBe(false);
    expect(s.sent).toHaveLength(1);

    s.saver.keepMine();
    expect(s.sent[1]).toEqual({ text: 'mio y mas', baseHash: 'h9', reason: 'overwrite' });
  });

  it('reloading from disk resets to the disk version', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('mio');
    s.timers.fire();
    s.saver.conflicted({ diskText: 'de obsidian', diskHash: 'h9' });

    expect(s.saver.takeDisk()).toBe('de obsidian');
    expect(s.saver.current).toBe('clean');
    expect(s.saver.hash).toBe('h9');
    expect(s.saver.conflict).toBeNull();
  });

  it('a note deleted outside is recreated when keeping mine', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('mio');
    s.timers.fire();
    s.saver.conflicted({ diskText: '', diskHash: '' });
    s.saver.keepMine();
    expect(s.sent[1].baseHash).toBeNull();
  });

  it('an error keeps the changes pending so a manual save retries', () => {
    const s = setup();
    s.saver.load('h1');
    s.type('mio');
    s.timers.fire();
    s.saver.failed('disco lleno');
    expect(s.saver.current).toBe('error');
    expect(s.saver.flush('manual')).toBe(true);
    expect(s.sent).toHaveLength(2);
  });
});
