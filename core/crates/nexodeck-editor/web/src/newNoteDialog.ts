// Titulo y ruta de una nota nueva. La ruta sale del titulo mientras el usuario
// no escriba la suya.

import { Lock } from 'lucide';

import { button, el, icon } from './dom';
import {
  LOCAL_PREFIX,
  inFolder,
  isPrivatePath,
  normalizeNewNotePath,
  regroupPath,
  splitVirtual,
  suggestPathInGroup,
} from './notePaths';
import type { FolderDto, GroupDto } from './protocol';

export interface NewNote {
  path: string;
  title: string;
}

/** Con que carpeta abre el dialogo cuando se pulsa el "+" de una carpeta del
 * arbol. `basePath` es la ruta de la carpeta dentro de su raiz: es lo que
 * decide donde cae la nota, tambien en una subcarpeta. */
export interface NewNotePreset {
  folder: string;
  group: string;
  basePath: string;
}

export function askNewNote(
  groups: readonly GroupDto[] = [],
  folders: readonly FolderDto[] = [],
  preset?: NewNotePreset,
): Promise<NewNote | null> {
  return new Promise((resolve) => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;

    const title = el('input');
    title.type = 'text';
    title.placeholder = 'Reunión de soporte';
    const path = el('input');
    path.type = 'text';
    path.placeholder = 'inbox/soporte o privado/ideas';
    path.spellcheck = false;
    const help = el('p', 'field-help');
    const error = el('p', 'field-help field-error');
    error.hidden = true;
    let pathEdited = false;
    // La carpeta que fija el "+": mientras no se toque la agrupacion, la ruta se
    // sugiere dentro de ella (una subcarpeta incluida).
    let base = preset?.basePath ?? '';

    // La agrupacion decide la carpeta. Sin agrupacion, la bandeja: lo mismo que
    // hace `save_note` desde Claude Code.
    //
    // Cada carpeta de notas tiene sus agrupaciones: el valor de cada opcion es
    // el nombre de la carpeta de la agrupacion dentro de su carpeta de notas.
    const folder = el('select');
    const locals = folders.filter((entry) => entry.local && entry.available);
    folder.append(new Option(folders.find((entry) => !entry.local)?.name ?? 'Bóveda', ''));
    for (const entry of locals) {
      folder.append(new Option(`${entry.name} · notas locales`, entry.id));
    }
    if (preset) {
      folder.value = preset.folder;
    }
    const group = el('select');
    let known: string[] = [];
    const fillGroups = () => {
      const inside = groups
        .map((entry) => ({ entry, split: splitVirtual(entry.id) }))
        .filter(({ split }) => (split[0] ?? '') === folder.value);
      group.replaceChildren(new Option('Bandeja (sin agrupar)', ''));
      for (const { entry, split } of inside) {
        group.append(new Option(entry.name, split[1]));
      }
      known = inside.map(({ split }) => split[1]);
    };
    fillGroups();

    const describePath = () => {
      const privateNote = isPrivatePath(path.value);
      help.classList.toggle('private', privateNote);
      help.replaceChildren(
        ...(privateNote
          ? [icon(Lock), 'Privada: ningún agente la lee ni sale en las búsquedas.']
          : ['Dentro de privado/ ningún agente la lee.']),
      );
    };
    title.addEventListener('input', () => {
      if (!pathEdited) {
        path.value = suggestPathInGroup(title.value, base || group.value);
        describePath();
      }
    });
    group.addEventListener('change', () => {
      // Con la ruta escrita a mano solo se cambia la carpeta de agrupacion: el
      // nombre y un `privado/` los decidio el usuario.
      base = '';
      path.value = pathEdited
        ? regroupPath(path.value, group.value, known)
        : suggestPathInGroup(title.value, group.value);
      error.hidden = true;
      describePath();
    });
    folder.addEventListener('change', () => {
      // Otra carpeta, otras agrupaciones: se vuelve a la bandeja de esa carpeta.
      base = '';
      const previous = group.value;
    fillGroups();
    if (preset && preset.group) {
      group.value = preset.group;
    }
      group.value = '';
      path.value = pathEdited
        ? regroupPath(path.value, '', [...known, previous])
        : suggestPathInGroup(title.value, '');
      error.hidden = true;
      describePath();
    });
    path.addEventListener('input', () => {
      pathEdited = true;
      error.hidden = true;
      describePath();
    });

    const cancel = button('chip', 'Cancelar');
    const create = el('button', 'chip primary', 'Crear nota');
    create.type = 'submit';
    const form = el(
      'form',
      'dialog',
      el('h2', undefined, 'Nota nueva'),
      el('label', 'field', el('span', undefined, 'Título'), title),
      // Sin carpetas locales ni agrupaciones, un desplegable con una sola
      // opcion seria ruido.
      ...(locals.length > 0 ? [el('label', 'field', el('span', undefined, 'Carpeta de notas'), folder)] : []),
      ...(groups.length > 0 ? [el('label', 'field', el('span', undefined, 'Agrupación'), group)] : []),
      el('label', 'field', el('span', undefined, 'Ruta dentro de la carpeta'), path, help, error),
      el('div', 'dialog-actions', cancel, create),
    );
    form.setAttribute('role', 'dialog');
    form.setAttribute('aria-modal', 'true');
    const backdrop = el('div', 'palette-backdrop', form);

    const finish = (value: NewNote | null) => {
      document.removeEventListener('keydown', onKey, true);
      backdrop.classList.add('closing');
      window.setTimeout(() => backdrop.remove(), 140);
      if (!value) {
        previous?.focus();
      }
      resolve(value);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        finish(null);
      }
    };

    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const normalized = normalizeNewNotePath(path.value);
      if (!normalized) {
        error.textContent = 'Una ruta dentro de la bóveda, sin «..» ni carpetas ocultas.';
        error.hidden = false;
        path.focus();
        return;
      }
      // Una ruta que ya nombra su carpeta (`@apuntes/…`, escrita a mano) se
      // respeta; si no, va a la elegida.
      finish({
        path: normalized.startsWith(LOCAL_PREFIX) ? normalized : inFolder(normalized, folder.value || null),
        title: title.value.trim(),
      });
    });
    cancel.addEventListener('click', () => finish(null));
    backdrop.addEventListener('mousedown', (event) => {
      if (event.target === backdrop) {
        finish(null);
      }
    });
    document.addEventListener('keydown', onKey, true);

    describePath();
    document.body.append(backdrop);
    title.focus();
  });
}
