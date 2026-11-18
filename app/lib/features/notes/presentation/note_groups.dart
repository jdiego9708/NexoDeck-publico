import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/color_palette_picker.dart';
import '../../actions/presentation/widgets/action_icons.dart';
import '../application/notes_controller.dart';
import '../domain/notes.dart';

/// El filtro "sin agrupar", distinto de `null` (todas). Ningún id de agrupación
/// puede estar vacío: es el nombre de una carpeta.
const String kUngroupedFilter = '';

/// El color de una agrupación. Un hex mal escrito a mano en la configuración se
/// pinta gris en vez de romper la lista.
Color noteGroupColor(NoteGroup group) =>
    ColorPalettePicker.parse(group.colorHex);

/// La carpeta de notas de una agrupación: `@apuntes/clientes` es de la carpeta
/// local `apuntes`; sin `@`, de la bóveda principal (`null`).
String? noteGroupFolder(NoteGroup group) {
  final slash = group.id.indexOf('/');
  if (!group.id.startsWith('@') || slash < 0) return null;
  return group.id.substring(1, slash);
}

/// El nombre de la agrupación dentro de su carpeta de notas (`clientes`): es lo
/// que se pasa para mover una nota a ella.
String noteGroupSlug(NoteGroup group) =>
    group.id.substring(group.id.lastIndexOf('/') + 1);

/// Crear una agrupación, o editar una con [existing].
///
/// La paleta es **la misma que los grupos del deck**: para el usuario son el
/// mismo concepto, y dos paletas distintas harían que no se reconocieran.
Future<void> showNoteGroupDialog(
  BuildContext context, {
  NoteGroup? existing,
  List<NoteFolder> folders = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _NoteGroupDialog(existing: existing, folders: folders),
  );
}

class _NoteGroupDialog extends ConsumerStatefulWidget {
  const _NoteGroupDialog({this.existing, this.folders = const []});

  final NoteGroup? existing;
  final List<NoteFolder> folders;

  @override
  ConsumerState<_NoteGroupDialog> createState() => _NoteGroupDialogState();
}

class _NoteGroupDialogState extends ConsumerState<_NoteGroupDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late String _colorHex =
      widget.existing?.colorHex ?? kActionColorPalette.first;

  /// La carpeta de notas donde crearla. `null` es la bóveda principal.
  late String? _folder = widget.existing == null
      ? null
      : noteGroupFolder(widget.existing!);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(notesProvider.notifier)
          .upsertGroup(
            name,
            _colorHex,
            id: widget.existing?.id,
            // Al editar, la carpeta la dice el id: no se puede cambiar.
            folder: widget.existing == null ? _folder : null,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      // Rust dice exactamente qué está mal (un nombre reservado, por ejemplo):
      // se enseña tal cual en vez de un "no se pudo guardar" que no ayuda.
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    // Elegir carpeta solo tiene sentido al crear, y si hay más de una.
    final chooseFolder = existing == null && widget.folders.length > 1;
    return AlertDialog(
      title: Text(existing == null ? 'Nueva agrupación' : 'Editar agrupación'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (chooseFolder) ...[
              const SizedBox(height: AppSpacing.md),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Carpeta de notas',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _folder,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final folder in widget.folders)
                        DropdownMenuItem(
                          value: folder.local ? folder.id : null,
                          child: Text(
                            folder.local
                                ? '${folder.name} · notas locales'
                                : folder.name,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _folder = value),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Que es una carpeta no es un detalle: decide qué pasa al renombrar,
            // y quien abre la bóveda en Obsidian la va a ver.
            Text(
              existing == null
                  ? 'Se crea como una carpeta dentro de esa carpeta de notas, así '
                        'que también la verás en Obsidian y en el explorador.'
                  : 'Cambiar el nombre no mueve la carpeta: las notas se quedan '
                        'donde están.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            ColorPalettePicker(
              palette: kActionColorPalette,
              selected: _colorHex,
              onSelected: (hex) => setState(() => _colorHex = hex),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Filtrar la lista por agrupación: "Todas", la bandeja y un chip por grupo.
///
/// Mismo lenguaje que `ActionGroupFilterBar` del deck —chip con un punto de
/// color— para que una agrupación de notas se reconozca como lo mismo que un
/// grupo de acciones. Clic derecho o pulsación larga sobre un grupo lo edita.
class NoteGroupBar extends StatelessWidget {
  const NoteGroupBar({
    super.key,
    required this.groups,
    required this.selected,
    required this.ungrouped,
    required this.onSelected,
    this.folders = const [],
  });

  final List<NoteGroup> groups;
  final List<NoteFolder> folders;

  /// `null` = todas; [kUngroupedFilter] = sin agrupar; si no, el id.
  final String? selected;

  /// Cuántas notas hay sin agrupar.
  final int ungrouped;
  final ValueChanged<String?> onSelected;

  String _label(NoteGroup group) {
    final folderId = noteGroupFolder(group);
    if (folderId == null) return '${group.name} (${group.notes})';
    // Dos carpetas pueden tener cada una su `clientes`: el chip tiene que decir
    // de cuál es.
    final folder = folders
        .where((f) => f.local && f.id == folderId)
        .firstOrNull;
    return '${group.name} · ${folder?.name ?? folderId} (${group.notes})';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('Todas'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              avatar: const Icon(Icons.inbox_outlined, size: 16),
              label: Text('Bandeja ($ungrouped)'),
              selected: selected == kUngroupedFilter,
              onSelected: (_) => onSelected(kUngroupedFilter),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: GestureDetector(
                onLongPress: () => showNoteGroupDialog(
                  context,
                  existing: group,
                  folders: folders,
                ),
                onSecondaryTap: () => showNoteGroupDialog(
                  context,
                  existing: group,
                  folders: folders,
                ),
                child: Tooltip(
                  message: 'Clic derecho para editar',
                  child: ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: noteGroupColor(group),
                      radius: AppSizes.groupDotRadius,
                    ),
                    label: Text(_label(group)),
                    selected: selected == group.id,
                    // Volver a pulsar el grupo elegido quita el filtro.
                    onSelected: (on) => onSelected(on ? group.id : null),
                  ),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('Agrupación'),
            onPressed: () => showNoteGroupDialog(context, folders: folders),
          ),
        ],
      ),
    );
  }
}

/// "Mover a…" una nota: a otra agrupación de su carpeta, de vuelta a la bandeja,
/// o a otra carpeta de notas.
///
/// **Mueve el fichero**, porque cada agrupación es una carpeta. Los enlaces de
/// otras notas que la citaban los reescribe Rust solo, y entre carpetas de notas
/// que estén en discos distintos copia, verifica y solo entonces borra.
///
/// Si sale bien **no interrumpe**: el usuario eligió que los enlaces se
/// arreglen solos, no que se lo cuenten, y la nota ya aparece en su sitio nuevo.
/// Si falla **lo dice en un diálogo** y no en un `SnackBar`: estamos dentro del
/// diálogo de Notas, y un `SnackBar` saldría tapado detrás de él, o sea mudo.
class MoveNoteButton extends ConsumerWidget {
  const MoveNoteButton({
    super.key,
    required this.path,
    required this.current,
    required this.groups,
    this.folder,
    this.folders = const [],
    this.onMoved,
  });

  final String path;

  /// Su agrupación actual. `null` si está en la bandeja.
  final String? current;

  /// Su carpeta de notas: el id de una local, o `null` si es de la principal.
  final String? folder;
  final List<NoteGroup> groups;
  final List<NoteFolder> folders;
  final ValueChanged<String>? onMoved;

  static const _groupPrefix = 'group:';
  static const _folderPrefix = 'folder:';

  Future<void> _move(BuildContext context, WidgetRef ref, String target) async {
    final notes = ref.read(notesProvider.notifier);
    try {
      final NoteMove moved;
      if (target.startsWith(_folderPrefix)) {
        // Entre carpetas conserva su ruta: la nota se lleva su sitio.
        moved = await notes.moveToGroup(
          path,
          null,
          folder: target.substring(_folderPrefix.length),
        );
      } else {
        final slug = target.substring(_groupPrefix.length);
        moved = await notes.moveToGroup(path, slug.isEmpty ? null : slug);
      }
      onMoved?.call(moved.to);
    } catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No se movió la nota'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solo las agrupaciones de su carpeta: la de otra carpeta de notas se
    // alcanza moviéndola primero a esa carpeta.
    final targets = [
      for (final group in groups)
        if (noteGroupFolder(group) == folder && group.id != current) group,
    ];
    // Una carpeta no disponible (disco desconectado) no se ofrece: la copia
    // fallaría.
    final otherFolders = [
      for (final f in folders)
        if (f.available &&
            (folder == null ? f.local : !(f.local && f.id == folder)))
          f,
    ];
    return PopupMenuButton<String>(
      tooltip: 'Mover a otra agrupación o carpeta',
      icon: const Icon(Icons.drive_file_move_outline),
      onSelected: (target) => _move(context, ref, target),
      itemBuilder: (_) => [
        if (current != null)
          const PopupMenuItem(
            value: '$_groupPrefix$kUngroupedFilter',
            child: ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('Bandeja (sin agrupar)'),
            ),
          ),
        for (final group in targets)
          PopupMenuItem(
            value: '$_groupPrefix${noteGroupSlug(group)}',
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: noteGroupColor(group),
                radius: AppSizes.groupDotRadius,
              ),
              title: Text(group.name),
            ),
          ),
        if (otherFolders.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final f in otherFolders)
            PopupMenuItem(
              value: '$_folderPrefix${f.id}',
              child: ListTile(
                leading: Icon(
                  f.local
                      ? Icons.folder_shared_outlined
                      : Icons.inventory_2_outlined,
                ),
                title: Text('A «${f.name}»'),
                subtitle: Text(f.local ? 'Notas locales' : 'Bóveda'),
              ),
            ),
        ],
        // Sin ningún destino, un menú vacío parecería roto: se dice por qué.
        if (targets.isEmpty && current == null && otherFolders.isEmpty)
          const PopupMenuItem(
            enabled: false,
            child: Text('No hay agrupaciones: crea una en la barra de arriba.'),
          ),
      ],
    );
  }
}
