import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'daos/action_groups_dao.dart';
import 'daos/action_parameters_dao.dart';
import 'daos/actions_dao.dart';
import 'daos/alert_rules_dao.dart';
import 'daos/app_settings_dao.dart';
import 'daos/chat_conversations_dao.dart';
import 'daos/devices_dao.dart';
import 'daos/hardware_history_dao.dart';
import 'daos/hub_messages_dao.dart';
import 'daos/hub_subscriptions_dao.dart';
import 'daos/macro_steps_dao.dart';
import 'daos/profile_actions_dao.dart';
import 'daos/profiles_dao.dart';
import 'daos/secrets_refs_dao.dart';
import 'daos/window_layouts_dao.dart';
import 'tables/action_groups_table.dart';
import 'tables/action_parameters_table.dart';
import 'tables/actions_table.dart';
import 'tables/alert_rules_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/chat_conversations_table.dart';
import 'tables/chat_messages_table.dart';
import 'tables/devices_table.dart';
import 'tables/hardware_history_table.dart';
import 'tables/hub_messages_table.dart';
import 'tables/hub_subscriptions_table.dart';
import 'daos/notes_mirror_dao.dart';
import 'tables/macro_steps_table.dart';
import 'tables/note_mirror_table.dart';
import 'tables/note_outbox_table.dart';
import 'tables/profile_actions_table.dart';
import 'tables/profiles_table.dart';
import 'tables/secrets_refs_table.dart';
import 'tables/window_layouts_table.dart';

part 'database.g.dart';

/// Union de las tablas del esquema. Las primeras 11 se crearon todas de
/// una sola vez en schemaVersion 1 (decision explicita del usuario, ver
/// CLAUDE.md) en vez de agregarlas incrementalmente fase por fase;
/// `ActionGroups` se agrego despues en schemaVersion 2 (grupos/categorias
/// de acciones), y `ActionsTable.showTerminalWindow` en schemaVersion 3
/// (ver `onUpgrade` abajo).
@DriftDatabase(
  tables: [
    ActionsTable,
    ActionParameters,
    MacroSteps,
    Profiles,
    ProfileActions,
    Devices,
    AlertRules,
    HardwareHistory,
    SecretsRefs,
    WindowLayouts,
    AppSettings,
    ActionGroups,
    HubSubscriptions,
    HubMessages,
    ChatConversations,
    ChatMessages,
    NoteMirror,
    NoteOutbox,
  ],
  daos: [
    ActionsDao,
    ActionParametersDao,
    MacroStepsDao,
    ProfilesDao,
    ProfileActionsDao,
    DevicesDao,
    AlertRulesDao,
    HardwareHistoryDao,
    SecretsRefsDao,
    WindowLayoutsDao,
    AppSettingsDao,
    ActionGroupsDao,
    HubSubscriptionsDao,
    HubMessagesDao,
    ChatConversationsDao,
    NotesMirrorDao,
  ],
)
class NexoDeckDatabase extends _$NexoDeckDatabase {
  NexoDeckDatabase() : super(driftDatabase(name: 'nexodeck'));

  NexoDeckDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaults(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(actionGroups);
        await _addColumnIfMissing(m, actionsTable, actionsTable.groupId);
      }
      if (from < 3) {
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.showTerminalWindow,
        );
      }
      if (from < 4) {
        // Historial persistido (Fase 9): faltaban las tasas de red, que la
        // tabla original no preveia.
        await _addColumnIfMissing(
          m,
          hardwareHistory,
          hardwareHistory.netRxBytesPerSec,
        );
        await _addColumnIfMissing(
          m,
          hardwareHistory,
          hardwareHistory.netTxBytesPerSec,
        );
      }
      if (from < 5) {
        // `showTerminalWindow` cambio de significado con la ejecucion
        // capturada: ya no es "mostrar una consola" sino "necesito una
        // terminal REAL (comando interactivo)". El `true` viejo queria decir
        // "quiero ver la salida", y ahora la salida se ve dentro de la app,
        // asi que darlas vuelta preserva la intencion en vez de dejar todas
        // las acciones existentes abriendo ventanas que el usuario ya no
        // quiere. Quien de verdad tenga un comando interactivo vuelve a
        // prender el toggle en el editor.
        await customStatement(
          'UPDATE actions_table SET show_terminal_window = 0',
        );
      }
      if (from < 6) {
        // Pegado en la ventana activa para acciones de portapapeles. Entra
        // apagada en las filas existentes: prenderla sola haria que decks ya
        // armados empezaran a escribir en la app que el usuario tenga
        // adelante, que es justo lo que nadie espera de un cambio de version.
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.pasteToActiveWindow,
        );
      }
      if (from < 7) {
        // Direccion fija para alcanzar la PC fuera de la LAN (Tailscale y
        // similares). Entra en null: quien ya tenia un dispositivo
        // emparejado sigue reconectando por mDNS exactamente igual que
        // antes, y la direccion manual solo existe si la escribe.
        await _addColumnIfMissing(m, devices, devices.manualHost);
        await _addColumnIfMissing(m, devices, devices.manualPort);
      }
      if (from < 8) {
        // Suscripciones en vivo (SignalR o WebSocket crudo) + su historial
        // de mensajes -- tablas nuevas, no columnas, asi que no hace falta
        // `_addColumnIfMissing` aca.
        await m.createTable(hubSubscriptions);
        await m.createTable(hubMessages);
      }
      if (from < 9) {
        // Auto-suscripcion al terminar un comando capturado (ver el
        // comentario de las columnas en `actions_table.dart`). Entra en
        // null/`false`: ninguna accion existente empieza a suscribirse sola.
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.autoSubscribeBaseUrl,
        );
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.autoSubscribeHubPath,
        );
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.autoSubscribeInvokeMethod,
        );
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.autoSubscribeJsonField,
        );
        await _addColumnIfMissing(
          m,
          actionsTable,
          actionsTable.autoSubscribeAllowInvalidCert,
        );
      }
      if (from < 10) {
        // Resumen del ultimo mensaje, para el panel remoto de Android (ver
        // el comentario de la columna en `hub_subscriptions_table.dart`).
        // Entra en null: las suscripciones existentes lo ganan recien con
        // el proximo mensaje que reciban.
        await _addColumnIfMissing(
          m,
          hubSubscriptions,
          hubSubscriptions.lastEventSummary,
        );
      }
      if (from < 11) {
        // Tunel por relay para fuera de la LAN (ver el comentario de las
        // columnas en `devices_table.dart`). Entra en null: ningun
        // dispositivo emparejado tiene tunel hasta que la PC lo prenda y
        // llegue el primer `RelayOfferReceived`.
        await _addColumnIfMissing(m, devices, devices.relayHost);
        await _addColumnIfMissing(m, devices, devices.relayPort);
        await _addColumnIfMissing(m, devices, devices.relayTokenHex);
      }
      if (from < 12) {
        // Las conversaciones del asistente pasan a guardarse. Antes vivian
        // solo en memoria: cerrar el dialogo las perdia, y el historial del
        // modelo (que si sobrevivia, del lado Rust) quedaba sin pantalla que
        // lo mostrara.
        //
        // `createTable` es idempotente en la practica porque drift emite
        // `CREATE TABLE IF NOT EXISTS`, igual de seguro que los
        // `_addColumnIfMissing` de arriba frente a una migracion cortada a
        // medias por un apagon.
        await m.createTable(chatConversations);
        await m.createTable(chatMessages);
      }
      if (from < 13) {
        // Las notas en el movil: la copia local de la boveda y la cola de lo
        // que falta mandarle a la PC. Entran vacias -- la primera sincronizacion
        // las llena, y hasta entonces la pantalla de notas dice que todavia no
        // hay nada. Mismo `createTable` idempotente que la 12.
        await m.createTable(noteMirror);
        await m.createTable(noteOutbox);
      }
    },
    beforeOpen: (details) async {
      // sqlite3 no habilita foreign keys por defecto -- sin esto, los
      // onDelete: KeyAction.cascade de las tablas no se aplican en runtime.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// `ALTER TABLE ... ADD COLUMN` que tolera que la columna YA exista.
  ///
  /// No es paranoia defensiva: la base real del equipo principal aparecio
  /// con `paste_to_active_window` ya creada y `user_version` todavia en 5,
  /// o sea a mitad de la migracion a la 6 -- el PC se apago mientras
  /// corria. Sin esto la app no vuelve a abrir NUNCA: cada arranque
  /// reintenta el mismo ALTER y muere con "duplicate column name", que es
  /// un error del que el usuario no tiene forma de salir.
  ///
  /// Va en todos los `addColumn` y no solo en el que fallo: cualquiera de
  /// ellos puede quedar a medias por el mismo motivo.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    final rows = await customSelect(
      "PRAGMA table_info('${table.actualTableName}')",
    ).get();
    final existing = rows.map((r) => r.read<String>('name')).toSet();
    if (existing.contains(column.name)) return;
    await m.addColumn(table, column);
  }
}

/// Perfil "General" por defecto + 2-3 acciones de ejemplo por perfil
/// (dev/streaming/edicion) para que el potencial de la app se vea desde el
/// primer arranque.
Future<void> _seedDefaults(NexoDeckDatabase db) async {
  const uuid = Uuid();

  final generalProfileId = uuid.v4();
  await db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: Value(generalProfileId),
          name: 'General',
          icon: const Value('folder'),
          colorHex: const Value('#22C55E'),
          isDefault: const Value(true),
        ),
      );

  final devProfileId = uuid.v4();
  await db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: Value(devProfileId),
          name: 'Desarrollo',
          icon: const Value('code'),
          colorHex: const Value('#6366F1'),
        ),
      );

  final streamingProfileId = uuid.v4();
  await db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: Value(streamingProfileId),
          name: 'Streaming',
          icon: const Value('videocam'),
          colorHex: const Value('#EF4444'),
        ),
      );

  // Grupos/categorias de ejemplo -- distintos de los profiles de arriba
  // (ver `action_groups_table.dart`): esto es solo para que la barra de
  // filtro de la grilla no arranque vacia en el primer uso.
  final devGroupId = uuid.v4();
  await db
      .into(db.actionGroups)
      .insert(
        ActionGroupsCompanion.insert(
          id: Value(devGroupId),
          name: 'Desarrollo',
          icon: const Value('code'),
          colorHex: const Value('#6366F1'),
          orderIndex: const Value(0),
        ),
      );

  final streamingGroupId = uuid.v4();
  await db
      .into(db.actionGroups)
      .insert(
        ActionGroupsCompanion.insert(
          id: Value(streamingGroupId),
          name: 'Streaming',
          icon: const Value('videocam'),
          colorHex: const Value('#EF4444'),
          orderIndex: const Value(1),
        ),
      );

  Future<void> seedAction({
    required String profileId,
    String? groupId,
    required String name,
    required String description,
    required String icon,
    required ActionType type,
    String? commandTemplate,
    TerminalType? terminalType,
    bool showTerminalWindow = true,
  }) async {
    final actionId = uuid.v4();
    await db
        .into(db.actionsTable)
        .insert(
          ActionsTableCompanion.insert(
            id: Value(actionId),
            name: name,
            description: Value(description),
            icon: Value(icon),
            actionType: type,
            commandTemplate: Value(commandTemplate),
            terminalType: Value(terminalType),
            showTerminalWindow: Value(showTerminalWindow),
            groupId: Value(groupId),
          ),
        );
    await db
        .into(db.profileActions)
        .insert(
          ProfileActionsCompanion.insert(
            profileId: profileId,
            actionId: actionId,
          ),
        );
  }

  await seedAction(
    profileId: devProfileId,
    groupId: devGroupId,
    name: 'Git status',
    description: 'Muestra el estado del repo actual',
    icon: 'terminal',
    type: ActionType.terminal,
    commandTemplate: 'git status',
    terminalType: TerminalType.defaultShell,
  );
  await seedAction(
    profileId: devProfileId,
    groupId: devGroupId,
    name: 'Migracion Drift',
    description: 'Pega el comando para crear una migracion',
    icon: 'storage',
    type: ActionType.clipboard,
    commandTemplate: 'dart run drift_dev make-migrations',
  );

  await seedAction(
    profileId: streamingProfileId,
    groupId: streamingGroupId,
    name: 'Abrir OBS',
    description: 'Levanta OBS Studio',
    icon: 'videocam',
    type: ActionType.terminal,
    commandTemplate: 'start obs64.exe',
    terminalType: TerminalType.cmd,
    showTerminalWindow: false,
  );
  await seedAction(
    profileId: streamingProfileId,
    groupId: streamingGroupId,
    name: 'Copiar plantilla de titulo',
    description: 'Pega una plantilla de titulo para el stream',
    icon: 'edit',
    type: ActionType.clipboard,
    commandTemplate: '🔴 EN VIVO — {{tema}}',
  );
}
