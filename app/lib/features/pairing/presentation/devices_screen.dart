import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/interactive_card.dart';
import 'widgets/device_avatar.dart';
import '../application/devices_provider.dart';
import '../application/pairing_provider.dart';
import '../domain/paired_device.dart';
import 'pairing_sheet.dart';
import 'widgets/usb_status_banner.dart';

/// Rol PC: lista de dispositivos emparejados, con revocacion y borrado.
/// "Emparejar dispositivo" abre `showPairingSheet`.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(pairedDevicesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPairingSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Emparejar dispositivo'),
      ),
      body: Column(
        children: [
          const _TransportHostErrorBanner(),
          const UsbStatusBanner(),
          Expanded(
            child: devices.when(
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.devices_other_outlined,
                      title: 'Ningun dispositivo emparejado',
                      message:
                          'Emparejá tu telefono para usarlo como control '
                          'remoto de este equipo.',
                      action: FilledButton.tonalIcon(
                        onPressed: () => showPairingSheet(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Emparejar dispositivo'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _DeviceTile(device: list[index]),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Center(child: Text('Error cargando dispositivos: $error')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explica por que emparejar no va a funcionar cuando el host de
/// transporte no arranco. Sin esto, el boton "Emparejar dispositivo" abria
/// una hoja que simplemente nunca mostraba un PIN, sin decir por que.
class _TransportHostErrorBanner extends ConsumerWidget {
  const _TransportHostErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(transportHostErrorProvider);
    if (error == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No se pudo iniciar el servidor de conexiones, asi que no se '
              'puede emparejar por WiFi. Suele ser el puerto ocupado por '
              'otra instancia de NexoDeck.\n$error',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `InteractiveCard` y no un `Container` decorado a mano: era literalmente
    // `AppSurface.cardDecoration` reimplementado, pero sin hover ni foco de
    // teclado, en una pantalla de escritorio.
    return InteractiveCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.xs,
        ),
        leading: DeviceAvatar(platform: device.platform),
        title: Text(
          device.name,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(_subtitle(device)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: device.isAuthorized,
              onChanged: (value) => ref
                  .read(devicesRepositoryProvider)
                  .setAuthorized(device.id, value),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  ref.read(devicesRepositoryProvider).deleteDevice(device.id),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(PairedDevice device) {
    if (!device.isAuthorized) return 'Revocado';
    final connected = device.lastConnectedAt;
    if (connected == null) return 'Nunca conectado';
    return 'Ultima conexion: ${connected.toLocal()}';
  }
}
