import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../../stack/application/stack_controller.dart';
import '../../../stack/domain/stack_profile.dart';
import '../../application/ai_profiles_controller.dart';
import '../../application/ai_providers.dart';
import '../../data/stack_catalog_repository.dart';
import '../../domain/ai_profile.dart';
import '../../domain/setup_progress.dart';
import '../profile_remote_dialog.dart';

/// Elige el modelo de un slot de un perfil, agrupado por motor.
///
/// Devuelve el [ProfileSlot] elegido, o `null` si se cerro sin elegir.
Future<ProfileSlot?> showProfileSlotPicker(
  BuildContext context, {
  required String profile,
  required String slot,
}) {
  return showModalBottomSheet<ProfileSlot>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProfileSlotPicker(profile: profile, slot: slot),
  );
}

class _ProfileSlotPicker extends ConsumerWidget {
  const _ProfileSlotPicker({required this.profile, required this.slot});

  final String profile;
  final String slot;

  String get _roleLabel => slot == 'router' ? 'Router' : 'Pensamiento';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(aiProfilesProvider);
    final ollama = ref.watch(aiOllamaProvider).value;
    final light = ref.watch(aiModelOptionsProvider(bridge.AiTier.light)).value;
    final balanced = ref
        .watch(aiModelOptionsProvider(bridge.AiTier.balanced))
        .value;
    final performance = ref
        .watch(aiModelOptionsProvider(bridge.AiTier.performance))
        .value;

    // El router es liviano; el pensamiento, mediano o alto.
    final llamaOptions = <bridge.AiModelOption>[
      ...?light,
      if (slot == 'thinking') ...?balanced,
      if (slot == 'thinking') ...?performance,
    ];

    // Contexto de VRAM: el **otro** slot de este perfil (lo que ya esta puesto),
    // la huella por rol del catalogo y el presupuesto del equipo. Con eso cada
    // tile del stack sabe si cabe o no. Un slot de otro motor no puntua (no lo
    // carga vLLM).
    final cfg = profiles.config.forProfile(profile);
    final otherSlot = slot == 'router' ? cfg.thinking : cfg.router;
    final otherRole = otherSlot.isStack ? otherSlot.model : null;
    final vramByRole = {for (final m in profiles.catalog) m.role: m.vramGb};
    final vram = ref.watch(aiVramBudgetProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Perfil $profile · $_roleLabel',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionTitle('Stack vLLM (local)'),
          if (profiles.catalog.where((m) => !m.alternative).isEmpty)
            _Hint('No se pudo leer models.json de la carpeta del stack.'),
          // La deteccion corre sola al entrar a «Configura tus perfiles»; aca
          // solo queda explicar por que un tile del stack sigue «Sin comprobar».
          if (profiles.detection.error != null)
            _Hint(
              'No se pudo comprobar los descargados: ${profiles.detection.error}',
            ),
          if (vram.budgetGb > 0)
            _Hint(
              'La VRAM se suma por perfil. Un modelo que no cabe junto al otro '
              'slot no se puede elegir (equipo: ${vram.budgetGb.toStringAsFixed(1)} GiB'
              '${vram.gpu != null ? ' · ${vram.gpu}' : ''}).',
            ),
          for (final model in profiles.catalog.where((m) => !m.alternative))
            _StackTile(
              model: model,
              slot: slot,
              fits: stackSelectionFitsVram(
                otherStackRole: otherRole,
                candidateRole: model.role,
                vramByRole: vramByRole,
                budgetGb: vram.budgetGb,
              ),
              downloaded: profiles.detection.installedDirs.contains(model.dir),
              detected: profiles.detected && profiles.detection.error == null,
              onPick: () => Navigator.of(context).pop(
                ProfileSlot(source: ProfileSlotSource.stack, model: model.role),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          _SectionTitle('llama.cpp (en tu equipo)'),
          for (final option in llamaOptions)
            _LlamaCppTile(
              option: option,
              onPick: () => Navigator.of(context).pop(
                ProfileSlot(
                  source: ProfileSlotSource.llamaCpp,
                  model: option.id,
                ),
              ),
            ),

          if (ollama != null && ollama.models.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle('Ollama'),
            for (final model in ollama.models)
              _SimpleTile(
                icon: Icons.dns_outlined,
                title: model,
                subtitle: 'Del Ollama que ya tenés corriendo',
                onPick: () => Navigator.of(context).pop(
                  ProfileSlot(source: ProfileSlotSource.ollama, model: model),
                ),
              ),
          ],

          const SizedBox(height: AppSpacing.lg),
          _SectionTitle('Corresponsal'),
          _SimpleTile(
            icon: Icons.hub_outlined,
            title: 'Claude Code',
            subtitle:
                'Usa la sesión que ya tenés vigilada en la terminal. '
                'No necesita clave. Tarda minutos.',
            onPick: () => Navigator.of(
              context,
            ).pop(const ProfileSlot(source: ProfileSlotSource.claudeCode)),
          ),

          const SizedBox(height: AppSpacing.lg),
          _RemoteSlotSection(profile: profile, slot: slot),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// La seccion de **servicio por internet** de un slot.
///
/// Lista los servicios que ya tienen la clave guardada (DeepSeek, tipicamente)
/// y el «configurar otro», que abre el dialogo por slot. Es la misma seccion
/// para el router y el pensamiento: lo unico que cambia es el `providerId`, que
/// lleva el rol dentro. Un servicio detectado usa la clave **global** del
/// preset (`deepseek.key`), no una copia por slot.
class _RemoteSlotSection extends ConsumerWidget {
  const _RemoteSlotSection({required this.profile, required this.slot});

  final String profile;
  final String slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final presets = ref.watch(aiRemotePresetsProvider).value ?? const [];
    final saved =
        ref.watch(aiRemoteKeysSavedProvider).value ?? const <String>{};
    // Solo los servicios con URL **fija** se ofrecen de un tap: uno elegido
    // asi usa la URL y el modelo del preset. `custom` («Otro (proxy propio)»)
    // no los trae a proposito, asi que se configura por el dialogo (que ya
    // reusa su clave si la hay); si no, el slot quedaria con la direccion vacia.
    final withKey = [
      for (final preset in presets)
        if (saved.contains(preset.id) && preset.baseUrl.isNotEmpty) preset,
    ];
    final roleLabel = slot == 'router' ? 'Router' : 'Pensamiento';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('O usa un servicio por internet'),
        if (withKey.isNotEmpty) ...[
          _Hint('Detectados con una clave que ya tenés guardada:'),
          for (final preset in withKey)
            _SimpleTile(
              icon: Icons.cloud_done,
              iconColor: theme.colorScheme.tertiary,
              title: preset.label,
              subtitle: 'Clave guardada · ${preset.defaultModel}',
              onPick: () => Navigator.of(context).pop(
                ProfileSlot(
                  source: ProfileSlotSource.remote,
                  remoteProviderId: preset.id,
                  remoteBaseUrl: preset.baseUrl,
                  remoteModel: preset.defaultModel,
                  remoteDisplayName: preset.label,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _SimpleTile(
          icon: Icons.cloud_outlined,
          title: withKey.isEmpty
              ? 'Configurar un servicio...'
              : 'Configurar otro servicio...',
          subtitle:
              'Se usará en el $roleLabel de este perfil. '
              'DeepSeek, OpenAI o un proxy propio, con su clave.',
          onPick: () async {
            final slotValue = await showProfileRemoteDialog(
              context,
              providerId: 'remote:$profile.$slot',
            );
            if (slotValue != null && context.mounted) {
              Navigator.of(context).pop(slotValue);
            }
          },
        ),
      ],
    );
  }
}

class _StackTile extends ConsumerStatefulWidget {
  const _StackTile({
    required this.model,
    required this.slot,
    required this.fits,
    required this.downloaded,
    required this.detected,
    required this.onPick,
  });

  final StackModel model;

  /// El slot que se esta eligiendo (`router` o `thinking`): con el se marca si
  /// este rol es apto para lo que se busca.
  final String slot;

  /// Si este rol **cabe** junto al que ya tiene el otro slot del perfil. En
  /// `false` la tarjeta no se deja elegir: es la validacion de VRAM en el sitio.
  final bool fits;
  final bool downloaded;

  /// Si ya se consulto WSL2: sin esto no se puede afirmar que falte, y decir
  /// «falta descargar» de todo antes de mirar es mentir.
  final bool detected;
  final VoidCallback onPick;

  @override
  ConsumerState<_StackTile> createState() => _StackTileState();
}

class _StackTileState extends ConsumerState<_StackTile> {
  /// Se pulso «Descargar» en este tile: su descarga esta (o estaba) en marcha.
  bool _launched = false;

  /// Bytes que ya ocupa el modelo en `~/models/<dir>`, mientras baja. `null`
  /// hasta la primera medida. `hf download --local-dir` escribe los pesos ahi
  /// directo (la cache solo guarda metadatos), asi que sube de forma monotona.
  int? _bytes;

  /// Medida anterior y su instante, para sacar la tasa. Nulos hasta la segunda
  /// lectura: con una sola no hay ventana de tiempo.
  int? _previousBytes;
  DateTime? _previousSampleAt;

  /// Velocidad suavizada en MB/s, o `null` hasta tener dos medidas.
  double? _mbps;

  Timer? _poll;

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(stackControllerProvider)
        .download(widget.model.role);
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _launched = true;
      _bytes = null;
      _previousBytes = null;
      _previousSampleAt = null;
      _mbps = null;
    });
    _startPolling();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Descarga de ${widget.model.label} lanzada. '
          'El detalle completo sale en el panel de Ejecuciones.',
        ),
      ),
    );
  }

  /// Mide el modelo en WSL2 cada 2 s mientras baja. Es una lectura barata
  /// (`du`) y la distro ya esta arrancada por la propia descarga.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _readBytes());
    _readBytes();
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _readBytes() async {
    final bytes =
        await StackCatalogRepository(
          ref.read(stackScriptsDirProvider),
        ).modelDirBytes(
          distro: ref.read(stackDistroProvider),
          dir: widget.model.dir,
        );
    if (!mounted || bytes == null) return;

    final now = DateTime.now();
    final previousBytes = _previousBytes;
    final previousAt = _previousSampleAt;
    double? rate = _mbps;
    if (previousBytes != null && previousAt != null) {
      final sample = downloadRateMbps(
        previousBytes: previousBytes,
        bytes: bytes,
        elapsed: now.difference(previousAt),
      );
      if (sample != null) {
        // Suavizado exponencial: `du` da saltos discretos y sin esto el numero
        // parpadearia una vez cada dos segundos.
        rate = rate == null ? sample : rate * 0.4 + sample * 0.6;
        _previousBytes = bytes;
        _previousSampleAt = now;
      }
    } else {
      // Primera medida: solo fija la linea base.
      _previousBytes = bytes;
      _previousSampleAt = now;
    }

    setState(() {
      _bytes = bytes;
      if (rate != null) _mbps = rate;
    });
  }

  String _progressLabel(double? fraction) {
    final detail = <String>[
      if (fraction != null && _bytes != null) '${(fraction * 100).round()}%',
      if (_bytes != null)
        '${(_bytes! / 1024 / 1024 / 1024).toStringAsFixed(1)} GB',
      if (_mbps != null) '${_mbps!.toStringAsFixed(1)} MB/s',
    ];
    if (detail.isEmpty) return 'Descargando…';
    return 'Descargando… ${detail.join(' · ')}';
  }

  @override
  void initState() {
    super.initState();
    // Si al abrir la hoja ya hay una descarga de **este** rol en marcha (se
    // cerro y se reabrio el selector), se retoma la barra sin haber pulsado
    // nada en esta sesion de la hoja.
    if (ref.read(activeStackDownloadRoleProvider) == widget.model.role) {
      _launched = true;
      _startPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cuando la descarga que se lanzo aqui deja de estar activa, se apaga el
    // «Descargando…». Volver a mirar WSL2 lo hace el controlador de perfiles
    // (una sola vez por transicion), para que el tile pase a «Descargado».
    ref.listen<bool>(stackDownloadingProvider, (previous, next) {
      if (_launched && previous == true && next == false) {
        _stopPolling();
        setState(() {
          _launched = false;
          _bytes = null;
          _previousBytes = null;
          _previousSampleAt = null;
          _mbps = null;
        });
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final model = widget.model;
    // Cualquier descarga activa bloquea el boton: dos `download-models.sh` a la
    // vez compartirian la cache de HuggingFace y se pisarian.
    final downloading = ref.watch(stackDownloadingProvider);
    final done = widget.detected && widget.downloaded;
    final status = !widget.detected
        ? 'Sin comprobar'
        : widget.downloaded
        ? 'Descargado'
        : 'Falta descargar';

    // Fraccion para la barra: bytes medidos / tamano esperado del catalogo. Sin
    // `size_gb` no se puede calcular y queda indeterminada.
    final expectedBytes = model.sizeGb > 0
        ? model.sizeGb * 1024 * 1024 * 1024
        : 0.0;
    final fraction = _launched && expectedBytes > 0 && _bytes != null
        ? (_bytes! / expectedBytes).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        // Sin `fits` la tarjeta queda deshabilitada (cursor normal, sin accion):
        // es la validacion de VRAM, no un aviso que se pueda ignorar.
        onTap: widget.fits ? widget.onPick : null,
        semanticLabel: model.label,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    done ? Icons.download_done : Icons.cloud_download_outlined,
                    size: 16,
                    color: done ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (model.notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  model.notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              if (!widget.fits) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'No cabe junto al modelo del otro slot: la suma se pasa de la VRAM.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rol ${model.role}'
                      '${model.expectedQuant.isNotEmpty ? ' · ${model.expectedQuant}' : ''}'
                      '${model.sizeGb > 0 ? ' · ${model.sizeGb} GB' : ''}'
                      ' · ideal: ${model.role == 'router' ? 'Router' : 'Pensamiento'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        // Si es apto para el slot que se esta eligiendo, se
                        // resalta; si no, queda neutro. El modelo extrano sigue
                        // siendo elegible, solo no se recomienda.
                        color: stackRoleFitsSlot(model.role, widget.slot)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: stackRoleFitsSlot(model.role, widget.slot)
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
                  // Solo se ofrece descargar cuando ya se miro WSL2 y de verdad
                  // falta: antes de detectar no se puede afirmar que haga falta.
                  // Con la descarga en marcha el boton desaparece y manda la barra.
                  if (widget.detected && !done && !_launched)
                    TextButton.icon(
                      onPressed: downloading ? null : _download,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Descargar'),
                    ),
                ],
              ),
              if (_launched) ...[
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _progressLabel(fraction),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleTile extends StatelessWidget {
  const _SimpleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPick,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPick;

  /// Color del icono. `null` usa el neutro; un servicio **detectado** con su
  /// clave ya guardada lo tiñe para que no se vea igual que «configurar otro».
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        onTap: onPick,
        semanticLabel: title,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: iconColor ?? theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un modelo de llama.cpp con su estado y, si falta, la descarga **inline**.
///
/// Es el unico motor con barra dentro de la seccion: Ollama y vLLM descargan
/// por comandos capturados y su progreso sale en el panel de Ejecuciones.
class _LlamaCppTile extends ConsumerStatefulWidget {
  const _LlamaCppTile({required this.option, required this.onPick});

  final bridge.AiModelOption option;
  final VoidCallback onPick;

  @override
  ConsumerState<_LlamaCppTile> createState() => _LlamaCppTileState();
}

class _LlamaCppTileState extends ConsumerState<_LlamaCppTile> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  StreamSubscription<bridge.AiSetupEvent>? _events;

  @override
  void initState() {
    super.initState();
    // El evento no trae el id del modelo, solo el nombre visible del asset; se
    // usa mientras **esta** descarga es la que corre (el motor admite una a la
    // vez), que es suficiente para la barra de este tile.
    _events = aiSetupEventStreamOf(ref).listen((event) {
      if (!mounted || !_downloading) return;
      if (event is bridge.AiSetupEvent_Downloading) {
        final total = event.totalBytes;
        if (total > BigInt.zero) {
          setState(
            () => _progress = event.downloaded.toDouble() / total.toDouble(),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await ref
          .read(aiRepositoryProvider)
          .downloadModel(modelId: widget.option.id);
      ref.invalidate(aiModelOptionsProvider(widget.option.tier));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final option = widget.option;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InteractiveCard(
        onTap: option.installed ? widget.onPick : null,
        semanticLabel: option.displayName,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      option.displayName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (option.installed)
                    Icon(Icons.download_done, size: 16, color: scheme.primary),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                option.notes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    option.installed
                        ? 'Descargado'
                        : formatBytes(option.totalDownloadBytes),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (option.installed)
                    TextButton(
                      onPressed: widget.onPick,
                      child: const Text('Elegir'),
                    )
                  else if (!_downloading)
                    TextButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Descargar'),
                    ),
                ],
              ),
              if (_downloading) ...[
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
