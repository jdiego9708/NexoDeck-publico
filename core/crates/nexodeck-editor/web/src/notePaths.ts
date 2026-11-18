// Rutas de notas nuevas. Rust las vuelve a comprobar (y ademas los junctions):
// esto es para decirlo en el dialogo y no con un error despues de crear.

/** La ruta relativa a la boveda y con `.md`, o `null` si no vale. */
export function normalizeNewNotePath(input: string): string | null {
  let path = input.trim().replaceAll('\\', '/');
  while (path.startsWith('/')) {
    path = path.slice(1);
  }
  if (path.toLowerCase().endsWith('.md')) {
    path = path.slice(0, -3);
  }
  if (path === '' || path.includes(':')) {
    return null;
  }
  const invalid = path
    .split('/')
    .some((segment) => segment.trim() === '' || segment === '..' || segment.startsWith('.'));
  return invalid ? null : `${path}.md`;
}

/** Una ruta a partir del titulo, mientras el usuario no escriba la suya. */
export function suggestNotePath(title: string): string {
  return title
    .trim()
    .toLowerCase()
    .replace(/[<>:"/\\|?*#^[\]]/g, '')
    .replace(/\s+/g, '-');
}

/** La carpeta de las notas sin agrupacion. Es la misma que usa `save_note` desde
 * Claude Code: dos reglas distintas para "donde cae una nota nueva" confundirian. */
export const INBOX_DIR = 'inbox';

/** La ruta de una nota nueva dentro de su agrupacion, o de la bandeja sin ella.
 * Vacia mientras no haya titulo, para que se vea el ejemplo del campo. */
export function suggestPathInGroup(title: string, group: string): string {
  const slug = suggestNotePath(title);
  return slug === '' ? '' : `${group || INBOX_DIR}/${slug}`;
}

/** Cambia la agrupacion de una ruta que el usuario ya escribio a mano.
 *
 * Solo toca la primera carpeta si es la bandeja o una agrupacion conocida: una
 * ruta en `privado/` o en `diario/` es una decision suya, y cambiar de grupo no
 * puede sacarla de ahi en silencio. */
export function regroupPath(path: string, group: string, known: readonly string[]): string {
  const parts = path.replaceAll('\\', '/').split('/');
  if (parts.length < 2) {
    return path;
  }
  const head = parts[0].toLowerCase();
  if (head !== INBOX_DIR && !known.includes(head)) {
    return path;
  }
  parts[0] = group || INBOX_DIR;
  return parts.join('/');
}

/** Las notas de una carpeta local se nombran `@<id>/<ruta>`. Es el mismo prefijo
 * que `nexodeck-docs` (`notes/roots.rs`); la regla se repite aqui porque la
 * pagina no puede preguntar a Rust por cada tecla. */
export const LOCAL_PREFIX = '@';

/** `[carpeta local o null, ruta dentro de ella]`. */
export function splitVirtual(path: string): [string | null, string] {
  if (!path.startsWith(LOCAL_PREFIX)) {
    return [null, path];
  }
  const slash = path.indexOf('/');
  return slash < 0 ? [null, path] : [path.slice(1, slash), path.slice(slash + 1)];
}

/** La ruta de [inner] dentro de la carpeta [folder] (`null` = la principal). */
export function inFolder(inner: string, folder: string | null): string {
  return folder ? `${LOCAL_PREFIX}${folder}/${inner}` : inner;
}

/** Como escribir un enlace a [target] desde la nota [source], igual que
 * `link_form` en Rust: dentro de la misma carpeta, relativo a ella —asi la
 * carpeta sigue abriendose bien en Obsidian—; entre carpetas, la ruta virtual. */
export function linkForm(target: string, source: string | null | undefined): string {
  const [targetFolder, targetInner] = splitVirtual(target);
  const [sourceFolder] = splitVirtual(source ?? '');
  return targetFolder !== null && targetFolder === sourceFolder ? targetInner : target;
}

/** El nombre que se sugiere al exportar: `notas-AAAA-MM-DD.zip`, con la fecha
 * local. Con la fecha, dos exportaciones de dias distintos no se pisan. */
export function exportFileName(now: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `notas-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.zip`;
}

/** Esta en `privado/` (a cualquier nivel): ningun agente la lee. */
export function isPrivatePath(path: string): boolean {
  return path.replaceAll('\\', '/').toLowerCase().split('/').includes('privado');
}
