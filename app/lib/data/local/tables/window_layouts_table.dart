import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

enum WindowMode { compact, fullscreen }

/// Configuracion de posicion/tamano para el modo compacto anclado
/// (multi-monitor incluido).
class WindowLayouts extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  TextColumn get mode => textEnum<WindowMode>()();

  RealColumn get posX => real()();
  RealColumn get posY => real()();
  RealColumn get width => real()();
  RealColumn get height => real()();

  /// Identificador de monitor del SO.
  TextColumn get monitorId => text().nullable()();
  BoolColumn get alwaysOnTop =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
