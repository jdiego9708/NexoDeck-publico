import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexodeck/core/di/database_provider.dart';
import 'package:nexodeck/data/local/daos/action_parameters_dao.dart';
import 'package:nexodeck/data/local/daos/actions_dao.dart';
import 'package:nexodeck/data/local/daos/hub_messages_dao.dart';
import 'package:nexodeck/data/local/daos/hub_subscriptions_dao.dart';
import 'package:nexodeck/data/local/daos/macro_steps_dao.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/data/local/tables/devices_table.dart';
import 'package:nexodeck/features/actions/application/actions_provider.dart';
import 'package:nexodeck/features/actions/data/actions_repository.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/ai_assistant/application/ai_providers.dart';
import 'package:nexodeck/features/ai_assistant/data/ai_repository.dart';
import 'package:nexodeck/features/control/application/control_settings_controller.dart';
import 'package:nexodeck/features/control/data/control_repository.dart';
import 'package:nexodeck/features/dashboard/application/hardware_metrics_provider.dart';
import 'package:nexodeck/features/dashboard/application/host_components_provider.dart';
import 'package:nexodeck/features/dashboard/domain/host_components.dart';
import 'package:nexodeck/features/host_runtime/application/host_runtime.dart';
import 'package:nexodeck/features/hub_subscriptions/application/hub_subscriptions_provider.dart';
import 'package:nexodeck/features/hub_subscriptions/data/hub_subscriptions_repository.dart';
import 'package:nexodeck/features/pairing/application/connection_provider.dart';
import 'package:nexodeck/features/pairing/application/devices_provider.dart';
import 'package:nexodeck/features/pairing/data/connection_repository.dart';
import 'package:nexodeck/features/pairing/application/pairing_provider.dart';
import 'package:nexodeck/features/pairing/data/pairing_repository.dart';
import 'package:nexodeck/features/pairing/domain/paired_device.dart';
import 'package:nexodeck/features/profiles/application/profiles_provider.dart';
import 'package:nexodeck/src/rust/api/ai.dart' as ai_bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;
import 'package:nexodeck/src/rust/api/control.dart' as control_bridge;
import 'package:nexodeck/src/rust/api/hub.dart' as hub_bridge;
import 'package:nexodeck/src/rust/api/pairing.dart' as pairing_bridge;

/// Registra lo que `HostRuntime` le manda al telefono, sin tocar el FFI.
class _FakeConnectionRepository extends Fake implements ConnectionRepository {
  final events = StreamController<bridge.ConnectionEvent>.broadcast();

  final catalogsSentTo = <String>[];
  final hubSnapshotsSentTo = <String>[];
  final componentsSentTo = <String>[];
  final aiStatusSentTo = <String>[];
  final acks = <({String actionId, bool success, String? error})>[];
  final authorizedSyncs = <List<PairedDevice>>[];

  @override
  Stream<bridge.ConnectionEvent> watchConnectionEvents() => events.stream;

  @override
  Future<void> sendActionsCatalog(
    String deviceId,
    List<DeckAction> actions, {
    List<ActionGroup> groups = const [],
  }) async => catalogsSentTo.add(deviceId);

  @override
  Future<void> sendHubSubscriptionsSnapshot(
    String deviceId,
    List<bridge.HubSubscriptionSummary> subscriptions,
  ) async => hubSnapshotsSentTo.add(deviceId);

  @override
  Future<void> sendHostComponents(
    String deviceId,
    HostComponents components,
  ) async => componentsSentTo.add(deviceId);

  @override
  Future<void> sendAiStatus(
    String deviceId, {
    required bool enabled,
    required bool ready,
  }) async => aiStatusSentTo.add(deviceId);

  @override
  Future<void> sendActionAck({
    required String deviceId,
    required String actionId,
    required bool success,
    String? error,
  }) async => acks.add((actionId: actionId, success: success, error: error));

  @override
  Future<void> syncAuthorizedDevices(List<PairedDevice> devices) async =>
      authorizedSyncs.add(devices);
}

/// El motor real ejecuta por FFI; aca solo interesa cuantas veces se pidio.
class _RecordingActionsRepository extends ActionsRepository {
  _RecordingActionsRepository(NexoDeckDatabase db, HubSubscriptionsRepository hubs)
    : super(db, ActionsDao(db), ActionParametersDao(db), MacroStepsDao(db), hubs);

  final executed = <String>[];

  @override
  Future<void> execute(
    DeckAction action, {
    Map<String, String> paramValues = const {},
    void Function(int index, int total, DeckAction step)? onStep,
    bool waitForCompletion = true,
    void Function(String runId)? onRunStarted,
  }) async => executed.add(action.id);
}

class _SilentHubSubscriptionsRepository extends HubSubscriptionsRepository {
  _SilentHubSubscriptionsRepository(NexoDeckDatabase db)
    : super(HubSubscriptionsDao(db), HubMessagesDao(db));

  @override
  Stream<hub_bridge.HubSubscriptionEvent> watchEvents() => const Stream.empty();
}

class _SilentAiRepository extends Fake implements AiRepository {
  @override
  Stream<ai_bridge.AiSetupEvent> watchSetupEvents() => const Stream.empty();

  @override
  Stream<ai_bridge.AiChatEvent> watchChatEvents() => const Stream.empty();
}

class _SilentPairingRepository extends Fake implements PairingRepository {
  @override
  Stream<pairing_bridge.PairingEvent> watchPairingEvents() =>
      const Stream.empty();
}

class _SilentControlRepository extends Fake implements ControlRepository {
  @override
  Stream<control_bridge.CorrespondentEvent> watchCorrespondent() =>
      const Stream.empty();
}

/// Espera a que [condition] se cumpla: `HostRuntime` reacciona a eventos de
/// forma asincrona (lee Drift antes de contestar), y un `pump` fijo seria
/// flaky en una maquina cargada.
Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('la condicion no se cumplio a tiempo');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late NexoDeckDatabase db;
  late _FakeConnectionRepository connection;
  late _RecordingActionsRepository actions;
  late ProviderContainer container;
  late HostRuntime runtime;

  setUp(() {
    db = NexoDeckDatabase.forTesting(NativeDatabase.memory());
    connection = _FakeConnectionRepository();
    final hubs = _SilentHubSubscriptionsRepository(db);
    actions = _RecordingActionsRepository(db, hubs);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        connectionRepositoryProvider.overrideWithValue(connection),
        actionsRepositoryProvider.overrideWithValue(actions),
        hubSubscriptionsRepositoryProvider.overrideWithValue(hubs),
        aiRepositoryProvider.overrideWithValue(_SilentAiRepository()),
        controlRepositoryProvider.overrideWithValue(_SilentControlRepository()),
        pairingRepositoryProvider.overrideWithValue(_SilentPairingRepository()),
        hostComponentsProvider.overrideWith((ref) async => const HostComponents()),
        hardwareMetricsProvider.overrideWith((ref) => const Stream.empty()),
        foregroundAppProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );

    // Ningun widget montado: es justo lo que tiene que funcionar.
    runtime = HostRuntime(container)..start();
  });

  tearDown(() async {
    runtime.dispose();
    container.dispose();
    await connection.events.close();
    await db.close();
  });

  Future<String> createClipboardAction(String name) =>
      actions.createAction(
        name: name,
        icon: 'content_copy',
        colorHex: '#FF5722',
        actionType: ActionType.clipboard,
        commandTemplate: 'hola',
      );

  test('pushes catalog, hubs, components and AI status to a device that connects', () async {
    connection.events.add(
      const bridge.ConnectionEvent.deviceConnected(deviceId: 'phone-1'),
    );

    await _eventually(() => connection.aiStatusSentTo.isNotEmpty);
    expect(connection.catalogsSentTo, ['phone-1']);
    expect(connection.hubSnapshotsSentTo, ['phone-1']);
    expect(connection.componentsSentTo, ['phone-1']);
    expect(connection.aiStatusSentTo, ['phone-1']);
    expect(container.read(connectedDeviceIdsProvider), {'phone-1'});
  });

  test('forgets a device that disconnects', () async {
    connection.events
      ..add(const bridge.ConnectionEvent.deviceConnected(deviceId: 'phone-1'))
      ..add(const bridge.ConnectionEvent.deviceDisconnected(deviceId: 'phone-1'));

    await _eventually(() => connection.aiStatusSentTo.isNotEmpty);
    await _eventually(() => container.read(connectedDeviceIdsProvider).isEmpty);
  });

  test('runs two identical execute requests twice', () async {
    // Regresion de la regla de `CLAUDE.md`: dos `ExecuteAction` identicos
    // seguidos son `==`, y por `ref.listen` el segundo se perdia en silencio.
    final actionId = await createClipboardAction('Copiar saludo');
    final request = bridge.ConnectionEvent.actionExecutionRequested(
      deviceId: 'phone-1',
      actionId: actionId,
      params: const [],
    );

    connection.events
      ..add(request)
      ..add(request);

    await _eventually(() => connection.acks.length == 2);
    expect(actions.executed, [actionId, actionId]);
    expect(connection.acks.every((ack) => ack.success), isTrue);
  });

  test('acks a failure for an action that does not exist', () async {
    connection.events.add(
      const bridge.ConnectionEvent.actionExecutionRequested(
        deviceId: 'phone-1',
        actionId: 'missing',
        params: [],
      ),
    );

    await _eventually(() => connection.acks.isNotEmpty);
    expect(connection.acks.single.success, isFalse);
    expect(actions.executed, isEmpty);
  });

  test('re-sends the catalog when actions change with a device connected', () async {
    connection.events.add(
      const bridge.ConnectionEvent.deviceConnected(deviceId: 'phone-1'),
    );
    await _eventually(() => connection.aiStatusSentTo.isNotEmpty);
    final sentBefore = connection.catalogsSentTo.length;

    await createClipboardAction('Nueva accion');

    await _eventually(() => connection.catalogsSentTo.length > sentBefore);
  });

  test('syncs authorized devices with Rust when the devices table changes', () async {
    // Sin esto Rust arranca con la cache de autorizados vacia y rechaza toda
    // reconexion -- y antes solo lo hacia `_HomeShell`, que no se monta en
    // modo compacto.
    await _eventually(() => connection.authorizedSyncs.isNotEmpty);

    await container
        .read(devicesRepositoryProvider)
        .pairDevice(
          id: 'phone-1',
          name: 'S24 Ultra',
          platform: DevicePlatform.android,
          certFingerprint: 'ab:cd',
        );

    await _eventually(
      () => connection.authorizedSyncs.last.any((d) => d.id == 'phone-1'),
    );
  });

  test('clipTail cuts on a whole line', () {
    expect(clipTail('corto', 4096), 'corto');
    expect(clipTail('linea uno\nlinea dos\nlinea tres', 14), 'linea tres');
  });
}
