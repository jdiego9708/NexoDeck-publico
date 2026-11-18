import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nexodeck/data/local/daos/app_settings_dao.dart';
import 'package:nexodeck/data/local/daos/window_layouts_dao.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/di/database_provider.dart';
import '../data/window_layout_repository.dart';

/// `window_manager` solo tiene implementacion nativa en Windows/Linux/macOS
/// -- este proyecto solo apunta a Windows y Linux en desktop (Android usa
/// su propio mecanismo de overlay, fuera de alcance de esta feature).
bool get isDesktopWindowPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

const _kCompactSize = Size(320, 460);
const _kFullscreenSize = Size(1100, 750);
const _kCompactMargin = 24.0;

/// Cuanto de la ventana tiene que quedar dentro de una pantalla real para
/// considerar que la posicion guardada sigue sirviendo. Se pide un area y no
/// una interseccion cualquiera a proposito: una ventana asomando 3 px es tan
/// inservible como una totalmente fuera de pantalla.
const _kMinVisibleOverlap = Size(160, 80);

/// `true` si el rectangulo guardado cae, al menos parcialmente, dentro de
/// alguna pantalla conectada AHORA.
///
/// Existe por un bug real: `window_layouts` persiste la posicion por modo, y
/// al restaurarla nadie comprobaba que ese monitor siguiera existiendo. Con
/// una fila guardada en `pos_x: 2033` desde un monitor secundario ya
/// desconectado, la ventana se abria **entera fuera del area visible**: la
/// app arrancaba bien, sin ningun error, y era imposible verla ni traerla al
/// frente. Sintoma mudo, y muy confuso de diagnosticar.
///
/// Ante cualquier fallo devuelve `true`: sin informacion de pantallas es
/// preferible respetar lo guardado antes que recentrar la ventana del
/// usuario en cada arranque.
Future<bool> isWindowRectUsable(Offset position, Size size) async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) return true;
    final windowRect = position & size;
    for (final display in displays) {
      final displayRect =
          (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size);
      final overlap = windowRect.intersect(displayRect);
      // `Rect.intersect` no normaliza: sin solape devuelve lados negativos,
      // asi que comparar contra el minimo ya cubre el caso "no se tocan".
      if (overlap.width >= _kMinVisibleOverlap.width &&
          overlap.height >= _kMinVisibleOverlap.height) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return true;
  }
}

final windowLayoutRepositoryProvider = Provider<WindowLayoutRepository>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return WindowLayoutRepository(WindowLayoutsDao(db), AppSettingsDao(db));
});

/// Modo actual de la ventana. El valor inicial real se decide en `main()`
/// (antes de `runApp`, leyendo la ultima preferencia guardada) y se inyecta
/// vía `overrideWith` en el `ProviderScope` -- el default de aqui solo
/// aplica en tests o si por algun motivo no se pudo leer la preferencia.
final windowModeProvider = StateProvider<WindowMode>(
  (ref) => WindowMode.fullscreen,
);

/// Tamano que le corresponde a [mode].
///
/// El modo compacto **ignora deliberadamente lo que haya guardado** en
/// `window_layouts`: es una ventana no redimensionable
/// (`setResizable(false)`), asi que su tamano es una constante y no un dato
/// del usuario. Persistirlo no aportaba nada y si abria un agujero: la fila
/// `compact` de una instalacion real termino con `1100x720` -- el tamano de
/// pantalla completa -- y el modo compacto abria con la ventana entera. Ver
/// el cerrojo `_switching` en [WindowModeController.switchTo] para el como.
///
/// De pantalla completa si se restaura el tamano: ahi el usuario la
/// redimensiona a mano y esperar que se recuerde es lo razonable.
Size windowSizeFor(WindowMode mode, PersistedWindowLayout? layout) {
  if (mode == WindowMode.compact) return _kCompactSize;
  return layout != null
      ? Size(layout.width, layout.height)
      : _kFullscreenSize;
}

final windowModeControllerProvider = Provider<WindowModeController>((ref) {
  return WindowModeController(ref, ref.watch(windowLayoutRepositoryProvider));
});

class WindowModeController {
  WindowModeController(this._ref, this._repository);

  final Ref _ref;
  final WindowLayoutRepository _repository;

  /// Mientras dura un cambio de modo, [persistCurrentBounds] no escribe.
  /// Ver el comentario largo en [switchTo].
  bool _switching = false;

  Future<void> toggle() {
    final current = _ref.read(windowModeProvider);
    final next = current == WindowMode.compact
        ? WindowMode.fullscreen
        : WindowMode.compact;
    return switchTo(next);
  }

  Future<void> switchTo(WindowMode mode) async {
    if (!isDesktopWindowPlatform) return;
    if (_ref.read(windowModeProvider) == mode) return;

    await persistCurrentBounds();
    await applyGeometry(mode);

    _ref.read(windowModeProvider.notifier).state = mode;
    await _repository.setLastActiveMode(mode);
    // Ya con el modo nuevo en el provider: deja la fila correcta al dia sin
    // depender de que llegue (o no) un evento tardio del listener.
    await persistCurrentBounds();
  }

  /// Aplica a la ventana el tamano, la decoracion y la posicion de [mode], sin
  /// tocar el modo activo ni persistir nada.
  ///
  /// Separada de [switchTo] porque volver del modo solo telefono (y sobre todo
  /// de la ventana emergente de emparejamiento, que cambia tamano y
  /// always-on-top) tiene que restaurar la geometria del modo que YA esta
  /// activo, y [switchTo] no hace nada cuando el modo no cambia.
  Future<void> applyGeometry(WindowMode mode) async {
    if (!isDesktopWindowPlatform) return;

    // Todo lo que sigue redimensiona y mueve la ventana, y **cada uno de
    // esos pasos dispara `onWindowResized`/`onWindowMoved`** en
    // `WindowListenerWrapper`, que llama a `persistCurrentBounds()`. Sin
    // este cerrojo esos eventos escriben con el modo VIEJO todavia en el
    // provider (recien se actualiza al final), o sea que guardan la
    // geometria del modo nuevo en la fila del modo viejo.
    //
    // No es teorico: asi fue como la fila `compact` de una instalacion real
    // termino con `1100x720`, el tamano de pantalla completa. El sintoma que
    // ve el usuario es que el modo compacto abre del tamano equivocado
    // "despues de mover la ventana", porque mover es lo que dispara el
    // guardado.
    _switching = true;
    try {
      final layout = await _repository.getLayout(mode);
      final size = windowSizeFor(mode, layout);

      // `setResizable` va ANTES de `setTitleBarStyle` a proposito: el plugin
      // cambia el estilo con `SetWindowLong` y no llama a
      // `SetWindowPos(SWP_FRAMECHANGED)`, asi que Windows recien recalcula
      // el marco en la siguiente operacion de tamano. Yendo primero, lo
      // flushea el `SWP_FRAMECHANGED` que si hace `setTitleBarStyle`, en vez
      // de quedar pendiente hasta el primer arrastre del usuario.
      await windowManager.setResizable(mode != WindowMode.compact);
      await windowManager.setAlwaysOnTop(mode == WindowMode.compact);
      await windowManager.setTitleBarStyle(
        mode == WindowMode.compact
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
        windowButtonVisibility: mode != WindowMode.compact,
      );
      await windowManager.setSize(size);

      // La posicion guardada puede apuntar a un monitor que ya no esta -- ver
      // `isWindowRectUsable`. Si no sirve, se cae al comportamiento de "sin
      // layout guardado" en vez de dejar la ventana fuera de pantalla.
      if (layout != null &&
          await isWindowRectUsable(Offset(layout.posX, layout.posY), size)) {
        await windowManager.setPosition(Offset(layout.posX, layout.posY));
      } else if (mode == WindowMode.compact) {
        await _positionCompactAtDefaultCorner(size);
      } else {
        await windowManager.center();
      }
    } finally {
      _switching = false;
    }
  }

  /// Guarda posicion/tamano actuales bajo el modo activo -- se llama antes
  /// de cambiar de modo, y desde el `WindowListener` cuando el usuario
  /// termina de mover/redimensionar la ventana a mano.
  Future<void> persistCurrentBounds() async {
    if (!isDesktopWindowPlatform) return;
    // Ver el comentario en `switchTo`: durante la transicion la ventana pasa
    // por estados intermedios que no le corresponden a ningun modo.
    if (_switching) return;
    final mode = _ref.read(windowModeProvider);
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();

    String? monitorId;
    try {
      monitorId = (await screenRetriever.getPrimaryDisplay()).id;
    } catch (_) {
      // best-effort: si screen_retriever falla, guardamos sin monitorId.
    }

    await _repository.saveLayout(
      mode,
      posX: position.dx,
      posY: position.dy,
      width: size.width,
      height: size.height,
      monitorId: monitorId,
      alwaysOnTop: mode == WindowMode.compact,
    );
  }

  Future<void> _positionCompactAtDefaultCorner(Size windowSize) async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final screenSize = display.size;
      await windowManager.setPosition(
        Offset(
          screenSize.width - windowSize.width - _kCompactMargin,
          screenSize.height - windowSize.height - _kCompactMargin,
        ),
      );
    } catch (_) {
      // Sin info de pantalla disponible -- se deja donde el SO la abra.
    }
  }
}
