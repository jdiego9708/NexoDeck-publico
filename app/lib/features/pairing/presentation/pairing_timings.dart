/// Tiempos del FLUJO de emparejamiento.
///
/// No viven en `app_motion.dart` a proposito: eso son tokens de movimiento
/// (cuanto tarda una animacion), y esto es cuanto se espera a que conteste la
/// otra punta o un humano. Mezclarlos haria que alguien "unifique" una
/// animacion de 200 ms con un timeout de red.
abstract final class PairingTimings {
  /// Cuanto se muestra "buscando" antes de admitir que no hay nada.
  ///
  /// El descubrimiento por mDNS en una LAN sana contesta en 1-2 s; a los 8 s
  /// ya no es que este tardando, es que no hay ninguna PC anunciando.
  static const discoverySearchHint = Duration(seconds: 8);

  /// Desde que se toca un host hasta que llega el PIN. Cubre TCP + handshake
  /// TLS + un round trip en red local.
  static const connectHandshake = Duration(seconds: 20);

  /// Desde que el telefono confirma el PIN hasta que la PC acepta o rechaza.
  /// Es espera por un HUMANO, por eso es tan larga.
  ///
  /// Alineada con `PAIRING_STEP_TIMEOUT` (120 s) de
  /// `core/crates/nexodeck-transport/src/server.rs`, mas un margen: si el host
  /// corta primero, preferimos que el mensaje al usuario lo de esta punta.
  /// Si alguna vez cambia el valor de Rust, este tiene que seguirlo.
  static const hostDecision = Duration(seconds: 125);

  /// Cuanto se deja ver el momento de exito antes de cerrar la hoja.
  static const successDwell = Duration(milliseconds: 900);
}
