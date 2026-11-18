import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/stack_controller.dart';
import '../domain/stack_profile.dart';

/// Abre el dialogo para apuntar la carpeta del stack.
Future<void> showStackConfigDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const StackConfigDialog(),
);

/// Carpeta que contiene `Start-Stack.ps1` y `Stop-Stack.ps1`, con el comando
/// que se lanzaria para el perfil elegido, para que se vea antes de guardar.
class StackConfigDialog extends ConsumerStatefulWidget {
  const StackConfigDialog({super.key});

  @override
  ConsumerState<StackConfigDialog> createState() => _StackConfigDialogState();
}

class _StackConfigDialogState extends ConsumerState<StackConfigDialog> {
  late final TextEditingController _dir;

  @override
  void initState() {
    super.initState();
    _dir = TextEditingController(text: ref.read(stackScriptsDirProvider))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _dir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(selectedStackProfileProvider);
    final preview = stackCommandFor(profile, _dir.text);

    return AlertDialog(
      title: const Text('Carpeta del stack'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Carpeta con Start-Stack.ps1 y Stop-Stack.ps1 (y llm-gateway.exe).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _dir,
              decoration: const InputDecoration(labelText: 'Carpeta'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Comando para «${profile.label}»:',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: SelectableText(
                preview,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            await ref.read(stackControllerProvider).setScriptsDir(_dir.text);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
