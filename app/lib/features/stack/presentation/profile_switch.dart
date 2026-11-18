import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/stack_controller.dart';
import '../application/stack_health.dart';
import '../domain/stack_profile.dart';
import 'stack_config_dialog.dart';

/// El perfil del stack (A / B / C / Apagado), en un menu sutil.
///
/// **MODO…** abre los tres perfiles, con el actual marcado y que levanta cada
/// uno; al lado va el estado real (que dice la pasarela) y el engranaje para
/// apuntar la carpeta. Antes eran tres segmentos fijos ocupando una fila
/// entera, que pesaban mas que la propia conversacion.
///
/// Es un control de ESCRITORIO: arranca scripts de PowerShell/WSL en la PC. No
/// se monta en el dialogo del asistente (ni en el movil).
class ProfileSwitch extends ConsumerWidget {
  const ProfileSwitch({
    super.key,
    this.describe,
    this.onSelect,
    this.localModelsExpected,
  });

  /// Texto de los modelos de cada perfil, para el menu. Lo cablea quien monta el
  /// switch (`ai_chat_view`) desde la config del asistente: asi el renglon dice
  /// los modelos **elegidos** (locales o de la nube) en vez de los de la receta,
  /// y se actualiza en tiempo real. Sin esto cae al `detail` de reserva.
  final String Function(StackProfile profile)? describe;

  /// Si el perfil elegido tiene roles locales en el stack (lo cablea el chat).
  /// `false` hace que una pasarela caida no se anuncie como fallo: el perfil es
  /// de nube. `null` = no se sabe, mensaje de siempre.
  final bool? localModelsExpected;

  /// Aplica el perfil elegido. Lo cablea `ai_chat_view` con `activateProfile`,
  /// que ademas de arrancar/parar el stack pone a contestar el motor del slot de
  /// Pensamiento (y apaga el anterior, p. ej. el llama.cpp local). Sin esto el
  /// switch solo arranca vLLM y el motor local se quedaria ocupando la GPU.
  /// Devuelve `null` o el motivo del fallo.
  final Future<String?> Function(StackProfile profile)? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = ref.watch(selectedStackProfileProvider);
    final health = ref.watch(stackHealthProvider).value;
    final starting = ref.watch(stackStartingProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          PopupMenuButton<StackProfile>(
            tooltip: 'Modo del stack',
            // Mientras arranca (o para) el perfil no se puede pedir otro: dos
            // arranques se pelearian por la GPU y el segundo llegaria con el
            // primero a medias.
            enabled: !starting,
            onSelected: (profile) => _select(context, ref, profile),
            itemBuilder: (context) => [
              for (final profile in StackProfile.values)
                PopupMenuItem<StackProfile>(
                  value: profile,
                  child: _ModeItem(
                    profile: profile,
                    selected: profile == selected,
                    detail: describe?.call(profile),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MODO…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Icon(
                    Icons.expand_more,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _HealthLine(
              health: health,
              starting: starting,
              profileLabel: selected.label,
              localModelsExpected: localModelsExpected,
            ),
          ),
          IconButton(
            tooltip: 'Carpeta del stack',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings_outlined, size: 18),
            onPressed: () => showStackConfigDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    StackProfile profile,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = onSelect != null
        ? await onSelect!(profile)
        : await ref.read(stackControllerProvider).select(profile);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Un renglon del menu de modo: el nombre y, debajo, que levanta.
class _ModeItem extends StatelessWidget {
  const _ModeItem({required this.profile, required this.selected, this.detail});

  final StackProfile profile;
  final bool selected;

  /// Los modelos elegidos, si quien monta el switch los conoce. Cae al `detail`
  /// de reserva si no.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Ancho fijo: el detalle son los modelos elegidos y puede ser largo
    // ("Router: Qwen 3.5 4B (NVFP4) · Pensamiento: Gemma 4 12B (AWQ)"). Sin
    // limite el renglon desbordaba el menu; con `Expanded` el `Text` envuelve.
    return SizedBox(
      width: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check,
            size: 16,
            color: selected ? scheme.primary : Colors.transparent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.label, style: theme.textTheme.labelLarge),
                Text(
                  detail ?? profile.detail,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una linea con lo que la pasarela dice que hay cargado. Distingue tres casos
/// que desde la pantalla se ven igual: sin respuesta, pasarela arriba sin
/// modelos, y modelos cargados.
class _HealthLine extends StatelessWidget {
  const _HealthLine({
    required this.health,
    this.starting = false,
    this.profileLabel = '',
    this.localModelsExpected,
  });

  final StackHealth? health;

  /// Hay un comando del stack en marcha: arrancando o parando.
  final bool starting;

  final String profileLabel;

  /// Si el perfil elegido tiene roles locales en el stack. `null` = no se sabe
  /// (o es «Apagado»). En `false`, la pasarela caida no es un fallo que reportar:
  /// el perfil es de nube y no levanta ningun modelo local.
  final bool? localModelsExpected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Lo que pasa ahora manda sobre lo que dice la pasarela: mientras arranca,
    // "la pasarela no responde" es lo esperado, no un fallo que haya que
    // reportar aparte.
    if (starting) {
      return Text(
        'Arrancando «$profileLabel»… puede tardar 2–6 minutos.',
        style: style,
      );
    }

    final current = health;
    if (current == null) {
      return Text('Consultando el stack…', style: style);
    }
    if (!current.reachable) {
      if (localModelsExpected == false) {
        return Text(
          'Sin modelos locales: este perfil usa la nube.',
          style: style,
        );
      }
      return Text(
        'La pasarela no responde (stack apagado o arrancando).',
        style: style,
      );
    }
    if (!current.hasAnythingUp) {
      return Text('Pasarela arriba, sin modelos cargados.', style: style);
    }
    final loaded = [
      if (current.router == 'up') 'Router',
      if (current.fast == 'up') 'Gemma',
      if (current.complex == 'up') 'Complejo',
      if (current.writer == 'up') 'Qwen 9B',
    ];
    return Text('En tu equipo: ${loaded.join(' · ')}', style: style);
  }
}
