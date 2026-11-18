import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/hardware.dart' as bridge;

import '../domain/hardware_snapshot.dart';

/// Nota: Riverpod 3 con codegen (`@riverpod`) es la decision de arquitectura
/// del proyecto, pero riverpod_generator/build_runner no resuelven en este
/// SDK de Flutter (analyzer que necesitan choca con la version de `meta`
/// que fija el Flutter SDK actual). Este provider se escribe a mano con la
/// API clasica de Riverpod hasta que el ecosistema se ponga al dia.
final hardwareMetricsProvider = StreamProvider.autoDispose<HardwareSnapshot>((
  ref,
) {
  return bridge.watchHardwareMetrics().map(HardwareSnapshot.fromBridge);
});
