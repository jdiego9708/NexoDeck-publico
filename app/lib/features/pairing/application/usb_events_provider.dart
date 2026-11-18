import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/usb.dart' as bridge;

/// Estado del **cable** USB del lado PC (Fase 5). Los eventos de la sesion
/// en si (conectado, accion pedida...) no vienen por aca: salen por
/// `connectionEventsProvider` como los de WiFi, porque para el resto de la
/// app da igual por donde entro el dispositivo.
final usbEventsProvider = StreamProvider<bridge.UsbEvent>((ref) {
  return bridge.watchUsbEvents();
});

/// Ultimo estado relevante para mostrar en la UI, quedandose con el evento
/// mas reciente. `null` mientras no haya pasado nada con el cable.
final usbStatusProvider = Provider<bridge.UsbEvent?>((ref) {
  return ref.watch(usbEventsProvider).value;
});
