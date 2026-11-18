import 'package:nexodeck/data/local/database.dart' show ActionGroup;
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';
import 'package:nexodeck/data/local/tables/actions_table.dart';
import 'package:nexodeck/features/actions/domain/action_param.dart';
import 'package:nexodeck/features/actions/domain/deck_action.dart';
import 'package:nexodeck/features/actions/domain/macro_plan.dart';
import 'package:nexodeck/features/dashboard/domain/host_components.dart';
import 'package:nexodeck/src/rust/api/components.dart' as bridge;
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;

import '../domain/paired_device.dart';

/// Envuelve las funciones del bridge para la sesion post-pairing (ambos
/// roles). Wrapper delgado -- la logica real vive en `nexodeck-transport`.
class ConnectionRepository {
  const ConnectionRepository();

  Stream<bridge.ConnectionEvent> watchConnectionEvents() =>
      bridge.watchConnectionEvents();

  /// Rol Android. [paramValues] son los valores que el usuario cargo en el
  /// prompt del telefono; va vacio si la accion no tiene parametros.
  Future<void> sendExecuteAction(
    String actionId, {
    Map<String, String> paramValues = const {},
  }) => bridge.sendExecuteAction(
    actionId: actionId,
    params: [
      for (final entry in paramValues.entries)
        bridge.ActionParamValue(key: entry.key, value: entry.value),
    ],
  );

  /// Rol PC: empuja el catalogo de acciones disponibles hacia un
  /// dispositivo recien conectado -- ver el comentario en
  /// `MessageV1::ActionsCatalog` (nexodeck-protocol) sobre por que esto es
  /// necesario (cada dispositivo siembra su propia base Drift con ids
  /// aleatorios propios). [groups] resuelve `DeckAction.groupId` a
  /// nombre/color reales -- se manda denormalizado por accion porque
  /// Android no tiene su propio catalogo de grupos contra el cual
  /// resolver un id.
  /// Los parametros viajan **resueltos con `promptParametersFor`**, no
  /// crudos: para una macro eso es la union de los parametros de todos sus
  /// pasos, que es exactamente lo que el telefono tiene que preguntar. Sin
  /// esto, tocar una macro parametrizada desde Android corria con los
  /// valores por defecto sin avisar.
  Future<void> sendActionsCatalog(
    String deviceId,
    List<DeckAction> actions, {
    List<ActionGroup> groups = const [],
  }) {
    final groupsById = {for (final g in groups) g.id: g};
    return bridge.sendActionsCatalog(
      deviceId: deviceId,
      actions: actions.map((a) {
        final group = a.groupId == null ? null : groupsById[a.groupId];
        return bridge.RemoteAction(
          id: a.id,
          name: a.name,
          icon: a.icon,
          colorHex: a.colorHex,
          groupId: group?.id,
          groupName: group?.name,
          groupColorHex: group?.colorHex,
          kind: _toBridgeKind(a.actionType),
          parameters: [
            for (final param in promptParametersFor(a, actions))
              bridge.RemoteActionParam(
                key: param.key,
                label: param.label,
                kind: _toBridgeParamKind(param.inputType),
                defaultValue: param.defaultValue,
                // Ya vienen parseadas del dominio: el protocolo no lleva
                // JSON (ADR 0001).
                options: param.options,
              ),
          ],
          // Se cuentan los pasos RESUELTOS (`planMacro`), no las filas
          // crudas: un paso que apunta a una accion borrada o a otra macro
          // no se va a ejecutar, asi que anunciarlo seria mentir.
          stepCount: a.actionType == ActionType.macro
              ? planMacro(a, actions).length
              : 0,
        );
      }).toList(),
    );
  }

  static bridge.RemoteActionKind _toBridgeKind(ActionType type) =>
      switch (type) {
        ActionType.clipboard => bridge.RemoteActionKind.clipboard,
        ActionType.terminal => bridge.RemoteActionKind.terminal,
        ActionType.macro => bridge.RemoteActionKind.macro,
      };

  static bridge.RemoteParamKind _toBridgeParamKind(ParamInputType type) =>
      switch (type) {
        ParamInputType.text => bridge.RemoteParamKind.text,
        ParamInputType.number => bridge.RemoteParamKind.number,
        ParamInputType.select => bridge.RemoteParamKind.select,
      };

  /// Convierte los parametros que llegaron por el catalogo al tipo de
  /// dominio que consume `showParameterPromptDialog` -- asi el telefono
  /// dibuja exactamente el mismo prompt que la PC.
  static List<ActionParam> paramsFromBridge(
    List<bridge.RemoteActionParam> params,
  ) => [
    for (final (index, param) in params.indexed)
      ActionParam(
        // El catalogo no trae ids de fila (son de la base de la PC y no
        // significan nada aca); el indice alcanza porque solo se usa como
        // identidad dentro del dialogo.
        id: 'remote-$index-${param.key}',
        key: param.key,
        label: param.label,
        inputType: switch (param.kind) {
          bridge.RemoteParamKind.text => ParamInputType.text,
          bridge.RemoteParamKind.number => ParamInputType.number,
          bridge.RemoteParamKind.select => ParamInputType.select,
        },
        defaultValue: param.defaultValue,
        options: param.options,
        orderIndex: index,
      ),
  ];

  /// Rol PC: empuja el estado completo de las suscripciones en vivo hacia un
  /// dispositivo ya conectado -- se llama al recibir
  /// `ConnectionEvent::DeviceConnected` y de nuevo cada vez que
  /// `hubSubscriptionsListProvider` cambia (ver `main.dart`), mismo patron
  /// que `sendActionsCatalog`.
  Future<void> sendHubSubscriptionsSnapshot(
    String deviceId,
    List<bridge.HubSubscriptionSummary> subscriptions,
  ) => bridge.sendHubSubscriptionsSnapshot(
    deviceId: deviceId,
    subscriptions: subscriptions,
  );

  /// Rol PC: empuja los nombres de las piezas hacia un dispositivo ya
  /// conectado -- se llama una sola vez, al recibir
  /// `ConnectionEvent::DeviceConnected` (ver `main.dart`). No se resuelve de
  /// nuevo en cada cambio como el catalogo o las suscripciones: esto no
  /// cambia mientras la sesion vive.
  Future<void> sendHostComponents(String deviceId, HostComponents components) =>
      bridge.sendHostComponents(
        deviceId: deviceId,
        components: bridge.HostComponents(
          cpuName: components.cpuName,
          ramVendor: components.ramVendor,
          ramPartNumber: components.ramPartNumber,
          ramSpeedMts: components.ramSpeedMts,
          ramSpeedRatedMts: components.ramSpeedRatedMts,
          ramModuleCount: components.ramModuleCount,
          gpuName: components.gpuName,
          gpuVramTotalMb: components.gpuVramTotalMb,
          networkAdapter: components.networkAdapter,
        ),
      );

  /// Rol PC.
  Future<void> sendActionAck({
    required String deviceId,
    required String actionId,
    required bool success,
    String? error,
  }) => bridge.sendActionAck(
    deviceId: deviceId,
    actionId: actionId,
    success: success,
    error: error,
  );

  /// Rol PC: cuenta al dispositivo remoto como termino el comando que pidio.
  /// Pasa por aca (y no directo al bridge) para que `HostRuntime` se pueda
  /// probar sin FFI.
  Future<void> sendActionRunUpdate({
    required String deviceId,
    required String runId,
    required String actionId,
    required bridge.RunPhase phase,
    int? exitCode,
    required int elapsedMs,
    required String outputTail,
  }) => bridge.sendActionRunUpdate(
    deviceId: deviceId,
    runId: runId,
    actionId: actionId,
    phase: phase,
    exitCode: exitCode,
    elapsedMs: elapsedMs,
    outputTail: outputTail,
  );

  /// Rol PC: mantiene la cache de autorizados de Rust sincronizada con la
  /// tabla `devices` de Drift -- se llama cada vez que cambia la lista.
  Future<void> syncAuthorizedDevices(List<PairedDevice> devices) =>
      bridge.syncAuthorizedDevices(
        devices: devices
            .map(
              (d) => bridge.AuthorizedDevice(
                id: d.id,
                isAuthorized: d.isAuthorized,
              ),
            )
            .toList(),
      );

  Future<void> setDeviceAuthorized(String deviceId, bool isAuthorized) =>
      bridge.setDeviceAuthorized(
        deviceId: deviceId,
        isAuthorized: isAuthorized,
      );

  /// Rol PC: empuja si el asistente de IA esta habilitado y listo hacia un
  /// dispositivo ya conectado -- se llama al recibir
  /// `ConnectionEvent::DeviceConnected` y de nuevo cada vez que cambia el
  /// switch de arriba o el motor termina de activarse (ver `main.dart`).
  Future<void> sendAiStatus(
    String deviceId, {
    required bool enabled,
    required bool ready,
  }) => bridge.sendAiStatus(deviceId: deviceId, enabled: enabled, ready: ready);

  /// Rol PC: reenvia un evento de la conversacion con el asistente hacia un
  /// dispositivo ya conectado -- ver `ai_chat_view.dart`.
  Future<void> sendAiChatEvent(String deviceId, bridge.AiRemoteChatEvent event) =>
      bridge.sendAiChatEvent(deviceId: deviceId, event: event);

  /// Rol Android: manda un mensaje al chat del asistente que corre en la PC.
  Future<void> sendAiMessage(String text) => bridge.sendAiMessage(text: text);

  /// Rol Android: pide que la PC active el asistente. Solo tiene sentido si
  /// el ultimo `AiStatusReceived` dijo `enabled: true, ready: false`.
  Future<void> sendAiActivate() => bridge.sendAiActivate();

  /// Rol Android: pide guardar un borrador como boton nuevo. Los comandos de
  /// cada paso ya vienen resueltos -- el telefono ya junto los parametros
  /// con el mismo dialogo que usa la PC.
  Future<void> sendAiApplyDraft(bridge.AiRemoteDraft draft) =>
      bridge.sendAiApplyDraft(draft: draft);

  /// Rol Android: pide correr un borrador ahora, en vivo.
  Future<void> sendAiRunDraft(bridge.AiRemoteDraft draft) =>
      bridge.sendAiRunDraft(draft: draft);
}
