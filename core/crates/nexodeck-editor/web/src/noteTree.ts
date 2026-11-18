// Las notas en arbol, gemelo de `app/lib/features/notes/domain/note_tree.dart`.

import { splitVirtual } from './notePaths';
import type { FolderDto, NoteSummaryDto, OverviewDto } from './protocol';

export interface TreeFolder {
  name: string;
  /** Su ruta dentro de la carpeta de notas. Vacia en la raiz. Es la clave para
   * recordar que esta abierto. */
  path: string;
  folders: TreeFolder[];
  notes: NoteSummaryDto[];
  /** Cuantas notas hay dentro, subcarpetas incluidas. */
  count: number;
}

export interface TreeRoot {
  folder: FolderDto;
  tree: TreeFolder;
}

function node(name: string, path: string): TreeFolder {
  return { name, path, folders: [], notes: [], count: 0 };
}

/** Las notas repartidas por carpeta de notas y por subcarpeta, **en el orden del
 * Explorador**: carpetas primero y despues notas, en orden natural y sin
 * distinguir mayusculas.
 *
 * Es el orden que el usuario ya tenia en su disco, y no sale de ningun sitio:
 * el indice ordena por fecha y el disco no garantiza orden. Por eso se ordena
 * aqui en cada nivel. */
/** Como se ordena el arbol: por nombre (el orden del Explorador) o por fecha,
 * de mas reciente a mas antigua y al reves. Por fecha se reordenan tambien las
 * carpetas, por la fecha de las notas que llevan dentro; por nombre se quedan
 * en orden natural, que es su orden del disco. */
export type SortMode = 'name' | 'newest' | 'oldest';

export function buildNoteTree(overview: OverviewDto, sort: SortMode = 'name'): TreeRoot[] {
  const folders: FolderDto[] =
    overview.folders && overview.folders.length > 0
      ? overview.folders
      : // Una foto sin carpetas (un binario anterior): todo a la principal.
        [{ id: '', name: 'Bóveda', path: overview.root ?? '', local: false, available: true }];
  const roots = folders.map((folder) => ({ folder, tree: node(folder.name, '') }));

  for (const note of overview.notes) {
    const [id, inner] = splitVirtual(note.path);
    const root = roots.find((r) => (id === null ? !r.folder.local : r.folder.local && r.folder.id === id));
    if (!root) {
      continue;
    }
    const segments = inner.split('/');
    let current = root.tree;
    for (const segment of segments.slice(0, -1)) {
      let child = current.folders.find((f) => f.name === segment);
      if (!child) {
        child = node(segment, current.path === '' ? segment : `${current.path}/${segment}`);
        current.folders.push(child);
      }
      current = child;
    }
    current.notes.push(note);
  }

  for (const root of roots) {
    finish(root.tree, sort);
  }
  return roots;
}

/** Lo que una rama ya ordenada le cuenta a su madre: cuantas notas lleva
 * dentro y con que fecha entra en el orden. */
interface Branch {
  count: number;
  /** La fecha que representa a la carpeta, o `null` si ninguna nota suya tiene
   * fecha. En `name` no se calcula: ahi no ordena nada. */
  time: number | null;
}

function finish(folder: TreeFolder, sort: SortMode): Branch {
  const branches = new Map<TreeFolder, Branch>();
  for (const child of folder.folders) {
    branches.set(child, finish(child, sort));
  }
  folder.notes.sort((a, b) => compareNotes(a, b, sort));
  folder.folders.sort((a, b) => compareFolders(a, b, branches, sort));
  folder.count = folder.notes.length + folder.folders.reduce((sum, child) => sum + (branches.get(child)?.count ?? 0), 0);
  return { count: folder.count, time: folderTime(folder, branches, sort) };
}

/** Por fecha, las carpetas se reordenan con sus notas: la que tiene el cambio
 * mas reciente sube, aunque el cambio este en una subcarpeta suya. Si no, el
 * usuario ve la nota recien tocada escondida en la ultima carpeta de la lista,
 * que es justo lo que este orden viene a evitar. En `name` mandan los nombres:
 * ahi la carpeta es estructura, no contenido. */
function compareFolders(a: TreeFolder, b: TreeFolder, branches: Map<TreeFolder, Branch>, sort: SortMode): number {
  if (sort !== 'name') {
    const at = branches.get(a)?.time ?? null;
    const bt = branches.get(b)?.time ?? null;
    // Sin ninguna nota con fecha, al final, igual que una nota sin fecha.
    if (at === null && bt !== null) return 1;
    if (bt === null && at !== null) return -1;
    if (at !== null && bt !== null && at !== bt) {
      return sort === 'newest' ? bt - at : at - bt;
    }
  }
  return compareNatural(a.name, b.name);
}

/** La fecha con la que una carpeta entra en el orden: la de su nota mas
 * reciente —o mas antigua, segun el modo—, contando las de sus subcarpetas. */
function folderTime(folder: TreeFolder, branches: Map<TreeFolder, Branch>, sort: SortMode): number | null {
  if (sort === 'name') {
    return null;
  }
  const times = [
    ...folder.notes.map(noteTime),
    ...folder.folders.map((child) => branches.get(child)?.time ?? null),
  ];
  let best: number | null = null;
  for (const time of times) {
    if (time === null) {
      continue;
    }
    if (best === null || (sort === 'oldest' ? time < best : time > best)) {
      best = time;
    }
  }
  return best;
}

/** Una lista plana de notas en el mismo orden, sin mutarla (el filtro de
 * agrupacion no usa el arbol). */
export function sortNotes(notes: NoteSummaryDto[], sort: SortMode): NoteSummaryDto[] {
  return [...notes].sort((a, b) => compareNotes(a, b, sort));
}

function compareNotes(a: NoteSummaryDto, b: NoteSummaryDto, sort: SortMode): number {
  if (sort === 'name') {
    return compareNatural(fileName(a.path), fileName(b.path));
  }
  const at = noteTime(a);
  const bt = noteTime(b);
  if (at === null && bt === null) {
    return compareNatural(fileName(a.path), fileName(b.path));
  }
  // Sin fecha, al final: no se puede saber si es nueva o vieja.
  if (at === null) return 1;
  if (bt === null) return -1;
  return sort === 'newest' ? bt - at : at - bt;
}

/** La fecha para ordenar una nota: la de modificacion, y si no, la del diario. */
function noteTime(note: NoteSummaryDto): number | null {
  const raw = note.modified ?? note.date;
  if (!raw) return null;
  const time = Date.parse(raw);
  return Number.isNaN(time) ? null : time;
}

function fileName(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1);
}

/** Orden natural sin distinguir mayusculas: `nota 2` antes que `nota 10`. */
export function compareNatural(a: string, b: string): number {
  const chunks = /\d+|\D+/g;
  const left = a.toLowerCase().match(chunks) ?? [];
  const right = b.toLowerCase().match(chunks) ?? [];
  for (let i = 0; i < left.length && i < right.length; i++) {
    const x = left[i];
    const y = right[i];
    const numeric = /^\d/.test(x) && /^\d/.test(y);
    const order = numeric ? Number(x) - Number(y) : x < y ? -1 : x > y ? 1 : 0;
    if (order !== 0) {
      return Math.sign(order);
    }
  }
  return Math.sign(left.length - right.length);
}
