import 'dart:async';
import 'dart:io' show pid;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:nexodeck/data/local/daos/chat_conversations_dao.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge_actions;
import 'package:nexodeck/src/rust/api/ai.dart' as ai_bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as connection_bridge;
import 'package:nexodeck/src/rust/api/control.dart' as control_bridge;
import 'package:nexodeck/src/rust/api/hub.dart' as hub_bridge;
import 'package:nexodeck/src/rust/api/pairing.dart' as pairing_bridge;
import 'package:nexodeck/src/rust/api/processes.dart' as processes_bridge;

import '../../../core/di/database_provider.dart';
import '../../actions/application/action_groups_provider.dart';
import '../../actions/application/actions_provider.dart';
import '../../ai_assistant/application/ai_draft_applier.dart';
import '../../ai_assistant/application/ai_enabled_controller.dart';
import '../../ai_assistant/application/ai_live_runner.dart';
import '../../ai_assistant/application/ai_providers.dart';
import '../../ai_assistant/application/chat_destinations_controller.dart';
import '../../ai_assistant/domain/action_draft.dart';
import '../../control/application/control_settings_controller.dart';
import '../../dashboard/application/hardware_history_provider.dart';
import '../../dashboard/application/hardware_metrics_provider.dart';
import '../../dashboard/application/host_components_provider.dart';
import '../../dashboard/data/hardware_history_repository.dart';
import '../../hub_subscriptions/application/hub_subscriptions_provider.dart';
import '../../hub_subscriptions/domain/hub_subscription_summary.dart';
import '../../pairing/application/connection_provider.dart';
import '../../pairing/application/devices_provider.dart';
import '../../pairing/application/pairing_provider.dart';
import '../../processes/domain/process_ai_prompt.dart';
import '../../processes/domain/process_group.dart';
import '../../profiles/application/active_profile_controller.dart';
import '../../profiles/application/profiles_provider.dart';
import '../../profiles/presentation/profile_auto_switcher.dart';
import '../../run_center/application/run_center_controller.dart';
import '../../run_center/domain/command_run.dart';
import 'host_presentation_controller.dart';

/// Toda la logica del rol PC, fuera del arbol de widgets.
///
/// **Por que existe.** Esto vivia repartido entre `_HomeShellState`
/// (`main.dart`) y cuatro widgets envoltorio (`HardwareHistoryRecorder`,
/// `HubEventsRecorder`, `ProfileAutoSwitcher`, `ControlActivityHost`). Un
/// widget solo escucha mientras esta montado, y eso tenia dos consecuencias:
///
/// - En **modo compacto** `_HomeShell` no se monta, asi que el telefono no
///   recibia el catalogo, sus acciones no se ejecutaban y Rust rechazaba
///   todas las reconexiones (la cache de autorizados nunca se sincronizaba).
/// - El modo **solo telefono** desmonta la interfaz entera para no gastar
///   CPU/GPU en render. Con la logica colgada de widgets, ocultar la ventana
///   era apagar el host.
///
/// Recibe el `ProviderContainer` y no un `Ref`: `container.listen` mantiene
/// vivos los providers `autoDispose` que escucha sin depender del ciclo de
/// vida de otro provider, y nada aca se reconstruye.
///
/// **Regla que se hereda de `CLAUDE.md`:** los eventos del bridge van por
/// suscripcion directa al `Stream`, nunca por `listen` sobre un provider,
/// porque Riverpod no re-notifica valores `==`. Los `container.listen` de
/// abajo son todos sobre **estado** (listas de Drift, flags), donde solo
/// importa el ultimo valor.
class HostRuntime {
  HostRuntime(this._container);

  final ProviderContainer _container;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<ProviderSubscription<Object?>> _listeners = [];

  bool _started = false;

  /// Un solo `Typing` por tanda de tokens, nunca uno por token.
  bool _typingSentToRemote = false;

  DateTime? _lastHistoryWrite;

  void start() {
    if (_started) return;
    _started = true;

    // Rol PC: al conectar un dispositivo le empuja el catalogo; al pedir
    // ejecutar una accion la corre localmente y responde con el resultado.
    _subscriptions.add(
      _container
          .read(connectionRepositoryProvider)
          .watchConnectionEvents()
          .listen(_handleConnectionEvent),
    );

    // Dos `SetupEvent.Ready` seguidos con el mismo modelo son identicos.
    // `aiReadyProvider` es lo unico que le importa a `AiStatus`; el resto
    // del progreso (Probing/Downloading/...) lo mira el wizard, no aca.
    final aiRepository = _container.read(aiRepositoryProvider);
    _subscriptions
      ..add(aiRepository.watchSetupEvents().listen(_handleAiSetupEvent))
      // Reenvio PERSISTENTE de la conversacion hacia los telefonos. No puede
      // vivir en el dialogo "Crear con IA": una pregunta hecha desde el
      // telefono se contestaba bien pero la respuesta **nunca salia** si
      // nadie tenia el dialogo abierto en la PC.
      ..add(aiRepository.watchChatEvents().listen(_handleAiChatEvent))
      ..add(
        _container
            .read(controlRepositoryProvider)
            .watchCorrespondent()
            .listen(_handleCorrespondentEvent),
      )
      // Dos mensajes identicos seguidos de un hub son perfectamente
      // posibles (un hub que reenvia el mismo progreso dos veces).
      ..add(
        _container
            .read(hubSubscriptionsRepositoryProvider)
            .watchEvents()
            .listen(_handleHubEvent),
      )
      // Emparejamiento a demanda: un telefono pidio emparejarse sin el PIN
      // armado y Rust lo esta reteniendo (ver `wait_for_on_demand_arming` en
      // `server.rs`). Aca solo se abre la interfaz que arma el PIN -- **quien
      // arma es siempre `HostPinCard`**: si esto armara tambien, `arm_pairing`
      // generaria otro PIN y el telefono recibiria uno distinto del que se ve.
      ..add(
        _container.read(pairingRepositoryProvider).watchPairingEvents().listen((
          event,
        ) {
          if (event
              is pairing_bridge.PairingEvent_PairingRequestedWhileDisarmed) {
            unawaited(
              _container
                  .read(hostPresentationControllerProvider)
                  .openPairingOnRequest(),
            );
          }
        }),
      );

    _listenToHostState();

    // `Timer.run` y no `addPostFrameCallback` (que es lo que usaba
    // `_HomeShellState`): con la ventana oculta puede no haber ningun frame,
    // y estas dos tareas no correrian nunca.
    //
    // Archiva las conversaciones que llevan mas de un mes quietas. Va fuera
    // del flag de IA porque no toca el puente: es solo higiene de la base, y
    // **no borra nada** -- las archivadas siguen enteras y se pueden reabrir.
    //
    // Las dos comprueban `_started`: corren en el siguiente turno del event
    // loop, y para entonces el runtime pudo haberse desechado (en los tests
    // pasa enseguida), con lo que leer del container reventaria.
    Timer.run(() {
      if (!_started) return;
      unawaited(
        ChatConversationsDao(_container.read(databaseProvider))
            .archiveStale()
            .catchError((Object error) {
              debugPrint('NexoDeck: no se pudo archivar conversaciones: $error');
              return 0;
            }),
      );
    });

    // Levanta el destino por defecto del chat, para que el asistente este
    // listo sin que nadie abra su dialogo. **Es lo que hace que la
    // configuracion sobreviva a cerrar el programa**: sin esto la clave y el
    // modelo quedaban en disco pero nadie volvia a instalar el proveedor, y el
    // telefono recibia `ready: false` sin explicacion.
    //
    // Va detras del flag de IA porque el registro pregunta por los modelos, y
    // eso inicializa NVML y una instancia de Vulkan. La regla del proyecto es
    // que con la IA apagada NO se llama a nada del puente de IA.
    Timer.run(() {
      if (!_started || !_container.read(aiEnabledProvider)) return;
      unawaited(
        _container
            .read(chatDestinationsProvider.notifier)
            .restoreDefault()
            .catchError((Object error) {
              // No es fatal: la app funciona igual y el usuario puede elegir
              // destino a mano. Pero no puede quedar mudo.
              debugPrint('NexoDeck: no se pudo restaurar el destino: $error');
            }),
      );
    });
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    for (final listener in _listeners) {
      listener.close();
    }
    _listeners.clear();
    _started = false;
  }

  /// `container.listen` guardando la suscripcion para `dispose`.
  ///
  /// Existe por la inferencia de tipos, no por comodidad: escrito como
  /// `_listeners.add(_container.listen(...))`, Dart toma el tipo de la lista
  /// (`ProviderSubscription<Object?>`) como contexto, infiere `T = Object?` y
  /// el `next` del listener pierde su tipo. Aca `T` sale del provider.
  void _listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener,
  ) {
    _listeners.add(_container.listen<T>(provider, listener));
  }

  void _listenToHostState() {
    // Mantiene la cache de autorizados de Rust sincronizada con la tabla
    // `devices` de Drift. Sin esto Rust arranca con el mapa vacio y rechaza
    // toda reconexion.
    _listen(pairedDevicesListProvider, (previous, next) {
      next.whenData(
        (devices) => _container
            .read(connectionRepositoryProvider)
            .syncAuthorizedDevices(devices),
      );
    });

    // El catalogo se empujaba SOLO al conectar, asi que crear un grupo (o una
    // accion) con el telefono ya conectado no llegaba nunca: del otro lado
    // seguian sin aparecer las pestañas hasta reconectar.
    //
    // La primera carga NO es un cambio y no se reenvia: quien acaba de
    // conectar ya recibio el catalogo en `DeviceConnected`. Sin este filtro,
    // un telefono que conecta mientras Drift todavia carga recibe el mismo
    // catalogo tres veces (el suyo y uno por cada provider que termina).
    _listen(actionsListProvider, (previous, next) {
      if (previous == null || !previous.hasValue) return;
      next.whenData((_) => _sendCatalogTo(_connectedDevices));
    });
    _listen(actionGroupsListProvider, (previous, next) {
      if (previous == null || !previous.hasValue) return;
      next.whenData((_) => _sendCatalogTo(_connectedDevices));
    });

    // Mismo motivo, para el estado de las suscripciones en vivo.
    _listen(hubSubscriptionsListProvider, (previous, next) {
      if (previous == null || !previous.hasValue) return;
      next.whenData((_) => _sendHubSubscriptionsSnapshotTo(_connectedDevices));
    });

    // El switch de la IA tambien tiene que reflejarse en los telefonos ya
    // conectados -- `_handleAiSetupEvent` es el otro disparador.
    _listen(aiEnabledProvider, (previous, next) {
      _sendAiStatusTo(
        _connectedDevices,
        ready: next && _container.read(aiReadyProvider),
      );
    });

    // Persiste una muestra del hardware cada `sampleEvery`. Mantiene vivo el
    // stream de metricas de Rust (es `autoDispose`) aunque no haya ninguna
    // metrica en pantalla: es el precio de que el historial no tenga huecos en
    // modo compacto ni con la ventana oculta. Solo la PC graba: el telefono
    // recibe snapshots de otra maquina.
    _listen(hardwareMetricsProvider, (previous, next) {
      next.whenData((snapshot) async {
        final now = DateTime.now();
        final last = _lastHistoryWrite;
        // Submuestreo por tiempo y no "1 de cada N eventos": si el stream se
        // corta y vuelve, contar eventos dejaria el ritmo corrido.
        if (last != null &&
            now.difference(last) < HardwareHistoryRepository.sampleEvery) {
          return;
        }
        _lastHistoryWrite = now;
        await _container
            .read(hardwareHistoryRepositoryProvider)
            .record(snapshot, at: now);
      });
    });

    // Auto-cambio de perfil. `listen` y no suscripcion directa: aca solo
    // importa el ULTIMO valor (que app esta adelante), y Rust ya emite solo
    // cuando el foco cambia.
    _listen(foregroundAppProvider, (previous, next) {
      next.whenData((app) async {
        // La propia ventana de NexoDeck NO cuenta como cambio de aplicacion:
        // para elegir un perfil a mano hay que enfocar NexoDeck, y si eso
        // contara el override manual se borraria al volver a la app anterior.
        if (app != null && app.pid == pid) return;
        // Tampoco cuenta "no se puede saber" (sin ventana en foco).
        if (app == null) return;

        _container.read(lastExternalAppProvider.notifier).state =
            app.processName;

        final profiles = _container.read(profilesListProvider).value ?? const [];
        if (profiles.isEmpty) return;
        await _container
            .read(activeProfileControllerProvider)
            .onForegroundChanged(app.processName, profiles);
      });
    });
  }

  Set<String> get _connectedDevices => _container.read(connectedDeviceIdsProvider);

  void _handleAiSetupEvent(ai_bridge.AiSetupEvent event) {
    final ready = switch (event) {
      ai_bridge.AiSetupEvent_Ready() => true,
      ai_bridge.AiSetupEvent_Failed() => false,
      _ => _container.read(aiReadyProvider),
    };
    if (ready == _container.read(aiReadyProvider)) return;
    _container.read(aiReadyProvider.notifier).state = ready;
    _sendAiStatusTo(_connectedDevices, ready: ready);
  }

  /// El unico reenvio de la conversacion hacia los telefonos.
  ///
  /// No sabe de `AssistantMode`/"modo en vivo": la supresion de la frase de
  /// relleno que se muestra antes de ejecutar un borrador es local al
  /// dialogo, y acoplar este reenvio a un estado que solo existe con el
  /// dialogo abierto le devolveria el problema que se esta arreglando. Costo
  /// aceptado: en modo en vivo el telefono puede ver esa frase de mas.
  void _handleAiChatEvent(ai_bridge.AiChatEvent event) {
    // Los tokens nunca cruzan el cable (ver `MessageV1::AiChatEvent`): se
    // resumen en un solo `Typing` por tanda.
    if (event case ai_bridge.AiChatEvent_AssistantToken()) {
      if (_typingSentToRemote) return;
      _typingSentToRemote = true;
      _forwardAiChatEvent(const connection_bridge.AiRemoteChatEvent.typing());
      return;
    }
    if (event case ai_bridge.AiChatEvent_Thinking()) return;

    _typingSentToRemote = false;
    _forwardAiChatEvent(aiChatEventToRemote(event));
  }

  /// Lo que conteste Claude Code tiene que llegarle al telefono igual que lo
  /// que contesta un modelo.
  ///
  /// Se traduce a los MISMOS eventos del cable (`AiRemoteChatEvent`) en vez de
  /// inventar mensajes nuevos en el protocolo: para la pantalla de chat del
  /// telefono, quien contesta da igual. `Delivered` se manda como `typing`
  /// porque significa exactamente eso.
  void _handleCorrespondentEvent(control_bridge.CorrespondentEvent event) {
    switch (event) {
      case control_bridge.CorrespondentEvent_Delivered():
        _forwardAiChatEvent(const connection_bridge.AiRemoteChatEvent.typing());
      case control_bridge.CorrespondentEvent_Replied(:final text):
        _forwardAiChatEvent(
          connection_bridge.AiRemoteChatEvent.assistantMessage(text: text),
        );
        _forwardAiChatEvent(const connection_bridge.AiRemoteChatEvent.turnDone());
      case control_bridge.CorrespondentEvent_Posted(:final text, :final from):
        _forwardAiChatEvent(
          connection_bridge.AiRemoteChatEvent.assistantMessage(
            text: from == null ? text : '[$from] $text',
          ),
        );
        _forwardAiChatEvent(const connection_bridge.AiRemoteChatEvent.turnDone());
      case control_bridge.CorrespondentEvent_TimedOut(:final reason):
        // Vencer se dice, **y con el motivo**: "no contesto" a secas no
        // distingue una terminal cerrada de una lenta.
        _forwardAiChatEvent(
          connection_bridge.AiRemoteChatEvent.failed(
            detail: 'Claude Code no contestó: $reason.',
          ),
        );
      case control_bridge.CorrespondentEvent_SessionsChanged():
        // Al telefono no le afecta: el destino lo elige la PC.
        break;
    }
  }

  void _forwardAiChatEvent(connection_bridge.AiRemoteChatEvent event) {
    final devices = _connectedDevices;
    if (devices.isEmpty) return;
    final repository = _container.read(connectionRepositoryProvider);
    for (final deviceId in devices) {
      unawaited(repository.sendAiChatEvent(deviceId, event).catchError((_) {}));
    }
  }

  void _handleHubEvent(hub_bridge.HubSubscriptionEvent event) {
    final repository = _container.read(hubSubscriptionsRepositoryProvider);
    switch (event) {
      case hub_bridge.HubSubscriptionEvent_Connected(:final subscriptionId):
        repository.markConnected(subscriptionId);
      case hub_bridge.HubSubscriptionEvent_MessageReceived(
        :final subscriptionId,
        :final eventName,
        :final payloadJson,
      ):
        repository.recordMessage(
          subscriptionId: subscriptionId,
          eventName: eventName,
          payloadJson: payloadJson,
        );
      case hub_bridge.HubSubscriptionEvent_Disconnected(:final subscriptionId):
        repository.markDisconnected(subscriptionId);
      case hub_bridge.HubSubscriptionEvent_Stopped(:final subscriptionId):
        repository.markStopped(subscriptionId);
      case hub_bridge.HubSubscriptionEvent_Failed(:final subscriptionId):
        repository.markFailed(subscriptionId);
    }
  }

  /// Empuja el catalogo a los dispositivos indicados.
  ///
  /// Se leen los repositorios directamente, esperando el primer valor real,
  /// en vez de tomar el snapshot de `actionsListProvider`. Esos providers
  /// son `autoDispose`: si en el momento de conectar el stream recien
  /// arranca, `.value` devuelve `null` y se le enviaba al telefono un
  /// catalogo vacio. El sintoma era mudo: el telefono se quedaba en
  /// "Esperando el catalogo de acciones..." sin ningun error. Verificado en
  /// un E2E real con un S24 Ultra.
  Future<void> _sendCatalogTo(Iterable<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    final actions = await _container
        .read(actionsRepositoryProvider)
        .watchAll()
        .first;
    final groups = await _container
        .read(actionGroupsRepositoryProvider)
        .watchAll()
        .first;
    final repository = _container.read(connectionRepositoryProvider);
    for (final deviceId in deviceIds) {
      await repository.sendActionsCatalog(deviceId, actions, groups: groups);
    }
  }

  /// Empuja el estado de las suscripciones en vivo -- mismo criterio que
  /// `_sendCatalogTo`.
  Future<void> _sendHubSubscriptionsSnapshotTo(Iterable<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    final subscriptions = await _container
        .read(hubSubscriptionsRepositoryProvider)
        .watchAll()
        .first;
    final summaries = subscriptions.map(hubSubscriptionSummaryOf).toList();
    final repository = _container.read(connectionRepositoryProvider);
    for (final deviceId in deviceIds) {
      await repository.sendHubSubscriptionsSnapshot(deviceId, summaries);
    }
  }

  /// Empuja los nombres de las piezas. Una sola vez por conexion: esto no
  /// cambia mientras la sesion vive. `hostComponentsProvider.future` reusa
  /// el probe ya cacheado -- no vuelve a consultar WMI/NVML.
  Future<void> _sendHostComponentsTo(Iterable<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    final components = await _container.read(hostComponentsProvider.future);
    final repository = _container.read(connectionRepositoryProvider);
    for (final deviceId in deviceIds) {
      await repository.sendHostComponents(deviceId, components);
    }
  }

  /// Empuja si el asistente esta habilitado y listo. `ready` lo decide quien
  /// llama: `aiReadyProvider` es la unica fuente real.
  Future<void> _sendAiStatusTo(
    Iterable<String> deviceIds, {
    required bool ready,
  }) async {
    if (deviceIds.isEmpty) return;
    final enabled = _container.read(aiEnabledProvider);
    final repository = _container.read(connectionRepositoryProvider);
    for (final deviceId in deviceIds) {
      try {
        await repository.sendAiStatus(deviceId, enabled: enabled, ready: ready);
      } catch (_) {
        // El telefono pudo desconectarse justo ahora -- se ignora igual que
        // el resto de los push a un dispositivo que ya no esta.
      }
    }
  }

  /// Le cuenta al dispositivo remoto como termino el comando que pidio.
  ///
  /// Va aparte del ack a proposito: el ack sale enseguida ("lo lance") y esto
  /// llega cuando el comando de verdad termino, que puede ser medio minuto
  /// despues.
  Future<void> _forwardRunToDevice({
    required String deviceId,
    required String actionId,
    required String runId,
  }) async {
    final connection = _container.read(connectionRepositoryProvider);

    Future<void> send(
      connection_bridge.RunPhase phase,
      int elapsedMs, {
      int? exitCode,
      String outputTail = '',
    }) async {
      try {
        await connection.sendActionRunUpdate(
          deviceId: deviceId,
          runId: runId,
          actionId: actionId,
          phase: phase,
          exitCode: exitCode,
          elapsedMs: elapsedMs,
          outputTail: outputTail,
        );
      } catch (_) {
        // El telefono pudo desconectarse mientras el comando corria. No es
        // un error del comando: la ejecucion local sigue mostrandose bien.
      }
    }

    await send(connection_bridge.RunPhase.started, 0);

    final outcome = await _container
        .read(actionsRepositoryProvider)
        .awaitCommandRun(runId);
    final phase = switch (outcome.status) {
      bridge_actions.CommandRunStatus.succeeded =>
        connection_bridge.RunPhase.succeeded,
      bridge_actions.CommandRunStatus.detached =>
        connection_bridge.RunPhase.launched,
      bridge_actions.CommandRunStatus.cancelled =>
        connection_bridge.RunPhase.cancelled,
      bridge_actions.CommandRunStatus.failed =>
        connection_bridge.RunPhase.failed,
    };
    await send(
      phase,
      outcome.elapsedMs,
      exitCode: outcome.exitCode,
      // Recortado de nuevo antes del cable: el anillo de Rust ya manda ~8 KB
      // y para dibujar una notificacion en un telefono alcanza con menos.
      outputTail: clipTail(outcome.outputTail, 4096),
    );
  }

  /// Sin `BuildContext`: no toca UI (solo Drift, el motor de acciones y el
  /// bridge).
  Future<void> _handleConnectionEvent(
    connection_bridge.ConnectionEvent event,
  ) async {
    switch (event) {
      case connection_bridge.ConnectionEvent_DeviceConnected(:final deviceId):
        _container
            .read(connectedDeviceIdsProvider.notifier)
            .update((devices) => {...devices, deviceId});
        await _sendCatalogTo([deviceId]);
        await _sendHubSubscriptionsSnapshotTo([deviceId]);
        await _sendHostComponentsTo([deviceId]);
        await _sendAiStatusTo(
          [deviceId],
          ready: _container.read(aiReadyProvider),
        );
      case connection_bridge.ConnectionEvent_ActionExecutionRequested(
        :final deviceId,
        :final actionId,
        :final params,
      ):
        // Mismo motivo que `_sendCatalogTo`, y aca el sintoma era peor: con
        // el provider autoDispose sin observadores, la lista venia vacia y el
        // telefono recibia "accion no encontrada" para una que existe.
        final actionsRepository = _container.read(actionsRepositoryProvider);
        final actions = await actionsRepository.watchAll().first;
        final action = actions.where((a) => a.id == actionId).firstOrNull;
        final repository = _container.read(connectionRepositoryProvider);
        if (action == null) {
          await repository.sendActionAck(
            deviceId: deviceId,
            actionId: actionId,
            success: false,
            error: 'accion no encontrada',
          );
          return;
        }
        try {
          await actionsRepository.execute(
            action,
            // El telefono recolecta los valores de los `{{placeholders}}` y
            // los manda en `ExecuteAction`; sin pasarlos, una accion
            // parametrizada corria con los valores por defecto, en silencio.
            paramValues: {for (final param in params) param.key: param.value},
            // El ack significa "arranco". Esperar a que termine dejaria al
            // telefono con un spinner 30 segundos por un `flutter analyze`;
            // el resultado real le llega por la notificacion.
            waitForCompletion: false,
            onRunStarted: (runId) {
              _container
                  .read(runCenterProvider.notifier)
                  .declareOrigin(runId, RunOrigin.remote);
              // Sin `await`: seguir el comando hasta el final es exactamente
              // lo que NO se puede hacer antes de mandar el ack.
              unawaited(
                _forwardRunToDevice(
                  deviceId: deviceId,
                  actionId: actionId,
                  runId: runId,
                ),
              );
            },
          );
          await repository.sendActionAck(
            deviceId: deviceId,
            actionId: actionId,
            success: true,
          );
        } catch (e) {
          await repository.sendActionAck(
            deviceId: deviceId,
            actionId: actionId,
            success: false,
            error: '$e',
          );
        }
      case connection_bridge.ConnectionEvent_DeviceDisconnected(
        :final deviceId,
      ):
        _container
            .read(connectedDeviceIdsProvider.notifier)
            .update((devices) => {...devices}..remove(deviceId));
      case connection_bridge.ConnectionEvent_AiMessageRequested(
        :final deviceId,
        :final text,
      ):
        // Hay un solo asistente, no una conversacion por dispositivo -- lo
        // que conteste ya le llega a todos los conectados. `exceptDeviceId`
        // evita duplicar el eco en el telefono que escribio.
        unawaited(
          // **El fallo NO se traga.** Con `catchError((_) => null)` el
          // telefono se quedaba diciendo "el asistente esta trabajando" para
          // siempre y en ningun sitio aparecia el motivo. Se manda `Failed`,
          // que es justo lo que cierra su turno y le enseña por que.
          sendAiMessageBroadcast(
            _container.read,
            text,
            exceptDeviceId: deviceId,
          ).catchError((error) {
            debugPrint('NexoDeck: fallo el mensaje de IA del telefono: $error');
            _forwardAiChatEvent(
              connection_bridge.AiRemoteChatEvent.failed(detail: '$error'),
            );
            return null;
          }),
        );
      case connection_bridge.ConnectionEvent_AiActivateRequested():
        // Si ya esta listo no hay nada que hacer. Que haya cambiado de estado
        // lo entera `_handleAiSetupEvent`, no esto.
        if (_container.read(aiReadyProvider)) break;
        unawaited(
          _container.read(aiRepositoryProvider).startSetup().catchError((_) {}),
        );
      case connection_bridge.ConnectionEvent_AiApplyDraftRequested(:final draft):
        unawaited(
          applyDraftHeadless(
            _container.read,
            ActionDraft.fromRemote(draft),
          ).catchError((_) => null),
        );
      case connection_bridge.ConnectionEvent_AiRunDraftRequested(
        :final deviceId,
        :final draft,
      ):
        unawaited(
          runDraftLiveHeadless(
            _container.read,
            ActionDraft.fromRemote(draft),
            onRunStarted: (stepName, runId) {
              // Mismo mecanismo que una accion remota comun.
              unawaited(
                _forwardRunToDevice(
                  deviceId: deviceId,
                  actionId: stepName,
                  runId: runId,
                ),
              );
            },
          ).catchError((_) => const <LiveStepResult>[]),
        );
      case connection_bridge.ConnectionEvent_AiAskAboutProcessRequested(
        :final group,
      ):
        // El grupo llega tal cual lo tiene el telefono en pantalla; la PC
        // completa lo que falta (padre, linea de comando, dueño) con una
        // consulta fresca antes de armar la pregunta.
        unawaited(
          () async {
            final domainGroup = ProcessGroup.fromBridge(group);
            final details = await processes_bridge.processDetails(
              name: domainGroup.name,
              pids: domainGroup.pids,
            );
            final prompt = buildProcessQuestionPrompt(
              domainGroup,
              details: details,
            );
            // Sin `exceptDeviceId`: la pregunta enriquecida solo existe de
            // este lado, y el eco es lo unico que se la va a mostrar.
            await sendAiMessageBroadcast(_container.read, prompt);
          }().catchError((_) {}),
        );
      case connection_bridge.ConnectionEvent_Connected():
      case connection_bridge.ConnectionEvent_Disconnected():
      case connection_bridge.ConnectionEvent_HardwareSnapshotReceived():
      case connection_bridge.ConnectionEvent_ActionsCatalogReceived():
      case connection_bridge.ConnectionEvent_ActionAckReceived():
      case connection_bridge.ConnectionEvent_ActionRunUpdateReceived():
      case connection_bridge.ConnectionEvent_TopProcessesReceived():
      case connection_bridge.ConnectionEvent_ProcessTerminatedReceived():
      case connection_bridge.ConnectionEvent_RelayOfferReceived():
      case connection_bridge.ConnectionEvent_HubSubscriptionsSnapshotReceived():
      case connection_bridge.ConnectionEvent_HostComponentsReceived():
      case connection_bridge.ConnectionEvent_AiStatusReceived():
      case connection_bridge.ConnectionEvent_AiChatEventReceived():
      case connection_bridge.ConnectionEvent_NotesResponseReceived():
      case connection_bridge.ConnectionEvent_NotesChanged():
        break; // eventos de rol cliente, no aplican en la PC
    }
  }
}

/// Deja las ultimas [maxBytes] del texto, cortando por linea entera. Cortar
/// al medio de una linea produce una primera fila mutilada que confunde mas
/// de lo que informa.
@visibleForTesting
String clipTail(String text, int maxBytes) {
  if (text.length <= maxBytes) return text;
  final cut = text.substring(text.length - maxBytes);
  final firstBreak = cut.indexOf('\n');
  return firstBreak == -1 ? cut : cut.substring(firstBreak + 1);
}
