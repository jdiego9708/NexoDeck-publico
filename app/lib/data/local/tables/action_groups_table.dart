import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Categorias que el usuario define para organizar/filtrar sus acciones
/// (ej. Desarrollo, Juegos, Entretenimiento, General). Una accion
/// pertenece a lo sumo un grupo (ver `ActionsTable.groupId`) -- a
/// diferencia de `Profiles`/`ProfileActions` (N:N, perfiles exclusivos
/// con auto-deteccion de proceso), esto es una simple etiqueta visual de
/// categoria, no un layout activo.
class ActionGroups extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text().withDefault(const Constant('folder'))();
  TextColumn get colorHex => text().withDefault(const Constant('#6366F1'))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
