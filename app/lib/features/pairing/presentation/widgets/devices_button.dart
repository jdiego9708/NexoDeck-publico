import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/devices_provider.dart';
import '../devices_screen.dart';

/// Entrada al flujo de pairing/dispositivos, solo desktop -- en Android el
/// pairing vive directo en `AndroidShell` (no hay un "home" previo desde
/// donde abrir esto).
class DevicesButton extends ConsumerWidget {
  const DevicesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(pairedDevicesListProvider);
    final count = devices.value?.length ?? 0;

    return IconButton(
      tooltip: 'Dispositivos emparejados',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.devices_outlined),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DevicesScreen()),
      ),
    );
  }
}
