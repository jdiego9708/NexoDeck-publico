import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

import '../data/pairing_repository.dart';

final pairingRepositoryProvider = Provider<PairingRepository>(
  (ref) => const PairingRepository(),
);

/// Motivo por el que el host de transporte NO arranco, o `null` si arranco
/// bien. Lo sobreescribe `main()` con el resultado real.
///
/// Existe porque ese fallo se tragaba en silencio: el caso tipico es el
/// puerto 58643 ocupado (otra instancia de la app, o un ejemplo de
/// diagnostico corriendo), y el sintoma era simplemente que emparejar no
/// funcionaba, sin ninguna explicacion en ningun lado.
final transportHostErrorProvider = Provider<String?>((ref) => null);

final pairingEventsProvider = StreamProvider.autoDispose<bridge.PairingEvent>((
  ref,
) {
  final repository = ref.watch(pairingRepositoryProvider);
  return repository.watchPairingEvents();
});

/// Suscripcion directa al stream de eventos de pairing, para efectos que
/// tienen que correr **una vez por evento**. Mismo motivo (y misma trampa)
/// que `connectionEventStream`: Riverpod no vuelve a notificar cuando el
/// valor nuevo es `==` al anterior, y estos eventos son value types de
/// freezed.
///
/// El caso concreto que costo encontrar, contra el telefono real: dos
/// `PairingRejected { reason: "dispositivo no autorizado" }` seguidos son
/// identicos, asi que el segundo no llegaba nunca. La pantalla quedaba
/// esperando un evento que ya habia ocurrido y no volvia a reintentar.
Stream<bridge.PairingEvent> pairingEventStream(WidgetRef ref) =>
    ref.read(pairingRepositoryProvider).watchPairingEvents();

/// Acumula los hosts descubiertos por mDNS en una lista (dedupe por
/// nombre de instancia) -- el stream de Rust emite uno a la vez a medida
/// que se resuelven, no la lista completa.
final discoveredHostsProvider = StreamProvider.autoDispose<List<bridge.DiscoveredHost>>((
  ref,
) async* {
  final repository = ref.watch(pairingRepositoryProvider);
  final seen = <String, bridge.DiscoveredHost>{};
  await for (final host in repository.discoverHosts()) {
    seen[host.name] = host;
    yield seen.values.toList(growable: false);
  }
});
