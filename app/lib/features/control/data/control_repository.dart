import 'package:nexodeck/src/rust/api/control.dart' as control_bridge;
import 'package:nexodeck/src/rust/api/notify.dart' as notify_bridge;

import '../domain/notify_channel.dart';

/// Envuelve el bridge del servidor de control y de los avisos.
///
/// Existe para que ninguna pantalla llame al bridge directo: la UI habla de
/// canales y de avisos, no de cadenas JSON.
class ControlRepository {
  const ControlRepository();

  Future<int> get defaultPort => control_bridge.defaultControlPort();

  /// El token de esta instalacion. Lo genera y lo guarda Rust la primera vez;
  /// aca solo se lee para poder enseñarlo.
  Future<String> ensureToken() => control_bridge.ensureControlToken();

  Future<String> tokenPath() => control_bridge.controlTokenPath();

  Future<bool> isRunning() => control_bridge.isControlServerRunning();

  /// Devuelve el puerto real en el que quedo escuchando.
  Future<int> start({
    required int port,
    required List<NotifyChannel> channels,
  }) {
    return control_bridge.startControlServer(
      port: port,
      channelsJson: encodeNotifyChannels(channels),
    );
  }

  Future<void> stop() => control_bridge.stopControlServer();

  /// Empuja los canales al servidor ya corriendo. Sin esto, una peticion MCP
  /// seguiria usando la configuracion con la que se arranco.
  Future<void> pushChannels(List<NotifyChannel> channels) =>
      control_bridge.setControlChannels(
        channelsJson: encodeNotifyChannels(channels),
      );

  Stream<control_bridge.ControlEvent> watchEvents() =>
      control_bridge.watchControlEvents();

  // --- Correspondencia con Claude Code ---
  //
  // El sentido que el servidor MCP no tiene. NexoDeck encola y un oyente
  // externo lo recoge; la respuesta vuelve como llamada a herramienta.

  /// Encola una pregunta y devuelve su id. **No falla si no hay nadie
  /// escuchando**: el mensaje espera en la cola. Que nadie lo haya recogido se
  /// ve en la ausencia de `Delivered`, no en un error aca.
  /// `session` en `null` encola para **todas** las sesiones.
  Future<String> askClaudeCode(String text, {String? session}) =>
      control_bridge.askClaudeCode(text: text, session: session);

  Future<String> tellClaudeCode(String text, {String? session}) =>
      control_bridge.tellClaudeCode(text: text, session: session);

  /// Las sesiones de Claude Code que estan escuchando ahora.
  Future<List<control_bridge.CorrespondentSession>> claudeCodeSessions() =>
      control_bridge.claudeCodeSessions();

  /// `false` con preguntas encoladas significa que **nadie esta escuchando**,
  /// que es justo lo que el chat tiene que decir en vez de dejar esperando.
  Future<bool> listenerEverSeen() => control_bridge.claudeCodeListenerSeen();

  Stream<control_bridge.CorrespondentEvent> watchCorrespondent() =>
      control_bridge.watchCorrespondentEvents();

  /// Manda un aviso por los canales dados. Con [dryRun] compone y explica sin
  /// mandar nada.
  ///
  /// Una lista vacia de resultados significa **ningun canal configurado**, no
  /// exito. Quien llame tiene que distinguirlo.
  Future<List<notify_bridge.NotifyOutcome>> send({
    required List<NotifyChannel> channels,
    required String text,
    notify_bridge.NotifyLevel level = notify_bridge.NotifyLevel.milestone,
    bool dryRun = false,
  }) {
    return notify_bridge.sendNotification(
      channelsJson: encodeNotifyChannels(channels),
      text: text,
      level: level,
      dryRun: dryRun,
    );
  }
}
