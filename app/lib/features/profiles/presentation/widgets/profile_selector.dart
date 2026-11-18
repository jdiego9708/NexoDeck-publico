import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../actions/presentation/widgets/action_icons.dart';
import '../../application/active_profile_controller.dart';
import '../../application/profiles_provider.dart';
import '../../domain/deck_profile.dart';
import '../profile_editor_dialog.dart';

/// Selector del perfil activo para la barra superior.
///
/// Muestra el perfil actual y, si se activo solo por deteccion de proceso,
/// lo dice: un deck que cambia de contenido sin que nadie lo toque es
/// desconcertante si no se explica de donde salio.
class ProfileSelector extends ConsumerWidget {
  const ProfileSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesListProvider).value ?? const [];
    final active = ref.watch(activeProfileProvider);

    // Sin perfiles no hay nada que seleccionar: en vez de un desplegable
    // vacio, un acceso directo a crear el primero.
    if (profiles.isEmpty) {
      return TextButton.icon(
        onPressed: () => showProfileEditorDialog(context),
        icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
        label: const Text('Perfiles'),
      );
    }

    return PopupMenuButton<_ProfileMenuValue>(
      tooltip: 'Perfil activo',
      onSelected: (value) async {
        switch (value) {
          case _ProfileMenuAll():
            await ref.read(activeProfileControllerProvider).select(null);
          case _ProfileMenuCreate():
            if (context.mounted) await showProfileEditorDialog(context);
          case _ProfileMenuEdit(:final profile):
            if (context.mounted) {
              await showProfileEditorDialog(context, existing: profile);
            }
          case _ProfileMenuPick(:final profile):
            await ref.read(activeProfileControllerProvider).select(profile.id);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: const _ProfileMenuAll(),
          child: _MenuRow(
            icon: Icons.apps_rounded,
            label: 'Todas las acciones',
            selected: active == null,
          ),
        ),
        const PopupMenuDivider(),
        for (final profile in profiles)
          PopupMenuItem(
            value: _ProfileMenuPick(profile),
            child: _MenuRow(
              icon: iconForName(profile.icon),
              color: colorFromHex(profile.colorHex),
              label: profile.name,
              // El ejecutable que lo dispara es justo el dato que uno
              // necesita cuando el perfil "no cambia solo" y no se sabe por
              // que.
              subtitle: profile.autoDetectProcess,
              selected: active?.id == profile.id,
              onEdit: () => Navigator.of(
                context,
              ).pop(_ProfileMenuEdit(profile)),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ProfileMenuCreate(),
          child: _MenuRow(icon: Icons.add, label: 'Nuevo perfil'),
        ),
      ],
      child: _ActiveProfileChip(active: active),
    );
  }
}

class _ActiveProfileChip extends StatelessWidget {
  const _ActiveProfileChip({required this.active});

  final DeckProfile? active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = this.active;
    final color = active == null
        ? scheme.onSurfaceVariant
        : colorFromHex(active.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active == null ? Icons.apps_rounded : iconForName(active.icon),
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          // `Flexible` + elipsis: la barra superior puede apretar este chip
          // (mas botones a la derecha, o una ventana angosta) y sin esto el
          // nombre del perfil desbordaba la fila del titulo en vez de
          // recortarse.
          Flexible(
            child: Text(
              active?.name ?? 'Todas',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    this.selected = false,
    this.onEdit,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final bool selected;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: selected
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  'auto: $subtitle',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (selected)
          Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
        if (onEdit != null)
          IconButton(
            tooltip: 'Editar perfil',
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: onEdit,
          ),
      ],
    );
  }
}

sealed class _ProfileMenuValue {
  const _ProfileMenuValue();
}

class _ProfileMenuAll extends _ProfileMenuValue {
  const _ProfileMenuAll();
}

class _ProfileMenuCreate extends _ProfileMenuValue {
  const _ProfileMenuCreate();
}

class _ProfileMenuPick extends _ProfileMenuValue {
  const _ProfileMenuPick(this.profile);
  final DeckProfile profile;
}

class _ProfileMenuEdit extends _ProfileMenuValue {
  const _ProfileMenuEdit(this.profile);
  final DeckProfile profile;
}
