import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'action_groups_table.dart';

enum ActionType { clipboard, terminal, macro }

enum TerminalType { defaultShell, powershell, bash, cmd }

/// Tabla central: una "accion" es cualquier boton ejecutable (pegar texto,
/// correr un comando, o ser contenedora de una macro).
///
/// Nombrada `ActionsTable` (no `Actions`) para no chocar con
/// `package:flutter/widgets.dart`, que ya exporta una clase `Actions`
/// (el sistema de Actions/Intents de Flutter).
class ActionsTable extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('bolt'))();
  TextColumn get colorHex => text().withDefault(const Constant('#6366F1'))();

  TextColumn get actionType => textEnum<ActionType>()();

  /// Plantilla del comando/texto, con placeholders {{variable}}. Texto
  /// libre en vez de columnas por variable porque el numero de parametros
  /// es dinamico -- ver `ActionParameters`.
  TextColumn get commandTemplate => text().nullable()();

  BoolColumn get requiresAdmin =>
      boolean().withDefault(const Constant(false))();

  TextColumn get terminalType => textEnum<TerminalType>().nullable()();

  /// Solo aplica a `actionType = terminal`. Elige entre los DOS modos de
  /// ejecucion:
  ///
  /// - `false` (por defecto) -- **modo capturado**: el comando corre dentro
  ///   de NexoDeck, sin ninguna ventana, y su salida, su duracion y su codigo
  ///   de salida vuelven como notificacion. Es lo que se quiere casi siempre.
  /// - `true` -- **modo ventana**: abre una consola real y NO se captura
  ///   nada. Es la unica via para comandos interactivos (`ssh`, `npm init`),
  ///   que capturados se colgarian esperando un input que nadie puede
  ///   escribir.
  ///
  /// El default cambio a `false` en `schemaVersion 5`, junto con una
  /// migracion que dio vuelta las filas existentes: antes `true` queria decir
  /// "quiero ver la salida", y la forma de ver la salida ahora es el modo
  /// capturado, asi que darlas vuelta **preserva la intencion original**.
  BoolColumn get showTerminalWindow =>
      boolean().withDefault(const Constant(false))();

  /// Solo aplica a `actionType = clipboard`. Con `true`, ademas de copiar el
  /// texto, NexoDeck le devuelve el foco a la ventana que lo tenia antes del
  /// clic y le manda Ctrl+V.
  ///
  /// Existe porque sin esto una accion de portapapeles disparada con el mouse
  /// es, en la practica, media accion: el propio clic en el deck le saca el
  /// foco a la app de destino, asi que el texto queda copiado pero nunca
  /// llega a donde el usuario tenia el cursor. Ver `focus.rs` en
  /// `nexodeck-actions`.
  ///
  /// Por defecto `false`: copiar sin pegar sigue siendo un uso legitimo
  /// (guardarse un token para mas tarde), y pegar solo por las dudas
  /// escribiria en la ventana equivocada.
  BoolColumn get pasteToActiveWindow =>
      boolean().withDefault(const Constant(false))();

  /// Auto-suscripcion al terminar. Solo tiene efecto en modo capturado
  /// (`showTerminalWindow = false`): cuando el comando termina bien, se
  /// interpreta `outputTail` como JSON, se saca el campo [autoSubscribeJsonField]
  /// (ej. `job_id`) y se arranca una suscripcion SignalR con ese valor como
  /// unico argumento del metodo invocado -- pensado para encadenar un
  /// `curl` que lanza un job con la suscripcion a su progreso, sin que el
  /// usuario tenga que copiar el id a mano. "Activada" = las cuatro
  /// columnas de abajo estan completas; ninguna tiene sentido sola.
  TextColumn get autoSubscribeBaseUrl => text().nullable()();
  TextColumn get autoSubscribeHubPath => text().nullable()();
  TextColumn get autoSubscribeInvokeMethod => text().nullable()();
  TextColumn get autoSubscribeJsonField => text().nullable()();
  BoolColumn get autoSubscribeAllowInvalidCert =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get isFavorite =>
      boolean().withDefault(const Constant(false))();

  /// Categoria a la que pertenece la accion. `null` = sin categorizar.
  /// Borrar el grupo deja la accion sin grupo (`setNull`), no la borra.
  TextColumn get groupId => text()
      .nullable()
      .references(ActionGroups, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
