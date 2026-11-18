import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';

import '../../../core/di/database_provider.dart';
import '../data/control_repository.dart';
import '../domain/notify_channel.dart';

const _kControlEnabledSettingKey = 'control_server_enabled';
const _kNotifyChannelsSettingKey = 'notify_channels';

/// Si el servidor de control esta habilitado. **Arranca apagado siempre.**
///
/// Mismo criterio que la IA (`ai_enabled_controller.dart`): un servidor que
/// acepta ordenes de otros programas de la maquina no puede aparecer solo
/// porque alguien actualizo la app. Ausente significa apagado.
///
/// El valor inicial real lo decide `main()` antes de `runApp` y se inyecta con
/// `overrideWith`, igual que `themeModeProvider`.
final controlServerEnabledProvider = StateProvider<bool>((ref) => false);

/// Los canales de aviso configurados.
///
/// Viven en `app_settings` (clave/valor, sin migracion de Drift) porque son
/// configuracion, no estado. **El token NO esta aca**: es un secreto y vive en
/// el directorio de datos del usuario, del lado Rust, al lado de la clave
/// privada del certificado del host.
final notifyChannelsProvider = StateProvider<List<NotifyChannel>>((ref) => const []);

/// En que estado quedo el servidor. `port` es el real, que con puerto 0 lo
/// elige el sistema.
class ControlServerStatus {
  const ControlServerStatus({this.port, this.error});

  final int? port;

  /// El motivo por el que no esta corriendo, si lo hay. El caso frecuente es
  /// el puerto ocupado por otra instancia de NexoDeck, y ese mensaje es lo
  /// unico que lo distingue de un fallo cualquiera.
  final String? error;

  bool get isRunning => port != null;

  static const stopped = ControlServerStatus();
}

/// Estado del servidor, para que la UI pueda decir por que no esta arriba en
/// vez de limitarse a no funcionar. Mismo patron que
/// `transportHostErrorProvider`.
final controlServerStatusProvider = StateProvider<ControlServerStatus>(
  (ref) => ControlServerStatus.stopped,
);

final controlRepositoryProvider = Provider<ControlRepository>(
  (ref) => const ControlRepository(),
);

final controlSettingsControllerProvider = Provider<ControlSettingsController>((ref) {
  final db = ref.watch(databaseProvider);
  return ControlSettingsController(
    ref,
    AppSettingsDao(db),
    ref.watch(controlRepositoryProvider),
  );
});

class ControlSettingsController {
  ControlSettingsController(this._ref, this._dao, this._repository);

  final Ref _ref;
  final AppSettingsDao _dao;
  final ControlRepository _repository;

  Future<void> toggle() =>
      setEnabled(!_ref.read(controlServerEnabledProvider));

  Future<void> setEnabled(bool enabled) async {
    _ref.read(controlServerEnabledProvider.notifier).state = enabled;
    await _dao.setValue(_kControlEnabledSettingKey, enabled.toString());

    if (enabled) {
      await _start();
    } else {
      // Apagar el switch tiene que **cerrar el puerto**, no solo esconder el
      // panel: si el servidor ya se levanto en esta sesion, sigue aceptando
      // peticiones hasta que se cierre la app.
      await _repository.stop();
      _ref.read(controlServerStatusProvider.notifier).state =
          ControlServerStatus.stopped;
    }
  }

  /// Levanta el servidor y deja el resultado en [controlServerStatusProvider].
  ///
  /// No lanza: el fallo se cuenta por el provider para que la UI lo muestre.
  /// Que el servidor no arranque no puede impedir que la app funcione.
  Future<void> _start() async {
    try {
      final port = await _repository.start(
        port: await _repository.defaultPort,
        channels: _ref.read(notifyChannelsProvider),
      );
      _ref.read(controlServerStatusProvider.notifier).state =
          ControlServerStatus(port: port);
    } catch (e) {
      _ref.read(controlServerStatusProvider.notifier).state =
          ControlServerStatus(error: e.toString());
    }
  }

  /// Reintenta el arranque tras un fallo, sin tocar la preferencia.
  Future<void> retryStart() async {
    if (!_ref.read(controlServerEnabledProvider)) return;
    await _start();
  }

  Future<void> setChannels(List<NotifyChannel> channels) async {
    _ref.read(notifyChannelsProvider.notifier).state = channels;
    await _dao.setValue(
      _kNotifyChannelsSettingKey,
      encodeNotifyChannels(channels),
    );
    // Empujarlos al servidor **siempre**, no solo si esta corriendo: si no lo
    // esta, la llamada es inocua, y asi no queda un camino en el que la
    // configuracion guardada y la que usa el servidor difieran.
    await _repository.pushChannels(channels);
  }

  Future<void> upsertChannel(NotifyChannel channel) {
    final channels = [..._ref.read(notifyChannelsProvider)];
    final index = channels.indexWhere((c) => c.id == channel.id);
    if (index >= 0) {
      channels[index] = channel;
    } else {
      channels.add(channel);
    }
    return setChannels(channels);
  }

  Future<void> removeChannel(String id) {
    final channels = _ref
        .read(notifyChannelsProvider)
        .where((c) => c.id != id)
        .toList();
    return setChannels(channels);
  }
}

/// Lee la preferencia guardada antes de `runApp`. Ausente es **apagado**: una
/// instalacion nueva nunca levanta el servidor sola.
Future<bool> readInitialControlEnabled(AppSettingsDao dao) async {
  return await dao.getValue(_kControlEnabledSettingKey) == 'true';
}

Future<List<NotifyChannel>> readInitialNotifyChannels(AppSettingsDao dao) async {
  return decodeNotifyChannels(await dao.getValue(_kNotifyChannelsSettingKey));
}
