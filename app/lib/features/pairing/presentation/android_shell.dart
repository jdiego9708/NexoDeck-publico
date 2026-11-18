import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/presentation/editor_spike_screen.dart';
import '../application/devices_provider.dart';
import '../application/usb_accessory_provider.dart';
import 'android_pairing_screen.dart';
import 'connected_device_screen.dart';

/// Paso 0 del editor en el movil: arranca en la pantalla de prueba en vez de en
/// la del dispositivo, para poder probarla sin emparejar nada. **Temporal**: se
/// quita en cuanto el paso 0 este decidido.
const bool kEditorSpike = false;

/// Rol Android: sin dispositivos emparejados todavia -> pantalla de
/// pairing; ya emparejado -> pantalla del dispositivo conectado (v1: un
/// solo dispositivo emparejado a la vez, el primero de la lista).
class AndroidShell extends ConsumerWidget {
  const AndroidShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kEditorSpike) {
      return const EditorSpikeScreen();
    }
    // Se observa solo por su efecto: deja escuchando el cable USB mientras
    // el shell viva, tanto para el primer pairing (la pantalla de abajo
    // muestra el dialogo del PIN igual que por WiFi) como para reconectar
    // uno ya emparejado.
    ref.watch(usbAccessoryServiceProvider);

    final devices = ref.watch(pairedDevicesListProvider);

    return devices.when(
      data: (list) => list.isEmpty
          ? const AndroidPairingScreen()
          : ConnectedDeviceScreen(device: list.first),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) =>
          Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}
