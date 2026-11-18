/// Sufijo del tipo de servicio mDNS, tal como lo anuncia
/// `nexodeck-transport/src/discovery.rs`.
const _kServiceSuffix = '._nexodeck._tcp.local.';

/// Nombre presentable de una PC descubierta por mDNS.
///
/// `DiscoveredHost.name` viene de `info.get_fullname()`, o sea el nombre de
/// instancia MAS el tipo de servicio: al usuario se le mostraba literalmente
/// `JUANDIEGO-PC._nexodeck._tcp.local.` como nombre de su computadora.
///
/// Ojo: esto sigue siendo el nombre **sanitizado** por
/// `sanitize_instance_name` (todo lo no alfanumerico pasa a `-`), asi que no
/// es igual al `hostName` real que llega en `PairPin`. En cuanto ese dato
/// esta disponible hay que preferirlo.
String hostDisplayName(String fullname) {
  final withoutSuffix = fullname.endsWith(_kServiceSuffix)
      ? fullname.substring(0, fullname.length - _kServiceSuffix.length)
      : fullname;
  return withoutSuffix.isEmpty ? fullname : withoutSuffix;
}
