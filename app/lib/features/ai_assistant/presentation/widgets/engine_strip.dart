import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../application/ai_providers.dart';
import '../../../stack/application/stack_health.dart';

/// Lo primero de «Configura tus perfiles»: **que motor hay configurado**.
///
/// Solo mira lo que se puede saber sin arrancar nada: llama.cpp es nativo y
/// siempre esta; Ollama se detecta por HTTP en loopback; vLLM se lee de la
/// pasarela (`:8888`). WSL2 **no se levanta** para dibujar esto.
class EngineStrip extends ConsumerWidget {
  const EngineStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ollama = ref.watch(aiOllamaProvider);
    final health = ref.watch(stackHealthProvider).value;

    final ollamaModels = ollama.value?.models ?? const <String>[];

    final vllmLoaded = <String>[
      if (health?.router == 'up') 'Router',
      if (health?.fast == 'up') 'Gemma',
      if (health?.complex == 'up') 'Complejo',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Motor configurado',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            const _EngineChip(
              icon: Icons.memory_outlined,
              label: 'llama.cpp',
              status: 'integrado',
              ok: true,
            ),
            _EngineChip(
              icon: Icons.dns_outlined,
              label: 'Ollama',
              status: ollamaModels.isEmpty
                  ? 'no detectado'
                  : '${ollamaModels.length} modelos',
              ok: ollamaModels.isNotEmpty,
            ),
            _EngineChip(
              icon: Icons.cloud_outlined,
              label: 'vLLM',
              status: health == null
                  ? 'consultando...'
                  : !health.reachable
                  ? 'apagado'
                  : vllmLoaded.isEmpty
                  ? 'pasarela arriba, sin modelos'
                  : 'cargados: ${vllmLoaded.join(' · ')}',
              ok: health?.hasAnythingUp ?? false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'WSL2 se levanta solo al activar un perfil del stack, y se libera al '
          'apagar el asistente.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({
    required this.icon,
    required this.label,
    required this.status,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: ok ? scheme.primary : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: ok ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
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
    );
  }
}
