import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../domain/note_tree.dart';
import '../domain/notes.dart';

/// Las notas en árbol: una rama por carpeta de notas y, dentro, sus subcarpetas
/// en el orden del Explorador (`buildNoteTree`).
///
/// Las hojas las pinta quien lo usa ([leaf]), para que una nota se vea igual en
/// el árbol que en la lista filtrada.
///
/// Las carpetas de notas empiezan abiertas y las subcarpetas cerradas, **salvo la
/// que contiene la nota abierta**: seleccionar una nota no puede dejarla
/// escondida dentro de una rama plegada.
class NoteTreeView extends StatefulWidget {
  const NoteTreeView({
    super.key,
    required this.roots,
    required this.selectedPath,
    required this.leaf,
  });

  final List<NoteTreeRoot> roots;
  final String? selectedPath;
  final Widget Function(NoteSummary note) leaf;

  @override
  State<NoteTreeView> createState() => _NoteTreeViewState();
}

class _NoteTreeViewState extends State<NoteTreeView> {
  /// Subcarpetas abiertas, por `carpeta:ruta`.
  final _open = <String>{};

  /// Carpetas de notas cerradas a mano, por id.
  final _closedRoots = <String>{};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final root in widget.roots) _root(context, root)],
    );
  }

  Widget _root(BuildContext context, NoteTreeRoot root) {
    final theme = Theme.of(context);
    final folder = root.folder;
    return ExpansionTile(
      key: PageStorageKey<String>('root:${folder.id}'),
      initiallyExpanded: !_closedRoots.contains(folder.id),
      onExpansionChanged: (open) => setState(
        () =>
            open ? _closedRoots.remove(folder.id) : _closedRoots.add(folder.id),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      childrenPadding: const EdgeInsets.only(left: AppSpacing.sm),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        folder.local
            ? Icons.folder_shared_outlined
            : Icons.inventory_2_outlined,
        size: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              folder.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Lo que pidió el usuario: una etiqueta sutil que diga que estas notas
          // viven en su propia ruta y no se copian.
          if (folder.local) const _Tag('Notas locales'),
          if (!folder.available) ...[
            const SizedBox(width: AppSpacing.xs),
            const _Tag('No disponible', warn: true),
          ],
        ],
      ),
      subtitle: Text(
        folder.path,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      children: folder.available
          ? _children(context, root, root.tree)
          : [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  'La carpeta no está disponible ahora (¿un disco desconectado?). '
                  'Sus notas vuelven solas cuando vuelva.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
    );
  }

  List<Widget> _children(
    BuildContext context,
    NoteTreeRoot root,
    NoteTreeFolder node,
  ) {
    final theme = Theme.of(context);
    return [
      for (final folder in node.folders) _folder(context, root, folder),
      for (final note in node.notes) widget.leaf(note),
      if (node.path.isEmpty && node.folders.isEmpty && node.notes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text('Sin notas todavía.', style: theme.textTheme.bodySmall),
        ),
    ];
  }

  Widget _folder(BuildContext context, NoteTreeRoot root, NoteTreeFolder node) {
    final theme = Theme.of(context);
    final key = '${root.folder.id}:${node.path}';
    final prefix =
        '${root.folder.local ? '@${root.folder.id}/' : ''}${node.path}/';
    final holdsSelection = widget.selectedPath?.startsWith(prefix) ?? false;
    return ExpansionTile(
      key: PageStorageKey<String>(key),
      initiallyExpanded: _open.contains(key) || holdsSelection,
      onExpansionChanged: (open) =>
          setState(() => open ? _open.add(key) : _open.remove(key)),
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      childrenPadding: const EdgeInsets.only(left: AppSpacing.md),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.folder_outlined, size: 18),
      title: Row(
        children: [
          Flexible(child: Text(node.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpacing.xs),
          Text('${node.count}', style: theme.textTheme.bodySmall),
        ],
      ),
      children: _children(context, root, node),
    );
  }
}

/// Una etiqueta pequeña y apagada. Tiene que informar sin competir con el
/// nombre de la carpeta.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warn ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.2),
      ),
    );
  }
}
