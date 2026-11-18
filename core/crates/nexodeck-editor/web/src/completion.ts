// Autocompletar `[[` con las notas de la boveda que manda Rust.

import type { Completion, CompletionContext, CompletionResult } from '@codemirror/autocomplete';
import type { EditorView } from '@codemirror/view';

import { linkForm } from './notePaths';
import type { LinkTargetDto } from './protocol';

/** [getSource] es la nota que se esta escribiendo: dentro de una carpeta local,
 * el enlace a otra nota de la misma carpeta se escribe relativo a ella, igual
 * que lo haria Obsidian abriendo esa carpeta. */
export function wikiLinkCompletions(
  getTargets: () => readonly LinkTargetDto[],
  getSource: () => string | null | undefined = () => null,
) {
  return (context: CompletionContext): CompletionResult | null => {
    const typed = context.matchBefore(/\[\[[^[\]|#\n]*$/);
    if (!typed) {
      return null;
    }
    const from = typed.from + 2;
    const source = getSource();
    const options: Completion[] = getTargets().map((target) => {
      const link = linkForm(target.target, source);
      return {
        label: link,
        detail: target.title,
        type: 'text',
        apply: (view: EditorView, _completion: Completion, applyFrom: number, applyTo: number) => {
          // `closeBrackets` ya dejo `]]` detras del cursor al escribir `[[`.
          const closed = view.state.sliceDoc(applyTo, applyTo + 2) === ']]';
          const insert = closed ? link : `${link}]]`;
          view.dispatch({
            changes: { from: applyFrom, to: applyTo, insert },
            selection: { anchor: applyFrom + link.length + 2 },
            userEvent: 'input.complete',
          });
        },
      };
    });
    return { from, options, validFor: /^[^[\]|#\n]*$/ };
  };
}
