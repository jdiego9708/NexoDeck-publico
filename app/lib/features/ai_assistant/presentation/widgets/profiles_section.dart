import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../../stack/application/stack_controller.dart';
import '../../../stack/application/stack_health.dart';
import '../../../stack/domain/stack_profile.dart';
import '../../application/ai_profiles_controller.dart';
import '../../application/ai_providers.dart';
import '../../application/chat_destinations_controller.dart';
import '../../domain/ai_profile.dart';
import '../../domain/chat_backend.dart';
import 'engine_strip.dart';
import 'model_picker_sheet.dart';

/// Aplica un perfil: deja andando **lo que contesta** el chat.
///
/// El slot de pensamiento decide quien contesta de verdad: un rol del stack
/// (vLLM), un modelo de llama.cpp, uno de Ollama, la sesion de Claude Code o un
/// servicio por internet. Instalar el motor **reemplaza el anterior** —asi un
/// perfil de nube apaga el llama.cpp local y libera su VRAM— y ademas se fija el
/// **destino del chat** para que la etiqueta y el enrutado coincidan. Devuelve
/// `null` si salio bien o el motivo si no.
///
/// Si el perfil **no tiene ningun rol local** (los dos slots fuera del stack),
/// ademas **para el stack**: si no, los modelos vLLM que ya estuvieran cargados
/// se quedan ocupando la GPU aunque la UI diga que se usa la nube.
Future<String?> activateProfile(WidgetRef ref, String profile) async {
  final config = ref.read(aiProfilesProvider).config.forProfile(profile);
  final thinking = config.thinking;

  try {
    // Un perfil sin rol local no arranca vLLM: al contrario, si habia uno
    // levantado hay que pararlo. Fue lo que dejo un `vllm-writer` vivo ocupando
    // 13 GiB tras pasar el perfil C a DeepSeek.
    final hasLocalRole = config.router.isStack || config.thinking.isStack;
    if (!hasLocalRole) {
      // Se para vLLM pero **conservando** el perfil elegido en el MODO: asi
      // elegir «Perfil C» (todo nube) libera la GPU sin acabar diciendo «Apagado».
      final stopError = await ref
          .read(stackControllerProvider)
          .stopStackKeeping(stackProfileFor(profile));
      if (stopError != null) return stopError;
    }

    switch (thinking.source) {
      case ProfileSlotSource.stack:
        // El stack ya lee `profiles.json`; solo hay que lanzarlo.
        return await ref
            .read(stackControllerProvider)
            .select(stackProfileFor(profile));
      case ProfileSlotSource.llamaCpp:
        await ref
            .read(aiRepositoryProvider)
            .startSetup(modelId: thinking.model);
        // Instalar un motor ya apaga el anterior (libera su VRAM); ademas se
        // fija el **destino** y se guarda por defecto, para que la etiqueta del
        // chat y el enrutado coincidan y sobreviva al reinicio.
        await ref
            .read(chatDestinationsProvider.notifier)
            .setDefault('local:${thinking.model}');
        ref.read(chatBackendProvider.notifier).state =
            'local:${thinking.model}';
        return null;
      case ProfileSlotSource.ollama:
        await ref.read(aiRepositoryProvider).useOllama(thinking.model!);
        await ref
            .read(chatDestinationsProvider.notifier)
            .setDefault('ollama:${thinking.model}');
        ref.read(chatBackendProvider.notifier).state =
            'ollama:${thinking.model}';
        return null;
      case ProfileSlotSource.remote:
        final providerId = thinking.remoteProviderId;
        if (providerId == null) {
          return 'Ese slot no tiene el servicio configurado.';
        }
        final key = await ref
            .read(aiRepositoryProvider)
            .remoteApiKey(providerId);
        if (key == null || key.isEmpty) {
          return 'Falta la clave del servicio. Configuralo de nuevo.';
        }
        await ref
            .read(aiRepositoryProvider)
            .useRemote(
              providerId: providerId,
              baseUrl: thinking.remoteBaseUrl ?? '',
              model: thinking.remoteModel ?? '',
              apiKey: key,
              displayName:
                  thinking.remoteDisplayName ?? 'Servicio por internet',
            );
        // `useRemote` reemplaza el proveedor del motor: si el anterior era el
        // llama.cpp local, se apaga y libera la VRAM. Ademas se guarda como
        // **config remota** y **destino por defecto**, para que `restoreDefault`
        // lo vuelva a instalar al arrancar (si no, DeepSeek no sobrevivia).
        final destinations = ref.read(chatDestinationsProvider.notifier);
        await destinations.saveRemoteConfig(
          RemoteProviderConfig(
            providerId: providerId,
            baseUrl: thinking.remoteBaseUrl ?? '',
            model: thinking.remoteModel ?? '',
            displayName: thinking.remoteDisplayName ?? 'Servicio por internet',
          ),
        );
        await destinations.setDefault('remote:$providerId');
        ref.read(chatBackendProvider.notifier).state = 'remote:$providerId';
        return null;
      case ProfileSlotSource.claudeCode:
        ref.read(chatBackendProvider.notifier).state = kClaudeCodeBackendId;
        return null;
    }
  } catch (error) {
    return '$error';
  }
}

/// «Configura tus perfiles»: una sola seccion que reemplaza a «Quien puede
/// contestar» y a «Elegi el modelo».
///
/// Cada perfil (A, B y C) tiene dos slots —router y pensamiento— y cada slot
/// sale de un motor: un rol del stack vLLM, un modelo de llama.cpp, un modelo
/// de Ollama, la sesion de Claude Code o un servicio por internet.
class ProfilesSection extends ConsumerStatefulWidget {
  const ProfilesSection({super.key, this.onActivate});

  /// Se llama cuando el usuario pide levantar el perfil. Lo cablea quien monta
  /// la seccion (F4), para no meter dependencias del stack en este widget.
  final Future<void> Function(String profile)? onActivate;

  @override
  ConsumerState<ProfilesSection> createState() => _ProfilesSectionState();
}

class _ProfilesSectionState extends ConsumerState<ProfilesSection> {
  @override
  void initState() {
    super.initState();
    // Se comprueba al ENTRAR, no con un boton. `detectInstalled` **no levanta
    // WSL2**: solo mira si esta arriba y, si lo esta, lista `~/models`. Es lo que
    // hace que los perfiles y los botones «Descargar» aparezcan solos, sin un
    // paso manual. Un fallo (distro apagada) se muestra, no se esconde.
    Future.microtask(
      () => ref.read(aiProfilesProvider.notifier).detectInstalled(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(aiProfilesProvider);
    final vram = ref.watch(aiVramBudgetProvider);
    final vramByRole = {for (final m in state.catalog) m.role: m.vramGb};
    // Salud real de la pasarela: dice que perfil esta **levantado** ahora, para
    // que la tarjeta muestre «Perfil iniciado» en vez de «Levantar».
    final health = ref.watch(stackHealthProvider).value;

    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Un perfil cuyos modelos del stack no esten descargados no se puede
    // arrancar: mostrar su tarjeta solo invita a pulsar «Levantar» y comerse un
    // error. Se oculta, pero **solo cuando ya se miro WSL2**: sin detectar no se
    // puede afirmar que falte nada, y esconder los tres seria peor.
    const allProfiles = ['A', 'B', 'C'];
    final canFilter =
        state.detected &&
        state.detection.error == null &&
        state.catalog.isNotEmpty;
    final visibleProfiles = canFilter
        ? allProfiles.where(state.isProfileRunnable).toList()
        : allProfiles;
    final hiddenProfiles = canFilter
        ? allProfiles.where((p) => !state.isProfileRunnable(p)).toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EngineStrip(),
        const SizedBox(height: AppSpacing.lg),

        Row(
          children: [
            Expanded(
              child: Text(
                'Configura tus perfiles',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (state.detecting) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Comprobando descargados…',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'PERFIL A, B y C: cada uno con su modelo liviano (router) y su '
          'modelo de pensamiento. Se guarda en el stack para que lo levante la '
          'próxima vez. El C es el trabajador de texto para preguntas y '
          'conocimiento general.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (state.detection.error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            state.detection.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),

        for (final profile in visibleProfiles) ...[
          _ProfileCard(
            profile: profile,
            config: state.config.forProfile(profile),
            state: state,
            vramByRole: vramByRole,
            budgetGb: vram.budgetGb,
            health: health,
            onPick: (slot) async {
              final chosen = await showProfileSlotPicker(
                context,
                profile: profile,
                slot: slot,
              );
              if (chosen == null) return;
              final current = ref
                  .read(aiProfilesProvider)
                  .config
                  .forProfile(profile);
              final next = slot == 'router'
                  ? current.copyWith(router: chosen)
                  : current.copyWith(thinking: chosen);
              final error = await ref
                  .read(aiProfilesProvider.notifier)
                  .save(profile, next);
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error)));
              }
            },
            onActivate: widget.onActivate == null
                ? null
                : () => widget.onActivate!(profile),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (hiddenProfiles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ocultos hasta descargar sus modelos: ${hiddenProfiles.join(', ')}. '
            'Se bajan desde el selector de cualquier perfil: tocá un modelo → '
            '«Comprobar descargados» → «Descargar».',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.config,
    required this.state,
    required this.vramByRole,
    required this.budgetGb,
    required this.health,
    required this.onPick,
    required this.onActivate,
  });

  final String profile;
  final AiProfileConfig config;
  final AiProfilesState state;

  /// Huella de VRAM por rol del stack y presupuesto del equipo (GiB). `0` en el
  /// presupuesto es "no se sabe".
  final Map<String, double> vramByRole;
  final double budgetGb;

  /// Salud de la pasarela: con ella se sabe si este es el perfil **iniciado**.
  final StackHealth? health;
  final ValueChanged<String> onPick;
  final Future<void> Function()? onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detected = state.detected && state.detection.error == null;

    // Huella de VRAM del perfil: los roles del stack, cada uno una vez. Un slot
    // de otro motor no puntua (no lo sirve vLLM).
    final footprint = stackRolesVramGb([
      if (config.router.isStack) config.router.model ?? '',
      if (config.thinking.isStack) config.thinking.model ?? '',
    ], vramByRole);
    final overBudget = budgetGb > 0 && footprint > budgetGb;

    // «Iniciado» = todos los roles del stack de este perfil reportan `up`. Un
    // perfil a medias (p. ej. solo el router) no cuenta.
    final stackRoles = <String>{
      if (config.router.isStack) config.router.model ?? '',
      if (config.thinking.isStack) config.thinking.model ?? '',
    }..removeWhere((role) => role.isEmpty);
    final h = health;
    final started = h != null && stackRolesStarted(stackRoles, h);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppSurface.cardDecoration(
        scheme,
        hovered: false,
        focused: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Perfil $profile',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (started)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: scheme.primary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Perfil iniciado',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else if (onActivate != null)
                TextButton(
                  onPressed: onActivate,
                  child: const Text('Levantar'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _SlotTile(
            slotLabel: 'Router',
            detail: 'Modelo liviano: clasifica y enruta.',
            slot: config.router,
            state: state,
            detected: detected,
            onTap: () => onPick('router'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SlotTile(
            slotLabel: 'Pensamiento',
            detail: 'El modelo trabajador: el que responde de verdad.',
            slot: config.thinking,
            state: state,
            detected: detected,
            onTap: () => onPick('thinking'),
          ),
          if (budgetGb > 0 && footprint > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              overBudget
                  ? 'No caben juntos: ${footprint.toStringAsFixed(1)} GiB > '
                        '${budgetGb.toStringAsFixed(1)} GiB de VRAM.'
                  : 'VRAM estimada: ${footprint.toStringAsFixed(1)} / '
                        '${budgetGb.toStringAsFixed(1)} GiB.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: overBudget ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slotLabel,
    required this.detail,
    required this.slot,
    required this.state,
    required this.detected,
    required this.onTap,
  });

  final String slotLabel;
  final String detail;
  final ProfileSlot slot;
  final AiProfilesState state;
  final bool detected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stackModel = slot.isStack ? state.stackModelByRole(slot.model) : null;
    final subtitle = stackModel?.notes.isNotEmpty == true
        ? stackModel!.notes
        : detail;

    String? status;
    Color? statusColor;
    if (slot.isRemote) {
      status = 'Por internet';
      statusColor = scheme.tertiary;
    } else if (slot.isClaudeCode) {
      status = 'Terminal';
      statusColor = scheme.tertiary;
    } else if (slot.isStack) {
      if (!detected) {
        status = 'Sin comprobar';
      } else {
        final installed = state.isStackRoleInstalled(slot.model);
        status = installed ? 'Descargado' : 'Falta descargar';
        statusColor = installed ? scheme.primary : scheme.error;
      }
    }

    return InteractiveCard(
      onTap: onTap,
      semanticLabel: '$slotLabel: ${slot.label}',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  slotLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (status != null)
                  Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor ?? scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              stackModel?.label ?? slot.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
