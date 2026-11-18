import 'dart:io';

import 'package:flutter/services.dart';

/// El descubrimiento mDNS del lado Android corre sobre un socket UDP
/// multicast crudo (`mdns-sd` en Rust, no la API `NsdManager` de Android),
/// y Android descarta paquetes multicast por defecto salvo que se adquiera
/// un `WifiManager.MulticastLock` -- ver `MainActivity.kt` y el skill
/// `kotlin-android-plugin`.
class MulticastLockService {
  const MulticastLockService();

  static const _channel = MethodChannel('com.nexodeck.nexodeck/multicast');

  Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('acquireMulticastLock');
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('releaseMulticastLock');
  }
}
