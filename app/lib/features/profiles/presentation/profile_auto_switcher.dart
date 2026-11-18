import 'package:flutter_riverpod/legacy.dart';

/// Ultima aplicacion en primer plano **que no era NexoDeck**.
///
/// Existe para que el editor de perfiles pueda ofrecer "usar esta app" con
/// algo util: mientras el dialogo esta abierto, la app en foco es NexoDeck,
/// asi que preguntar por el foco actual siempre devolveria `nexodeck.exe`.
///
/// Se distingue por **pid propio** (`dart:io`) y no comparando el nombre
/// del ejecutable: el nombre cambia entre debug/release y por plataforma,
/// el pid no puede equivocarse.
final lastExternalAppProvider = StateProvider<String?>((ref) => null);

// El auto-cambio de perfil que antes vivia aca como widget envoltorio
// (`ProfileAutoSwitcher`) paso a `HostRuntime`: tiene que seguir funcionando
// con la ventana oculta, y un widget desmontado no escucha nada.
