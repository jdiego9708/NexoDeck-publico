import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../docs_inbox/application/docs_inbox_controller.dart';
import '../application/notes_controller.dart';
import '../domain/vault_config.dart';

/// Elegir la carpeta de la bóveda desde la interfaz.
///
/// Antes esto solo se podía hacer editando a mano el JSON del buzón, que es
/// donde viven también los proyectos de documentación: un sitio incómodo y
/// fácil de romper para algo tan simple como decir en qué carpeta están las
/// notas.
///
/// **No reescribe la configuración entera.** Lee el JSON, cambia la bóveda y
/// devuelve el resto intacto (`writeVaultFolder`), porque en ese mismo fichero
/// están los proyectos de IA y Mapas y el modelo remoto.
Future<void> showVaultDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _VaultDialog(),
  );
}

class _VaultDialog extends ConsumerStatefulWidget {
  const _VaultDialog();

  @override
  ConsumerState<_VaultDialog> createState() => _VaultDialogState();
}

class _VaultDialogState extends ConsumerState<_VaultDialog> {
  final _folder = TextEditingController();
  final _repos = TextEditingController();

  /// El JSON tal como estaba al abrir: es lo que se modifica al guardar, para
  /// no perder nada de lo que este diálogo no sabe editar.
  String? _configJson;
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
    _folder.dispose();
    _repos.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final json = await ref.read(docsInboxProvider.notifier).configJson();
      final settings = readVaultSettings(json);
      if (!mounted) return;
      setState(() {
        _configJson = json;
        _folder.text = settings.root ?? '';
        _repos.text = settings.repos.join('\n');
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

  Future<void> _browse() async {
    final current = _folder.text.trim();
    final path = await getDirectoryPath(
      initialDirectory: current.isEmpty || !Directory(current).existsSync()
          ? null
          : current,
      confirmButtonText: 'Usar esta carpeta',
    );
    if (path == null || !mounted) return; // cancelado
    setState(() {
      _folder.text = path;
      _error = null;
    });
  }

  /// Añadir una carpeta local. Solo cambia el JSON en memoria: se guarda con
  /// "Guardar", junto con lo demás, y es entonces cuando Rust dice si la
  /// admite (que no sea documentación del buzón ni esté dentro de otra).
  Future<void> _addLocal() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Añadir esta carpeta',
    );
    if (path == null || !mounted) return; // cancelado
    final base = _configJson ?? '{}';
    final already = readLocalFolders(
      base,
    ).any((f) => f.path.toLowerCase() == path.toLowerCase());
    setState(() {
      if (already) {
        _error = 'Esa carpeta ya está añadida.';
      } else {
        _configJson = addLocalFolder(base, path);
        _error = null;
      }
    });
  }

  void _removeLocal(LocalFolder folder) {
    setState(() {
      _configJson = removeLocalFolder(_configJson ?? '{}', folder.id);
      _error = null;
    });
  }

  Future<void> _save() async {
    final folder = _folder.text.trim();
    if (folder.isEmpty) {
      setState(() => _error = 'Dime en qué carpeta están las notas.');
      return;
    }
    // Una carpeta que no existe se rechaza aquí y no al leer la bóveda: el
    // error de Rust llegaría después y sin decir que fue una errata al teclear.
    if (!Directory(folder).existsSync()) {
      setState(
        () => _error =
            'Esa carpeta no existe: $folder. Elígela con "Examinar…" o créala '
            'antes.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final base = _configJson ?? '{}';
      final repos = _repos.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final updated = writeVaultRepos(writeVaultFolder(base, folder), repos);
      await ref.read(docsInboxProvider.notifier).saveConfig(updated);
      // La bóveda cambió entera: la lista que se esté viendo detrás ya no vale.
      await ref.read(notesProvider.notifier).refresh();
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
      title: const Text('Bóveda de notas'),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            // Con varias carpetas locales la lista crece: sin scroll el
            // diálogo desbordaría en una ventana baja.
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Las notas son ficheros .md de una carpeta: sigue abriéndolas '
                      'en Obsidian o donde quieras. Lo que haya en "privado/" o '
                      'lleve "ai: false" no lo lee ningún agente.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _folder,
                            decoration: const InputDecoration(
                              labelText: 'Carpeta de las notas',
                              hintText: r'D:\Notas',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: FilledButton.tonalIcon(
                            onPressed: _saving ? null : _browse,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('Examinar…'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _repos,
                      minLines: 2,
                      maxLines: 4,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const ['Courier New', 'monospace'],
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Repositorios a cruzar (uno por línea)',
                        helperText:
                            'Sus commits se relacionan con las notas. Puede quedar vacío.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _LocalFolders(
                      folders: readLocalFolders(_configJson ?? '{}'),
                      enabled: !_saving,
                      onAdd: _addLocal,
                      onRemove: _removeLocal,
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

/// Las carpetas de notas que NexoDeck lee **en su sitio**, sin copiarlas.
class _LocalFolders extends StatelessWidget {
  const _LocalFolders({
    required this.folders,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<LocalFolder> folders;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<LocalFolder> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Carpetas locales',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Añadir carpeta…'),
            ),
          ],
        ),
        // Lo importante de estas carpetas es lo que NO pasa: no se copian. Y
        // editar, agrupar o mover sí cambia los ficheros de esa ruta.
        Text(
          'Carpetas con .md que ya tienes ordenados. Se leen y se editan en su '
          'ruta, con todas sus subcarpetas: no se copian a la bóveda. Una '
          'carpeta de documentación del buzón no se puede añadir.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (folders.isEmpty)
          Text('Ninguna todavía.', style: theme.textTheme.bodySmall)
        else
          for (final folder in folders)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_shared_outlined),
              title: Text(folder.name),
              subtitle: Text(folder.path, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: enabled ? () => onRemove(folder) : null,
                // Quitar no borra nada del disco, y el botón no puede parecer
                // que sí.
                child: const Text('Quitar'),
              ),
            ),
      ],
    );
  }
}
