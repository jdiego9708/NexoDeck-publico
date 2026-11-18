import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/docs_inbox_controller.dart';

/// Editor de la configuracion del buzon: proyectos, documentos y modelo.
///
/// Es un JSON validado por Rust y no un formulario, a proposito, en esta
/// primera version: los proyectos se configuran una vez, y un formulario para
/// listas anidadas de documentos es mucho codigo para algo que casi no se toca.
/// Lo que si hace falta es que un error diga exactamente que corregir, y eso lo
/// da la validacion de Rust, que lista todos los problemas a la vez.
Future<void> showDocsProjectsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DocsProjectsDialog(),
  );
}

class _DocsProjectsDialog extends ConsumerStatefulWidget {
  const _DocsProjectsDialog();

  @override
  ConsumerState<_DocsProjectsDialog> createState() =>
      _DocsProjectsDialogState();
}

class _DocsProjectsDialogState extends ConsumerState<_DocsProjectsDialog> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final json = await ref.read(docsInboxProvider.notifier).configJson();
      if (!mounted) return;
      setState(() {
        _controller.text = json;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(docsInboxProvider.notifier).saveConfig(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Proyectos de documentación'),
      content: SizedBox(
        width: 760,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cada proyecto dice en qué repositorio vive y qué documentos '
                    'alimenta el buzón: "journal" es un diario con lo más reciente '
                    'arriba, "plan" un plan con secciones fijas e "index" un '
                    'índice. En "remote" va el modelo remoto; su clave es la que '
                    'guardaste en el asistente de IA.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Con un modelo remoto, el contenido de estos documentos sale '
                    'de la máquina hacia ese servicio cada vez que se prepara una '
                    'propuesta.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _controller,
                    minLines: 16,
                    maxLines: 24,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['Courier New', 'monospace'],
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
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
          onPressed: _loading || _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
