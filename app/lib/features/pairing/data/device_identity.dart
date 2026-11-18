import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Nombre para identificar este dispositivo durante el pairing.
/// `Platform.localHostname` no sirve en Android -- la plataforma no expone
/// un hostname real y devuelve literalmente "localhost", inutil para que
/// el operador de la PC sepa a quien esta aceptando. Se usa marca+modelo
/// real del telefono, con fallback a la IP local si `device_info_plus`
/// falla por algun motivo (MAC no es una opcion viable: Android 6+ devuelve
/// un valor dummy "02:00:00:00:00:00" para apps normales, por privacidad).
Future<String> resolveDeviceName() async {
  if (Platform.isAndroid) {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final parts = <String>{
        info.brand.trim(),
        info.model.trim(),
      }..removeWhere((s) => s.isEmpty);
      final name = parts.join(' ').trim();
      if (name.isNotEmpty) return name;
    } catch (_) {
      // sigue al fallback de IP
    }
  }

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {
    // sigue al fallback final
  }

  return 'Dispositivo Android';
}
