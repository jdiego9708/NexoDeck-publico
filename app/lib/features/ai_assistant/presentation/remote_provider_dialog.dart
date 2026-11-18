import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../application/ai_providers.dart';
import '../application/chat_destinations_controller.dart';

/// Configura un servicio de IA por internet: DeepSeek, OpenAI, o cualquier otro
/// que hable el mismo dialecto.
///
/// Devuelve `true` si el proveedor quedo instalado.
Future<bool?> showRemoteProviderDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _RemoteProviderDialog(),
  );
}

class _RemoteProviderDialog extends ConsumerStatefulWidget {
  const _RemoteProviderDialog();

  @override
  ConsumerState<_RemoteProviderDialog> createState() =>
      _RemoteProviderDialogState();
}

class _RemoteProviderDialogState extends ConsumerState<_RemoteProviderDialog> {
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
    // La clave guardada se recupera al elegir el servicio: quien ya lo
    // configuro no tiene que volver a pegarla para cambiar de modelo.
    final saved = await ref
        .read(aiRepositoryProvider)
        .remoteApiKey(preset.id)
        .catchError((_) => null);
    if (!mounted) return;
    setState(() {
      _preset = preset;
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.defaultModel;
      _keyController.text = saved ?? '';
      _models = const [];
      _error = null;
    });
  }

  /// Pide la lista de modelos al servicio. Es opcional: se puede escribir el
  /// nombre a mano, porque no todos los servicios publican un catalogo.
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
      final models = await ref.read(aiRepositoryProvider).remoteModels(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: key,
      );
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
      // Comprueba la clave contra el servicio ANTES de instalar nada, y solo
      // la guarda si contesto. Una clave mal pegada tiene que fallar aca, en
      // el dialogo donde se puede corregir, no dentro de la conversacion.
      final baseUrl = _baseUrlController.text.trim();
      final model = _modelController.text.trim();

      await ref.read(aiRepositoryProvider).useRemote(
        providerId: preset.id,
        baseUrl: baseUrl,
        model: model,
        apiKey: _keyController.text.trim(),
        displayName: preset.label,
      );

      // **Recien ahora se guarda la configuracion**, con el servicio ya
      // comprobado. Guardarla antes dejaria en disco algo que no funciona, y
      // el arranque siguiente intentaria levantarlo en silencio.
      //
      // Sin esto, la clave quedaba guardada pero el modelo y la direccion no,
      // asi que al reiniciar la app el asistente volvia inactivo y el wizard
      // ofrecia descargar un modelo local. Verificado en vivo el 9-sep-2026.
      await ref.read(chatDestinationsProvider.notifier).saveRemoteConfig(
        RemoteProviderConfig(
          providerId: preset.id,
          baseUrl: baseUrl,
          model: model,
          displayName: preset.label,
        ),
      );
      // Queda como el destino por defecto: el usuario acaba de elegirlo, y no
      // hacerlo obligaria a elegirlo otra vez en el proximo arranque.
      await ref
          .read(chatDestinationsProvider.notifier)
          .setDefault('remote:${preset.id}');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _forget() async {
    final preset = _preset;
    if (preset == null) return;
    await ref.read(aiRepositoryProvider).forgetRemoteApiKey(preset.id);
    if (!mounted) return;
    setState(() => _keyController.text = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _preset;

    return AlertDialog(
      title: const Text('Servicio de IA por internet'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lo primero, y sin rodeos: lo que el asistente lea de tus
                    // ficheros viaja a un tercero. Es la diferencia real con el
                    // modelo local, y descubrirla despues seria tarde.
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        'Los mensajes salen de tu máquina. Lo que el asistente '
                        'lea de tus proyectos para contestar viaja al servicio '
                        'que elijas, y el uso se te factura a ti.',
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
                        helperText: 'Se guarda en el directorio de datos de '
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
                    // `apiKeysUrl` vacio en un preset propio (proxy): no hay
                    // pagina que copiar, asi que no se promete ninguna.
                    if (preset != null && preset.apiKeysUrl.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          // No abre el navegador: copia. Sin lanzador de URLs
                          // en el proyecto, un boton que no hace nada seria
                          // peor que uno que hace algo util.
                          label: Text('Copiar dónde sacarla: ${preset.apiKeysUrl}'),
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
                              onPressed: () => setState(
                                () => _modelController.text = model,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),

                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección base',
                        helperText: 'Si pegás la URL completa del endpoint, se '
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
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
