// El divisor arrastrable entre la lista de notas y el editor.
//
// No dibuja nada: la linea y el cursor los pone el CSS (`.resizer`). Aca solo
// se traduce el arrastre del puntero en un ancho en px, con topes, y se avisa
// en cada movimiento y al soltar. El `setPointerCapture` es lo que deja seguir
// el arrastre aunque el cursor se salga de los pocos px de la manija, y el
// doble clic devuelve el ancho de fabrica: la salida de un arrastre
// desafortunado no puede ser volver a acertarle al pixel.

export interface PanelResizerOptions {
  /** Ancho actual del panel, en px. */
  getWidth(): number;
  /** Aplica el ancho durante el arrastre. */
  setWidth(width: number): void;
  /** Se solto: es el momento de persistir (durante el arrastre no). */
  onDragEnd(width: number): void;
  /** Doble clic: volver al ancho por defecto. */
  onReset(): void;
  min: number;
  max: number;
}

export function attachPanelResizer(handle: HTMLElement, options: PanelResizerOptions): void {
  handle.setAttribute('role', 'separator');
  handle.setAttribute('aria-orientation', 'vertical');
  handle.setAttribute('aria-label', 'Redimensionar la lista de notas');

  let dragging = false;
  let startX = 0;
  let startWidth = 0;

  const clamp = (value: number) => Math.max(options.min, Math.min(options.max, Math.round(value)));

  handle.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) {
      return;
    }
    dragging = true;
    startX = event.clientX;
    startWidth = options.getWidth();
    handle.classList.add('dragging');
    document.body.classList.add('resizing');
    handle.setPointerCapture(event.pointerId);
    event.preventDefault();
  });

  handle.addEventListener('pointermove', (event) => {
    if (!dragging) {
      return;
    }
    options.setWidth(clamp(startWidth + (event.clientX - startX)));
  });

  const finish = () => {
    if (!dragging) {
      return;
    }
    dragging = false;
    handle.classList.remove('dragging');
    document.body.classList.remove('resizing');
    options.onDragEnd(options.getWidth());
  };

  handle.addEventListener('pointerup', finish);
  handle.addEventListener('pointercancel', finish);
  handle.addEventListener('dblclick', () => options.onReset());
}
