import 'package:nexodeck/data/local/database.dart';

/// Un conjunto de acciones agrupadas por contexto (Streaming, Edicion,
/// Desarrollo...). A diferencia de `ActionGroup` —que es una categoria
/// visual 1:N dentro del deck— un perfil **decide que acciones componen el
/// deck**, es N:N (una accion puede estar en varios perfiles) y puede
/// activarse solo cuando cierta aplicacion pasa a primer plano.
class DeckProfile {
  const DeckProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.isDefault,
    required this.autoDetectProcess,
  });

  factory DeckProfile.fromRow(Profile row) => DeckProfile(
    id: row.id,
    name: row.name,
    icon: row.icon,
    colorHex: row.colorHex,
    isDefault: row.isDefault,
    autoDetectProcess: row.autoDetectProcess,
  );

  final String id;
  final String name;
  final String icon;
  final String colorHex;
  final bool isDefault;

  /// Nombre del ejecutable que activa este perfil solo (`obs64.exe`).
  /// `null` o vacio = solo activacion manual.
  final String? autoDetectProcess;

  bool get hasAutoDetect =>
      autoDetectProcess != null && autoDetectProcess!.trim().isNotEmpty;
}
