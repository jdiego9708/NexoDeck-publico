import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as bridge;

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_surface.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/ai_providers.dart';
import '../domain/setup_progress.dart';
import 'widgets/download_progress_card.dart';
import 'widgets/hardware_summary_card.dart';
import 'widgets/profiles_section.dart';

/// Wizard de instalacion del motor de IA.
///
/// La configuracion de modelos vive ahora en **una sola seccion**,
/// `ProfilesSection`: los perfiles A y B, cada uno con su router y su modelo de
/// pensamiento, elegidos entre los motores detectados (stack vLLM, llama.cpp,
/// Ollama, Claude Code o un servicio por internet). Antes eran dos bloques
/// separados («Quien puede contestar» y «Elegi el modelo»).
class AiSetupWizard extends ConsumerStatefulWidget {
  const AiSetupWizard({super.key, required this.onReady});

  final VoidCallback onReady;

  @override
  ConsumerState<AiSetupWizard> createState() => _AiSetupWizardState();
}

class _AiSetupWizardState extends ConsumerState<AiSetupWizard> {
  StreamSubscription<bridge.AiSetupEvent>? _subscription;
  SetupProgress _progress = SetupProgress.idle;

  @override
  void initState() {
    super.initState();
    _subscription = aiSetupEventStreamOf(ref).listen((event) {
      if (!mounted) return;
      setState(() => _progress = progressFor(event));
      if (_progress.phase == SetupPhase.ready) widget.onReady();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// El id llega **resuelto** desde el pie, nunca `null`.
  Future<void> _start(String modelId) async {
    setState(
      () => _progress = const SetupProgress(
        phase: SetupPhase.probing,
        title: 'Preparando',
      ),
    );
    try {
      await ref.read(aiRepositoryProvider).startSetup(modelId: modelId);
    } catch (error) {
      if (!mounted) return;
      // El stream ya emitio un `Failed`, pero si la llamada fallo antes de
      // llegar al engine (por ejemplo, plataforma no soportada) no habria
      // ningun evento y el wizard se quedaria mudo.
      setState(() {
        if (_progress.phase != SetupPhase.failed) {
          _progress = SetupProgress(
            phase: SetupPhase.failed,
            title: 'No se pudo preparar el asistente',
            detail: '$error',
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDuration.state,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_progress.phase == SetupPhase.failed) {
      return SingleChildScrollView(
        key: const ValueKey('failed'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _Failure(
          progress: _progress,
          onRetry: () => setState(() => _progress = SetupProgress.idle),
        ),
      );
    }
    if (_progress.isRunning) {
      return Center(
        key: const ValueKey('running'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: DownloadProgressCard(
            progress: _progress,
            onCancel: _progress.phase == SetupPhase.downloading
                ? () => ref.read(aiRepositoryProvider).cancelSetup()
                : null,
          ),
        ),
      );
    }

    return _Chooser(key: const ValueKey('choose'), onStart: _start);
  }
}

class _Chooser extends ConsumerWidget {
  const _Chooser({super.key, required this.onStart});

  /// Recibe el id **ya resuelto** del modelo local a instalar.
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(aiCapabilitiesProvider);

    return capabilities.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: EmptyState(
          icon: Icons.memory,
          title: 'Revisando tu equipo',
          message: 'Detectando GPU, memoria y espacio libre.',
          leading: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'No se pudo leer el hardware',
          message: '$error',
        ),
      ),
      data: (capabilities) {
        // El pie sigue ofreciendo el modelo local recomendado: los perfiles
        // deciden que carga el stack, pero activar el motor de llama.cpp en
        // esta maquina sigue siendo una accion del wizard.
        final options = ref.watch(
          aiModelOptionsProvider(capabilities.recommendedTier),
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HardwareSummaryCard(capabilities: capabilities),
            const SizedBox(height: AppSpacing.lg),
            ProfilesSection(
              onActivate: (profile) async {
                final error = await activateProfile(ref, profile);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                }
              },
            ),
          ],
        );

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: content,
              ),
            ),
            // Pie fijo: la accion primaria no puede depender de que el usuario
            // scrollee.
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: AppSurface.hairline(Theme.of(context).colorScheme),
                ),
              ),
              child: Builder(
                builder: (context) {
                  final available = options.value;
                  final effective = available
                      ?.firstWhere(
                        (option) => option.isDefault,
                        orElse: () => available.first,
                      )
                      .id;

                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: effective == null
                          ? null
                          : () => onStart(effective),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(
                        effective == null
                            ? 'Cargando el catalogo...'
                            : _startLabel(available!, effective),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _startLabel(List<bridge.AiModelOption> options, String modelId) {
    final option = options.firstWhere(
      (option) => option.id == modelId,
      orElse: () => options.first,
    );
    if (option.installed) return 'Activar el asistente local';
    // El tamano exacto **antes** de empezar: descargar varios GB sin avisar no
    // es una opcion.
    return 'Descargar ${formatBytes(option.totalDownloadBytes)} y activar';
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.progress, required this.onRetry});

  final SetupProgress progress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          EmptyState(
            icon: Icons.cloud_off,
            title: progress.title,
            message: progress.detail ?? '',
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
