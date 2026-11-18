import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';
import 'package:nexodeck/data/local/tables/hub_subscriptions_table.dart';
import 'package:nexodeck/data/local/tables/window_layouts_table.dart';
import 'package:nexodeck/src/rust/api/actions.dart' as bridge_actions;
import 'package:nexodeck/src/rust/api/pairing.dart' as pairing_bridge;
import 'package:nexodeck/src/rust/api/relay.dart' as relay_bridge;
import 'package:nexodeck/src/rust/frb_generated.dart';
import 'package:window_manager/window_manager.dart';

import 'core/di/database_provider.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_brand.dart';
import 'core/widgets/neural_background.dart';
import 'features/actions/presentation/action_editor_sheet.dart';
import 'features/actions/presentation/deck_transfer.dart';
import 'features/actions/application/actions_panel_controller.dart';
import 'features/run_center/presentation/run_panel_dialog.dart';
import 'features/stack/application/stack_controller.dart';
import 'features/ai_assistant/application/chat_conversations_providers.dart';
import 'features/ai_assistant/application/ai_enabled_controller.dart';
import 'features/ai_assistant/application/ollama_control_controller.dart';
import 'features/ai_assistant/presentation/ai_assistant_dialog.dart';
import 'features/ai_assistant/presentation/widgets/ai_assistant_button.dart';
import 'features/compact_overlay/application/window_mode_controller.dart';
import 'features/home/application/home_layout_controller.dart';
import 'features/home/application/panel_split_controller.dart';
import 'features/home/presentation/home_layout_button.dart';
import 'features/home/presentation/home_layout_view.dart';
import 'features/host_runtime/application/host_presentation_controller.dart';
import 'features/host_runtime/application/host_runtime.dart';
import 'features/host_runtime/application/tray_controller.dart';
import 'features/host_runtime/presentation/pairing_popup_view.dart';
import 'features/host_runtime/presentation/shutdown_overlay.dart';
import 'features/compact_overlay/data/window_layout_repository.dart';
import 'features/compact_overlay/presentation/compact_deck_view.dart';
import 'features/compact_overlay/presentation/widgets/window_mode_toggle_button.dart';
import 'features/compact_overlay/presentation/window_listener_wrapper.dart';

import 'features/control/application/control_activity_controller.dart';
import 'features/control/application/control_settings_controller.dart';
import 'features/control/data/control_repository.dart';
import 'features/control/presentation/control_panel_dialog.dart';
import 'features/docs_inbox/application/docs_inbox_controller.dart';
import 'features/docs_inbox/data/docs_inbox_repository.dart';
import 'features/docs_inbox/presentation/docs_inbox_dialog.dart';
import 'features/notes/application/notes_controller.dart';
import 'features/notes/application/notes_sync_engine.dart';
import 'features/notes/presentation/notes_dialog.dart';
import 'features/notes/presentation/vault_dialog.dart';
import 'features/dashboard/application/sensor_helper_controller.dart';
import 'features/dashboard/presentation/sensor_helper_dialog.dart';
import 'features/hub_subscriptions/application/hub_subscriptions_provider.dart';
import 'features/hub_subscriptions/presentation/hub_subscriptions_panel.dart';
import 'features/dashboard/application/metrics_visibility_controller.dart';
import 'features/dashboard/application/monitor_mode_controller.dart';
import 'features/dashboard/presentation/history_screen.dart';
import 'features/pairing/application/pairing_provider.dart';
import 'features/pairing/application/relay_provider.dart';
import 'features/pairing/presentation/android_shell.dart';
import 'features/pairing/presentation/widgets/devices_button.dart';
import 'features/pairing/presentation/widgets/relay_tunnel_dialog.dart';
import 'features/profiles/application/active_profile_controller.dart';
import 'features/profiles/presentation/widgets/profile_selector.dart';
import 'features/run_center/application/run_center_controller.dart';
import 'features/run_center/presentation/run_history_sheet.dart';
import 'features/run_center/presentation/run_toast_host.dart';
import 'features/theme/application/theme_mode_controller.dart';
import 'features/theme/presentation/theme_mode_toggle_button.dart';

/// La ventana de notas pide el buzón: se trae la ventana principal al frente y se
/// abre ahí, que es donde se aprueban las propuestas.
Future<void> _openInboxFromNotes() async {
  if (isDesktopWindowPlatform) {
    await windowManager.show();
    await windowManager.focus();
  }
  final context = rootNavigatorKey.currentContext;
  if (context != null && context.mounted) {
    await showDocsInboxDialog(context);
  }
}

Future<void> main() async {
  // window_manager usa un MethodChannel antes de runApp(), lo que requiere
  // el binding inicializado explicitamente (runApp() normalmente lo hace
  // por nosotros, pero aca lo necesitamos antes).
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  var initialMode = WindowMode.fullscreen;
  String? transportHostError;

  // Se abre la base de datos aca (no via el provider) porque necesitamos
  // leer la ultima preferencia de tema (y, en desktop, el modo/layout de
  // ventana) ANTES de `runApp`, para no mostrar un flash del tema
  // equivocado ni que la ventana "salte" despues del primer frame. La
  // misma instancia se inyecta al ProviderScope mas abajo para no abrir la
  // conexion dos veces.
  final database = NexoDeckDatabase();
  final initialThemeMode = await readInitialThemeMode(database.appSettingsDao);
  final initialMetricsCollapsed = await readInitialMetricsCollapsed(
    database.appSettingsDao,
  );
  // El panel de acciones del centro de control: mismo motivo que las metricas,
  // el primer frame ya tiene que mostrar si estaba plegado.
  final initialActionsPanelCollapsed = await readInitialActionsPanelCollapsed(
    database.appSettingsDao,
  );
  // El panel de conversaciones del chat: mismo motivo que el de acciones.
  final initialConversationsPanelCollapsed =
      await readInitialConversationsPanelCollapsed(database.appSettingsDao);
  // El switch del stack: carpeta de los scripts y ultimo perfil elegido.
  final (initialStackDir, initialStackProfile) = await readInitialStackPreferences(
    database.appSettingsDao,
  );
  final initialStackDistro = await readInitialStackDistro(
    database.appSettingsDao,
  );
  // Modo monitor del telefono (deck escondido, metricas a pantalla completa).
  // Mismo motivo que el resto para leerlo aca: el primer frame ya tiene que
  // mostrar lo que el usuario dejo elegido.
  final initialMonitorMode = await readInitialMonitorMode(
    database.appSettingsDao,
  );
  // Igual que el tema: se lee antes de `runApp` para que el primer frame ya
  // muestre el deck del perfil correcto, en vez de mostrar todas las
  // acciones y filtrar un frame despues.
  final initialActiveProfileId = await readInitialActiveProfileId(
    database.appSettingsDao,
  );
  // Las funciones de IA son opt-in: si nunca se activaron, la clave no
  // existe y esto devuelve `false` (ver `ai_enabled_controller.dart`).
  final initialAiEnabled = await readInitialAiEnabled(database.appSettingsDao);
  final initialControlEnabled = await readInitialControlEnabled(
    database.appSettingsDao,
  );
  final initialNotifyChannels = await readInitialNotifyChannels(
    database.appSettingsDao,
  );
  var initialControlStatus = ControlServerStatus.stopped;
  // El tunel por relay tambien es opt-in (ver `relay_provider.dart`): si
  // nunca se prendio, `initialRelayTunnelEnabled` es `false` y no se llama
  // a `startRelayTunnel` mas abajo.
  final (initialRelayTunnelEnabled, initialRelayTunnelConfig) =
      await readInitialRelayTunnelConfig(database.appSettingsDao);
  final initialHomeLayout = await readInitialHomeLayout(
    database.appSettingsDao,
  );
  // Lo que el usuario dejo arrastrado en cada divisor. Se lee aca por el mismo
  // motivo que el resto: sin esto el primer frame dibuja el reparto por
  // defecto y los paneles saltan a su tamano guardado un frame despues.
  final initialPanelSplits = await readInitialPanelSplits(
    database.appSettingsDao,
  );

  if (isDesktopWindowPlatform) {
    // Antes que nada: a partir de aca Rust anota que ventana tiene el foco,
    // que es lo unico que despues permite devolverselo. No sirve arrancarlo
    // cuando se ejecuta la accion -- para entonces el foco ya es de NexoDeck
    // y la ventana anterior es indeducible. Ver `focus.rs`.
    bridge_actions.startFocusTracking();

    await windowManager.ensureInitialized();

    final repository = WindowLayoutRepository(
      database.windowLayoutsDao,
      database.appSettingsDao,
    );
    initialMode = await repository.getLastActiveMode();
    final layout = await repository.getLayout(initialMode);

    // Misma regla que al cambiar de modo en caliente: el compacto NO
    // restaura tamano (no es redimensionable), pantalla completa si. Sin
    // esto, una fila `compact` corrupta hace que la app arranque con la
    // ventana entera en modo compacto -- ver `windowSizeFor`.
    final size = windowSizeFor(initialMode, layout);
    // La posicion guardada puede apuntar a un monitor que ya no esta
    // conectado -- ver `isWindowRectUsable`. Se comprueba ANTES de
    // restaurarla: si no, la app arranca invisible, fuera del area visible,
    // sin ningun error y sin forma de traerla al frente.
    final restorePosition =
        layout != null &&
        await isWindowRectUsable(Offset(layout.posX, layout.posY), size);

    final options = WindowOptions(
      size: size,
      alwaysOnTop: initialMode == WindowMode.compact,
      titleBarStyle: initialMode == WindowMode.compact
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: initialMode != WindowMode.compact,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setResizable(initialMode != WindowMode.compact);
      if (restorePosition) {
        await windowManager.setPosition(Offset(layout.posX, layout.posY));
      } else {
        await windowManager.center();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    // Rol PC: arranca el servidor WebSocket+TLS y el anuncio mDNS antes de
    // `runApp` para que este listo apenas se muestre el primer frame. Si
    // falla (ej. puerto ocupado), la app sigue funcionando localmente --
    // el pairing simplemente no va a estar disponible.
    try {
      await pairing_bridge.startTransportHost(
        deviceName: Platform.localHostname,
      );
    } catch (e) {
      // No es fatal (la app sigue sirviendo localmente), pero tampoco puede
      // quedar mudo: se propaga a la UI via `transportHostErrorProvider`
      // para que la pantalla de dispositivos diga por que no se puede
      // emparejar en vez de limitarse a no funcionar.
      transportHostError = e.toString();
    }

    // El tunel necesita el host de transporte ya arriba (`start_relay_tunnel`
    // lo exige), asi que va DESPUES del bloque de arriba y solo si ese
    // arranco bien -- sin transporte, prender el tunel no tendria a que
    // sesion ofrecerselo al conectar un telefono.
    if (transportHostError == null && initialRelayTunnelEnabled) {
      try {
        await relay_bridge.startRelayTunnel(
          host: initialRelayTunnelConfig.host,
          port: initialRelayTunnelConfig.port,
          tokenHex: initialRelayTunnelConfig.tokenHex,
        );
      } catch (_) {
        // No fatal: el usuario puede reintentar desde el dialogo del
        // tunel, que muestra `RelayStatus` en vivo.
      }
    }

    // El servidor de control, si el usuario lo dejo encendido. Va antes de
    // `runApp` para que Claude Code pueda hablarle desde el primer momento,
    // sin depender de que alguien abra su panel.
    //
    // Un fallo aca **no** es fatal y **no** puede quedar mudo: se lleva a la
    // UI por `controlServerStatusProvider`, igual que el del host de
    // transporte. El caso frecuente es el puerto ocupado por otra instancia.
    if (initialControlEnabled) {
      const repository = ControlRepository();
      try {
        final port = await repository.start(
          port: await repository.defaultPort,
          channels: initialNotifyChannels,
        );
        initialControlStatus = ControlServerStatus(port: port);
      } catch (e) {
        initialControlStatus = ControlServerStatus(error: e.toString());
      }
    }
  }

  // El buzon de documentacion vive aunque el servidor de control este apagado:
  // los hallazgos ya guardados se siguen procesando. Se abre antes de leer su
  // provider porque el stream de avisos termina en el acto si el buzon todavia
  // no existe. Un fallo no es fatal y no queda mudo: el dialogo del buzon lo
  // muestra al pedir la foto.
  var docsInboxReady = false;
  if (isDesktopWindowPlatform) {
    try {
      await const DocsInboxRepository().init(aiEnabled: initialAiEnabled);
      docsInboxReady = true;
    } catch (error) {
      debugPrint('NexoDeck: no se pudo abrir el buzon de documentacion: $error');
    }
  }

  // El container se crea aca y no dentro de un `ProviderScope` porque la
  // logica de host (`HostRuntime`) tiene que vivir FUERA del arbol de
  // widgets: con la ventana en modo compacto, o sin interfaz, el arbol que la
  // sostenia no esta montado. La UI usa el mismo container via
  // `UncontrolledProviderScope`, asi que los dos ven el mismo estado.
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      notesInboxOpenerProvider.overrideWithValue(_openInboxFromNotes),
      windowModeProvider.overrideWith((ref) => initialMode),
      themeModeProvider.overrideWith((ref) => initialThemeMode),
      metricsCollapsedProvider.overrideWith((ref) => initialMetricsCollapsed),
      actionsPanelCollapsedProvider.overrideWith(
        (ref) => initialActionsPanelCollapsed,
      ),
      conversationsPanelCollapsedProvider.overrideWith(
        (ref) => initialConversationsPanelCollapsed,
      ),
      stackScriptsDirProvider.overrideWith((ref) => initialStackDir),
      selectedStackProfileProvider.overrideWith((ref) => initialStackProfile),
      stackDistroProvider.overrideWith((ref) => initialStackDistro),
      monitorModeProvider.overrideWith((ref) => initialMonitorMode),
      activeProfileIdProvider.overrideWith((ref) => initialActiveProfileId),
      aiEnabledProvider.overrideWith((ref) => initialAiEnabled),
      controlServerEnabledProvider.overrideWith((ref) => initialControlEnabled),
      notifyChannelsProvider.overrideWith((ref) => initialNotifyChannels),
      controlServerStatusProvider.overrideWith((ref) => initialControlStatus),
      homeLayoutProvider.overrideWith((ref) => initialHomeLayout),
      panelSplitsProvider.overrideWith((ref) => initialPanelSplits),
      transportHostErrorProvider.overrideWith((ref) => transportHostError),
      relayTunnelEnabledProvider.overrideWith(
        (ref) => initialRelayTunnelEnabled,
      ),
      relayTunnelConfigProvider.overrideWith((ref) => initialRelayTunnelConfig),
    ],
  );

  // Los dos escuchan un `broadcast` de Rust, y lo que se emite sin receptores
  // se pierde. Antes los encendian `ControlActivityHost` y `RunToastHost` al
  // montarse; ahora se leen una vez desde el arranque, sin depender de que
  // haya interfaz. Ninguno es `autoDispose`, asi que viven lo que el
  // container.
  container
    ..read(controlActivityProvider)
    ..read(runCenterProvider);
  // Mismo motivo: el contador de propuestas de la barra y de la bandeja tiene
  // que estar al dia aunque nadie haya abierto el buzon.
  if (docsInboxReady) container.read(docsInboxProvider);
  // Las notas viven en el mismo servicio: sin buzon no hay boveda.
  if (docsInboxReady) container.read(notesProvider);

  if (isDesktopWindowPlatform) {
    HostRuntime(container).start();
  }

  // Rol Android: la copia local de la boveda se mantiene al dia fuera del arbol
  // de widgets, por lo mismo que `HostRuntime` -- lo que el usuario escribio sin
  // cobertura tiene que salir hacia la PC en cuanto haya sesion, este montada o
  // no la pantalla de notas.
  if (Platform.isAndroid) {
    final notesSync = NotesSyncEngine(container)..start();
    // La pantalla de notas guarda por el mismo motor: uno solo, o dos colas
    // mandarian lo mismo a la PC.
    container.read(notesSyncEngineProvider.notifier).state = notesSync;
  }

  // Bandeja del sistema y salida ordenada, solo en Windows -- ver
  // `TrayController`. Un fallo no es fatal: la app funciona igual, solo que
  // sin el camino para ocultarla y volver.
  if (Platform.isWindows) {
    try {
      await TrayController(container).start();
    } catch (error) {
      debugPrint('NexoDeck: no se pudo crear el icono de la bandeja: $error');
    }
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Modo solo telefono: **nada**, ni siquiera `MaterialApp`. Ocultar la
    // ventana no alcanza para dejar de gastar -- `NeuralBackground` repinta a
    // la tasa de refresco y los charts se reconstruyen cada segundo aunque
    // nadie los vea. Sin widgets no hay tickers ni frames que programar, y se
    // cae tambien la suscripcion de la UI a las metricas. El host sigue entero
    // porque vive en `HostRuntime`, fuera de este arbol.
    final presentation = isDesktopWindowPlatform
        ? ref.watch(hostPresentationProvider)
        : HostPresentation.window;
    if (presentation == HostPresentation.phoneOnly) {
      return const SizedBox.shrink();
    }

    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      // Un `MaterialApp` nuevo por presentacion. Cambiarle solo `home` a un
      // `Navigator` vivo no reemplaza la ruta raiz, y volver de la emergente
      // de emparejamiento a la ventana dejaria el PIN en pantalla. Por lo
      // mismo `rootNavigatorKey` va solo en la ventana: una `GlobalKey`
      // compartida haria que Flutter reusara el Navigator viejo con sus rutas.
      key: ValueKey(presentation),
      navigatorKey: presentation == HostPresentation.window
          ? rootNavigatorKey
          : null,
      title: 'NexoDeck',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        // Las notificaciones de ejecucion cuelgan de la RAIZ, no de un
        // Scaffold: en escritorio hay dos Scaffold disjuntos (pantalla
        // completa y modo compacto) y ninguno esta vivo siempre. Envuelve
        // tambien a Android, que muestra las mismas notificaciones de lo que
        // corre en la PC.
        // La emergente de emparejamiento es solo el PIN: sin fondo animado
        // (seria volver a gastar lo que el modo sin interfaz ahorra) y sin
        // toasts tapando la tarjeta en una ventana tan chica.
        if (presentation == HostPresentation.pairingPopup) return child;
        if (!isDesktopWindowPlatform) return RunToastHost(child: child);
        return ShutdownOverlay(
          child: RunToastHost(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(child: NeuralBackground()),
                  ),
                ),
                child,
              ],
            ),
          ),
        );
      },
      home: presentation == HostPresentation.pairingPopup
          ? const PairingPopupView()
          : const WindowListenerWrapper(child: _ModeAwareHome()),
    );
  }
}

class _ModeAwareHome extends ConsumerWidget {
  const _ModeAwareHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) return const AndroidShell();

    // Aca ya no cuelga nada de host (historial, hubs, auto-cambio de perfil,
    // lo que pide el telefono): vive en `HostRuntime` y no depende de cual de
    // los dos modos este montado.
    final mode = ref.watch(windowModeProvider);
    return mode == WindowMode.compact
        ? const CompactDeckView()
        : const _HomeShell();
  }
}

enum _DeckMenu {
  phoneOnly,
  export,
  import,
  runHistory,
  toggleAi,
  ollama,
  relayTunnel,
  controlServer,
  docsInbox,
  notes,
  noteFolders,
  cpuSensor,
}

/// Boton que abre el panel de ejecuciones. Lleva un punto cuando hay algo
/// corriendo: el toast puede estar tapado por otra ventana (o el usuario lo
/// cerro), y sin esta senal no habria forma de saber desde la app que un
/// comando sigue vivo.
///
/// Desde F4 abre el panel como **dialogo** (antes se acoplaba al costado del
/// deck): el cronometro y la salida en vivo son los mismos.
class _RunPanelButton extends ConsumerWidget {
  const _RunPanelButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(runCenterProvider);
    final failures = state.runs.where((r) => r.isFailure).length;

    return IconButton(
      tooltip: 'Ejecuciones',
      onPressed: () => showRunPanelDialog(context),
      icon: Badge(
        isLabelVisible: state.hasActive || failures > 0,
        backgroundColor: state.hasActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        label: state.hasActive ? null : Text('$failures'),
        smallSize: 8,
        child: const Icon(Icons.terminal_outlined),
      ),
    );
  }
}

/// Boton para el panel de suscripciones (SignalR/WebSocket). Muestra un
/// punto cuando alguna esta activa, mismo lenguaje visual que
/// `_RunPanelButton`.
class _HubSubscriptionsButton extends ConsumerWidget {
  const _HubSubscriptionsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions =
        ref.watch(hubSubscriptionsListProvider).value ?? const [];
    final active = subscriptions
        .where((s) => s.status == HubSubscriptionStatus.active)
        .length;

    return IconButton(
      tooltip: 'Suscripciones',
      onPressed: () => showHubSubscriptionsPanel(context),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        smallSize: 8,
        child: const Icon(Icons.podcasts_outlined),
      ),
    );
  }
}

/// Boton del buzon de documentacion. El numero son las propuestas que esperan
/// una decision: Claude Code las manda y el usuario las aprueba, y sin esta
/// senal una propuesta lista podria quedarse dias sin que nadie la mire.
class _DocsInboxButton extends ConsumerWidget {
  const _DocsInboxButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(docsInboxProvider).pendingCount;

    return IconButton(
      tooltip: pending == 0
          ? 'Buzón de documentación'
          : 'Buzón de documentación: $pending propuestas',
      onPressed: () => showDocsInboxDialog(context),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        smallSize: 8,
        child: const Icon(Icons.edit_note_outlined),
      ),
    );
  }
}

/// Boton de las notas. Solo aparece con una boveda configurada: sin ella no hay
/// nada que abrir, y el acceso para configurarla ya esta en "Mas". El punto dice
/// que el asistente esta trabajando en alguna nota.
class _NotesButton extends ConsumerWidget {
  const _NotesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    if (!notes.configured) return const SizedBox.shrink();
    final active = notes.activeDigests;

    return IconButton(
      tooltip: active == 0
          ? 'Notas'
          : 'Notas: el asistente está con $active',
      onPressed: () => openNotes(context, ref),
      icon: Badge(
        isLabelVisible: active > 0,
        smallSize: 8,
        child: const Icon(Icons.sticky_note_2_outlined),
      ),
    );
  }
}

/// Dashboard y deck en una sola pantalla (ya no hay pestanas separadas):
/// la franja de metricas ocupa ~20% del alto disponible del `body` (medido
/// con `LayoutBuilder`, no de la pantalla completa, para no contar el
/// espacio del AppBar) acotado a un rango razonable, y el resto es la
/// grilla de acciones. Si el usuario pliega las metricas, la franja se
/// reduce a la barrita del chevron y el deck se queda con todo.
class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiEnabled = ref.watch(aiEnabledProvider);
    final ollamaStatus = ref.watch(ollamaControlStatusProvider);
    // `valueOrNull` y no `when`: mientras se resuelve, el item no se
    // muestra. Un menu que aparece medio segundo despues de abrirse es
    // peor que uno que no ofrece algo que casi nunca hace falta.
    final sensorHelper = ref.watch(sensorHelperStatusProvider).value;
    final relayTunnelEnabled = ref.watch(relayTunnelEnabledProvider);
    final controlEnabled = ref.watch(controlServerEnabledProvider);
    final docsPending = ref.watch(docsInboxProvider).pendingCount;
    final notes = ref.watch(notesProvider);
    final notesSubtitle = !notes.configured
        ? 'Tus notas de trabajo en markdown, cruzadas con commits'
        : notes.activeDigests > 0
        ? 'El asistente está con ${notes.activeDigests} notas'
        : '${notes.overview?.notes.length ?? 0} notas en la bóveda';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NexoDeckWordmark(),
            const SizedBox(width: AppSpacing.lg),
            // Junto a la marca y no entre las acciones de la derecha: el
            // perfil activo dice QUE deck se esta viendo, es contexto de la
            // pantalla, no un comando.
            //
            // `Flexible`: en una ventana angosta con varios botones a la
            // derecha (asistente de IA, historial, panel de ejecuciones,
            // menu "Mas"...) el espacio que AppBar le deja al titulo puede
            // quedar por debajo de lo que pide "NexoDeck" + el chip de
            // perfil enteros -- sin esto la fila del titulo desbordaba de
            // costado.
            const Flexible(child: ProfileSelector()),
          ],
        ),
        // La accion primaria vive en la barra, no en un FAB: el FAB flota
        // SOBRE el contenido y tapaba la descripcion de la ultima tarjeta
        // del deck (se ve en una captura). Ademas es un patron de movil --
        // en escritorio la accion primaria va en la toolbar.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: () => showActionEditorSheet(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva acción'),
            ),
          ),
          // Solo con la IA activada: sin esto, el unico atajo al asistente
          // vivia en el estado vacio del deck, o sea que dejaba de existir
          // apenas se creaba la primera accion.
          if (aiEnabled)
            AiAssistantButton(onPressed: () => showAiAssistantDialog(context)),
          IconButton(
            tooltip: 'Historial de hardware',
            icon: const Icon(Icons.timeline_outlined),
            onPressed: () => showHistoryDialog(context),
          ),
          const _RunPanelButton(),
          const _HubSubscriptionsButton(),
          const _DocsInboxButton(),
          const _NotesButton(),
          PopupMenuButton<_DeckMenu>(
            tooltip: 'Más',
            icon: const Icon(Icons.more_vert),
            // El estado de Ollama cambia por fuera (el arranque de Windows, la
            // bandeja del sistema, el propio usuario), asi que se consulta al
            // abrir el menu: el interruptor tiene que mostrar lo que hay ahora,
            // no lo que habia la ultima vez que se miro.
            onOpened: () {
              if (aiEnabled) {
                ref.read(ollamaControlControllerProvider).refresh();
              }
            },
            onSelected: (value) => switch (value) {
              _DeckMenu.phoneOnly =>
                ref.read(hostPresentationControllerProvider).enterPhoneOnly(),
              _DeckMenu.export => exportDeck(context, ref),
              _DeckMenu.import => importDeck(context, ref),
              _DeckMenu.runHistory => showRunHistorySheet(context),
              _DeckMenu.toggleAi =>
                ref.read(aiEnabledControllerProvider).toggle(),
              _DeckMenu.ollama =>
                ref.read(ollamaControlControllerProvider).toggle(),
              _DeckMenu.relayTunnel => showRelayTunnelDialog(context),
              _DeckMenu.controlServer => showControlPanelDialog(context),
              _DeckMenu.docsInbox => showDocsInboxDialog(context),
              _DeckMenu.notes => openNotes(context, ref),
              _DeckMenu.noteFolders => showVaultDialog(context),
              _DeckMenu.cpuSensor => showSensorHelperDialog(context),
            },
            itemBuilder: (context) => [
              // Solo en Windows: es el unico escritorio con bandeja del
              // sistema (ver `TrayController`), y sin bandeja no habria forma
              // de volver a mostrar la ventana.
              if (Platform.isWindows) ...[
                const PopupMenuItem(
                  value: _DeckMenu.phoneOnly,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.phone_android_outlined),
                    title: Text('Solo teléfono'),
                    subtitle: Text(
                      'Oculta la ventana; vuelve desde el icono de la bandeja',
                    ),
                  ),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: _DeckMenu.export,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Exportar deck…'),
                ),
              ),
              const PopupMenuItem(
                value: _DeckMenu.import,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Importar deck…'),
                  subtitle: Text('Agrega, no reemplaza'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _DeckMenu.runHistory,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_outlined),
                  title: Text('Historial de ejecuciones…'),
                  subtitle: Text('Todo lo de esta sesión, con su salida'),
                ),
              ),
              // Solo cuando falta de verdad. Con el servicio corriendo este
              // item no ofreceria nada, y en Linux/Android la temperatura la
              // da el propio SO.
              if (sensorHelper == SensorHelperStatus.notInstalled ||
                  sensorHelper == SensorHelperStatus.stopped) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _DeckMenu.cpuSensor,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.thermostat_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Temperatura del procesador'),
                    subtitle: Text(
                      sensorHelper == SensorHelperStatus.stopped
                          ? 'Instalada pero detenida'
                          : 'Sin activar — la ficha de CPU no muestra grados',
                    ),
                  ),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _DeckMenu.toggleAi,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Asistente de IA'),
                  subtitle: Text(
                    aiEnabled
                        ? 'Activado'
                        : 'Desactivado — no descarga ni ejecuta nada',
                  ),
                  // El switch es solo el indicador: quien maneja el toque es
                  // el propio item del menu (`onSelected`). Con un `Switch`
                  // interactivo aca, tocarlo cambiaria el valor pero dejaria
                  // el menu abierto mostrando el estado viejo del resto.
                  trailing: IgnorePointer(
                    child: Switch(value: aiEnabled, onChanged: (_) {}),
                  ),
                ),
              ),
              // Solo con la IA activada: Ollama es un proveedor suyo, y la
              // regla del proyecto es no llamar al bridge de IA con el flag en
              // false. Con la IA apagada no hay nada que configurar aqui.
              if (aiEnabled)
                PopupMenuItem(
                  value: _DeckMenu.ollama,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Ollama'),
                    subtitle: Text(ollamaControlSubtitle(ollamaStatus)),
                    // Mismo criterio que el switch de la IA: es solo el
                    // indicador, quien maneja el toque es el item del menu.
                    trailing: IgnorePointer(
                      child: Switch(
                        value: ollamaStatus.running,
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              PopupMenuItem(
                value: _DeckMenu.controlServer,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Servidor de control…'),
                  subtitle: Text(
                    controlEnabled
                        ? 'Encendido — Claude Code puede pedirte avisos'
                        : 'Apagado — no escucha en ningún puerto',
                  ),
                  trailing: IgnorePointer(
                    child: Switch(value: controlEnabled, onChanged: (_) {}),
                  ),
                ),
              ),
              PopupMenuItem(
                value: _DeckMenu.docsInbox,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('Buzón de documentación…'),
                  subtitle: Text(
                    docsPending == 0
                        ? 'Hallazgos de Claude Code para tus documentos'
                        : '$docsPending propuestas esperando tu decisión',
                  ),
                ),
              ),
              PopupMenuItem(
                value: _DeckMenu.notes,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: const Text('Notas…'),
                  subtitle: Text(notesSubtitle),
                ),
              ),
              // Aparte de "Notas…" a proposito: con WebView2, "Notas…" abre la
              // ventana del editor, que no tiene configuracion, y el "Cambiar…"
              // del dialogo de Flutter no se ve nunca. Sin esto no habria forma
              // de elegir la boveda ni añadir carpetas locales desde la app.
              const PopupMenuItem(
                value: _DeckMenu.noteFolders,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('Carpetas de notas…'),
                  subtitle: Text('Bóveda y notas locales'),
                ),
              ),
              PopupMenuItem(
                value: _DeckMenu.relayTunnel,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Túnel remoto…'),
                  subtitle: Text(
                    relayTunnelEnabled
                        ? 'Prendido'
                        : 'Apagado — datos móviles sin Tailscale',
                  ),
                  trailing: IgnorePointer(
                    child: Switch(value: relayTunnelEnabled, onChanged: (_) {}),
                  ),
                ),
              ),
            ],
          ),
          const DevicesButton(),
          const HomeLayoutButton(),
          const ThemeModeToggleButton(),
          const WindowModeToggleButton(),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      // Como se reparten metricas y deck lo decide `HomeLayout` (boton de la
      // barra, persistido en `app_settings`), no esta pantalla.
      body: const HomeLayoutView(),
    );
  }
}
