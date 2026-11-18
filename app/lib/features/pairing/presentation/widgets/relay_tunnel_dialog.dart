import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/relay.dart' as bridge;

import '../../../../core/theme/app_spacing.dart';
import '../../application/relay_provider.dart';

/// Rol PC: prender/apagar el tunel por relay (fuera de la LAN, sin
/// Tailscale) y ver su estado en vivo. Los campos vienen prellenados con el
/// relay ya desplegado (`relayTunnelConfigProvider`), asi que activarlo por
/// primera vez es solo tocar el switch -- son editables por si el usuario
/// migra a otro VPS alguna vez.
Future<void> showRelayTunnelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _RelayTunnelDialog(),
  );
}

class _RelayTunnelDialog extends ConsumerStatefulWidget {
  const _RelayTunnelDialog();

  @override
  ConsumerState<_RelayTunnelDialog> createState() => _RelayTunnelDialogState();
}

class _RelayTunnelDialogState extends ConsumerState<_RelayTunnelDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(relayTunnelConfigProvider);
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _tokenController = TextEditingController(text: config.tokenHex);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// `null` si los campos no alcanzan para guardar -- deja `_error` puesto.
  RelayTunnelConfig? _parseFields() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final token = _tokenController.text.trim();
    if (host.isEmpty || port == null || token.length != 64) {
      setState(
        () => _error = 'Revisá host, puerto y token (64 caracteres hex).',
      );
      return null;
    }
    setState(() => _error = null);
    return RelayTunnelConfig(host: host, port: port, tokenHex: token);
  }

  Future<void> _generateToken() async {
    final token = await ref.read(relayRepositoryProvider).generateToken();
    setState(() => _tokenController.text = token);
  }

  Future<void> _save() async {
    final config = _parseFields();
    if (config == null) return;
    await ref.read(relayTunnelControllerProvider).saveConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Guardado')));
    }
  }

  Future<void> _toggle(bool enabled) async {
    // Encender usa lo que ya este guardado, no lo que haya sin guardar en
    // los campos -- evita el caso confuso de prender el tunel con un valor
    // que el usuario todavia no confirmo.
    setState(() => _busy = true);
    try {
      await ref.read(relayTunnelControllerProvider).setEnabled(enabled);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(relayTunnelEnabledProvider);
    final status = ref.watch(relayStatusProvider);

    return AlertDialog(
      title: const Text('Túnel remoto'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Un punto de encuentro con IP pública para cuando ni mDNS ni '
              'una VPN alcanzan — la PC y el teléfono se encuentran ahí '
              'aunque los dos estén detrás de su propio CGNAT. El cifrado de '
              'siempre sigue intacto: el túnel solo empalma bytes, nunca '
              'termina el TLS.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.gutter),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Túnel prendido'),
              subtitle: _StatusLabel(enabled: enabled, status: status),
              value: enabled,
              onChanged: _busy ? null : _toggle,
            ),
            const Divider(),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host del relay',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puerto',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _tokenController,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Token (64 caracteres hex)',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _tokenController.text),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Generar uno nuevo',
                      icon: const Icon(Icons.refresh),
                      onPressed: _generateToken,
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.enabled, required this.status});

  final bool enabled;
  final AsyncValue<bridge.RelayStatus> status;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const Text('Apagado — datos móviles sin Tailscale');
    }
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = status.when(
      data: (value) => switch (value) {
        bridge.RelayStatus_Parked() => (
          'Aparcado en el relay, esperando…',
          scheme.primary,
        ),
        bridge.RelayStatus_Matched() => (
          'Conectado a través del túnel',
          Colors.green,
        ),
        bridge.RelayStatus_Stopped() => ('Detenido', scheme.onSurfaceVariant),
        bridge.RelayStatus_Failed(:final reason) => (
          'Reintentando… ($reason)',
          scheme.error,
        ),
      },
      loading: () => ('Conectando…', scheme.onSurfaceVariant),
      error: (e, _) => ('Error: $e', scheme.error),
    );
    return Text(text, style: TextStyle(color: color));
  }
}
