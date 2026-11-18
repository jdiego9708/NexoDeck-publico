import 'package:drift/drift.dart';

/// Configuracion clave-valor simple: tema, idioma, retencion de historial,
/// perfil activo actual, etc. El valor se guarda como string y se parsea
/// segun la clave en la capa de repositorio.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
