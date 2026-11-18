import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../ai_assistant/application/ai_enabled_controller.dart';
import '../../ai_assistant/application/ai_providers.dart';
import '../../control/application/control_settings_controller.dart';
import '../../docs_inbox/application/docs_inbox_controller.dart';
import '../../docs_inbox/presentation/docs_inbox_dialog.dart';
import '../../pairing/application/connection_provider.dart';
import '../../pairing/application/relay_provider.dart';
import 'host_presentation_controller.dart';
import 'shutdown_controller.dart';

/// Texto del tooltip del icono de la bandeja. Separado para poder probarlo.
@visibleForTesting
String trayToolTipFor(int connectedDevices) => switch (connectedDevices) {
  0 => 'NexoDeck — ningún teléfono conectado',
  1 => 'NexoDeck — 1 teléfono conectado',
  _ => 'NexoDeck — $connectedDevices teléfonos conectados',
};

const _kOpenKey = 'open';
const _kPhoneOnlyKey = 'phone_only';
const _kPairKey = 'pair';
const _kDocsKey = 'docs_inbox';
const _kQuitKey = 'quit';

/// Icono de la bandeja del sistema y todo lo que cuelga de el: el menu, la
/// salida ordenada y el aviso de una segunda instancia.
///
/// **Solo Windows.** En Linux `tray_manager` necesita appindicator, que no
/// esta garantizado, y sin bandeja no habria forma de volver del modo solo
/// telefono. Por eso tambien el item del menu "Mas" se ofrece solo en Windows.
///
/// Vive fuera del arbol de widgets por el mismo motivo que `HostRuntime`: en
/// modo solo telefono no hay ningun widget montado.
class TrayController with TrayListener, WindowListener {
  TrayController(this._container);

  final ProviderContainer _container;

  /// Lo abre el runner (`flutter_window.cpp`) cuando una segunda instancia
  /// pide mostrar la ventana -- ver `single_instance.h`.
  static const _instanceChannel = MethodChannel('nexodeck/instance');

  final List<ProviderSubscription<Object?>> _listeners = [];

  bool _shuttingDown = false;

  Future<void> start() async {
    trayManager.addListener(this);
    windowManager.addListener(this);

    // La X tiene que pasar por `shutdown()`: sin `trayManager.destroy()` el
    // icono queda "fantasma" en la bandeja hasta que el usuario le pasa el
    // mouse por encima. Cerrar sigue siendo salir, como siempre.
    await windowManager.setPreventClose(true);

    _instanceChannel.setMethodCallHandler((call) async {
      if (call.method == 'activate') {
        await _presentation.showWindow();
      }
    });

    // Ruta relativa a `data/flutter_assets`, que es donde la resuelve el
    // plugin en Windows.
    await trayManager.setIcon('assets/tray/tray_icon.ico');
    await _refresh();

    // Los dos son estado (no eventos), asi que `listen` es correcto: solo
    // importa el ultimo valor para dibujar el menu.
    _listeners
      ..add(
        _container.listen<HostPresentation>(
          hostPresentationProvider,
          (_, _) => unawaited(_refresh()),
        ),
      )
      ..add(
        _container.listen<Set<String>>(
          connectedDeviceIdsProvider,
          (_, _) => unawaited(_refresh()),
        ),
      )
      // Solo cuando cambia el numero: la foto del buzon se renueva con cada
      // aviso de Rust, y rehacer el menu nativo por cada una no aporta nada.
      ..add(
        _container.listen<DocsInboxState>(docsInboxProvider, (previous, next) {
          if (previous?.pendingCount != next.pendingCount) {
            unawaited(_refresh());
          }
        }),
      );
  }

  HostPresentationController get _presentation =>
      _container.read(hostPresentationControllerProvider);

  Future<void> _refresh() async {
    if (_shuttingDown) return;
    final presentation = _container.read(hostPresentationProvider);
    final devices = _container.read(connectedDeviceIdsProvider).length;
    // Con la ventana oculta, la bandeja es la unica senal de que hay
    // propuestas esperando: sin esto podrian quedarse dias sin que nadie las
    // mire.
    final proposals = _container.read(docsInboxProvider).pendingCount;

    await trayManager.setToolTip(
      proposals == 0
          ? trayToolTipFor(devices)
          : '${trayToolTipFor(devices)} · $proposals propuestas de documentación',
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _kOpenKey, label: 'Abrir NexoDeck'),
          MenuItem(
            key: _kDocsKey,
            label: proposals == 0
                ? 'Buzón de documentación…'
                : 'Buzón de documentación ($proposals)…',
          ),
          MenuItem.checkbox(
            key: _kPhoneOnlyKey,
            label: 'Modo solo teléfono',
            checked: presentation != HostPresentation.window,
          ),
          MenuItem.separator(),
          MenuItem(key: _kPairKey, label: 'Emparejar teléfono…'),
          MenuItem.separator(),
          MenuItem(key: _kQuitKey, label: 'Salir'),
        ],
      ),
    );
  }

  /// Muestra la ventana y abre el buzon encima. Desde el modo solo telefono
  /// `showWindow` vuelve a montar la app antes de mostrarla, asi que el
  /// Navigator ya existe cuando se busca.
  Future<void> _openDocsInbox() async {
    await _presentation.showWindow();
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      unawaited(showDocsInboxDialog(context));
    }
  }

  /// Sale de verdad: apaga lo pesado con feedback y despues cierra la ventana.
  ///
  /// El orden importa y el feedback tambien: `shuttingDownProvider` se enciende
  /// ANTES de cualquier `await`, asi el overlay aparece en el siguiente frame y
  /// el cierre no se siente colgado. Cada paso tiene un tope para que un
  /// `llama-server` que tarde en soltar la VRAM no impida salir.
  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;

    _container.read(shuttingDownProvider.notifier).state = true;
    _container.read(shutdownStepProvider.notifier).state = 'Cerrando…';

    if (_container.read(aiEnabledProvider)) {
      await _shutdownStep(
        'Deteniendo el asistente…',
        () => _container.read(aiRepositoryProvider).stop(),
      );
    }
    if (_container.read(controlServerEnabledProvider)) {
      await _shutdownStep(
        'Cerrando el servidor de control…',
        () => _container.read(controlRepositoryProvider).stop(),
      );
    }
    if (_container.read(relayTunnelEnabledProvider)) {
      await _shutdownStep(
        'Deteniendo el túnel…',
        () => _container.read(relayRepositoryProvider).stopTunnel(),
      );
    }

    for (final listener in _listeners) {
      listener.close();
    }
    try {
      await trayManager.destroy();
    } catch (error) {
      // Que falle sacar el icono no puede impedir salir.
      debugPrint('NexoDeck: no se pudo quitar el icono de la bandeja: $error');
    }
    await windowManager.destroy();
  }

  /// Corre un paso del apagado, enseñando su etiqueta, con un tope para que
  /// ningun paso pueda colgar la salida.
  Future<void> _shutdownStep(String label, Future<void> Function() action) async {
    _container.read(shutdownStepProvider.notifier).state = label;
    try {
      await action().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('NexoDeck: $label -> $error');
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_presentation.showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    // `bringAppToFront` no es cosmetico: sin `SetForegroundWindow` Windows no
    // cierra el menu de la bandeja al hacer clic afuera, y queda flotando.
    // ignore: deprecated_member_use
    unawaited(trayManager.popUpContextMenu(bringAppToFront: true));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kOpenKey:
        unawaited(_presentation.showWindow());
      case _kPhoneOnlyKey:
        unawaited(_presentation.toggle());
      case _kPairKey:
        unawaited(_presentation.openPairing());
      case _kDocsKey:
        unawaited(_openDocsInbox());
      case _kQuitKey:
        unawaited(shutdown());
    }
  }

  @override
  void onWindowClose() {
    // La emergente de emparejamiento no tiene barra de titulo, pero Alt+F4
    // igual llega aca: ahi cerrar es volver al modo sin interfaz, no salir.
    if (_container.read(hostPresentationProvider) ==
        HostPresentation.pairingPopup) {
      unawaited(_presentation.endPairingPopup(paired: false));
      return;
    }
    unawaited(shutdown());
  }
}
