import 'deck_profile.dart';

/// `true` si [processName] (lo que reporta el SO para la ventana en foco,
/// ej. `obs64.exe`) corresponde al ejecutable [configured] que el usuario
/// escribio en el perfil.
///
/// Reglas, y por que:
///
/// - **Sin distinguir mayusculas**: Windows no las distingue en nombres de
///   archivo, y nadie va a escribir `Code.exe` con la capitalizacion exacta
///   en un campo de texto libre.
/// - **Tolera que falte la extension** (`obs64` matchea `obs64.exe`): es el
///   error de tipeo garantizado en este campo.
/// - **NO matchea por prefijo**: `obs` no debe activar el perfil de
///   `obs64.exe`. Un `startsWith` haria que un nombre corto capture
///   ejecutables que no tienen nada que ver (`code` capturaria
///   `code_helper.exe`).
/// - **Vacio nunca matchea**: `autoDetectProcess` vacio significa "solo
///   activacion manual", no "cualquier cosa".
bool matchesProcess(String processName, String? configured) {
  final expected = (configured ?? '').trim().toLowerCase();
  if (expected.isEmpty) return false;

  final actual = processName.trim().toLowerCase();
  if (actual == expected) return true;

  final dot = actual.lastIndexOf('.');
  if (dot <= 0) return false;
  return actual.substring(0, dot) == expected;
}

/// El perfil que corresponde activar para [processName], o `null` si
/// ninguno lo reclama.
///
/// Con varios perfiles apuntando al mismo ejecutable gana **el primero de
/// la lista** (que viene ordenada por nombre). Es arbitrario pero estable:
/// lo importante es que no oscile entre dos perfiles en cada tick del
/// detector de foco.
DeckProfile? profileForProcess(
  String? processName,
  List<DeckProfile> profiles,
) {
  if (processName == null) return null;
  for (final profile in profiles) {
    if (matchesProcess(processName, profile.autoDetectProcess)) {
      return profile;
    }
  }
  return null;
}
