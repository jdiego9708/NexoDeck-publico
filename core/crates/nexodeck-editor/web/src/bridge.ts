// El canal con quien aloja la pagina.
//
// - En la PC, Rust: `window.ipc.postMessage` hacia alla (lo inyecta wry) y
//   `window.nexodeck.receive` hacia aca (Rust lo llama con `evaluate_script`).
// - En el movil, Dart: `window.nexodeckIpc.postMessage` (un `JavaScriptChannel`
//   de webview_flutter, que Android pone en la pagina antes de sus scripts) y el
//   mismo `window.nexodeck.receive` hacia aca. Alli contesta la copia local del
//   telefono, no la PC.

import type { HostMessage, PageMessage } from './protocol';

declare global {
  interface Window {
    ipc?: { postMessage(message: string): void };
    nexodeckIpc?: { postMessage(message: string): void };
    nexodeck: {
      receive(message: HostMessage | string): void;
      /** Solo en el movil: el boton atras de Android. `true` si lo uso la pagina. */
      back?: () => boolean;
    };
  }
}

type Listener = (message: HostMessage) => void;
const listeners: Listener[] = [];

function channel(): { postMessage(message: string): void } | undefined {
  return window.ipc ?? window.nexodeckIpc;
}

export function send(message: PageMessage): void {
  const payload = JSON.stringify(message);
  const target = channel();
  if (target) {
    target.postMessage(payload);
  } else {
    // Abierta en un navegador normal, para diseñar la pagina sin NexoDeck.
    console.debug('[nexodeck <-]', payload);
  }
}

export function onHostMessage(listener: Listener): void {
  listeners.push(listener);
}

window.nexodeck = {
  receive(message) {
    const parsed: HostMessage = typeof message === 'string' ? JSON.parse(message) : message;
    for (const listener of listeners) {
      listener(parsed);
    }
  },
};

export const hostAvailable = (): boolean => Boolean(channel());

/** La pagina vive en la app del movil: lista y editor a pantalla completa, y sin
 * lo que solo existe en la PC (asistente, carpetas, exportar). `?mobile` en la
 * URL lo fuerza en un navegador, para trabajar el diseño. */
export const isMobileHost = (): boolean =>
  (!window.ipc && Boolean(window.nexodeckIpc)) || new URLSearchParams(location.search).has('mobile');
