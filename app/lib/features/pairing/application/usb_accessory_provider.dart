import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_identity.dart';
import '../data/usb_accessory_service.dart';
import 'devices_provider.dart';

/// Mantiene vivo el servicio que atiende el cable USB mientras el shell de
/// Android este montado. No expone nada util: se observa por su efecto (ver
/// `AndroidShell`), que es escuchar los avisos de Kotlin y arrancar la
/// sesion cuando aparece un accessory.
final usbAccessoryServiceProvider = Provider<UsbAccessoryService>((ref) {
  final service = UsbAccessoryService(
    resolveDeviceName: resolveDeviceName,
    // Se lee en el momento de conectar, no al construir el provider: entre
    // que arranca la app y se enchufa el cable, el dispositivo pudo haberse
    // emparejado (o des-emparejado) por WiFi.
    resolvePairedDeviceId: () async {
      final devices = await ref.read(devicesRepositoryProvider).watchAll().first;
      return devices.isEmpty ? null : devices.first.id;
    },
  );
  service.start();
  ref.onDispose(service.stop);
  return service;
});
