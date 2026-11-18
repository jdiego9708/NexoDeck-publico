// Un menu emergente pequeño: el de tres puntos junto al buscador y el del clic
// derecho sobre una carpeta. Uno solo abierto a la vez.
//
// Se cierra con Escape, con un clic fuera o al elegir, y el foco vuelve a quien
// lo abrio. Las flechas mueven entre opciones: un menu que solo funciona con el
// raton no se puede usar con el teclado, y la ventana de notas se usa sobre todo
// con el teclado.

import type { IconNode } from 'lucide';

import { button, el, icon } from './dom';
import { normalizeForSearch } from './markdownText';

export interface MenuItem {
  label: string;
  detail?: string;
  icon: IconNode;
  run: () => void;
}

let close: (() => void) | null = null;

/** Abre el menu debajo de [anchor] (un elemento) o en un punto (clic derecho). */
export function openMenu(anchor: HTMLElement | { x: number; y: number }, items: MenuItem[]): void {
  close?.();
  const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;

  const menu = el('div', 'menu');
  menu.setAttribute('role', 'menu');
  const buttons = items.map((item) => {
    const node = button(
      'menu-item',
      icon(item.icon),
      el('span', 'menu-text', el('span', 'menu-label', item.label), ...(item.detail ? [el('span', 'menu-detail', item.detail)] : [])),
    );
    node.setAttribute('role', 'menuitem');
    node.addEventListener('click', () => {
      finish();
      item.run();
    });
    return node;
  });
  menu.append(...buttons);
  document.body.append(menu);

  // Posicion: debajo del ancla, o en el punto, sin salirse de la ventana.
  const rect = anchor instanceof HTMLElement ? anchor.getBoundingClientRect() : null;
  const width = menu.offsetWidth;
  const height = menu.offsetHeight;
  let x = rect ? rect.right - width : (anchor as { x: number }).x;
  let y = rect ? rect.bottom + 6 : (anchor as { y: number }).y;
  x = Math.max(8, Math.min(x, window.innerWidth - width - 8));
  y = Math.max(8, Math.min(y, window.innerHeight - height - 8));
  menu.style.left = `${x}px`;
  menu.style.top = `${y}px`;

  const onKey = (event: KeyboardEvent) => {
    const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      finish();
      previous?.focus();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const step = event.key === 'ArrowDown' ? 1 : -1;
      buttons[(index + step + buttons.length) % buttons.length]?.focus();
    } else if (event.key === 'Tab') {
      finish();
    }
  };
  const onPointer = (event: MouseEvent) => {
    if (!menu.contains(event.target as Node)) {
      finish();
    }
  };
  const finish = () => {
    document.removeEventListener('keydown', onKey, true);
    document.removeEventListener('mousedown', onPointer, true);
    window.removeEventListener('blur', finish);
    menu.remove();
    close = null;
  };
  close = finish;
  document.addEventListener('keydown', onKey, true);
  document.addEventListener('mousedown', onPointer, true);
  window.addEventListener('blur', finish);
  buttons[0]?.focus();
}

export interface PickerItem {
  label: string;
  hint?: string;
  icon: IconNode;
  run: () => void;
}

/** Un menu con buscador arriba: el "Mover a…" de una nota. El mismo cierre con
 * Escape, clic fuera o al elegir, y las flechas mueven entre lo que queda. */
export function openPicker(
  anchor: { x: number; y: number },
  placeholder: string,
  items: PickerItem[],
): void {
  close?.();
  const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;

  const menu = el('div', 'menu picker');
  menu.setAttribute('role', 'listbox');
  menu.setAttribute('aria-label', placeholder);

  const input = el('input', 'menu-search');
  input.placeholder = placeholder;
  input.spellcheck = false;
  input.setAttribute('aria-label', placeholder);

  const list = el('div', 'menu-list');

  const render = (): void => {
    const query = normalizeForSearch(input.value);
    const shown = items.filter(
      (item) => query === '' || normalizeForSearch(`${item.label} ${item.hint ?? ''}`).includes(query),
    );
    list.replaceChildren(
      ...shown.map((item) => {
        const node = button(
          'menu-item',
          icon(item.icon),
          el(
            'span',
            'menu-text',
            el('span', 'menu-label', item.label),
            ...(item.hint ? [el('span', 'menu-detail', item.hint)] : []),
          ),
        );
        node.setAttribute('role', 'option');
        node.addEventListener('click', () => {
          finish();
          item.run();
        });
        return node;
      }),
    );
    if (shown.length === 0) {
      list.append(el('div', 'menu-empty', 'Nada coincide'));
    }
  };

  menu.append(input, list);
  document.body.append(menu);
  render();

  const width = menu.offsetWidth;
  const height = menu.offsetHeight;
  const x = Math.max(8, Math.min(anchor.x, window.innerWidth - width - 8));
  const y = Math.max(8, Math.min(anchor.y, window.innerHeight - height - 8));
  menu.style.left = `${x}px`;
  menu.style.top = `${y}px`;

  const onKey = (event: KeyboardEvent) => {
    const buttons = [...list.querySelectorAll<HTMLButtonElement>('button')];
    const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      finish();
      previous?.focus();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const step = event.key === 'ArrowDown' ? 1 : -1;
      buttons[(index + step + buttons.length) % buttons.length]?.focus();
    } else if (event.key === 'Tab') {
      finish();
    }
  };
  const onPointer = (event: MouseEvent) => {
    if (!menu.contains(event.target as Node)) {
      finish();
    }
  };
  const finish = () => {
    document.removeEventListener('keydown', onKey, true);
    document.removeEventListener('mousedown', onPointer, true);
    window.removeEventListener('blur', finish);
    menu.remove();
    close = null;
  };
  close = finish;
  document.addEventListener('keydown', onKey, true);
  document.addEventListener('mousedown', onPointer, true);
  window.addEventListener('blur', finish);

  input.addEventListener('input', render);
  input.focus();
}
