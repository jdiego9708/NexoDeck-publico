import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Conjuntos de acciones agrupadas por contexto (Streaming, Edicion,
/// Desarrollo, etc).
class Profiles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text().withDefault(const Constant('folder'))();
  TextColumn get colorHex => text().withDefault(const Constant('#22C55E'))();
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();

  /// Nombre de proceso para auto-deteccion (ej. "obs64.exe"). `null` =
  /// solo activacion manual.
  TextColumn get autoDetectProcess => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
