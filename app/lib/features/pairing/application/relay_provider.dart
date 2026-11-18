import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/src/rust/api/relay.dart' as bridge;

import '../../../core/di/database_provider.dart';
import '../data/relay_repository.dart';

final relayRepositoryProvider = Provider<RelayRepository>(
  (ref) => const RelayRepository(),
);

const _kRelayTunnelEnabledKey = 'relay_tunnel_enabled';
const _kRelayHostKey = 'relay_host';
const _kRelayPortKey = 'relay_port';
const _kRelayTokenHexKey = 'relay_token_hex';

/// El relay ya desplegado en el VPS de el proyecto (`vps-relay`,
/// servicio `nexodeck-relay`, ver `docs/ESTADO-DEL-PROYECTO.md`). Son los
/// defaults con los que se prellena el dialogo: activar el tunel por
/// primera vez es tocar el switch, sin escribir nada a mano. Si el usuario
/// alguna vez migra a otro VPS, los tres campos siguen siendo editables.
const kDefaultRelayHost = 'relay.example.com';
const kDefaultRelayPort = 58644;
const kDefaultRelayTokenHex =
    '2f8fc363ea83a7bfe2f55e337b571a4cc1afb1410cc5136dc8e5a21175d93874';

class RelayTunnelConfig {
  const RelayTunnelConfig({
    required this.host,
    required this.port,
    required this.tokenHex,
  });

  final String host;
  final int port;
  final String tokenHex;
}

/// Si el tunel deberia estar prendido. Arranca apagado siempre en una
/// instalacion nueva -- misma razon que `aiEnabledProvider`: es preferencia
/// de usuario, vive en `app_settings`, y el valor inicial real lo decide
/// `main()` antes de `runApp` con `overrideWith` (ver
/// `readInitialRelayTunnelConfig`).
final relayTunnelEnabledProvider = StateProvider<bool>((ref) => false);

/// Host/puerto/token guardados, o los defaults del VPS si nunca se
/// configuro nada.
final relayTunnelConfigProvider = StateProvider<RelayTunnelConfig>(
  (ref) => const RelayTunnelConfig(
    host: kDefaultRelayHost,
    port: kDefaultRelayPort,
    tokenHex: kDefaultRelayTokenHex,
  ),
);

/// Rol PC: en que anda el tunel ahora mismo. Suscripcion comun (no
/// `ref.listen`/stream directo): esto es solo para MOSTRAR el ultimo
/// estado, no para reaccionar una vez por evento, asi que perder un
/// duplicado consecutivo (Riverpod no notifica valores `==`) no pierde
/// nada -- la pantalla ya esta mostrando ese mismo estado.
final relayStatusProvider = StreamProvider<bridge.RelayStatus>(
  (ref) => ref.watch(relayRepositoryProvider).watchStatus(),
);

final relayTunnelControllerProvider = Provider<RelayTunnelController>((ref) {
  final db = ref.watch(databaseProvider);
  return RelayTunnelController(ref, AppSettingsDao(db));
});

class RelayTunnelController {
  RelayTunnelController(this._ref, this._dao);

  final Ref _ref;
  final AppSettingsDao _dao;

  /// Guarda host/puerto/token sin prender ni apagar nada -- separado de
  /// `setEnabled` porque el dialogo permite editarlos con el tunel apagado.
  Future<void> saveConfig(RelayTunnelConfig config) async {
    _ref.read(relayTunnelConfigProvider.notifier).state = config;
    await _dao.setValue(_kRelayHostKey, config.host);
    await _dao.setValue(_kRelayPortKey, config.port.toString());
    await _dao.setValue(_kRelayTokenHexKey, config.tokenHex);
  }

  Future<void> setEnabled(bool enabled) async {
    _ref.read(relayTunnelEnabledProvider.notifier).state = enabled;
    await _dao.setValue(_kRelayTunnelEnabledKey, enabled.toString());
    final repository = _ref.read(relayRepositoryProvider);
    if (enabled) {
      final config = _ref.read(relayTunnelConfigProvider);
      await repository.startTunnel(
        host: config.host,
        port: config.port,
        tokenHex: config.tokenHex,
      );
    } else {
      await repository.stopTunnel();
    }
  }
}

/// Lee la config guardada antes de `runApp`, para poder encender el tunel
/// solo si ya estaba prendido (ver el bloque de `startTransportHost` en
/// `main.dart`). Ausente (instalacion nueva) cae en los defaults del VPS,
/// pero `enabled` arranca en `false` igual -- que el tunel exista no
/// significa que el usuario ya pidio usarlo.
Future<(bool enabled, RelayTunnelConfig config)> readInitialRelayTunnelConfig(
  AppSettingsDao dao,
) async {
  final enabled = await dao.getValue(_kRelayTunnelEnabledKey) == 'true';
  final host = await dao.getValue(_kRelayHostKey) ?? kDefaultRelayHost;
  final portRaw = await dao.getValue(_kRelayPortKey);
  final port = portRaw == null ? kDefaultRelayPort : int.parse(portRaw);
  final tokenHex = await dao.getValue(_kRelayTokenHexKey) ?? kDefaultRelayTokenHex;
  return (
    enabled,
    RelayTunnelConfig(host: host, port: port, tokenHex: tokenHex),
  );
}
