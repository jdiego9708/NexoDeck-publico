import 'manual_host.dart';

/// A donde intentar la reconexion: host y puerto, sin importar como se
/// llego a ellos.
typedef ReconnectTarget = ({String host, int port});

/// Un host anunciado por mDNS, reducido a lo que la decision necesita.
///
/// No es el `DiscoveredHost` del bridge a proposito: asi la regla se puede
/// testear sin arrastrar los tipos generados por flutter_rust_bridge.
typedef DiscoveredEndpoint = ({String name, String host, int port});

/// mDNS anuncia el nombre de instancia sanitizado -- todo lo que no es
/// alfanumerico pasa a `-`, ver `sanitize_instance_name` en
/// `nexodeck-transport/src/discovery.rs`. Para comparar contra el nombre
/// real guardado en Drift hay que aplicarle la misma transformacion.
String sanitizeInstanceName(String name) =>
    name.replaceAll(RegExp('[^A-Za-z0-9-]'), '-');

/// Elige a donde reconectar: **mDNS primero, direccion manual despues**.
///
/// El orden no es arbitrario. Dentro de la LAN la IP la reparte el DHCP y
/// cambia, asi que mDNS es la fuente correcta y la direccion escrita a mano
/// podria estar vieja. Fuera de la LAN --datos moviles, por Tailscale--
/// mDNS no encuentra nada nunca, y ahi la manual es la unica que puede
/// servir.
///
/// `mdnsGraceElapsed` es lo que evita salir corriendo a la direccion manual
/// en el primer intento: un TCP contra una IP que ya no existe no falla
/// rapido, cuelga hasta el timeout, y mientras tanto bloquea el reintento
/// que si habria funcionado. Quien llama decide cuanta gracia dar (y la
/// saltea cuando sabe que mDNS no puede servir, por ejemplo sin WiFi).
ReconnectTarget? resolveReconnectTarget({
  required String deviceName,
  required Iterable<DiscoveredEndpoint> discovered,
  required ManualHost? manual,
  required bool mdnsGraceElapsed,
}) {
  final needle = sanitizeInstanceName(deviceName);
  for (final endpoint in discovered) {
    if (endpoint.name.contains(needle)) {
      return (host: endpoint.host, port: endpoint.port);
    }
  }

  if (manual == null || !mdnsGraceElapsed) return null;
  return (host: manual.host, port: manual.port);
}
