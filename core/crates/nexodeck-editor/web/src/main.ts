// La ventana de notas: une CodeMirror, la barra lateral, el panel de la nota y
// el canal con Rust.

import './styles.css';

import { autocompletion, closeBrackets, closeBracketsKeymap, completionKeymap } from '@codemirror/autocomplete';
import { defaultKeymap, history, historyKeymap, indentWithTab, redo, undo } from '@codemirror/commands';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { python } from '@codemirror/lang-python';
import { rust } from '@codemirror/lang-rust';
import { sql } from '@codemirror/lang-sql';
import { yaml } from '@codemirror/lang-yaml';
import {
  HighlightStyle,
  type Language,
  StreamLanguage,
  bracketMatching,
  indentOnInput,
  syntaxHighlighting,
} from '@codemirror/language';
import { dart } from '@codemirror/legacy-modes/mode/clike';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { highlightSelectionMatches, openSearchPanel, search, searchKeymap } from '@codemirror/search';
import { EditorState, type Extension } from '@codemirror/state';
import { EditorView, drawSelection, dropCursor, keymap, placeholder, rectangularSelection } from '@codemirror/view';
import { tags } from '@lezer/highlight';
import {
  Bold,
  Brackets,
  CalendarPlus,
  Code,
  FilePlus,
  Focus,
  Heading1,
  Heading2,
  Heading3,
  Inbox,
  Italic,
  Library,
  Link,
  List,
  ListOrdered,
  ListTodo,
  PanelLeft,
  PanelRight,
  RefreshCw,
  Save,
  Search,
  SeparatorHorizontal,
  Sparkles,
  SquareCode,
  Strikethrough,
  Table,
  TextQuote,
} from 'lucide';

import { hostAvailable, isMobileHost, onHostMessage, send } from './bridge';
import {
  type Format,
  activeFormats,
  insertCodeBlock,
  insertLink,
  insertRule,
  insertTable,
  insertWikiLink,
  setHeading,
  toggleInline,
  toggleLinePrefix,
  toggleTaskUnderCursor,
} from './commands';
import { wikiLinkCompletions } from './completion';
import { ContextPanel } from './contextPanel';
import { linkClicks, livePreview, setCurrentNote } from './livePreview';
import { countWords, readingMinutes } from './markdownText';
import { askNewNote, type NewNotePreset } from './newNoteDialog';
import { exportFileName } from './notePaths';
import type { SortMode } from './noteTree';
import { OutlineView, extractHeadings } from './outline';
import { Palette, type PaletteItem } from './palette';
import type { DetailsDto, HostMessage, LinkTargetDto, NoteDto, OverviewDto, PageMessage, ThemeDto } from './protocol';
import { attachPanelResizer } from './resizer';
import { AutoSaver, type SaveStatus } from './save';
import { SIDEBAR_TABS, Sidebar, type SidebarTab, roleIcon } from './sidebar';
import { applyTheme } from './theme';
import { type ToolId, buildUi, icon, showToast } from './ui';
import { WelcomeView } from './welcome';

// ---------- lenguajes dentro de bloques de codigo ----------

const CODE_LANGUAGES: Array<[RegExp, () => Language]> = [
  [/^(js|javascript|ts|typescript|jsx|tsx)$/, () => javascript({ typescript: true, jsx: true }).language],
  [/^(rs|rust)$/, () => rust().language],
  [/^(py|python)$/, () => python().language],
  [/^(sql|postgres|postgresql|psql)$/, () => sql().language],
  [/^json$/, () => json().language],
  [/^ya?ml$/, () => yaml().language],
  [/^(sh|bash|shell|zsh|console)$/, () => StreamLanguage.define(shell)],
  [/^dart$/, () => StreamLanguage.define(dart)],
];
const languageCache = new Map<string, Language | null>();

function codeLanguage(info: string): Language | null {
  const key = info.trim().split(/\s+/)[0]?.toLowerCase() ?? '';
  if (!languageCache.has(key)) {
    const found = CODE_LANGUAGES.find(([pattern]) => pattern.test(key));
    languageCache.set(key, found ? found[1]() : null);
  }
  return languageCache.get(key) ?? null;
}

const codeHighlight = HighlightStyle.define([
  { tag: [tags.keyword, tags.controlKeyword, tags.modifier], color: 'var(--primary)', fontWeight: '500' },
  { tag: [tags.string, tags.special(tags.string), tags.regexp], color: 'var(--tertiary)' },
  { tag: [tags.number, tags.bool, tags.null, tags.atom], color: 'color-mix(in srgb, var(--primary) 65%, var(--tertiary))' },
  { tag: [tags.comment, tags.lineComment, tags.blockComment], color: 'var(--on-surface-variant)', fontStyle: 'italic' },
  { tag: [tags.function(tags.variableName), tags.function(tags.propertyName)], color: 'color-mix(in srgb, var(--primary) 75%, var(--on-surface))' },
  { tag: [tags.typeName, tags.className], color: 'color-mix(in srgb, var(--tertiary) 70%, var(--on-surface))' },
  { tag: [tags.processingInstruction, tags.meta], color: 'var(--on-surface-variant)' },
  { tag: tags.url, color: 'var(--primary)' },
]);

// ---------- preferencias de esta ventana ----------

function readPreference(key: string, fallback: string): string {
  try {
    return localStorage.getItem(`nexodeck.editor.${key}`) ?? fallback;
  } catch {
    return fallback;
  }
}

function writePreference(key: string, value: string): void {
  try {
    localStorage.setItem(`nexodeck.editor.${key}`, value);
  } catch {
    // Sin almacenamiento, la preferencia vale para esta sesion y ya.
  }
}

function readSortPreference(): SortMode {
  const value = readPreference('sort', 'name');
  return value === 'newest' || value === 'oldest' ? value : 'name';
}

// ---------- estado ----------

/** En la app del movil: lista y editor a pantalla completa, uno cada vez. */
const mobile = isMobileHost();

let note: NoteDto | null = null;
let overview: OverviewDto | null = null;
let targets: LinkTargetDto[] = [];
let lastDirty = false;
let closeRequested = false;
/** Abrir otra nota espera a que termine de guardarse la actual. */
let pendingNavigation: PageMessage | null = null;
/** La linea a la que saltar cuando cargue la nota (una tarea de la lista). */
let pendingLine: number | null = null;

const storedTab = readPreference('tab', 'notes') as SidebarTab;
const sidebar = new Sidebar(
  {
    openNote: (path, line) => openNote(path, line),
    search: (query) => send({ type: 'search', query }),
    showInbox: () => send({ type: 'showInbox' }),
    openDaily: () => openDaily(),
    newNote: (preset) => void newNote(preset),
    refresh: () => send({ type: 'refresh' }),
    tabChanged: (tab) => writePreference('tab', tab),
    sortChanged: (sort) => writePreference('sort', sort),
    moveNote: (path, group) => send({ type: 'moveNote', path, group }),
    chooseVault: () => send({ type: 'chooseVault' }),
    importLocalFolder: () => send({ type: 'importLocalFolder' }),
    importOneNote: () => send({ type: 'importOneNote' }),
    removeLocalFolder: (id) => send({ type: 'removeLocalFolder', id }),
    exportVault: () => send({ type: 'exportVault', fileName: exportFileName(new Date()) }),
  },
  SIDEBAR_TABS.includes(storedTab) ? storedTab : 'notes',
  mobile,
  readSortPreference(),
);
const context = new ContextPanel({
  openNote: (path) => openNote(path),
  digest: (path) => send({ type: 'digest', path }),
  showInbox: () => send({ type: 'showInbox' }),
});
const welcome = new WelcomeView({
  openDaily: () => openDaily(),
  newNote: () => void newNote(),
  palette: () => openPalette(),
  openNote: (path) => openNote(path),
});
const ui = buildUi(document.getElementById('app')!, sidebar.element, welcome.element, context.element);
applyTheme(null);

// Ancho de la lista de notas: el divisor lo arrastra y se recuerda entre
// sesiones. Vive como `--sidebar-width` en la raiz (styles.css), asi que
// moverlo reacomoda la lista, su contenido y el divisor de una sola vez.
const DEFAULT_SIDEBAR_WIDTH = 300;
const SIDEBAR_MIN_WIDTH = 220;
const SIDEBAR_MAX_WIDTH = 640;
let sidebarWidth = DEFAULT_SIDEBAR_WIDTH;

function clampSidebarWidth(width: number): number {
  return Math.max(SIDEBAR_MIN_WIDTH, Math.min(SIDEBAR_MAX_WIDTH, Math.round(width)));
}

function applySidebarWidth(width: number): void {
  sidebarWidth = clampSidebarWidth(width);
  ui.root.style.setProperty('--sidebar-width', `${sidebarWidth}px`);
}

if (!mobile) {
  const storedWidth = Number.parseInt(readPreference('sidebarWidth', ''), 10);
  applySidebarWidth(Number.isNaN(storedWidth) ? DEFAULT_SIDEBAR_WIDTH : storedWidth);

  attachPanelResizer(ui.sidebarResizer, {
    min: SIDEBAR_MIN_WIDTH,
    max: SIDEBAR_MAX_WIDTH,
    getWidth: () => sidebarWidth,
    setWidth: applySidebarWidth,
    onDragEnd: (width) => writePreference('sidebarWidth', String(width)),
    onReset: () => {
      applySidebarWidth(DEFAULT_SIDEBAR_WIDTH);
      writePreference('sidebarWidth', String(DEFAULT_SIDEBAR_WIDTH));
    },
  });
}

const STATUS_LABEL: Record<SaveStatus, string> = {
  idle: 'Sin nota',
  clean: 'Guardado',
  dirty: 'Sin guardar',
  saving: 'Guardando…',
  conflict: 'Conflicto',
  error: 'No se pudo guardar',
};

const saver = new AutoSaver({
  delayMs: 1000,
  getText: () => view.state.doc.toString(),
  send: (text, baseHash, reason) => {
    if (note) {
      send({ type: 'save', path: note.path, text, baseHash, reason });
    }
  },
  onStatus: renderSaveStatus,
});

function renderSaveStatus(status: SaveStatus): void {
  ui.savePill.dataset.status = status;
  ui.saveLabel.textContent = STATUS_LABEL[status];
  ui.savePill.title = status === 'error' ? (saver.error ?? '') : '';

  const dirty = status === 'dirty' || status === 'saving' || status === 'conflict' || status === 'error';
  if (dirty !== lastDirty) {
    lastDirty = dirty;
    send({ type: 'dirty', dirty });
  }

  renderConflict(status === 'conflict');

  if (status === 'clean') {
    if (closeRequested) {
      closeRequested = false;
      send({ type: 'closeReady' });
    } else if (pendingNavigation !== null) {
      const message = pendingNavigation;
      pendingNavigation = null;
      send(message);
    }
  }
}

function renderConflict(show: boolean): void {
  const conflict = saver.conflict;
  ui.banner.hidden = !show || conflict === null;
  if (!show || conflict === null) {
    return;
  }
  const deleted = conflict.diskHash === '';
  ui.bannerTitle.textContent = deleted ? 'La nota ya no existe en disco' : 'La nota cambió fuera de NexoDeck';
  ui.bannerDetail.textContent = deleted
    ? 'La borraron mientras escribías. Puedes volver a crearla con lo que tienes aquí.'
    : 'Alguien la editó (Obsidian, una propuesta aprobada…) mientras escribías. No se ha guardado nada.';
  ui.bannerReload.hidden = deleted;
  ui.bannerKeep.lastChild!.textContent = deleted ? 'Volver a crearla' : 'Quedarme con lo mío';
}

// ---------- editor ----------

function editorExtensions(): Extension[] {
  return [
    history(),
    drawSelection(),
    dropCursor(),
    rectangularSelection(),
    indentOnInput(),
    bracketMatching(),
    closeBrackets(),
    highlightSelectionMatches(),
    EditorView.lineWrapping,
    markdown({ base: markdownLanguage, codeLanguages: codeLanguage }),
    syntaxHighlighting(codeHighlight),
    livePreview,
    linkClicks({
      wiki: (target) => navigate({ type: 'openLink', target }),
      url: (href) => send({ type: 'openExternal', url: href }),
    }),
    autocompletion({ override: [wikiLinkCompletions(() => targets, () => note?.path)], icons: false }),
    search({ top: true }),
    placeholder('Empieza a escribir… Usa [[ para enlazar otra nota y Ctrl+P para ver todo lo que puedes hacer.'),
    EditorView.contentAttributes.of({ spellcheck: 'true', lang: 'es', autocorrect: 'on', autocapitalize: 'sentences' }),
    keymap.of([
      { key: 'Mod-s', preventDefault: true, run: () => (saver.flush('manual'), true) },
      { key: 'Mod-b', run: (v) => toggleInline(v, '**') },
      { key: 'Mod-i', run: (v) => toggleInline(v, '_') },
      { key: 'Mod-Shift-x', run: (v) => toggleInline(v, '~~') },
      { key: 'Mod-e', run: (v) => toggleInline(v, '`') },
      { key: 'Mod-k', run: insertLink },
      { key: 'Mod-1', run: (v) => setHeading(v, 1) },
      { key: 'Mod-2', run: (v) => setHeading(v, 2) },
      { key: 'Mod-3', run: (v) => setHeading(v, 3) },
      { key: 'Mod-0', run: (v) => setHeading(v, 0) },
      { key: 'Mod-Shift-8', run: (v) => toggleLinePrefix(v, 'bullet') },
      { key: 'Mod-Shift-7', run: (v) => toggleLinePrefix(v, 'ordered') },
      { key: 'Mod-Shift-9', run: (v) => toggleLinePrefix(v, 'task') },
      { key: 'Mod-Enter', run: toggleTaskUnderCursor },
      { key: 'Mod-p', preventDefault: true, run: () => (openPalette(), true) },
      { key: 'Mod-Shift-e', preventDefault: true, run: () => (toggleSidebar(), true) },
      { key: 'Mod-Shift-f', preventDefault: true, run: () => (focusVaultSearch(), true) },
      { key: 'Mod-j', preventDefault: true, run: () => (togglePanel(), true) },
      { key: 'Mod-.', preventDefault: true, run: () => (toggleFocus(), true) },
      ...closeBracketsKeymap,
      ...completionKeymap,
      ...searchKeymap,
      ...historyKeymap,
      indentWithTab,
      ...defaultKeymap,
    ]),
    EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        saver.edited();
      }
      if (update.docChanged || update.selectionSet) {
        scheduleRefresh();
      }
    }),
    EditorView.domEventHandlers({
      blur: () => {
        saver.flush('auto');
        return false;
      },
    }),
  ];
}

const view = new EditorView({
  parent: ui.editorHost,
  state: EditorState.create({ doc: '', extensions: editorExtensions() }),
});

function replaceDocument(text: string): void {
  // Estado nuevo y no una transaccion: el historial de deshacer es de cada
  // version de la nota, y recargar no cuenta como una edicion a guardar.
  view.setState(EditorState.create({ doc: text, extensions: editorExtensions() }));
  scheduleRefresh();
}

function jumpToLine(line: number): void {
  const target = view.state.doc.line(Math.max(1, Math.min(line, view.state.doc.lines)));
  view.dispatch({
    selection: { anchor: target.to },
    effects: EditorView.scrollIntoView(target.from, { y: 'center' }),
  });
  view.focus();
}

// ---------- esquema, estadisticas y botones activos ----------

const outline = new OutlineView(context.outlineList, context.outlineEmpty, (from) => {
  view.dispatch({
    selection: { anchor: from },
    effects: EditorView.scrollIntoView(from, { y: 'start', yMargin: 48 }),
  });
  view.focus();
});

const FORMAT_TOOLS = new Set<ToolId>(['h1', 'h2', 'h3', 'bold', 'italic', 'strike', 'code', 'link', 'bullet', 'ordered', 'task', 'quote']);
let refreshQueued = false;

function scheduleRefresh(): void {
  if (refreshQueued) {
    return;
  }
  refreshQueued = true;
  requestAnimationFrame(() => {
    refreshQueued = false;
    refresh();
  });
}

function refresh(): void {
  const { state } = view;
  const head = state.selection.main.head;
  const line = state.doc.lineAt(head);
  const words = countWords(state.doc.toString());
  ui.words.textContent = `${words.toLocaleString('es')} ${words === 1 ? 'palabra' : 'palabras'}`;
  ui.reading.textContent = words === 0 ? 'Nota vacía' : `${readingMinutes(words)} min de lectura`;
  ui.position.textContent = `Ln ${line.number}, Col ${head - line.from + 1}`;
  outline.update(extractHeadings(state), head);

  const formats = activeFormats(state);
  for (const [id, node] of ui.tools) {
    if (FORMAT_TOOLS.has(id)) {
      node.setAttribute('aria-pressed', String(formats.has(id as Format)));
    }
  }
}

// ---------- paneles y modos ----------

type Pane = 'sidebar' | 'panel';

function setPane(pane: Pane, open: boolean): void {
  ui.root.dataset[pane] = open ? 'open' : 'closed';
  ui.tools.get(pane)?.setAttribute('aria-pressed', String(open));
  writePreference(pane, open ? 'open' : 'closed');
}

function toggleSidebar(): void {
  setPane('sidebar', ui.root.dataset.sidebar !== 'open');
}

function togglePanel(): void {
  setPane('panel', ui.root.dataset.panel !== 'open');
}

function focusVaultSearch(): void {
  setPane('sidebar', true);
  if (ui.root.dataset.focus === 'on') {
    toggleFocus();
  }
  sidebar.focusSearch();
}

function toggleFocus(): void {
  const on = ui.root.dataset.focus !== 'on';
  ui.root.dataset.focus = on ? 'on' : 'off';
  ui.tools.get('focus')?.setAttribute('aria-pressed', String(on));
  if (on) {
    showToast('Modo concentración: acerca el ratón arriba para ver la barra');
  }
  view.focus();
}

if (mobile) {
  // Una sola cosa a la vez: se empieza por la lista, y el panel de la nota (quién
  // la enlaza, el asistente) no cabe en un teléfono.
  ui.root.dataset.mobile = 'true';
  setPane('sidebar', true);
  setPane('panel', false);
  window.nexodeck.back = () => {
    // Atrás desde una nota vuelve a la lista; desde la lista, sale de Notas.
    if (ui.root.dataset.sidebar === 'open') {
      return false;
    }
    saver.flush('auto');
    setPane('sidebar', true);
    return true;
  };
} else {
  setPane('sidebar', readPreference('sidebar', 'open') === 'open');
  setPane('panel', readPreference('panel', 'open') === 'open');
}

const palette = new Palette(document.body, paletteItems);

function openPalette(): void {
  palette.open(() => (note ? view.focus() : undefined));
}

function paletteItems(): PaletteItem[] {
  const current = note;
  const editing: PaletteItem[] = current
    ? [
        { label: 'Negrita', hint: 'Ctrl+B', keywords: 'bold', icon: icon(Bold), run: () => toggleInline(view, '**') },
        { label: 'Cursiva', hint: 'Ctrl+I', keywords: 'italic', icon: icon(Italic), run: () => toggleInline(view, '_') },
        { label: 'Tachado', hint: 'Ctrl+Shift+X', icon: icon(Strikethrough), run: () => toggleInline(view, '~~') },
        { label: 'Código en línea', hint: 'Ctrl+E', icon: icon(Code), run: () => toggleInline(view, '`') },
        { label: 'Título 1', hint: 'Ctrl+1', keywords: 'encabezado', icon: icon(Heading1), run: () => setHeading(view, 1) },
        { label: 'Título 2', hint: 'Ctrl+2', keywords: 'encabezado', icon: icon(Heading2), run: () => setHeading(view, 2) },
        { label: 'Título 3', hint: 'Ctrl+3', keywords: 'encabezado', icon: icon(Heading3), run: () => setHeading(view, 3) },
        { label: 'Lista', hint: 'Ctrl+Shift+8', keywords: 'viñetas', icon: icon(List), run: () => toggleLinePrefix(view, 'bullet') },
        { label: 'Lista numerada', hint: 'Ctrl+Shift+7', icon: icon(ListOrdered), run: () => toggleLinePrefix(view, 'ordered') },
        { label: 'Tarea', hint: 'Ctrl+Shift+9', keywords: 'todo checkbox', icon: icon(ListTodo), run: () => toggleLinePrefix(view, 'task') },
        { label: 'Cita', icon: icon(TextQuote), run: () => toggleLinePrefix(view, 'quote') },
        { label: 'Enlace', hint: 'Ctrl+K', icon: icon(Link), run: () => insertLink(view) },
        { label: 'Enlace a una nota', hint: '[[', keywords: 'wikilink', icon: icon(Brackets), run: () => insertWikiLink(view) },
        { label: 'Bloque de código', icon: icon(SquareCode), run: () => insertCodeBlock(view) },
        { label: 'Tabla', icon: icon(Table), run: () => insertTable(view) },
        { label: 'Separador', icon: icon(SeparatorHorizontal), run: () => insertRule(view) },
        { label: 'Buscar y reemplazar en la nota', hint: 'Ctrl+F', icon: icon(Search), run: () => openSearchPanel(view) },
        { label: 'Mostrar u ocultar el panel de la nota', hint: 'Ctrl+J', icon: icon(PanelRight), run: togglePanel },
        { label: 'Modo concentración', hint: 'Ctrl+.', icon: icon(Focus), run: toggleFocus },
        { label: 'Guardar ahora', hint: 'Ctrl+S', icon: icon(Save), run: () => saver.flush('manual') },
        ...(current.private
          ? []
          : [
              {
                label: 'Procesar esta nota con el asistente',
                keywords: 'digest agentes ia',
                icon: icon(Sparkles),
                run: () => send({ type: 'digest', path: current.path }),
              },
            ]),
      ]
    : [];
  const always: PaletteItem[] = [
    { label: 'Nota de hoy', keywords: 'diario daily', icon: icon(CalendarPlus), run: openDaily },
    { label: 'Nota nueva…', keywords: 'crear', icon: icon(FilePlus), run: () => void newNote() },
    { label: 'Buscar en todas las notas', hint: 'Ctrl+Shift+F', keywords: 'hallazgos commits', icon: icon(Library), run: focusVaultSearch },
    { label: 'Mostrar u ocultar la lista de notas', hint: 'Ctrl+Shift+E', icon: icon(PanelLeft), run: toggleSidebar },
    { label: 'Abrir el buzón de propuestas', keywords: 'inbox aprobar', icon: icon(Inbox), run: () => send({ type: 'showInbox' }) },
    { label: 'Volver a leer la bóveda', icon: icon(RefreshCw), run: () => send({ type: 'refresh' }) },
  ];
  const notes: PaletteItem[] = (overview?.notes ?? [])
    .filter((item) => item.path !== current?.path)
    .map((item) => ({
      label: `Ir a: ${item.title}`,
      hint: item.path,
      keywords: item.path,
      icon: icon(roleIcon(item.role)),
      run: () => openNote(item.path),
    }));
  return [...editing, ...always, ...notes];
}

// Los atajos de la ventana cuando el foco no esta en el editor (la lista, la
// bienvenida). Dentro del editor los atiende su keymap y llegan ya consumidos.
document.addEventListener('keydown', (event) => {
  if (event.defaultPrevented || !(event.ctrlKey || event.metaKey) || event.altKey) {
    return;
  }
  const key = event.key.toLowerCase();
  const shortcuts: Record<string, () => void> = event.shiftKey
    ? { e: toggleSidebar, f: focusVaultSearch }
    : { p: openPalette, j: togglePanel };
  const action = shortcuts[key];
  if (action) {
    event.preventDefault();
    action();
  }
});

// ---------- barra de herramientas ----------

const TOOL_ACTIONS: Record<ToolId, () => unknown> = {
  sidebar: toggleSidebar,
  undo: () => (undo(view), view.focus()),
  redo: () => (redo(view), view.focus()),
  h1: () => setHeading(view, 1),
  h2: () => setHeading(view, 2),
  h3: () => setHeading(view, 3),
  paragraph: () => setHeading(view, 0),
  bold: () => toggleInline(view, '**'),
  italic: () => toggleInline(view, '_'),
  strike: () => toggleInline(view, '~~'),
  code: () => toggleInline(view, '`'),
  link: () => insertLink(view),
  wikilink: () => insertWikiLink(view),
  bullet: () => toggleLinePrefix(view, 'bullet'),
  ordered: () => toggleLinePrefix(view, 'ordered'),
  task: () => toggleLinePrefix(view, 'task'),
  quote: () => toggleLinePrefix(view, 'quote'),
  codeblock: () => insertCodeBlock(view),
  table: () => insertTable(view),
  rule: () => insertRule(view),
  search: () => openSearchPanel(view),
  panel: togglePanel,
  focus: toggleFocus,
  palette: openPalette,
};

/** Sin nota abierta solo tienen sentido estas. */
const TOOLS_WITHOUT_NOTE = new Set<ToolId>(['sidebar', 'palette']);

for (const [id, node] of ui.tools) {
  // Sin esto, pulsar un boton le quita el foco al editor y pierde la seleccion.
  node.addEventListener('mousedown', (event) => event.preventDefault());
  node.addEventListener('click', () => {
    if (note || TOOLS_WITHOUT_NOTE.has(id)) {
      TOOL_ACTIONS[id]();
    }
  });
}

// Los dos botones de la banda devuelven el foco al editor: la banda se esconde al
// elegir, el botón con el foco desaparece, y lo siguiente que se escribía no
// llegaba a ninguna parte.
ui.bannerReload.addEventListener('click', () => {
  const text = saver.takeDisk();
  if (text !== null) {
    closeRequested = false;
    replaceDocument(text);
    showToast(mobile ? 'Recargada la versión de la PC' : 'Recargada la versión del disco');
    if (note) {
      send({ type: 'conflictResolved', path: note.path, kept: 'disk' });
    }
  }
  view.focus();
});

ui.bannerKeep.addEventListener('click', () => {
  closeRequested = false;
  saver.keepMine();
  if (note) {
    send({ type: 'conflictResolved', path: note.path, kept: 'mine' });
  }
  view.focus();
});

// ---------- navegar entre notas ----------

/** Todo lo que cambia de nota espera a que se guarde la actual. */
function navigate(message: PageMessage): void {
  switch (saver.current) {
    case 'dirty':
    case 'saving':
      pendingNavigation = message;
      saver.flush('auto');
      return;
    case 'conflict':
      showToast('Resuelve el conflicto antes de abrir otra nota', 'error');
      return;
    case 'error':
      showToast('La nota no se pudo guardar: guárdala antes de abrir otra', 'error');
      return;
    default:
      send(message);
  }
}

function openNote(path: string, line?: number): void {
  if (note?.path === path) {
    if (mobile) {
      // Es la nota que ya estaba abierta, detrás de la lista: basta con volver.
      setPane('sidebar', false);
    }
    if (line !== undefined) {
      jumpToLine(line);
    } else {
      view.focus();
    }
    return;
  }
  pendingLine = line ?? null;
  navigate({ type: 'openNote', path });
}

function openDaily(): void {
  navigate({ type: 'openDaily' });
}

async function newNote(preset?: NewNotePreset): Promise<void> {
  const answer = await askNewNote(overview?.groups ?? [], overview?.folders ?? [], preset);
  if (answer) {
    navigate({ type: 'createNote', path: answer.path, title: answer.title });
  }
}

function requestClose(): void {
  switch (saver.current) {
    case 'idle':
    case 'clean':
      send({ type: 'closeReady' });
      return;
    case 'conflict':
    case 'error':
      if (closeRequested) {
        send({ type: 'closeReady' });
        return;
      }
      closeRequested = true;
      showToast('Hay cambios sin guardar. Resuelve el aviso, o repite para descartarlos.', 'error');
      return;
    default:
      closeRequested = true;
      saver.flush('close');
  }
}

// ---------- mensajes de Rust ----------

function loadNote(next: NoteDto, nextTargets: LinkTargetDto[], theme: ThemeDto | null | undefined): void {
  if (theme) {
    applyTheme(theme);
  }
  note = next;
  targets = nextTargets;
  setCurrentNote(next.path);
  closeRequested = false;
  pendingNavigation = null;
  document.title = next.title;
  ui.title.textContent = next.title;
  ui.path.textContent = next.path;
  ui.lock.style.display = next.private ? '' : 'none';
  ui.root.dataset.empty = 'false';
  replaceDocument(next.text);
  saver.load(next.hash);
  sidebar.setCurrent(next.path);
  context.setNote(next);
  ui.editorHost.animate(
    [
      { opacity: 0.3, transform: 'translateY(6px)' },
      { opacity: 1, transform: 'none' },
    ],
    { duration: 260, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
  );
  if (mobile) {
    setPane('sidebar', false);
  }
  if (pendingLine !== null) {
    jumpToLine(pendingLine);
    pendingLine = null;
  } else if (!mobile) {
    // En el móvil no: enfocar abre el teclado y tapa media nota que se venía a
    // leer. Se escribe tocando donde se quiere.
    view.focus();
  }
}

function showOverview(next: OverviewDto): void {
  overview = next;
  sidebar.setOverview(next);
  context.setOverview(next);
  welcome.setOverview(next);
  if (!note) {
    ui.path.textContent = next.root ?? '';
  }
  if (next.error) {
    console.warn(next.error);
  }
}

function handle(message: HostMessage): void {
  switch (message.type) {
    case 'load':
      loadNote(message.note, message.targets, message.theme);
      break;
    case 'saved':
      if (note?.path === message.path) {
        saver.saved(message.hash);
      }
      break;
    case 'conflict':
      if (note?.path === message.path) {
        saver.conflicted({ diskText: message.diskText, diskHash: message.diskHash });
      }
      break;
    case 'error':
      if (saver.current === 'saving') {
        saver.failed(message.message);
      }
      pendingNavigation = null;
      pendingLine = null;
      showToast(message.message, 'error');
      break;
    case 'targets':
      targets = message.targets;
      break;
    case 'theme':
      applyTheme(message.theme);
      break;
    case 'overview':
      showOverview(message.overview);
      break;
    case 'searchResults':
      sidebar.setResults(message.query, message.hits);
      break;
    case 'details':
      context.setDetails(message.details);
      break;
    case 'notice':
      showToast(message.message);
      break;
    case 'requestClose':
      requestClose();
      break;
  }
}

onHostMessage(handle);

// ---------- arranque ----------

if (hostAvailable()) {
  send({ type: 'ready' });
} else {
  demo();
}

/** Abierta en un navegador: datos de muestra para trabajar el diseño. */
function demo(): void {
  const sample: NoteDto = {
    path: 'temas/malla.md',
    title: 'Malla',
    hash: 'muestra',
    private: false,
    text: [
      '---',
      'project: NexoDeck',
      '---',
      '# Malla',
      '',
      'La ortofoto de la **tanda R** sale deformada con la malla _2.5D_. Ver [[temas/odm|la nota de ODM]].',
      '',
      '## Tareas',
      '',
      '- [ ] Reprocesar con la malla 3D 📅 2026-09-10',
      '- [x] Avisar al equipo',
      '',
      '## Detalles',
      '',
      '> Lo que deja de ser cierto se borra.',
      '',
      '```rust',
      'fn main() { println!("hola"); }',
      '```',
    ].join('\n'),
  };
  const digest = {
    id: 'd-1',
    note: 'temas/malla.md',
    trigger: 'manual',
    state: 'proposed',
    stateDetail: null,
    proposalId: 'p-1',
    createdAt: '2026-09-15T14:05:00Z',
    modelLabel: 'deepseek-chat (deepseek)',
    hub: 'proyectos/NexoDeck.md',
    requeried: true,
    discardedIds: ['n:inventada.md#0'],
    redactions: 1,
    candidates: [
      { id: 'c:ExampleApi@abcdef1', kind: 'commit', title: 'reprocesar con malla 3D', snippet: 'La 2.5D deformaba la ortofoto.', date: '2026-09-14' },
    ],
    steps: [
      { agent: 'reader', ok: true, millis: 812, output: '{\n  "summary": "La ortofoto sale deformada"\n}', detail: null },
      { agent: 'memory#2', ok: false, millis: 40, output: null, detail: 'no es JSON valido' },
    ],
  };
  const sampleOverview: OverviewDto = {
    configured: true,
    root: 'D:\\Notas',
    notes: [
      { path: 'temas/malla.md', group: 'temas', title: 'Malla', role: 'note', date: null, tags: ['odm'], openTasks: 1, aiExcluded: false, modified: new Date().toISOString() },
      { path: 'diario/2026-09-15.md', group: null, title: '15 de septiembre de 2026', role: 'daily', date: '2026-09-15', tags: [], openTasks: 0, aiExcluded: false, modified: '2026-09-14T10:00:00Z' },
      { path: 'proyectos/NexoDeck.md', group: null, title: 'NexoDeck', role: 'hub', date: null, tags: [], openTasks: 2, aiExcluded: false, modified: '2026-09-10T10:00:00Z' },
      { path: 'temas/nomina.md', group: 'temas', title: 'Nómina', role: 'note', date: null, tags: [], openTasks: 0, aiExcluded: true, modified: '2026-09-01T10:00:00Z' },
      { path: 'inbox/2026-09-16-resumen.md', group: null, title: 'Resumen de la sesión', role: 'note', date: '2026-09-16', tags: [], openTasks: 0, aiExcluded: false, modified: '2026-09-16T09:00:00Z' },
    ],
    // Con datos de muestra para poder trabajar el diseño de las agrupaciones en
    // un navegador, sin la app.
    groups: [{ id: 'temas', name: 'Temas', colorHex: '#10B981', notes: 2 }],
    tasks: [
      { path: 'temas/malla.md', line: 10, text: 'Reprocesar con la malla 3D', done: false, due: '2026-09-10' },
      { path: 'proyectos/NexoDeck.md', line: 4, text: 'Probar el editor con la bóveda real', done: false, due: null },
    ],
    digests: [digest],
    error: null,
  };
  const sampleDetails: DetailsDto = {
    path: sample.path,
    backlinks: ['diario/2026-09-15.md'],
    related: [{ id: 'n:proyectos/NexoDeck.md#0', kind: 'note', title: 'NexoDeck › Pendiente', snippet: 'Reprocesar la tanda R con ultra.', date: null, path: 'proyectos/NexoDeck.md' }],
    digests: [digest],
  };
  handle({ type: 'overview', overview: sampleOverview });
  handle({ type: 'load', note: sample, targets: [{ target: 'temas/odm', title: 'ODM' }], theme: null });
  handle({ type: 'details', details: sampleDetails });
}
