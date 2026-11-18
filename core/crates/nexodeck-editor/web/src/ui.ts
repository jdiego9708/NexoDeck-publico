// La estructura de la ventana de notas: barra de herramientas, aviso de
// conflicto, barra lateral, editor (o bienvenida), panel de la nota y barra de
// estado. Lo que va dentro de la barra lateral y del panel lo ponen sus clases.

import {
  Bold,
  Brackets,
  Check,
  CircleAlert,
  Code,
  Command,
  FileText,
  Focus,
  Heading1,
  Heading2,
  Heading3,
  type IconNode,
  Italic,
  Link,
  List,
  ListOrdered,
  ListTodo,
  LoaderCircle,
  Lock,
  PanelLeft,
  PanelRight,
  Pilcrow,
  Redo2,
  RotateCcw,
  Save,
  Search,
  SeparatorHorizontal,
  SquareCode,
  Strikethrough,
  Table,
  TextQuote,
  Undo2,
} from 'lucide';

import { button, el, icon } from './dom';

export { icon } from './dom';

export type ToolId =
  | 'sidebar'
  | 'undo'
  | 'redo'
  | 'h1'
  | 'h2'
  | 'h3'
  | 'paragraph'
  | 'bold'
  | 'italic'
  | 'strike'
  | 'code'
  | 'link'
  | 'wikilink'
  | 'bullet'
  | 'ordered'
  | 'task'
  | 'quote'
  | 'codeblock'
  | 'table'
  | 'rule'
  | 'search'
  | 'panel'
  | 'focus'
  | 'palette';

interface ToolSpec {
  id: ToolId;
  icon: IconNode;
  tip: string;
}

const GROUPS: Array<{ tools: ToolSpec[]; optional?: boolean }> = [
  {
    tools: [
      { id: 'undo', icon: Undo2, tip: 'Deshacer · Ctrl+Z' },
      { id: 'redo', icon: Redo2, tip: 'Rehacer · Ctrl+Y' },
    ],
  },
  {
    tools: [
      { id: 'h1', icon: Heading1, tip: 'Título 1 · Ctrl+1' },
      { id: 'h2', icon: Heading2, tip: 'Título 2 · Ctrl+2' },
      { id: 'h3', icon: Heading3, tip: 'Título 3 · Ctrl+3' },
      { id: 'paragraph', icon: Pilcrow, tip: 'Texto normal · Ctrl+0' },
    ],
  },
  {
    tools: [
      { id: 'bold', icon: Bold, tip: 'Negrita · Ctrl+B' },
      { id: 'italic', icon: Italic, tip: 'Cursiva · Ctrl+I' },
      { id: 'strike', icon: Strikethrough, tip: 'Tachado · Ctrl+Shift+X' },
      { id: 'code', icon: Code, tip: 'Código · Ctrl+E' },
    ],
  },
  {
    tools: [
      { id: 'link', icon: Link, tip: 'Enlace · Ctrl+K' },
      { id: 'wikilink', icon: Brackets, tip: 'Enlace a una nota · [[' },
    ],
  },
  {
    tools: [
      { id: 'bullet', icon: List, tip: 'Lista · Ctrl+Shift+8' },
      { id: 'ordered', icon: ListOrdered, tip: 'Lista numerada · Ctrl+Shift+7' },
      { id: 'task', icon: ListTodo, tip: 'Tarea · Ctrl+Shift+9' },
      { id: 'quote', icon: TextQuote, tip: 'Cita' },
    ],
  },
  {
    optional: true,
    tools: [
      { id: 'codeblock', icon: SquareCode, tip: 'Bloque de código' },
      { id: 'table', icon: Table, tip: 'Tabla' },
      { id: 'rule', icon: SeparatorHorizontal, tip: 'Separador' },
    ],
  },
];

const SIDE_TOOLS: ToolSpec[] = [
  { id: 'search', icon: Search, tip: 'Buscar en la nota · Ctrl+F' },
  { id: 'panel', icon: PanelRight, tip: 'Panel de la nota · Ctrl+J' },
  { id: 'focus', icon: Focus, tip: 'Concentración · Ctrl+.' },
  { id: 'palette', icon: Command, tip: 'Comandos · Ctrl+P' },
];

export interface Ui {
  root: HTMLElement;
  title: HTMLElement;
  path: HTMLElement;
  lock: SVGElement;
  tools: Map<ToolId, HTMLButtonElement>;
  savePill: HTMLElement;
  saveLabel: HTMLElement;
  banner: HTMLElement;
  bannerTitle: HTMLElement;
  bannerDetail: HTMLElement;
  bannerReload: HTMLButtonElement;
  bannerKeep: HTMLButtonElement;
  editorHost: HTMLElement;
  sidebarResizer: HTMLElement;
  words: HTMLElement;
  reading: HTMLElement;
  position: HTMLElement;
}

function toolButton(spec: ToolSpec): HTMLButtonElement {
  const node = button('tool', icon(spec.icon));
  node.dataset.tip = spec.tip;
  node.dataset.tool = spec.id;
  node.setAttribute('aria-label', spec.tip.split(' · ')[0]);
  return node;
}

export function buildUi(container: HTMLElement, sidebar: HTMLElement, welcome: HTMLElement, context: HTMLElement): Ui {
  const tools = new Map<ToolId, HTMLButtonElement>();
  const addTool = (spec: ToolSpec) => {
    const node = toolButton(spec);
    tools.set(spec.id, node);
    return node;
  };

  const nav = el('div', 'tool-group nav-group', addTool({ id: 'sidebar', icon: PanelLeft, tip: 'Lista de notas · Ctrl+Shift+E' }));

  // Que nota es.
  const title = el('div', 'doc-title', 'Notas');
  const lock = icon(Lock);
  lock.setAttribute('aria-label', 'Nota privada: ningún agente la lee');
  lock.style.display = 'none';
  const path = el('span');
  const meta = el(
    'div',
    'doc-meta',
    el('div', 'doc-badge', icon(FileText)),
    el('div', 'doc-text', title, el('div', 'doc-path', lock, path)),
  );

  const toolsBox = el('div', 'tools');
  for (const group of GROUPS) {
    const box = el('div', group.optional ? 'tool-group optional' : 'tool-group');
    box.setAttribute('role', 'group');
    box.append(...group.tools.map(addTool));
    toolsBox.append(box);
  }

  // Estado de guardado: un glifo que se transforma (punto, giro, check, alerta).
  const saveLabel = el('span', undefined, 'Guardado');
  const glyph = el(
    'span',
    'glyph',
    el('span', 'dot'),
    icon(LoaderCircle, 'spinner'),
    icon(Check, 'check'),
    icon(CircleAlert, 'alert'),
  );
  const savePill = el('div', 'save-pill', glyph, saveLabel);
  savePill.dataset.status = 'idle';
  savePill.setAttribute('role', 'status');
  savePill.setAttribute('aria-live', 'polite');

  const side = el('div', 'side-tools', el('div', 'tool-group', ...SIDE_TOOLS.map(addTool)), savePill);
  const toolbar = el('header', 'toolbar', nav, meta, toolsBox, side);

  // Aviso de conflicto.
  const bannerTitle = el('strong');
  const bannerDetail = el('span');
  const bannerReload = button('chip', icon(RotateCcw), 'Recargar del disco');
  const bannerKeep = button('chip primary', icon(Save), 'Quedarme con lo mío');
  const banner = el(
    'div',
    'banner',
    icon(CircleAlert),
    el('div', 'banner-text', bannerTitle, bannerDetail),
    bannerReload,
    bannerKeep,
  );
  banner.setAttribute('role', 'alert');
  banner.hidden = true;

  const editorHost = el('div', 'editor-host');
  // El divisor entre la lista y el editor. No ocupa sitio en la rejilla: se
  // ancla al borde de la lista por `--sidebar-width` (position: absolute). Quien
  // le da vida es main.ts, con `attachPanelResizer`.
  const sidebarResizer = el('div', 'resizer');
  const workspace = el('div', 'workspace', sidebar, sidebarResizer, el('main', 'main', welcome, editorHost), context);

  // Barra de estado.
  const words = el('span', 'stat');
  const reading = el('span', 'stat');
  const position = el('span', 'stat');
  const hint = el('span', undefined, el('kbd', undefined, 'Ctrl'), ' + ', el('kbd', undefined, 'P'), ' comandos');
  const statusbar = el('footer', 'statusbar', words, reading, el('span', 'spacer'), position, hint);

  const root = el('div', 'app', toolbar, banner, workspace, statusbar);
  root.dataset.empty = 'true';
  root.dataset.focus = 'off';
  container.replaceWith(root);

  return {
    root,
    title,
    path,
    lock,
    tools,
    savePill,
    saveLabel,
    banner,
    bannerTitle,
    bannerDetail,
    bannerReload,
    bannerKeep,
    editorHost,
    sidebarResizer,
    words,
    reading,
    position,
  };
}

let toastTimer: number | undefined;

/** Un aviso breve abajo, que se va solo. */
export function showToast(message: string, kind: 'info' | 'error' = 'info'): void {
  document.querySelectorAll('.toast').forEach((old) => old.remove());
  const toast = el('div', 'toast', icon(kind === 'error' ? CircleAlert : Check), message);
  toast.setAttribute('role', kind === 'error' ? 'alert' : 'status');
  document.body.append(toast);
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(
    () => {
      toast.classList.add('leaving');
      window.setTimeout(() => toast.remove(), 200);
    },
    kind === 'error' ? 5200 : 2600,
  );
}
