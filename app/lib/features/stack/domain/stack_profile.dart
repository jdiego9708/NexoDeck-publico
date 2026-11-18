/// Perfil del stack multiagente que el switch de la pantalla principal puede
/// arrancar o parar.
///
/// El nombre visible es «Perfil A/B/C»: **que** modelos lleva cada uno no se
/// escribe aqui, sino que sale de la config del asistente y se muestra en tiempo
/// real (el desplegable recibe un `describe` desde el chat, que si ve la config).
/// El enum conserva los nombres viejos (`rapido`/`contextoLargo`/`texto`) porque
/// se persisten: cambiarlos dejaria una seleccion guardada apuntando a la nada.
/// `detail` queda como texto de reserva cuando no hay config a la vista.
enum StackProfile {
  rapido(label: 'Perfil A', detail: 'Router + Gemma'),
  contextoLargo(label: 'Perfil B', detail: 'Router + Qwen3-Coder'),
  texto(label: 'Perfil C', detail: 'Router + Qwen3.5 9B'),
  apagado(label: 'Apagado', detail: 'Se libera la GPU');

  const StackProfile({required this.label, required this.detail});

  /// Lo que ve el usuario en el menu de modo.
  final String label;

  /// Texto de reserva con los modelos de la receta. La UI lo pisa con la
  /// config real cuando la tiene a mano.
  final String detail;

  /// El nombre de perfil de «Configura tus perfiles» (`A`/`B`/`C`) que
  /// corresponde a este modo, o `null` para [apagado]. Es lo que permite ir de
  /// un [StackProfile] a su config sin repetir el mapeo.
  String? get profileName => switch (this) {
    StackProfile.rapido => 'A',
    StackProfile.contextoLargo => 'B',
    StackProfile.texto => 'C',
    StackProfile.apagado => null,
  };

  /// Tolera un valor guardado que ya no exista (version vieja): cae a
  /// `apagado`, que es el estado del que no se espera nada.
  ///
  /// El perfil C se llamaba `carrera` antes de ser «Texto»; un valor guardado
  /// con ese nombre se sigue leyendo como el mismo perfil (si no, una sesion
  /// vieja arrancaria en «Apagado» sin explicacion).
  static StackProfile fromName(String? name) {
    if (name == 'carrera') return texto;
    return values.firstWhere(
      (profile) => profile.name == name,
      orElse: () => apagado,
    );
  }
}

/// El [StackProfile] que corresponde al nombre de perfil de «Configura tus
/// perfiles» (`A`/`B`/`C`). Es el inverso de [StackProfile.profileName].
StackProfile stackProfileFor(String profile) => switch (profile.toUpperCase()) {
  'B' => StackProfile.contextoLargo,
  'C' => StackProfile.texto,
  _ => StackProfile.rapido,
};

/// El codigo **PowerShell** que arranca o para el perfil, listo para el runner
/// de comandos capturados (que le agrega `-NoProfile -NonInteractive
/// -ExecutionPolicy Bypass -File`).
///
/// Pura y testeada: es la unica definicion de que se ejecuta al tocar el
/// switch. `serve-profile.sh` ya hace `stop-models` antes de arrancar, asi que
/// cambiar de perfil es un solo `Start-Stack.ps1 -Profile X`.
String stackCommandFor(StackProfile profile, String scriptsDir) {
  final dir = scriptsDir.trim().replaceAll(RegExp(r'[\\/]+$'), '');
  final start = "$dir\\Start-Stack.ps1";
  final stop = "$dir\\Stop-Stack.ps1";
  return switch (profile) {
    StackProfile.rapido => "& '$start' -Profile A",
    StackProfile.contextoLargo => "& '$start' -Profile B",
    StackProfile.texto => "& '$start' -Profile C",
    // Apagado libera tambien la RAM de WSL2 (regla de uso del doc 11).
    StackProfile.apagado => "& '$stop' -ReleaseWsl",
  };
}

/// El codigo **PowerShell** que descarga UN modelo del stack, por el mismo
/// runner de comandos capturados.
///
/// `Download-Model.ps1` resuelve la ruta en WSL2 y ejecuta
/// `download-models.sh <rol>`, que lee `models.json`. Pura y testeada: es la
/// unica definicion de lo que se ejecuta al pulsar «Descargar» en el selector de
/// modelos.
String stackDownloadCommandFor(String role, String scriptsDir) {
  final dir = scriptsDir.trim().replaceAll(RegExp(r'[\\/]+$'), '');
  return "& '$dir\\Download-Model.ps1' -Role $role";
}

/// Velocidad de descarga en MB/s entre dos medidas del tamano de `~/models/<dir>`.
///
/// Pura y testeada. Devuelve `null` si no se puede afirmar nada —ventana de
/// tiempo nula o negativa, o el directorio encogio— en vez de dibujar un numero
/// inventado: `du` es una lectura espaciada y un pico aislado no es una tasa.
/// Es MB binario (1024²), el mismo criterio que el «GB» del tile.
double? downloadRateMbps({
  required int previousBytes,
  required int bytes,
  required Duration elapsed,
}) {
  final seconds = elapsed.inMilliseconds / 1000.0;
  if (seconds <= 0) return null;
  final delta = bytes - previousBytes;
  if (delta < 0) return null;
  return delta / seconds / (1024 * 1024);
}
