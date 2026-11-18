import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nexodeck/src/rust/api/usb.dart' as bridge;

/// Rol Android del transporte USB (Fase 5-D).
///
/// Android entrega el canal del cable como un `ParcelFileDescriptor`, que
/// solo se puede abrir desde Kotlin (`MainActivity.kt`). Este servicio hace
/// de puente entre ese lado y Rust, y **solo transporta el numero del fd**:
/// apenas lo tiene, se lo pasa al bridge FFI y Rust lee/escribe directo
/// sobre el descriptor. Los bytes del protocolo nunca pasan por Dart.
///
/// De ahi en adelante no hay nada especifico de USB: la sesion emite los
/// mismos eventos de pairing/conexion que una por WiFi, asi que la UI
/// existente (dialogo del PIN, `ConnectedDeviceScreen`) funciona igual sin
/// saber por donde entro.
class UsbAccessoryService {
  UsbAccessoryService({
    required this.resolveDeviceName,
    required this.resolvePairedDeviceId,
  });

  static const _channel = MethodChannel('com.nexodeck.nexodeck/usb_accessory');

  final Future<String> Function() resolveDeviceName;

  /// Id del dispositivo ya emparejado con esta PC, o `null` si es el primer
  /// pairing -- decide si la sesion arranca pidiendo PIN o reconectando.
  final Future<String?> Function() resolvePairedDeviceId;

  bool _sessionActive = false;

  void start() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(_onNativeCall);
    // La app puede haber sido ABIERTA por el intent del accessory (el
    // sistema la lanza cuando la PC arranca accessory mode), en cuyo caso el
    // cable ya esta listo y no va a llegar ningun broadcast: hay que
    // intentar abrirlo de entrada.
    unawaited(_tryOpenSession());
  }

  void stop() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onAccessoryAttached':
        await _tryOpenSession();
      case 'onAccessoryDetached':
        // No hay nada que cerrar desde aca: al desconectarse el cable, la
        // lectura del fd en Rust devuelve EOF y la sesion termina sola,
        // liberando el flag de abajo.
        break;
    }
    return null;
  }

  Future<void> _tryOpenSession() async {
    // Una sola sesion por cable. Sin esto, un `onAccessoryAttached` repetido
    // (llega uno por el broadcast y otro por el permiso concedido) abriria
    // dos sesiones sobre el mismo accessory.
    if (_sessionActive) return;

    final int? fd;
    try {
      fd = await _channel.invokeMethod<int>('openAccessoryFd');
    } on PlatformException catch (e) {
      debugPrint('USB: no se pudo abrir el accessory: ${e.message}');
      return;
    }
    // `null` = no hay cable, o falta el permiso y Kotlin acaba de pedirlo;
    // en ese caso vuelve a avisar por `onAccessoryAttached` cuando el
    // usuario responde.
    if (fd == null) return;

    _sessionActive = true;
    try {
      await bridge.startUsbAccessorySession(
        fd: fd,
        deviceName: await resolveDeviceName(),
        pairedDeviceId: await resolvePairedDeviceId(),
      );
    } catch (e) {
      debugPrint('USB: la sesion termino con error: $e');
    } finally {
      _sessionActive = false;
    }
  }
}
