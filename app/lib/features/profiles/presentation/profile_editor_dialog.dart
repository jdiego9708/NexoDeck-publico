import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../actions/application/actions_provider.dart';
import '../../actions/presentation/widgets/action_icons.dart';
import '../application/active_profile_controller.dart';
import '../application/profiles_provider.dart';
import '../domain/deck_profile.dart';
import 'profile_auto_switcher.dart';

/// Crear o editar un perfil (segun [existing]).
Future<void> showProfileEditorDialog(
  BuildContext context, {
  DeckProfile? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ProfileEditorDialog(existing: existing),
  );
}

class _ProfileEditorDialog extends ConsumerStatefulWidget {
  const _ProfileEditorDialog({this.existing});

  final DeckProfile? existing;

  @override
  ConsumerState<_ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<_ProfileEditorDialog> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name,
  );
  late final _processController = TextEditingController(
    text: widget.existing?.autoDetectProcess,
  );
  late String _icon = widget.existing?.icon ?? 'folder';
  late String _colorHex = widget.existing?.colorHex ?? '#22C55E';

  /// `null` hasta que carga la composicion guardada -- distinto de "el
  /// perfil no tiene ninguna accion", que es un set vacio.
  Set<String>? _selected;

  @override
  void dispose() {
    _nameController.dispose();
    _processController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.watch(actionsListProvider).value ?? const [];
    final existing = widget.existing;

    // La composicion guardada se carga una sola vez; despues manda el
    // estado local (si no, cada emision del stream pisaria lo que el
    // usuario acaba de tildar).
    if (_selected == null) {
      if (existing == null) {
        _selected = <String>{};
      } else {
        final stored = ref.watch(profileActionIdsProvider(existing.id)).value;
        if (stored != null) _selected = {...stored};
      }
    }
    final selected = _selected;

    return AlertDialog(
      title: Text(existing == null ? 'Nuevo perfil' : 'Editar perfil'),
      content: SizedBox(
        width: 460,
        child: selected == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildAutoDetectField(),
                    const SizedBox(height: AppSpacing.md),
                    _IconRow(
                      selected: _icon,
                      accent: colorFromHex(_colorHex),
                      onSelected: (i) => setState(() => _icon = i),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ColorRow(
                      selected: _colorHex,
                      onSelected: (c) => setState(() => _colorHex = c),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Acciones del perfil',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      // Regla del filtro del deck, dicha donde se decide.
                      'Un perfil sin acciones no filtra nada: muestra el deck '
                      'completo.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final action in actions)
                              CheckboxListTile(
                                dense: true,
                                value: selected.contains(action.id),
                                onChanged: (checked) => setState(() {
                                  if (checked ?? false) {
                                    selected.add(action.id);
                                  } else {
                                    selected.remove(action.id);
                                  }
                                }),
                                secondary: Icon(
                                  iconForName(action.icon),
                                  size: 18,
                                  color: colorFromHex(action.colorHex),
                                ),
                                title: Text(action.name),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: _delete,
            child: Text(
              'Eliminar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }

  /// Campo del ejecutable, con un atajo para no tener que ir a buscar el
  /// nombre al Administrador de tareas.
  Widget _buildAutoDetectField() {
    // NO se ofrece "la app actual": mientras este dialogo esta abierto, la
    // app en foco es NexoDeck. Se ofrece la ultima app externa vista, que
    // es la que el usuario estaba usando antes de abrir esto.
    final suggestion = ref.watch(lastExternalAppProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _processController,
          decoration: const InputDecoration(
            labelText: 'Activar automáticamente con (opcional)',
            hintText: 'obs64.exe',
            helperText: 'Vacío = solo cambio manual',
          ),
        ),
        if (suggestion != null) ...[
          const SizedBox(height: AppSpacing.xs),
          ActionChip(
            avatar: const Icon(Icons.bolt, size: 14),
            label: Text('Usar $suggestion'),
            onPressed: () => setState(() {
              _processController.text = suggestion;
            }),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El perfil necesita un nombre')),
      );
      return;
    }

    final repository = ref.read(profilesRepositoryProvider);
    final actionIds = (_selected ?? const <String>{}).toList();
    final existing = widget.existing;
    if (existing == null) {
      await repository.createProfile(
        name: name,
        icon: _icon,
        colorHex: _colorHex,
        autoDetectProcess: _processController.text,
        actionIds: actionIds,
      );
    } else {
      await repository.updateProfile(
        existing,
        name: name,
        icon: _icon,
        colorHex: _colorHex,
        autoDetectProcess: _processController.text,
        actionIds: actionIds,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    // Si el perfil borrado era el activo, el deck se quedaria filtrando por
    // un id que ya no existe. Se vuelve a "Todas" explicitamente.
    if (ref.read(activeProfileIdProvider) == existing.id) {
      await ref.read(activeProfileControllerProvider).select(null);
    }
    await ref.read(profilesRepositoryProvider).deleteProfile(existing.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final String selected;
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in kActionIcons.entries)
          GestureDetector(
            onTap: () => onSelected(entry.key),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected == entry.key
                    ? accent.withValues(alpha: 0.18)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: selected == entry.key ? accent : Colors.transparent,
                ),
              ),
              child: Icon(
                entry.value,
                size: 16,
                color: selected == entry.key ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final hex in kActionColorPalette)
          GestureDetector(
            onTap: () => onSelected(hex),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colorFromHex(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == hex
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: selected == hex
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
