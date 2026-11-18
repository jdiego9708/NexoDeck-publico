import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/notify.dart' as notify_bridge;

import '../../../core/theme/app_spacing.dart';
import '../application/control_activity_controller.dart';
import '../application/control_settings_controller.dart';
import '../domain/notify_channel.dart';
import 'notify_channel_editor_sheet.dart';

/// El panel del servidor de control: encenderlo, ver por donde escucha, copiar
/// lo que hace falta para configurar el cliente, gestionar los canales de aviso
/// y ver que le han pedido a la maquina.
Future<void> showControlPanelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ControlPanelDialog(),
  );
}

class _ControlPanelDialog extends ConsumerStatefulWidget {
  const _ControlPanelDialog();

  @override
  ConsumerState<_ControlPanelDialog> createState() =>
      _ControlPanelDialogState();
}

class _ControlPanelDialogState extends ConsumerState<_ControlPanelDialog> {
  bool _busy = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final token = await ref.read(controlRepositoryProvider).ensureToken();
      if (mounted) setState(() => _token = token);
    } catch (_) {
      // Sin token no se puede configurar el cliente, pero el resto del panel
      // sigue sirviendo. El estado del servidor ya dira que no arranco.
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _busy = true);
    try {
      await ref.read(controlSettingsControllerProvider).setEnabled(enabled);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what copiado')));
  }

  /// Prueba un canal: primero en seco, y despues de verdad si el usuario lo
  /// confirma. El ensayo es lo que permite comprobar la configuracion sin
  /// gastarle un mensaje al usuario.
  Future<void> _testChannel(NotifyChannel channel, {required bool dryRun}) async {
    final outcomes = await ref.read(controlRepositoryProvider).send(
      channels: [channel],
      text: dryRun
          ? 'Prueba de NexoDeck'
          : 'NexoDeck: prueba del canal ${channel.label}',
      level: notify_bridge.NotifyLevel.always,
      dryRun: dryRun,
    );
    if (!mounted) return;

    final outcome = outcomes.isEmpty ? null : outcomes.first;
    final message = switch (outcome) {
      null => 'El canal no se pudo leer.',
      final o when o.dryRun => 'Se ejecutaria: ${o.detail}',
      final o when o.delivered => 'Entregado.',
      final o when o.skipped => 'Saltado: ${o.detail}',
      final o => 'NO entregado. ${o.detail}',
    };
    final failed = outcome?.failed ?? true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: failed ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(controlServerEnabledProvider);
    final status = ref.watch(controlServerStatusProvider);
    final channels = ref.watch(notifyChannelsProvider);
    final activity = ref.watch(controlActivityProvider);

    return AlertDialog(
      title: const Text('Servidor de control'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Deja que Claude Code, en esta misma maquina, le pida cosas a '
                'NexoDeck: mandarte un aviso, o consultar que comandos estan '
                'corriendo. Escucha solo en 127.0.0.1 y exige el token.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: _busy ? null : _toggle,
                title: const Text('Servidor encendido'),
                subtitle: Text(_statusText(status, enabled)),
              ),
              if (status.error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ref
                        .read(controlSettingsControllerProvider)
                        .retryStart(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ),

              const Divider(height: AppSpacing.xl),
              Text('Configurar el cliente', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _CopyRow(
                label: 'URL',
                value: 'http://127.0.0.1:${status.port ?? 58646}/mcp',
                onCopy: _copy,
              ),
              const SizedBox(height: AppSpacing.xs),
              _CopyRow(
                label: 'Token',
                value: _token ?? 'cargando...',
                obscure: true,
                onCopy: _token == null ? null : _copy,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'El token es un secreto: no vive en la base de datos, sino en '
                'el directorio de datos de NexoDeck. Ponelo en una variable de '
                'entorno y referencialo desde la configuracion del cliente, en '
                'vez de escribirlo en un fichero del proyecto.',
                style: theme.textTheme.bodySmall,
              ),

              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Canales de aviso',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => showNotifyChannelEditor(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir'),
                  ),
                ],
              ),
              if (channels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'Sin canales, la herramienta de avisar falla en vez de '
                    'callarse. Un aviso que no tiene por donde salir no se '
                    'puede parecer a uno entregado.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else
                ...channels.map(
                  (channel) => _ChannelRow(
                    channel: channel,
                    onEdit: () =>
                        showNotifyChannelEditor(context, existing: channel),
                    onRemove: () => ref
                        .read(controlSettingsControllerProvider)
                        .removeChannel(channel.id),
                    onDryRun: () => _testChannel(channel, dryRun: true),
                    onSend: () => _testChannel(channel, dryRun: false),
                  ),
                ),

              const Divider(height: AppSpacing.xl),
              Text('Actividad', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (activity.entries.isEmpty)
                Text(
                  'Todavia no llego ninguna peticion.',
                  style: theme.textTheme.bodySmall,
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: activity.entries.length,
                    itemBuilder: (context, index) {
                      final entry = activity.entries[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxs,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _iconFor(entry.kind),
                              size: 16,
                              color: entry.ok
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                entry.text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: entry.ok
                                      ? null
                                      : theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  String _statusText(ControlServerStatus status, bool enabled) {
    if (status.error != null) return status.error!;
    if (status.isRunning) return 'Escuchando en 127.0.0.1:${status.port}';
    return enabled ? 'Arrancando...' : 'Apagado';
  }

  IconData _iconFor(ControlActivityKind kind) => switch (kind) {
    ControlActivityKind.started => Icons.play_arrow,
    ControlActivityKind.stopped => Icons.stop,
    ControlActivityKind.toolCall => Icons.bolt,
    ControlActivityKind.rejected => Icons.block,
  };
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.obscure = false,
  });

  final String label;
  final String value;
  final bool obscure;
  final Future<void> Function(String value, String what)? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // El token se muestra recortado: el panel se abre delante de quien esté
    // mirando la pantalla, y el valor entero no aporta nada a ojo.
    final shown = obscure && value.length > 12
        ? '${value.substring(0, 8)}...${value.substring(value.length - 4)}'
        : value;

    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: theme.textTheme.labelMedium),
        ),
        Expanded(
          child: Text(
            shown,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          onPressed: onCopy == null ? null : () => onCopy!(value, label),
          icon: const Icon(Icons.copy, size: 18),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.onEdit,
    required this.onRemove,
    required this.onDryRun,
    required this.onSend,
  });

  final NotifyChannel channel;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onDryRun;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: channel.enabled
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  [
                    channel.program,
                    if (channel.minLevel == NotifyMinLevel.always)
                      'solo lo critico',
                    if (!channel.enabled) 'desactivado',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDryRun, child: const Text('En seco')),
          TextButton(onPressed: onSend, child: const Text('Probar')),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 18),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}
