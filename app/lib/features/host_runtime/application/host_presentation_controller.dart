import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../../compact_overlay/application/window_mode_controller.dart';
import '../../pairing/presentation/pairing_sheet.dart';
import '../../pairing/presentation/widgets/host_pin_card.dart';
import '../../run_center/application/run_center_controller.dart';

/// Como se esta presentando NexoDeck en la PC.
enum HostPresentation {
  /// La ventana normal (pantalla completa o compacta, segun `windowModeProvider`).
  window,

  /// Sin ventana ni render: solo el host, para el telefono. La interfaz entera
  /// se desmonta (ver `MyApp.build`), que es lo que ahorra CPU y GPU.
  phoneOnly,

  /// Estando en [phoneOnly], un telefono pidio emparejarse: una ventana chica,
  /// siempre encima, con solo el PIN. Al terminar se vuelve a [phoneOnly].
  pairingPopup,
}

/// Presentacion actual. **No se persiste a proposito**: la app siempre
/// arranca con interfaz (tambien al iniciar Windows); el modo solo telefono se
/// elige a mano en cada sesion.
final hostPresentationProvider = StateProvider<HostPresentation>(
  (ref) => HostPresentation.window,
);

final hostPresentationControllerProvider = Provider<HostPresentationController>(
  HostPresentationController.new,
);

/// Navigator de la ventana normal. Hace falta para abrir la hoja de emparejar
/// desde fuera del arbol (la bandeja, o un pedido del telefono), donde no hay
/// `BuildContext`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Tamano de la ventana emergente de emparejamiento. Alcanza para el PIN y la
/// tarjeta de la solicitud entrante sin scrollear.
const _kPairingPopupSize = Size(440, 600);

/// Tras cerrar la emergente sin emparejar, cuanto se ignoran los pedidos
/// nuevos. Sin esto, un dispositivo que reintenta en bucle volveria a abrirle
/// la ventana al usuario apenas la cierra.
const _kPairingRequestSnooze = Duration(seconds: 30);

/// Entra y sale del modo solo telefono, y abre el emparejamiento.
///
/// Las operaciones van **en fila**: cada una espera a que termine la anterior.
/// Ocultar y mostrar son varias llamadas asincronas a `window_manager`, y dos
/// clics seguidos en la bandeja intercalarian sus pasos -- el sintoma seria
/// una ventana visible con la interfaz desmontada (un rectangulo vacio), o
/// oculta con la interfaz renderizando para nadie.
class HostPresentationController {
  HostPresentationController(this._ref);

  final Ref _ref;

  Future<void> _queue = Future.value();

  DateTime? _pairingPopupDismissedAt;

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    // Un fallo no puede trabar la fila para siempre: el siguiente clic tiene
    // que poder volver a intentar.
    _queue = next.catchError((Object _) {});
    return next;
  }

  HostPresentation get _current => _ref.read(hostPresentationProvider);

  set _current(HostPresentation value) =>
      _ref.read(hostPresentationProvider.notifier).state = value;

  /// Oculta la ventana y desmonta la interfaz. El host sigue entero: vive en
  /// `HostRuntime`, fuera del arbol de widgets.
  Future<void> enterPhoneOnly() => _enqueue(() async {
    if (!isDesktopWindowPlatform) return;
    switch (_current) {
      case HostPresentation.phoneOnly:
        return;
      case HostPresentation.pairingPopup:
        // La emergente ya es "sin interfaz" con un PIN encima: cerrarla es
        // volver al modo, y su geometria NO se guarda como la de la ventana.
        await _closePairingPopup(paired: false);
        return;
      case HostPresentation.window:
        break;
    }

    // Antes de ocultar: con la interfaz desmontada no hay `WindowListener`
    // que guarde nada, y la posicion tiene que estar al dia para volver.
    await _ref.read(windowModeControllerProvider).persistCurrentBounds();

    // **Primero se oculta y despues se desmonta.** Al reves, la ventana
    // alcanzaria a pintar un frame vacio antes de desaparecer.
    //
    // `hide()` y no `setSkipTaskbar`: `SW_HIDE` ya saca la ventana de la
    // barra de tareas y de Alt+Tab, y mezclar las dos cosas puede dejar el
    // boton de la barra sin volver al mostrarla.
    await windowManager.hide();
    _current = HostPresentation.phoneOnly;
  });

  /// Vuelve a la ventana normal, al frente.
  Future<void> showWindow() => _enqueue(() async {
    if (!isDesktopWindowPlatform) return;

    final previous = _current;
    if (previous != HostPresentation.window) {
      // Lo que termino bien mientras no habia interfaz ya no es noticia: sin
      // esto, al volver aparecerian de golpe todos los toasts acumulados. Los
      // fallos se quedan, que son justo lo que hay que poder leer.
      _ref.read(runCenterProvider.notifier).dismissFinishedSuccesses();

      // Desde la emergente, se oculta antes de redimensionar: si no, se ve a
      // la ventana chica estirarse hasta el tamano del deck.
      if (previous == HostPresentation.pairingPopup) {
        await windowManager.hide();
      }

      _current = HostPresentation.window;
      // La emergente cambia tamano, posicion y always-on-top; volver a
      // aplicar la geometria del modo activo lo deshace.
      await _ref
          .read(windowModeControllerProvider)
          .applyGeometry(_ref.read(windowModeProvider));
      await _awaitFreshFrame();
    }

    await windowManager.show();
    await windowManager.focus();
  });

  Future<void> toggle() => _current == HostPresentation.window
      ? enterPhoneOnly()
      : showWindow();

  /// Muestra el PIN para emparejar un telefono, venga de donde venga el pedido
  /// (la bandeja o el propio telefono).
  ///
  /// Con la ventana a la vista abre la hoja de siempre; sin interfaz, la
  /// ventana emergente. **Nunca arma el PIN por su cuenta**: lo arma la
  /// `HostPinCard` que se muestra, y si ya hay una no se abre otra (volver a
  /// armar reemplazaria el PIN que el telefono esta comparando).
  Future<void> openPairing() => _enqueue(() async {
    if (!isDesktopWindowPlatform) return;
    if (isHostPinCardMounted) {
      await windowManager.show();
      await windowManager.focus();
      return;
    }

    switch (_current) {
      case HostPresentation.window:
        await windowManager.show();
        await windowManager.focus();
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          unawaited(showPairingSheet(context));
        }
      case HostPresentation.phoneOnly:
      case HostPresentation.pairingPopup:
        _current = HostPresentation.pairingPopup;
        await windowManager.setResizable(false);
        await windowManager.setAlwaysOnTop(true);
        // Sin barra de titulo: su X pasaria por `onWindowClose`, que en la
        // ventana normal es salir de la app. La unica salida es el boton de
        // cerrar de la tarjeta, que antes de irse le contesta al telefono.
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.setSize(_kPairingPopupSize);
        await windowManager.center();
        await _awaitFreshFrame();
        await windowManager.show();
        await windowManager.focus();
    }
  });

  /// Lo que dispara un telefono pidiendo emparejarse sin el PIN armado (ver
  /// `HostRuntime`). Igual que [openPairing], pero respeta el descanso tras
  /// una emergente que el usuario cerro sin emparejar.
  Future<void> openPairingOnRequest() {
    final dismissedAt = _pairingPopupDismissedAt;
    if (dismissedAt != null &&
        DateTime.now().difference(dismissedAt) < _kPairingRequestSnooze) {
      return Future.value();
    }
    return openPairing();
  }

  /// La emergente termino (la llama `PairingPopupView` al cerrarse la tarjeta).
  Future<void> endPairingPopup({required bool paired}) =>
      _enqueue(() => _closePairingPopup(paired: paired));

  Future<void> _closePairingPopup({required bool paired}) async {
    if (_current != HostPresentation.pairingPopup) return;
    await windowManager.hide();
    _current = HostPresentation.phoneOnly;
    _pairingPopupDismissedAt = paired ? null : DateTime.now();
  }

  /// Espera a que la interfaz recien montada pinte un frame **antes** de
  /// mostrar la ventana: si no, lo primero que se ve es la superficie vieja
  /// (el ultimo frame de antes de ocultarla) o un rectangulo vacio.
  ///
  /// `scheduleForcedFrame` y no `scheduleFrame`: con la ventana oculta el
  /// ciclo de vida puede estar en `hidden`, y ahi un `scheduleFrame` normal se
  /// ignora y `endOfFrame` no terminaria nunca. El tope de tiempo es la red
  /// por si el engine no rasteriza con la ventana oculta: mejor mostrar un
  /// frame tarde que no mostrar la ventana.
  Future<void> _awaitFreshFrame() async {
    final binding = SchedulerBinding.instance;
    binding.scheduleForcedFrame();
    try {
      await binding.endOfFrame.timeout(const Duration(milliseconds: 300));
    } on TimeoutException {
      // Ver arriba: se muestra igual.
    }
  }
}
