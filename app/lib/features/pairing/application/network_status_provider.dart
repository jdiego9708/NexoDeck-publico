import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` si el dispositivo tiene WiFi activo. mDNS (necesario para
/// descubrir hosts NexoDeck, ver `discoverHosts`) solo funciona dentro de
/// la misma red local -- datos moviles no sirven aunque haya "internet",
/// y el error resultante ("Buscando dispositivos..." sin fin) no es obvio
/// para alguien que no sabe que mDNS depende de la red local.
final isOnWifiProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield initial.contains(ConnectivityResult.wifi);
  yield* connectivity.onConnectivityChanged.map(
    (results) => results.contains(ConnectivityResult.wifi),
  );
});
