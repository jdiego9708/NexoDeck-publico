import 'package:drift/drift.dart';

/// Solo metadatos. El valor cifrado real vive en nexodeck-vault (Rust),
/// identificado por keyName. Esta tabla existe unicamente para que la UI
/// pueda listar "que secretos existen" y permitir referenciarlos en
/// commandTemplate (ej. {{secret:API_TOKEN}}) sin que Drift/Dart vea jamas
/// el valor descifrado.
class SecretsRefs extends Table {
  /// Identificador usado en templates, ej. "API_TOKEN".
  TextColumn get keyName => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {keyName};
}
