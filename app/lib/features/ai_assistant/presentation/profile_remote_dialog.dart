import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../application/ai_providers.dart';
import '../domain/ai_profile.dart';

/// Configura el servicio por internet de **un slot** de un perfil (router o
/// pensamiento).
///
/// Es hermano de `showRemoteProviderDialog`, no el mismo: aquel guarda un unico
/// proveedor remoto y lo marca como destino por defecto del chat. Aqui la clave
/// vive por slot (`providerId` distinto por perfil y rol), asi que dos slots
/// pueden apuntar a servicios con claves distintas.
///
/// Devuelve el [ProfileSlot] remoto ya comprobado, o `null` si se cancelo.
Future<ProfileSlot?> showProfileRemoteDialog(
  BuildContext context, {
  required String providerId,
  String? initialBaseUrl,
  String? initialModel,
  String? initialDisplayName,
}) {
  return showDialog<ProfileSlot>(
    context: context,
    builder: (_) => _ProfileRemoteDialog(
      providerId: providerId,
      initialBaseUrl: initialBaseUrl,
      initialModel: initialModel,
      initialDisplayName: initialDisplayName,
    ),
  );
}

class _ProfileRemoteDialog extends ConsumerStatefulWidget {
  const _ProfileRemoteDialog({
    required this.providerId,
    this.initialBaseUrl,
    this.initialModel,
    this.initialDisplayName,
  });

  final String providerId;
  final String? initialBaseUrl;
  final String? initialModel;
  final String? initialDisplayName;

  @override
  ConsumerState<_ProfileRemoteDialog> createState() =>
      _ProfileRemoteDialogState();
}

class _ProfileRemoteDialogState extends ConsumerState<_ProfileRemoteDialog> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  List<bridge.AiRemotePreset> _presets = const [];
  bridge.AiRemotePreset? _preset;
  List<String> _models = const [];
  bool _loading = true;
  bool _busy = false;
  bool _obscureKey = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = widget.initialBaseUrl ?? '';
    _modelController.text = widget.initialModel ?? '';
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final presets = await ref.read(aiRepositoryProvider).remotePresets();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _loading = false;
    });
    if (presets.isNotEmpty) await _selectPreset(presets.first);
  }

  Future<void> _selectPreset(bridge.AiRemotePreset preset) async {
    // La clave se busca por el id del SLOT (no el del preset): asi el router y
    // el pensamiento del mismo perfil pueden tener claves distintas.
    var saved = await ref
        .read(aiRepositoryProvider)
        .remoteApiKey(widget.providerId)
        .catchError((_) => null);
    // Si este slot todavia no tiene clave, se reusa la del **preset**: la que el
    // usuario ya tenia guardada (p. ej. `deepseek.key`). No tiene que volver a
    // pegarla para dar de alta el mismo servicio en otro slot.
    if (saved == null || saved.isEmpty) {
      saved = await ref
          .read(aiRepositoryProvider)
          .remoteApiKey(preset.id)
          .catchError((_) => null);
    }
    if (!mounted) return;
    setState(() {
      _preset = preset;
      // Un valor ya guardado en el slot manda sobre el default del preset.
      _baseUrlController.text = widget.initialBaseUrl ?? preset.baseUrl;
      _modelController.text = widget.initialModel ?? preset.defaultModel;
      _keyController.text = saved ?? '';
      _models = const [];
      _error = null;
    });
  }

  Future<void> _loadModels() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Hace falta la clave para pedir los modelos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final models = await ref
          .read(aiRepositoryProvider)
          .remoteModels(baseUrl: _baseUrlController.text.trim(), apiKey: key);
      if (!mounted) return;
      setState(() => _models = models);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _use() async {
    final preset = _preset;
    if (preset == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final baseUrl = _baseUrlController.text.trim();
      final model = _modelController.text.trim();

      // Comprueba la clave antes de instalar nada. La guarda Rust bajo el id
      // del slot, que es el que la pasarela del stack usara para reenviar.
      await ref
          .read(aiRepositoryProvider)
          .useRemote(
            providerId: widget.providerId,
            baseUrl: baseUrl,
            model: model,
            apiKey: _keyController.text.trim(),
            displayName: preset.label,
          );

      if (!mounted) return;
      Navigator.of(context).pop(
        ProfileSlot(
          source: ProfileSlotSource.remote,
          remoteProviderId: widget.providerId,
          remoteBaseUrl: baseUrl,
          remoteModel: model,
          remoteDisplayName: preset.label,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _forget() async {
    await ref.read(aiRepositoryProvider).forgetRemoteApiKey(widget.providerId);
    if (!mounted) return;
    setState(() => _keyController.text = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _preset;

    return AlertDialog(
      title: const Text('Servicio por internet'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        'Los mensajes salen de tu máquina. Lo que el asistente '
                        'lea de tus proyectos viaja al servicio que elijas.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SegmentedButton<String>(
                      segments: [
                        for (final p in _presets)
                          ButtonSegment(value: p.id, label: Text(p.label)),
                      ],
                      selected: {preset?.id ?? ''},
                      onSelectionChanged: _busy
                          ? null
                          : (values) {
                              final chosen = _presets.firstWhere(
                                (p) => p.id == values.first,
                              );
                              _selectPreset(chosen);
                            },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _keyController,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'Clave de API',
                        helperText:
                            'Se guarda en el directorio de datos de '
                            'NexoDeck, en texto plano',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _obscureKey ? 'Mostrar' : 'Ocultar',
                              icon: Icon(
                                _obscureKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureKey = !_obscureKey),
                            ),
                            IconButton(
                              tooltip: 'Olvidar la clave guardada',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: _busy ? null : _forget,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (preset != null && preset.apiKeysUrl.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(
                            'Copiar dónde sacarla: ${preset.apiKeysUrl}',
                          ),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: preset.apiKeysUrl),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enlace copiado')),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'Modelo',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: _busy ? null : _loadModels,
                          child: const Text('Ver los que hay'),
                        ),
                      ],
                    ),
                    if (_models.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final model in _models.take(20))
                            ActionChip(
                              label: Text(model),
                              onPressed: () =>
                                  setState(() => _modelController.text = model),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección base',
                        helperText:
                            'Si pegás la URL completa del endpoint, se '
                            'recorta sola',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy || _loading ? null : _use,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Usar este servicio'),
        ),
      ],
    );
  }
}
