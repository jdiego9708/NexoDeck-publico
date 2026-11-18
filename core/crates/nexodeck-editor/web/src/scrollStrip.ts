// Una fila de controles que no cabe: sin barra de desplazamiento, con una flecha
// en el borde por donde se corta.
//
// Peticion del usuario para las pestañas (Notas, Tareas, Asistente) y la barra
// de agrupaciones: una barra de scroll horizontal come alto y casi no se ve en
// una fila de 30 px, y lo que queda cortado (el numero de una pestaña, una
// agrupacion) no dice que hay mas. La flecha si lo dice, y esta justo donde se
// corta.
//
// - La flecha de la derecha sale solo si hay algo oculto a la derecha, y la de la
//   izquierda solo cuando ya se avanzo: sin ella no habria forma de volver.
// - Cada pulsacion avanza casi un ancho entero, dejando a la vista un trozo de lo
//   que ya se veia para no perder el sitio.
// - La rueda del raton tambien desplaza en horizontal, y el teclado lleva solo al
//   control enfocado: el navegador lo trae a la vista.
// - Se recalcula al cambiar el tamaño de la fila o de cualquiera de sus controles
//   (un contador que pasa de 9 a 10 puede ser justo lo que ya no cabe).

import { ChevronLeft, ChevronRight } from 'lucide';

import { button, el, icon } from './dom';

/** Envuelve [track] (la fila de controles) y devuelve el contenedor a insertar. */
export function scrollStrip(track: HTMLElement, label: string): HTMLElement {
  track.classList.add('strip-track');
  const previous = button('strip-arrow start', icon(ChevronLeft));
  const next = button('strip-arrow end', icon(ChevronRight));
  previous.setAttribute('aria-label', `Ver ${label} anteriores`);
  next.setAttribute('aria-label', `Ver más ${label}`);
  // Fuera del orden de tabulacion: con el teclado se llega a cada control, y el
  // navegador ya lo trae a la vista.
  previous.tabIndex = -1;
  next.tabIndex = -1;
  const strip = el('div', 'strip', previous, track, next);

  const update = () => {
    const max = track.scrollWidth - track.clientWidth;
    // Un pixel de margen: con zoom, el scroll se queda en fracciones.
    previous.hidden = track.scrollLeft <= 1;
    next.hidden = track.scrollLeft >= max - 1;
    strip.classList.toggle('overflowing', max > 1);
  };
  const step = (direction: 1 | -1) => {
    track.scrollBy({ left: direction * Math.max(track.clientWidth * 0.75, 60), behavior: 'smooth' });
    // El desplazamiento suave no siempre avisa de cada paso (se vio en la prueba
    // con Edge): sin esto, la flecha de volver podia no aparecer nunca.
    window.setTimeout(update, 400);
  };
  previous.addEventListener('click', () => step(-1));
  next.addEventListener('click', () => step(1));
  track.addEventListener('scroll', update, { passive: true });
  track.addEventListener('scrollend', update);
  track.addEventListener(
    'wheel',
    (event) => {
      if (track.scrollWidth <= track.clientWidth || Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
        return;
      }
      event.preventDefault();
      track.scrollLeft += event.deltaY;
    },
    { passive: false },
  );

  const observer = new ResizeObserver(() => {
    // La barra de agrupaciones se redibuja entera con cada foto de la boveda: el
    // observador de una fila que ya no esta en la pagina se suelta solo.
    if (!strip.isConnected && strip.dataset.attached === 'true') {
      observer.disconnect();
      return;
    }
    strip.dataset.attached = String(strip.isConnected);
    update();
  });
  observer.observe(track);
  for (const child of Array.from(track.children)) {
    observer.observe(child);
  }
  update();
  return strip;
}

/** Trae [node] a la vista dentro de su fila, sin animacion (para restaurar). */
export function revealInStrip(node: HTMLElement | null | undefined): void {
  node?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
}
