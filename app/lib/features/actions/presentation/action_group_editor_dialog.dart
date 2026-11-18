import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/action_groups_provider.dart';
import 'widgets/action_icons.dart';

/// Abre el editor de grupos (crear si [existing] es null, editar/eliminar
/// si no).
Future<void> showActionGroupEditorDialog(
  BuildContext context, {
  ActionGroup? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ActionGroupEditorDialog(existing: existing),
  );
}

class _ActionGroupEditorDialog extends ConsumerStatefulWidget {
  const _ActionGroupEditorDialog({this.existing});

  final ActionGroup? existing;

  @override
  ConsumerState<_ActionGroupEditorDialog> createState() =>
      _ActionGroupEditorDialogState();
}

class _ActionGroupEditorDialogState
    extends ConsumerState<_ActionGroupEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late String _colorHex = widget.existing?.colorHex ?? kActionColorPalette.first;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar grupo' : 'Nuevo grupo'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final hex in kActionColorPalette)
                  GestureDetector(
                    onTap: () => setState(() => _colorHex = hex),
                    child: AnimatedContainer(
                      duration: AppDuration.selection,
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colorFromHex(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _colorHex == hex
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _colorHex == hex
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repository = ref.read(actionGroupsRepositoryProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repository.createGroup(
        name: _nameController.text.trim(),
        colorHex: _colorHex,
      );
    } else {
      await repository.renameGroup(
        existing,
        name: _nameController.text.trim(),
        icon: existing.icon,
        colorHex: _colorHex,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await ref.read(actionGroupsRepositoryProvider).deleteGroup(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}
