// El guardado automatico, sin DOM ni CodeMirror: se prueba con relojes falsos.
//
// Reglas:
// - Se guarda 1 s despues de la ultima tecla, al perder el foco y con Ctrl+S.
// - Nunca hay dos guardados en vuelo: lo que se escribe mientras uno viaja se
//   guarda cuando vuelve la respuesta.
// - Con un conflicto (la nota cambio en disco) no se guarda NADA hasta que el
//   usuario elija: recargar lo de disco o quedarse con lo suyo.

import type { SaveReason } from './protocol';

export type SaveStatus = 'idle' | 'clean' | 'dirty' | 'saving' | 'conflict' | 'error';

export interface Conflict {
  diskText: string;
  /** Vacio si la nota ya no existe en disco. */
  diskHash: string;
}

export interface Timers {
  set(callback: () => void, ms: number): unknown;
  clear(handle: unknown): void;
}

export interface AutoSaverOptions {
  delayMs: number;
  getText(): string;
  send(text: string, baseHash: string | null, reason: SaveReason): void;
  onStatus(status: SaveStatus): void;
  timers?: Timers;
}

const realTimers: Timers = {
  set: (callback, ms) => setTimeout(callback, ms),
  clear: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

export class AutoSaver {
  private status: SaveStatus = 'idle';
  private baseHash: string | null = null;
  private inFlight = false;
  private editedWhileSaving = false;
  private timer: unknown = null;
  private conflictState: Conflict | null = null;
  private lastError: string | null = null;
  private readonly timers: Timers;

  constructor(private readonly options: AutoSaverOptions) {
    this.timers = options.timers ?? realTimers;
  }

  get current(): SaveStatus {
    return this.status;
  }

  get hash(): string | null {
    return this.baseHash;
  }

  get conflict(): Conflict | null {
    return this.conflictState;
  }

  get error(): string | null {
    return this.lastError;
  }

  /** Nota recien abierta o recargada. `hash` null: todavia no existe en disco. */
  load(hash: string | null): void {
    this.cancelTimer();
    this.baseHash = hash;
    this.inFlight = false;
    this.editedWhileSaving = false;
    this.conflictState = null;
    this.lastError = null;
    this.setStatus('clean');
  }

  edited(): void {
    if (this.status === 'conflict' || this.status === 'idle') {
      return;
    }
    if (this.inFlight) {
      this.editedWhileSaving = true;
      return;
    }
    this.setStatus('dirty');
    this.arm();
  }

  /** Guarda ya si hay algo pendiente. `false` si no se puede (conflicto, en vuelo). */
  flush(reason: SaveReason = 'manual'): boolean {
    this.cancelTimer();
    if (this.status === 'conflict' || this.inFlight) {
      return false;
    }
    if (this.status !== 'dirty' && this.status !== 'error') {
      return true;
    }
    this.inFlight = true;
    this.editedWhileSaving = false;
    this.setStatus('saving');
    this.options.send(this.options.getText(), this.baseHash, reason);
    return true;
  }

  saved(hash: string): void {
    this.baseHash = hash;
    this.inFlight = false;
    this.lastError = null;
    if (this.editedWhileSaving) {
      this.editedWhileSaving = false;
      this.setStatus('dirty');
      this.arm();
    } else {
      this.setStatus('clean');
    }
  }

  conflicted(conflict: Conflict): void {
    this.cancelTimer();
    this.inFlight = false;
    this.editedWhileSaving = false;
    this.conflictState = conflict;
    this.setStatus('conflict');
  }

  failed(message: string): void {
    this.inFlight = false;
    this.lastError = message;
    this.setStatus('error');
  }

  /** Resolver el conflicto quedandose con lo del editor: sobrescribe lo de disco. */
  keepMine(): void {
    const conflict = this.conflictState;
    if (!conflict) {
      return;
    }
    this.conflictState = null;
    this.baseHash = conflict.diskHash === '' ? null : conflict.diskHash;
    this.setStatus('dirty');
    this.flush('overwrite');
  }

  /** Resolver el conflicto recargando lo de disco. Devuelve el texto a poner. */
  takeDisk(): string | null {
    const conflict = this.conflictState;
    if (!conflict) {
      return null;
    }
    this.load(conflict.diskHash === '' ? null : conflict.diskHash);
    return conflict.diskText;
  }

  private arm(): void {
    this.cancelTimer();
    this.timer = this.timers.set(() => {
      this.timer = null;
      this.flush('auto');
    }, this.options.delayMs);
  }

  private cancelTimer(): void {
    if (this.timer !== null) {
      this.timers.clear(this.timer);
      this.timer = null;
    }
  }

  private setStatus(status: SaveStatus): void {
    if (status !== this.status) {
      this.status = status;
      this.options.onStatus(status);
    }
  }
}
