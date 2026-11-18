// La barra lateral: buscar en toda la boveda, y las pestañas de notas, tareas
// abiertas y lo que hizo el asistente.

import {
  ArrowDownAZ,
  CalendarDays,
  CalendarPlus,
  EllipsisVertical,
  EyeOff,
  FileArchive,
  FolderInput,
  FolderMinus,
  FolderOpen,
  FilePlus,
  FileText,
  Folder,
  FolderKanban,
  FolderSymlink,
  GitCommitHorizontal,
  GripVertical,
  Inbox,
  type IconNode,
  Lightbulb,
  ListChecks,
  NotebookPen,
  Plus,
  RefreshCw,
  Search,
  SortAsc,
  SortDesc,
  Sparkles,
  X,
} from 'lucide';

import { renderDigest } from './digestView';
import { button, el, icon } from './dom';
import { hitKindLabel, isDigestActive, isOverdue, relativeDay, sortTasks } from './labels';
import { openMenu, openPicker, type PickerItem } from './menu';
import { revealInStrip, scrollStrip } from './scrollStrip';
import { inFolder, INBOX_DIR, isPrivatePath, splitVirtual } from './notePaths';
import { buildNoteTree, sortNotes, type SortMode, type TreeFolder, type TreeRoot } from './noteTree';
import type { NewNotePreset } from './newNoteDialog';
import type { GroupDto, HitDto, NoteSummaryDto, OverviewDto, TaskDto } from './protocol';

/** `#RRGGBB`. El color de una agrupación sale de la configuración, que se puede
 * editar a mano: lo que no case no entra en el estilo. Mismo criterio que
 * `theme.ts` con los colores del tema. */
const HEX = /^#[0-9a-fA-F]{6}$/;

/** El filtro "sin agrupar". Ningún id de agrupación puede estar vacío: es el
 * nombre de una carpeta. */
const UNGROUPED = '';

/** La agrupación de una nota, si la tiene y todavía existe. */
export function groupFor(overview: OverviewDto | null, note: NoteSummaryDto): GroupDto | undefined {
  if (!overview || note.group === null) {
    return undefined;
  }
  return overview.groups.find((group) => group.id === note.group);
}

/** El destino al soltar una nota sobre una carpeta del arbol. Solo el primer
 * nivel mueve (una agrupacion es una carpeta de primer nivel): `null` es la
 * bandeja, y `undefined` que esa carpeta no es un destino valido. */
function moveGroup(folder: TreeFolder, groups: GroupDto[]): string | null | undefined {
  if (folder.path.includes('/')) {
    return undefined;
  }
  if (folder.name.toLowerCase() === INBOX_DIR) {
    return null;
  }
  return groups.some((group) => group.id === folder.name) ? folder.name : undefined;
}

export type SidebarTab = 'notes' | 'tasks' | 'assistant';

export const SIDEBAR_TABS: readonly SidebarTab[] = ['notes', 'tasks', 'assistant'];

const TABS: Array<{ id: SidebarTab; label: string; icon: IconNode }> = [
  { id: 'notes', label: 'Notas', icon: FileText },
  { id: 'tasks', label: 'Tareas', icon: ListChecks },
  { id: 'assistant', label: 'Asistente', icon: Sparkles },
];

const SORT_SPECS: ReadonlyArray<{ id: SortMode; label: string; icon: IconNode }> = [
  { id: 'name', label: 'Por nombre', icon: ArrowDownAZ },
  { id: 'newest', label: 'Más recientes primero', icon: SortDesc },
  { id: 'oldest', label: 'Más antiguas primero', icon: SortAsc },
];

const NEXT_SORT: Record<SortMode, SortMode> = { name: 'newest', newest: 'oldest', oldest: 'name' };

const HIT_ICONS: Record<string, IconNode> = {
  note: FileText,
  finding: Lightbulb,
  commit: GitCommitHorizontal,
};

/** Cuantas filas entran con animacion escalonada; el resto aparece de golpe. */
const STAGGERED_ROWS = 18;

export function roleIcon(role: string): IconNode {
  switch (role) {
    case 'daily':
      return CalendarDays;
    case 'hub':
      return FolderKanban;
    default:
      return FileText;
  }
}

function row(iconNode: IconNode | Node, index: number, ...children: Array<Node | string>): HTMLButtonElement {
  const glyph = iconNode instanceof Node ? iconNode : icon(iconNode);
  const node = button('row', el('span', 'row-icon', glyph), ...children);
  node.style.setProperty('--i', String(Math.min(index, STAGGERED_ROWS)));
  return node;
}

/** Una nota en una lista. La usan la barra lateral y la pantalla de bienvenida. */
export function noteRow(
  note: NoteSummaryDto,
  index: number,
  onOpen: (path: string) => void,
  group?: GroupDto,
): HTMLButtonElement {
  const meta = el('span', 'row-meta');
  if (group) {
    meta.append(el('span', 'group-name', group.name));
  }
  if (note.aiExcluded) {
    meta.append(el('span', 'flag', icon(EyeOff), 'sin IA'));
  }
  const when = relativeDay(note.modified ?? note.date, new Date());
  if (when) {
    meta.append(el('span', undefined, when));
  }
  if (note.openTasks > 0) {
    meta.append(el('span', undefined, `${note.openTasks} ${note.openTasks === 1 ? 'tarea' : 'tareas'}`));
  }
  for (const tag of note.tags.slice(0, 2)) {
    meta.append(el('span', 'tag', `#${tag}`));
  }
  const node = row(roleIcon(note.role), index, el('span', 'row-title', note.title), meta);
  // El color no va como relleno ni como color de texto: se mezcla con el fondo
  // del tema en el CSS (`color-mix`), que es lo que lo hace legible en claro y
  // en oscuro sin calcular contraste.
  if (group && HEX.test(group.colorHex)) {
    node.style.setProperty('--group', group.colorHex);
    node.classList.add('grouped');
  }
  node.dataset.path = note.path;
  node.title = note.path;
  node.addEventListener('click', () => onOpen(note.path));
  return node;
}

function empty(title: string, detail?: string): HTMLElement {
  return el('div', 'side-empty', el('strong', undefined, title), ...(detail ? [el('p', undefined, detail)] : []));
}

function skeletons(count: number): HTMLElement[] {
  return Array.from({ length: count }, () => el('div', 'skeleton'));
}

export interface SidebarActions {
  openNote(path: string, line?: number): void;
  search(query: string): void;
  showInbox(): void;
  openDaily(): void;
  newNote(preset?: NewNotePreset): void;
  refresh(): void;
  tabChanged(tab: SidebarTab): void;
  sortChanged(sort: SortMode): void;
  moveNote(path: string, group: string | null): void;
  chooseVault(): void;
  importLocalFolder(): void;
  importOneNote(): void;
  removeLocalFolder(id: string): void;
  exportVault(): void;
}

export class Sidebar {
  readonly element: HTMLElement;
  private readonly input: HTMLInputElement;
  private readonly searchBox: HTMLElement;
  private readonly list: HTMLElement;
  private readonly tabButtons = new Map<SidebarTab, HTMLButtonElement>();
  private readonly counts = new Map<SidebarTab, HTMLElement>();
  private tab: SidebarTab;
  private sort: SortMode;
  private readonly sortButton: HTMLButtonElement;
  private overview: OverviewDto | null = null;
  private signature = '';
  private query = '';
  private hits: HitDto[] | null = null;
  private current: string | null = null;
  /** `null` = todas; `UNGROUPED` = la bandeja; si no, el id de la agrupación. */
  private groupFilter: string | null = null;
  /** Subcarpetas abiertas, por `carpeta:ruta`. Viven aqui y no en el DOM porque
   * `render` redibuja la lista entera con cada foto de la boveda. */
  private readonly openFolders = new Set<string>();
  /** Carpetas de notas cerradas a mano, por id: empiezan abiertas. */
  private readonly closedRoots = new Set<string>();
  /** Hasta donde se desplazo la barra de agrupaciones, que se redibuja entera. */
  private groupScroll = 0;
  private timer: number | undefined;

  constructor(
    private readonly actions: SidebarActions,
    initialTab: SidebarTab,
    /** En el movil no hay asistente ni gestion de carpetas: son de la PC. */
    private readonly mobile = false,
    initialSort: SortMode = 'name',
  ) {
    this.tab = mobile && initialTab === 'assistant' ? 'notes' : initialTab;
    this.sort = initialSort;

    this.input = el('input', 'search-input');
    this.input.type = 'text';
    this.input.placeholder = 'Buscar en notas, hallazgos y commits';
    this.input.spellcheck = false;
    this.input.setAttribute('aria-label', 'Buscar en la bóveda');
    const clear = button('search-clear', icon(X));
    clear.setAttribute('aria-label', 'Borrar la búsqueda');
    clear.addEventListener('click', () => {
      this.setQuery('');
      this.input.focus();
    });
    this.searchBox = el('label', 'search', icon(Search), this.input, clear);
    this.searchBox.dataset.empty = 'true';

    // Las carpetas de notas se gestionan aqui, en la misma ventana: antes solo
    // desde un dialogo de la app al que no se llegaba con esta ventana abierta.
    const more = button('search-menu', icon(EllipsisVertical));
    more.setAttribute('aria-label', 'Carpetas de notas');
    more.setAttribute('aria-haspopup', 'menu');
    more.dataset.tip = 'Carpetas de notas';
    more.addEventListener('click', () =>
      openMenu(more, [
        {
          label: 'Importar notas locales…',
          detail: 'Una carpeta con tus .md, leída en su sitio',
          icon: FolderInput,
          run: () => actions.importLocalFolder(),
        },
        {
          label: 'Importar desde OneNote…',
          detail: 'Un cuaderno .one, con sus imágenes',
          icon: NotebookPen,
          run: () => actions.importOneNote(),
        },
        {
          label: 'Importar espacio de NexoDeck…',
          detail: 'La carpeta principal de notas',
          icon: FolderOpen,
          run: () => actions.chooseVault(),
        },
        {
          label: 'Exportar notas…',
          detail: 'La carpeta principal en un .zip, por carpetas',
          icon: FileArchive,
          run: () => actions.exportVault(),
        },
      ]),
    );
    this.sortButton = button('search-menu');
    this.applySortButton();
    this.sortButton.addEventListener('click', () => this.cycleSort());

    const searchRow = el('div', 'search-row', this.searchBox, this.sortButton, ...(mobile ? [] : [more]));
    this.input.addEventListener('input', () => {
      this.searchBox.dataset.empty = String(this.input.value === '');
      window.clearTimeout(this.timer);
      this.timer = window.setTimeout(() => this.setQuery(this.input.value), 260);
    });
    this.input.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && this.input.value !== '') {
        event.preventDefault();
        event.stopPropagation();
        this.setQuery('');
      } else if (event.key === 'Enter') {
        window.clearTimeout(this.timer);
        this.setQuery(this.input.value);
      } else if (event.key === 'ArrowDown') {
        event.preventDefault();
        this.list.querySelector<HTMLElement>('button')?.focus();
      }
    });

    const tabs = el('div', 'tabs');
    tabs.setAttribute('role', 'tablist');
    for (const spec of TABS.filter((t) => !(mobile && t.id === 'assistant'))) {
      const count = el('span', 'tab-count');
      const tab = button('tab', icon(spec.icon), el('span', undefined, spec.label), count);
      tab.setAttribute('role', 'tab');
      tab.addEventListener('click', () => this.select(spec.id));
      this.tabButtons.set(spec.id, tab);
      this.counts.set(spec.id, count);
      tabs.append(tab);
    }

    this.list = el('div', 'side-list');

    const daily = button('chip', icon(CalendarPlus), 'Nota de hoy');
    daily.addEventListener('click', () => actions.openDaily());
    const create = button('chip', icon(FilePlus), 'Nota nueva');
    create.addEventListener('click', () => actions.newNote());
    const refresh = button('chip icon-only', icon(RefreshCw));
    refresh.setAttribute('aria-label', 'Volver a leer la bóveda');
    refresh.dataset.tip = 'Volver a leer la bóveda';
    refresh.addEventListener('click', () => {
      refresh.classList.remove('spin-once');
      void refresh.offsetWidth;
      refresh.classList.add('spin-once');
      actions.refresh();
    });

    this.element = el('aside', 'sidebar', searchRow, scrollStrip(tabs, 'pestañas'), this.list, el('div', 'side-footer', daily, create, refresh));
    this.select(this.tab, false);
  }

  focusSearch(): void {
    this.input.focus();
    this.input.select();
  }

  private cycleSort(): void {
    this.sort = NEXT_SORT[this.sort];
    this.actions.sortChanged(this.sort);
    this.applySortButton();
    this.render(true);
  }

  private applySortButton(): void {
    const spec = SORT_SPECS.find((s) => s.id === this.sort) ?? SORT_SPECS[0];
    this.sortButton.replaceChildren(icon(spec.icon));
    this.sortButton.setAttribute('aria-label', `Ordenar notas: ${spec.label}`);
    this.sortButton.dataset.tip = `Ordenar notas: ${spec.label.toLowerCase()}`;
  }

  /** Una nota con su menu de clic derecho y su asa para arrastrarla a otra
   * carpeta. El asa es solo la señal: se arrastra desde cualquier parte. */
  private noteNode(note: NoteSummaryDto, index: number, group?: GroupDto): HTMLButtonElement {
    const node = noteRow(note, index, (path) => this.actions.openNote(path), group);
    node.classList.add('draggable');
    node.draggable = true;
    node.append(el('span', 'drag-handle', icon(GripVertical)));
    node.addEventListener('dragstart', (event) => {
      if (!event.dataTransfer) return;
      event.dataTransfer.setData('text/plain', note.path);
      event.dataTransfer.effectAllowed = 'move';
      node.classList.add('dragging');
    });
    node.addEventListener('dragend', () => node.classList.remove('dragging'));
    node.addEventListener('contextmenu', (event) => {
      event.preventDefault();
      this.openNoteMenu(note, { x: event.clientX, y: event.clientY });
    });
    return node;
  }

  /** Marca una carpeta (de primer nivel) como destino de soltado. `group` es el
   * nombre de la agrupacion de destino, o `null` para la bandeja. */
  private bindDropTarget(target: HTMLElement, group: string | null): void {
    target.addEventListener('dragenter', (event) => {
      event.preventDefault();
      target.classList.add('drop-target');
    });
    target.addEventListener('dragover', (event) => {
      event.preventDefault();
      if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    });
    target.addEventListener('dragleave', (event) => {
      const related = event.relatedTarget as Node | null;
      if (!related || !target.contains(related)) {
        target.classList.remove('drop-target');
      }
    });
    target.addEventListener('drop', (event) => {
      event.preventDefault();
      target.classList.remove('drop-target');
      const path = event.dataTransfer?.getData('text/plain');
      if (path) {
        this.actions.moveNote(path, group);
      }
    });
  }

  /** El "+" al final de la fila de una carpeta: crear una nota ahi mismo. */
  private addNoteButton(root: TreeRoot, folder: TreeFolder): HTMLButtonElement {
    const node = button('tree-add', icon(Plus));
    node.setAttribute('aria-label', `Nueva nota en ${folder.name}`);
    node.title = `Nueva nota en ${folder.name}`;
    // El summary abre y cierra la carpeta: el "+" no puede hacer eso.
    node.addEventListener('mousedown', (event) => event.preventDefault());
    node.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.actions.newNote({
        folder: root.folder.local ? root.folder.id : '',
        group: folder.path.split('/')[0] ?? '',
        basePath: folder.path,
      });
    });
    return node;
  }

  private openNoteMenu(note: NoteSummaryDto, point: { x: number; y: number }): void {
    const privatePath = isPrivatePath(note.path);
    openMenu(point, [
      {
        label: privatePath ? 'Quitar de privado' : 'Mover a privado',
        detail: privatePath ? 'Vuelve a la bandeja' : 'Ningún agente la lee',
        icon: EyeOff,
        run: () => this.actions.moveNote(note.path, privatePath ? null : 'privado'),
      },
      {
        label: 'Mover a…',
        detail: 'Elige una carpeta',
        icon: FolderInput,
        run: () => this.openMovePicker(note, point),
      },
    ]);
  }

  private openMovePicker(note: NoteSummaryDto, point: { x: number; y: number }): void {
    const groups = this.overview?.groups ?? [];
    const items: PickerItem[] = [
      { label: 'Bandeja', hint: 'inbox', icon: Inbox, run: () => this.actions.moveNote(note.path, null) },
      { label: 'Privado', hint: 'privado', icon: EyeOff, run: () => this.actions.moveNote(note.path, 'privado') },
      ...groups.map((group) => ({
        label: group.name,
        hint: group.id,
        icon: Folder,
        run: () => this.actions.moveNote(note.path, group.id),
      })),
    ];
    openPicker(point, 'Mover a…', items);
  }

  setOverview(overview: OverviewDto): void {
    const signature = JSON.stringify(overview);
    if (signature === this.signature) {
      return;
    }
    const first = this.overview === null;
    this.signature = signature;
    this.overview = overview;
    this.counts.get('notes')!.textContent = String(overview.notes.length);
    this.counts.get('tasks')!.textContent = String(overview.tasks.length);
    const active = overview.digests.filter((digest) => isDigestActive(digest.state)).length;
    // En el movil la pestaña del asistente no existe.
    const assistant = this.counts.get('assistant');
    if (assistant) {
      assistant.textContent = String(active > 0 ? active : overview.digests.length);
      assistant.classList.toggle('busy', active > 0);
    }
    this.render(first);
  }

  setCurrent(path: string | null): void {
    this.current = path;
    this.list.querySelectorAll<HTMLElement>('[data-path]').forEach((node) => {
      const active = node.dataset.path === path;
      node.classList.toggle('active', active);
      // En el arbol, la nota abierta no puede quedar dentro de una rama plegada.
      for (let branch = node.parentElement?.closest('details'); active && branch; branch = branch.parentElement?.closest('details')) {
        branch.open = true;
      }
    });
  }

  setResults(query: string, hits: HitDto[]): void {
    if (query.trim() !== this.query) {
      return;
    }
    this.hits = hits;
    this.render(true);
  }

  private setQuery(raw: string): void {
    if (this.input.value !== raw) {
      this.input.value = raw;
    }
    this.searchBox.dataset.empty = String(raw === '');
    const query = raw.trim();
    if (query === this.query) {
      return;
    }
    this.query = query;
    this.hits = null;
    this.actions.search(query);
    this.render(true);
  }

  private select(tab: SidebarTab, notify = true): void {
    this.tab = tab;
    for (const [id, node] of this.tabButtons) {
      node.setAttribute('aria-selected', String(id === tab));
    }
    // La pestaña elegida (con el atajo o desde otra parte) no puede quedar oculta.
    revealInStrip(this.tabButtons.get(tab));
    if (notify) {
      this.actions.tabChanged(tab);
    }
    this.render(true);
  }

  /** `animate` en un cambio de pestaña o de busqueda; no en un refresco, que
   * llega con cada guardado y haria bailar la lista. */
  private render(animate: boolean): void {
    const scroll = this.list.scrollTop;
    this.list.dataset.animate = String(animate);
    this.list.replaceChildren(...this.content());
    this.list.scrollTop = animate ? 0 : scroll;
    // La barra de agrupaciones se redibuja con cada clic y cada foto: sin esto,
    // elegir una agrupacion que estaba a la derecha la volveria a esconder.
    const bar = this.list.querySelector<HTMLElement>('.group-bar');
    if (bar) {
      bar.scrollLeft = this.groupScroll;
    }
    this.setCurrent(this.current);
  }

  private content(): Node[] {
    const overview = this.overview;
    if (!overview) {
      return skeletons(5);
    }
    if (!overview.configured) {
      return [
        empty(
          'No hay ninguna bóveda configurada',
          'Pulsa ⋮ junto al buscador y elige «Importar espacio de NexoDeck…».',
        ),
      ];
    }
    if (this.query !== '') {
      return this.searchContent();
    }
    switch (this.tab) {
      case 'notes':
        return this.notesContent(overview);
      case 'tasks':
        return this.tasksContent(overview);
      case 'assistant':
        return this.assistantContent(overview);
    }
  }

  private notesContent(overview: OverviewDto): Node[] {
    if (overview.notes.length === 0) {
      return [empty('La bóveda está vacía', 'Empieza con la nota de hoy.')];
    }
    // Un filtro que apunta a una agrupación que ya no existe (su carpeta se
    // borró por fuera) se olvida, en vez de dejar la lista vacía sin explicar.
    if (this.groupFilter && !overview.groups.some((group) => group.id === this.groupFilter)) {
      this.groupFilter = null;
    }
    const filter = this.groupFilter;
    // Sin filtro, el arbol: es como el usuario ordeno sus carpetas. Con un
    // filtro, la lista plana, porque una agrupacion ya es una sola carpeta.
    if (filter === null) {
      return [this.groupBar(overview), ...this.treeContent(overview)];
    }
    const notes = overview.notes.filter((note) =>
      filter === null ? true : filter === UNGROUPED ? note.group === null : note.group === filter,
    );
    const rows = sortNotes(notes, this.sort).map((note, index) => this.noteNode(note, index, groupFor(overview, note)));
    return [
      this.groupBar(overview),
      ...(rows.length > 0
        ? rows
        : [empty('No hay notas aquí', filter === UNGROUPED ? 'Todas tus notas están agrupadas.' : 'Esta agrupación está vacía.')]),
    ];
  }

  /** Una rama por carpeta de notas y, dentro, sus subcarpetas en el orden del
   * disco. La subcarpeta que contiene la nota abierta se abre sola: abrir una
   * nota no puede dejarla escondida en una rama plegada. */
  private treeContent(overview: OverviewDto): Node[] {
    let index = 0;
    const leaf = (note: NoteSummaryDto) => this.noteNode(note, index++, groupFor(overview, note));

    const branch = (root: TreeRoot, folder: TreeFolder): Node[] => [
      ...folder.folders.map((child) => subfolder(root, child)),
      ...folder.notes.map(leaf),
    ];

    const subfolder = (root: TreeRoot, folder: TreeFolder): HTMLElement => {
      const key = `${root.folder.id}:${folder.path}`;
      const prefix = inFolder(`${folder.path}/`, root.folder.local ? root.folder.id : null);
      const node = el('details', 'tree-folder');
      node.open = this.openFolders.has(key) || (this.current?.startsWith(prefix) ?? false);
      const summary = el(
        'summary',
        undefined,
        icon(Folder),
        el('span', 'tree-name', folder.name),
        el('span', 'tree-count', String(folder.count)),
      );
      summary.append(this.addNoteButton(root, folder));
      node.append(summary, el('div', 'tree-children', ...branch(root, folder)));
      node.addEventListener('toggle', () => {
        if (node.open) {
          this.openFolders.add(key);
        } else {
          this.openFolders.delete(key);
        }
      });
      const target = moveGroup(folder, overview.groups);
      if (target !== undefined) {
        this.bindDropTarget(node, target);
      }
      return node;
    };

    return buildNoteTree(overview, this.sort).map((root) => {
      const { folder } = root;
      const summary = el(
        'summary',
        undefined,
        icon(folder.local ? FolderSymlink : FolderKanban),
        el('span', 'tree-name', folder.name),
      );
      // Lo que pidio el usuario: una etiqueta sutil que diga que estas notas
      // viven en su propia ruta y no se copian.
      if (folder.local) {
        summary.append(el('span', 'tree-tag', 'Notas locales'));
      }
      if (!folder.available) {
        summary.append(el('span', 'tree-tag warn', 'No disponible'));
      }
      summary.title = folder.path;
      // Clic derecho sobre una carpeta local para quitarla (decision del
      // usuario). La principal no se quita: se cambia desde el menu.
      // En el movil una pulsacion larga tambien es `contextmenu`: ahi no se ofrece,
      // las carpetas se gestionan en la PC.
      if (folder.local && !this.mobile) {
        summary.addEventListener('contextmenu', (event) => {
          event.preventDefault();
          openMenu({ x: event.clientX, y: event.clientY }, [
            {
              label: 'Quitar de NexoDeck',
              detail: 'Sus ficheros siguen en el disco',
              icon: FolderMinus,
              run: () => this.actions.removeLocalFolder(folder.id),
            },
          ]);
        });
      }
      const node = el('details', 'tree-root');
      node.open = !this.closedRoots.has(folder.id);
      summary.append(this.addNoteButton(root, root.tree));
      const children: Node[] = !folder.available
        ? [empty('La carpeta no está disponible', 'Quizá un disco desconectado. Sus notas vuelven solas cuando vuelva.')]
        : root.tree.count === 0
          ? [empty('Sin notas todavía')]
          : branch(root, root.tree);
      node.append(summary, el('div', 'tree-children', ...children));
      node.addEventListener('toggle', () => {
        if (node.open) {
          this.closedRoots.delete(folder.id);
        } else {
          this.closedRoots.add(folder.id);
        }
      });
      return node;
    });
  }

  /** "Todas", la bandeja y un chip por agrupación. Mismo lenguaje que la barra
   * de grupos del deck: un punto de color. */
  private groupBar(overview: OverviewDto): HTMLElement {
    const bar = el('div', 'group-bar');
    bar.setAttribute('role', 'toolbar');
    bar.setAttribute('aria-label', 'Filtrar por agrupación');
    const chip = (label: string, value: string | null, color?: string, glyph?: IconNode): HTMLButtonElement => {
      const children: Array<Node | string> = [];
      if (glyph) {
        children.push(icon(glyph));
      }
      if (color && HEX.test(color)) {
        const dot = el('span', 'group-dot');
        dot.style.setProperty('--group', color);
        children.push(dot);
      }
      children.push(label);
      const node = button('group-chip', ...children);
      node.setAttribute('aria-pressed', String(this.groupFilter === value));
      node.addEventListener('click', () => {
        // Volver a pulsar el filtro elegido lo quita.
        this.groupFilter = this.groupFilter === value ? null : value;
        this.render(true);
      });
      return node;
    };
    const ungrouped = overview.notes.filter((note) => note.group === null).length;
    bar.append(chip('Todas', null), chip(`Bandeja · ${ungrouped}`, UNGROUPED, undefined, Inbox));
    for (const group of overview.groups) {
      // Dos carpetas pueden tener cada una su `clientes`: el chip dice de cual.
      const [folderId] = splitVirtual(group.id);
      const folder = folderId ? overview.folders?.find((f) => f.local && f.id === folderId) : undefined;
      const label = folderId ? `${group.name} · ${folder?.name ?? folderId}` : group.name;
      bar.append(chip(`${label} · ${group.notes}`, group.id, group.colorHex));
    }
    bar.addEventListener('scroll', () => (this.groupScroll = bar.scrollLeft), { passive: true });
    return scrollStrip(bar, 'agrupaciones');
  }

  private tasksContent(overview: OverviewDto): Node[] {
    if (overview.tasks.length === 0) {
      return [empty('No hay tareas abiertas', 'Las casillas `- [ ]` de tus notas aparecen aquí.')];
    }
    const titles = new Map(overview.notes.map((note) => [note.path, note.title]));
    const today = new Date();
    return sortTasks(overview.tasks, today).map((task: TaskDto, index) => {
      const meta = el('span', 'row-meta', el('span', undefined, titles.get(task.path) ?? task.path));
      if (task.due) {
        meta.append(el('span', isOverdue(task.due, today) ? 'overdue' : undefined, task.due));
      }
      const node = row(el('span', 'task-dot'), index, el('span', 'row-title wrap', task.text), meta);
      node.classList.add('task');
      node.dataset.path = task.path;
      node.addEventListener('click', () => this.actions.openNote(task.path, task.line));
      return node;
    });
  }

  private assistantContent(overview: OverviewDto): Node[] {
    if (overview.digests.length === 0) {
      return [
        empty(
          'El asistente todavía no procesó ninguna nota',
          'Abre una nota y usa «Procesar nota» en el panel de la derecha.',
        ),
      ];
    }
    const titles = new Map(overview.notes.map((note) => [note.path, note.title]));
    return overview.digests.map((digest, index) => {
      const card = renderDigest(digest, {
        noteTitle: titles.get(digest.note) ?? digest.note,
        onOpenNote: () => this.actions.openNote(digest.note),
        onShowInbox: () => this.actions.showInbox(),
      });
      card.style.setProperty('--i', String(Math.min(index, STAGGERED_ROWS)));
      return card;
    });
  }

  private searchContent(): Node[] {
    const heading = el('p', 'side-heading', 'Resultados');
    if (this.hits === null) {
      return [heading, ...skeletons(3)];
    }
    if (this.hits.length === 0) {
      return [heading, empty(`Nada para «${this.query}»`, 'Busca por palabras: se comparan sin tildes y por su raíz.')];
    }
    return [
      heading,
      ...this.hits.map((hit, index) => {
        const meta = el('span', 'row-meta', el('span', undefined, hitKindLabel(hit.kind)));
        if (hit.date) {
          meta.append(el('span', undefined, hit.date));
        }
        const node = row(
          HIT_ICONS[hit.kind] ?? FileText,
          index,
          el('span', 'row-title', hit.title),
          el('span', 'row-snippet', hit.snippet),
          meta,
        );
        const path = hit.path;
        if (path) {
          node.dataset.path = path;
          node.addEventListener('click', () => this.actions.openNote(path));
        } else {
          node.classList.add('static');
        }
        return node;
      }),
    ];
  }
}
