// Crear elementos sin plantillas: todo el texto va por `append`, nunca por
// `innerHTML`, asi que el contenido de una nota no puede inyectar marcado.

import { type IconNode, createElement } from 'lucide';

export function icon(node: IconNode, className?: string): SVGElement {
  const svg = createElement(node);
  svg.setAttribute('aria-hidden', 'true');
  if (className) {
    svg.classList.add(className);
  }
  return svg;
}

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  ...children: Array<Node | string>
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  node.append(...children);
  return node;
}

/** Un boton que no envia formularios. */
export function button(className: string, ...children: Array<Node | string>): HTMLButtonElement {
  const node = el('button', className, ...children);
  node.type = 'button';
  return node;
}
