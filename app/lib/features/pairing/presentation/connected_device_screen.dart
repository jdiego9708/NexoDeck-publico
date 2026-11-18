import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge_pairing;
import 'package:nexodeck/src/rust/api/connection.dart' as bridge;
import 'package:nexodeck/src/rust/api/hardware.dart' as bridge_hardware;

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../actions/presentation/widgets/action_icons.dart';
import '../../actions/presentation/widgets/deck_grid_layout.dart';
import '../../actions/presentation/widgets/parameter_prompt_dialog.dart';
import '../../dashboard/domain/metric_kind.dart';
import '../../processes/application/process_providers.dart';
import '../../processes/domain/process_group.dart';
import '../../processes/domain/process_panel_dock.dart';
import '../../processes/presentation/process_panel.dart';
import '../../theme/presentation/theme_mode_toggle_button.dart';
import '../../dashboard/application/metrics_visibility_controller.dart';
import '../../dashboard/application/monitor_mode_controller.dart';
import '../../dashboard/application/host_components_provider.dart';
import '../../dashboard/domain/hardware_snapshot.dart';
import '../../dashboard/domain/host_components.dart';
import '../../dashboard/presentation/widgets/metric_specs.dart';
import '../../dashboard/presentation/widgets/metrics_panel.dart';
import '../../hub_subscriptions/application/hub_subscriptions_provider.dart';
import '../../hub_subscriptions/presentation/remote_hub_subscriptions_panel.dart';
import '../../run_center/application/run_center_controller.dart';
import '../application/connection_provider.dart';
import '../application/devices_provider.dart';
import '../application/network_status_provider.dart';
import '../application/pairing_provider.dart';
import '../application/relay_provider.dart';
import '../application/remote_ai_chat_provider.dart';
import '../data/connection_repository.dart';
import '../data/multicast_lock_service.dart';
import '../domain/connection_error.dart';
import '../domain/paired_device.dart';
import '../domain/reconnect_target.dart';
import 'remote_ai_chat_screen.dart';
import '../../notes/presentation/mobile_notes_screen.dart';
import 'widgets/manual_host_dialog.dart';
import 'widgets/no_wifi_banner.dart';
import 'widgets/remote_action_card.dart';

/// Rol Android, con un dispositivo ya emparejado: reconecta (mDNS +
/// fingerprint pinneado), muestra el hardware en vivo de la PC, y el
/// catalogo de acciones recibido -- tocar una la dispara del lado PC.
class ConnectedDeviceScreen extends ConsumerStatefulWidget {
  const ConnectedDeviceScreen({required this.device, super.key});

  final PairedDevice device;

  @override
  ConsumerState<ConnectedDeviceScreen> createState() =>
      _ConnectedDeviceScreenState();
}

class _ConnectedDeviceScreenState
    extends ConsumerState<ConnectedDeviceScreen> {
  static const _multicastLock = MulticastLockService();
  static const _kHistoryLength = 30;
  static const _kStaggerStep = AppDuration.staggerFast;
  static const _kMaxStaggerSteps = AppMotion.maxStaggerSteps;

  /// Cada cuanto se reintenta reconectar mientras no haya sesion.
  ///
  /// El reintento es propio y no se apoya en el stream de mDNS: ese stream
  /// emite solo cuando se RESUELVE un servicio nuevo, asi que si el primer
  /// intento falla (la PC todavia no acepta conexiones, cambio de red, un
  /// TCP rechazado) puede no volver a emitir nunca y el telefono se queda
  /// esperando para siempre. Ya paso.
  static const _kReconnectRetry = Duration(seconds: 4);

  /// Cuanto se le da a mDNS antes de probar la direccion manual.
  ///
  /// El orden importa: la IP de la LAN la reparte el DHCP y cambia, asi que
  /// mDNS es la fuente correcta cuando hay LAN. La direccion escrita a mano
  /// es el plan B --fuera de la red, por Tailscale-- y no el plan A.
  static const _kMdnsGrace = Duration(seconds: 6);

  HardwareSnapshot? _snapshot;
  List<bridge.RemoteAction> _actions = const [];
  bool _connected = false;
  bool _reconnectRequested = false;

  /// Ultima lista de hosts vista por mDNS. Se guarda porque el reintento
  /// por timer necesita algo contra que matchear sin esperar una emision
  /// nueva del stream.
  List<bridge_pairing.DiscoveredHost> _hosts = const [];

  /// Desde cuando se esta intentando reconectar sin exito. Es lo que mide
  /// la gracia de `_kMdnsGrace`; se reinicia en cada desconexion para que
  /// mDNS vuelva a tener su turno si la red cambio.
  late DateTime _reconnectingSince;
  Timer? _retryTimer;
  StreamSubscription<bridge.ConnectionEvent>? _connectionEvents;
  StreamSubscription<bridge_pairing.PairingEvent>? _pairingEvents;

  /// Motivo del ultimo intento fallido, para que el fallo no sea mudo: sin
  /// esto la pantalla decia "Reconectando..." indefinidamente sin ninguna
  /// pista de que estaba pasando.
  String? _lastReconnectError;

  /// La PC rechazo explicitamente la reconexion (revoco el dispositivo o ya
  /// no lo conoce). A diferencia de un fallo de red, reintentar no lo va a
  /// arreglar: hace falta volver a emparejar, asi que la UI ofrece salir.
  bool _rejected = false;

  /// Filtro de grupo activo (id de `RemoteAction.groupId`). `null` =
  /// "Todas". A diferencia de desktop, no hay CRUD de grupos aca -- solo
  /// se puede filtrar por los grupos que ya vienen en el catalogo.
  String? _selectedGroupId;

  final List<double> _cpuHistory = [];
  final List<double> _netRxHistoryKb = [];
  final List<double> _netTxHistoryKb = [];
  final Map<String, List<double>> _diskReadHistoryKb = {};
  final Map<String, List<double>> _diskWriteHistoryKb = {};

  @override
  void initState() {
    super.initState();
    _multicastLock.acquire();
    _reconnectingSince = DateTime.now();
    _retryTimer = Timer.periodic(_kReconnectRetry, (_) {
      _maybeReconnect(_hosts);
    });
    // Streams DIRECTOS y no `ref.listen(...)`: Riverpod descarta el evento
    // cuando es `==` al anterior, y estos son value types de freezed. Dos
    // `Disconnected` seguidos (que es exactamente lo que produce un rechazo
    // de reconexion reintentado) hacian que el segundo no llegara nunca, y
    // con el se perdia el unico lugar donde se limpia
    // `_reconnectRequested`: la pantalla quedaba trabada para siempre.
    // Verificado contra el telefono real. Ver `connectionEventStream`.
    _connectionEvents = connectionEventStream(ref).listen(
      _handleConnectionEvent,
    );
    // Un `ReconnectRejected` (la PC revoco o ya no conoce a este
    // dispositivo) llega como evento de PAIRING, no de conexion. Sin
    // escucharlo, el rechazo era invisible: la pantalla se quedaba en
    // "Reconectando..." sin mensaje y sin salida.
    _pairingEvents = pairingEventStream(ref).listen(_handlePairingEvent);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectionEvents?.cancel();
    _pairingEvents?.cancel();
    _multicastLock.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // La PC puede haber cambiado de IP (DHCP) desde el ultimo pairing --
    // se vuelve a resolver por mDNS antes de reconectar en vez de guardar
    // una IP fija. Heuristica simple para esta fase: matchea por nombre de
    // instancia mDNS sanitizado (ver `sanitize_instance_name` en
    // nexodeck-transport/src/discovery.rs) conteniendo el nombre guardado.
    ref.listen(discoveredHostsProvider, (previous, next) {
      next.whenData((hosts) {
        _hosts = hosts;
        _maybeReconnect(hosts);
      });
    });
    final isOnWifi = ref.watch(isOnWifiProvider).value;

    // En horizontal el recurso escaso es el alto, asi que las metricas
    // pasan a un riel lateral y el deck se queda con toda la altura; en
    // vertical van como franja arriba. Es lo unico que cambia el layout --
    // el resto lo resuelven los widgets midiendo su propio espacio.
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final selectedMetric = ref.watch(selectedMetricProvider);
    // Modo monitor: el deck desaparece y las metricas se quedan con la
    // pantalla entera. No depende de la orientacion --las dos usan la franja
    // horizontal-- porque el riel existe para convivir con el deck, y aca no
    // hay con quien repartir.
    final monitorMode = ref.watch(monitorModeProvider);

    return Scaffold(
      // Sin AppBar a proposito: el nombre de la PC ocupaba una fila entera
      // (~56 dp) para un dato que no cambia y que en horizontal es
      // justamente el espacio que necesitan las metricas y el deck. Al no
      // haber AppBar, el `SafeArea` tiene que cubrir tambien arriba (barra
      // de estado), ademas de abajo (barra de gestos) y los laterales
      // (notch en horizontal).
      body: SafeArea(
        child: Stack(
          children: [
            if (monitorMode)
              _buildMonitor(isOnWifi)
            else
              landscape ? _buildLandscape() : _buildPortrait(isOnWifi),
            // La hoja de procesos va **encima** del contenido y no dentro de
            // la `Column`: asi el deck no se reacomoda al abrirla, y al
            // cerrarla queda todo como estaba. Solo existe con una metrica
            // elegida, que es lo que ademas mantiene viva la suscripcion.
            if (selectedMetric != null) _buildProcessSheet(selectedMetric),
          ],
        ),
      ),
    );
  }

  Widget _buildPortrait(bool? isOnWifi) {
    return Column(
      children: [
        ..._buildConnectionHeader(isOnWifi),
        if (_connected && _snapshot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              4,
            ),
            child: _buildMetricsPanel(MetricsPanelAxis.horizontal),
          ),
        const Divider(height: 1),
        Expanded(child: _buildDeck()),
      ],
    );
  }

  /// Modo monitor: barra minima arriba (para volver) y las metricas con todo
  /// lo demas.
  ///
  /// Usa la franja horizontal en las dos orientaciones a proposito. El riel
  /// existe para dejarle el ancho al deck; sin deck, la franja reparte las 5
  /// metricas en el rectangulo entero y cada tile queda con alto de sobra --
  /// que es justo lo que hace que se dibujen apiladas, con el grafico grande
  /// y todos sus datos (ver `MetricTile`).
  Widget _buildMonitor(bool? isOnWifi) {
    return Column(
      children: [
        ..._buildConnectionHeader(isOnWifi),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: _buildTopBar(showGroups: false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _connected && _snapshot != null
                ? _buildMetricsPanel(MetricsPanelAxis.horizontal, fill: true)
                : const EmptyState(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Esperando las metricas',
                    message: 'La PC todavia no envio ninguna medicion.',
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape() {
    return Column(
      children: [
        ..._buildConnectionHeader(null),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_connected && _snapshot != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                  ),
                  child: _buildMetricsPanel(MetricsPanelAxis.vertical),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: _buildDeck()),
            ],
          ),
        ),
      ],
    );
  }

  /// Banda de estado de conexion, comun a las dos orientaciones. En
  /// horizontal el banner de "sin WiFi" se omite (no hay alto que gastar en
  /// el; el `LinearProgressIndicator` ya comunica que no hay conexion).
  List<Widget> _buildConnectionHeader(bool? isOnWifi) {
    if (_connected) return const [];
    final error = _lastReconnectError;
    final manual = widget.device.manualAddress;
    return [
      if (isOnWifi == false) const NoWifiBanner(),
      const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _rejected
            // Un rechazo explicito no se arregla esperando: se sigue
            // reintentando por si la PC vuelve a autorizar el dispositivo,
            // pero hay que ofrecer la salida real, que es re-emparejar.
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      'La PC rechazo la conexion: ${error ?? 'sin motivo'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _forgetDevice,
                    child: const Text('Olvidar esta PC'),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      // Se sigue reintentando cada `_kReconnectRetry`, asi
                      // que el error es informativo, no terminal: por eso
                      // acompania al "Reconectando..." en vez de
                      // reemplazarlo.
                      error == null
                          ? 'Reconectando...'
                          : 'Reconectando... ($error)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Aca y no en un menu: este es el momento exacto en que la
                  // reconexion no esta funcionando, que es cuando una
                  // direccion fija sirve de algo.
                  TextButton(
                    onPressed: _editManualAddress,
                    child: Text(
                      manual == null ? 'Conectar por IP' : 'Cambiar IP',
                    ),
                  ),
                ],
              ),
      ),
    ];
  }

  /// Chips de grupo + grilla de acciones.
  Widget _buildDeck() {
    return Column(
      children: [
        // La barra va siempre, tenga o no acciones el catalogo: es el unico
        // lugar del telefono donde viven el cambio de tema y el modo monitor,
        // y esconderla mientras la PC no manda nada dejaba a los dos sin
        // ninguna via de acceso.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: _buildTopBar(),
        ),
        Expanded(
          child: _actions.isEmpty
              ? const EmptyState(
                  // Un indicador en vez del badge: comunica "esperando", no
                  // "no hay nada". La variante compacta se activa sola en
                  // horizontal, donde el alto es el recurso escaso.
                  leading: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  icon: Icons.bolt_outlined,
                  title: 'Esperando el catalogo',
                  message: 'La PC esta por enviar sus acciones.',
                )
              : _buildActionsGrid(),
        ),
      ],
    );
  }

  /// Mismo panel (y por lo tanto las mismas 5 metricas, con MHz, °C, VRAM y
  /// totales) que muestra la PC en `MetricsRow`. Lo unico distinto es la
  /// fuente del snapshot: aca llega por red en vez de leerse local.
  Widget _buildMetricsPanel(MetricsPanelAxis axis, {bool fill = false}) {
    return SizedBox(
      // En franja hay que fijarle un alto (el `Column` padre no acota) --
      // el riel, en cambio, hereda la altura del `Row` expandido. En modo
      // monitor tampoco se fija: el panel esta dentro de un `Expanded` y se
      // queda con la pantalla entera, que es de lo que se trata el modo.
      height: axis == MetricsPanelAxis.horizontal && !fill
          ? (ref.watch(metricsCollapsedProvider)
                ? AppSizes.collapsedMetricsExtent
                : _portraitStripHeight(context))
          : null,
      child: MetricsPanel(
        specs: buildMetricSpecs(
          snapshot: _snapshot!,
          scheme: Theme.of(context).colorScheme,
          components:
              ref.watch(remoteHostComponentsProvider) ?? HostComponents.empty,
          cpuHistory: _cpuHistory,
          netRxHistoryKb: _netRxHistoryKb,
          netTxHistoryKb: _netTxHistoryKb,
          diskReadHistoryKb: _diskReadHistoryKb,
          diskWriteHistoryKb: _diskWriteHistoryKb,
        ),
        axis: axis,
        collapsed: ref.watch(metricsCollapsedProvider),
        onToggleCollapsed: () =>
            ref.read(metricsVisibilityControllerProvider).toggle(),
        // Las mismas tiles del escritorio, ahora tambien clicables aca: los
        // procesos que muestran son **los de la PC**, que es lo unico que le
        // interesa a alguien mirando el telefono.
        selectedMetric: ref.watch(selectedMetricProvider),
        onSelectMetric: _toggleProcessPanel,
      ),
    );
  }

  /// Abre el desglose de una metrica, o lo cierra si ya era esa.
  ///
  /// **Prende y apaga la suscripcion**: con el panel cerrado, la PC deja de
  /// recorrer sus procesos y el telefono deja de recibir. Es lo que hace que
  /// esta funcion no cueste bateria cuando no se usa.
  void _toggleProcessPanel(MetricKind kind) {
    final current = ref.read(selectedMetricProvider);
    final next = current == kind ? null : kind;
    ref.read(selectedMetricProvider.notifier).state = next;

    watchRemoteProcesses(next != null).ignore();
    if (next == null) {
      ref.read(remoteTopProcessesProvider.notifier).state = null;
    }
  }

  /// El panel de procesos de la PC, como hoja que sube desde abajo.
  ///
  /// **Hoja y no panel lateral**: en un telefono no hay ancho para partir la
  /// pantalla en dos, y en vertical menos todavia. La hoja se lleva el alto
  /// que le sobra al deck y se cierra deslizando, que es el gesto que la gente
  /// ya espera en Android.
  Widget _buildProcessSheet(MetricKind metric) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) => Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ProcessPanel(
          metric: metric,
          dock: ProcessPanelDock.maximized,
          remote: true,
          // La RAM total sale del snapshot que ya recibe el telefono: no puede
          // leer la memoria de la PC por su cuenta.
          totalRamMb: _snapshot?.ramTotalMb,
        ),
      ),
    );
  }

  /// Alto de la franja en vertical: hasta 2 filas de tiles en un telefono
  /// (donde entran 2 columnas) y 1 fila en una tablet ancha, sin pasarse de
  /// un tercio de la pantalla.
  static double _portraitStripHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final columns = metricColumnsFor(
      availableWidth:
          size.width - AppSpacing.md * 2 - AppSizes.collapsedMetricsExtent,
      count: 5,
    );
    final rows = (5 / columns).ceil();
    final height =
        AppSizes.minFullMetricTileHeight * rows + AppSpacing.sm * (rows - 1);
    return height.clamp(0.0, size.height * 0.34);
  }

  /// Grupos distintos presentes en el catalogo actual (dedupe por
  /// `groupId`, preservando el orden de primera aparicion). `RemoteAction`
  /// ya trae nombre/color denormalizados -- no hace falta resolver nada
  /// contra un catalogo de grupos aparte.
  List<bridge.RemoteAction> get _distinctGroups {
    final seen = <String>{};
    final result = <bridge.RemoteAction>[];
    for (final action in _actions) {
      final groupId = action.groupId;
      if (groupId != null && seen.add(groupId)) result.add(action);
    }
    return result;
  }

  /// Chips de grupo (cuando hay deck) y los dos controles de la pantalla.
  ///
  /// En modo monitor no hay grupos que filtrar, pero la barra se dibuja igual:
  /// es la que trae el boton para volver al deck.
  Widget _buildTopBar({bool showGroups = true}) {
    final groups = showGroups
        ? _distinctGroups
        : const <bridge.RemoteAction>[];
    final monitorMode = ref.watch(monitorModeProvider);

    return SizedBox(
      height: AppSizes.groupFilterBarHeight,
      child: Row(
        children: [
          if (groups.isEmpty)
            const Spacer()
          else
            Expanded(child: _buildGroupChips(groups)),
          // Las notas van siempre: funcionan sin conexión con la PC, contra la
          // copia del teléfono, así que no dependen de ningún estado remoto.
          IconButton(
            tooltip: 'Notas',
            onPressed: () => showMobileNotesScreen(context),
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),
          if (ref.watch(remoteAiStatusProvider).enabled)
            const _RemoteAiChatButton(),
          _RemoteHubSubscriptionsButton(
            subscriptions: ref.watch(remoteHubSubscriptionsProvider),
          ),
          // El icono es el de la ACCION y no el del estado: este boton es un
          // interruptor de dos posiciones, y mostrar el modo actual dejaria
          // al usuario sin saber que hace tocarlo.
          IconButton(
            onPressed: () =>
                ref.read(monitorModeControllerProvider).toggle(),
            icon: Icon(
              monitorMode ? Icons.grid_view_outlined : Icons.monitor_outlined,
            ),
            tooltip: monitorMode ? 'Volver al deck' : 'Modo monitor',
          ),
          // El unico lugar del telefono donde cabe el cambio de tema: esta
          // pantalla **no tiene AppBar** (se quito para ganar alto, ver
          // CLAUDE.md), asi que sin esto el modo claro/oscuro solo se podia
          // cambiar desde la PC. Se muestra aunque no haya grupos.
          const ThemeModeToggleButton(),
        ],
      ),
    );
  }

  Widget _buildGroupChips(List<bridge.RemoteAction> groups) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('Todas'),
              selected: _selectedGroupId == null,
              onSelected: (_) => setState(() => _selectedGroupId = null),
            ),
          ),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: colorFromHex(
                    group.groupColorHex ?? group.colorHex,
                  ),
                  radius: 6,
                ),
                label: Text(group.groupName ?? ''),
                selected: _selectedGroupId == group.groupId,
                onSelected: (_) =>
                    setState(() => _selectedGroupId = group.groupId),
              ),
            ),
      ],
    );
  }

  Widget _buildActionsGrid() {
    final selected = _selectedGroupId;
    final visible = selected == null
        ? _actions
        : _actions.where((a) => a.groupId == selected).toList();

    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Grupo vacio',
        message: 'Ninguna accion de la PC esta en este grupo.',
      );
    }

    // Ver `resolveDeckGrid`: con pocas acciones las tarjetas se estiran
    // para llenar la pantalla (en horizontal, una grilla de extent fijo
    // dejaba media pantalla vacia); con muchas, se acotan a un tamano
    // tocable y la grilla scrollea, a diferencia del deck de escritorio que
    // nunca scrollea.
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = AppSpacing.md;
        final layout = resolveDeckGrid(
          itemCount: visible.length,
          availableWidth: constraints.maxWidth - padding * 2,
          availableHeight: constraints.maxHeight - padding * 2,
        );

        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          physics: layout.scrolls
              ? null
              : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: layout.columns,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: layout.aspectRatio,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final action = visible[index];
            return RemoteActionCard(
              action: action,
              entryDelay: _kStaggerStep * index.clamp(0, _kMaxStaggerSteps),
              onExecute: () => _executeRemote(action),
            );
          },
        );
      },
    );
  }

  /// Dispara una accion del catalogo. Si trae parametros, los pide primero
  /// con el MISMO dialogo que usa la PC (`showParameterPromptDialog`) y
  /// manda los valores con el pedido.
  ///
  /// Antes se mandaba `sendExecuteAction(action.id)` pelado: la PC
  /// terminaba ejecutando con los valores por defecto y nadie se enteraba
  /// de que faltaba preguntar. Para una macro, `parameters` ya viene siendo
  /// la union de los parametros de todos sus pasos (lo resuelve la PC al
  /// armar el catalogo), asi que aca no hay nada especial que hacer.
  Future<void> _executeRemote(bridge.RemoteAction action) async {
    var values = const <String, String>{};
    if (action.parameters.isNotEmpty) {
      final entered = await showParameterPromptDialog(
        context,
        title: action.name,
        parameters: ConnectionRepository.paramsFromBridge(action.parameters),
      );
      if (entered == null) return; // cancelado
      values = entered;
    }
    if (!mounted) return;
    await ref
        .read(connectionRepositoryProvider)
        .sendExecuteAction(action.id, paramValues: values);
  }

  /// Convierte al snapshot de dominio apenas llega. Asi esta pantalla y el
  /// dashboard de la PC comparten tipo, y con el tipo, todo el pipeline de
  /// presentacion (`buildMetricSpecs` + `MetricsPanel`).
  void _recordSnapshot(bridge_hardware.HardwareSnapshot raw) {
    final snapshot = HardwareSnapshot.fromBridge(raw);
    setState(() {
      _snapshot = snapshot;
      _pushCapped(_cpuHistory, snapshot.cpuUsage);
      _pushCapped(_netRxHistoryKb, snapshot.netRxBytesPerSec / 1024);
      _pushCapped(_netTxHistoryKb, snapshot.netTxBytesPerSec / 1024);
      _recordDiskHistory(snapshot);
    });
  }

  /// Ver el gemelo en `metrics_row.dart` (PC): mismo criterio de podar las
  /// claves que ya no aparecen en el snapshot.
  void _recordDiskHistory(HardwareSnapshot snapshot) {
    final current = snapshot.disks.map((d) => d.mountPoint).toSet();
    _diskReadHistoryKb.removeWhere((key, _) => !current.contains(key));
    _diskWriteHistoryKb.removeWhere((key, _) => !current.contains(key));
    for (final disk in snapshot.disks) {
      if (disk.readBytesPerSec == null) continue;
      _pushCappedForKey(
        _diskReadHistoryKb,
        disk.mountPoint,
        disk.readBytesPerSec! / 1024,
      );
      _pushCappedForKey(
        _diskWriteHistoryKb,
        disk.mountPoint,
        (disk.writeBytesPerSec ?? 0) / 1024,
      );
    }
  }

  static void _pushCapped(List<double> list, double value) {
    list.add(value);
    if (list.length > _kHistoryLength) list.removeAt(0);
  }

  static void _pushCappedForKey(
    Map<String, List<double>> map,
    String key,
    double value,
  ) => _pushCapped(map.putIfAbsent(key, () => []), value);

  Future<void> _maybeReconnect(
    List<bridge_pairing.DiscoveredHost> hosts,
  ) async {
    if (_reconnectRequested || _connected || !mounted) return;
    final target = _resolveTarget(hosts);
    // Tercer nivel: solo cuando mDNS Y la direccion manual ya se agotaron
    // (mismo criterio que decide si probar la manual -- ver
    // `_mdnsGraceElapsed`). Es a proposito el ULTIMO recurso: agrega una
    // vuelta por un VPS ajeno que ni mDNS ni la manual necesitan.
    final relay = widget.device.relayEndpoint;
    final useRelay = target == null && relay != null && _mdnsGraceElapsed;
    if (target == null && !useRelay) return;

    _reconnectRequested = true;
    try {
      if (target != null) {
        await ref
            .read(pairingRepositoryProvider)
            .reconnectToHost(
              deviceId: widget.device.id,
              host: target.host,
              port: target.port,
              pinnedFingerprint: widget.device.certFingerprint,
            );
      } else {
        await ref
            .read(relayRepositoryProvider)
            .reconnectViaRelay(
              deviceId: widget.device.id,
              host: relay!.host,
              port: relay.port,
              tokenHex: relay.tokenHex,
              pinnedFingerprint: widget.device.certFingerprint,
            );
      }
      // Volver sin excepcion significa CONECTADO (la sesion sigue en
      // background del lado Rust), asi que el flag NO se limpia aca: lo
      // limpia el `Disconnected` cuando esa sesion termine. Limpiarlo aca
      // haria que el timer abriera una segunda sesion en paralelo a los 4
      // segundos -- pasaba, y se veia como dos `DeviceConnected` seguidos
      // sin `DeviceDisconnected` en el medio del lado PC.
    } catch (e) {
      // Un fallo de conexion (TCP rechazado, fingerprint que no matchea) no
      // pasa por `run_connection`, asi que no hay `Disconnected` que limpie
      // el flag: hay que limpiarlo aca o no se reintenta nunca mas.
      _reconnectRequested = false;
      if (!mounted) return;
      setState(() => _lastReconnectError = describeConnectionError(e));
    }
  }

  /// A donde intentar la reconexion: mDNS primero, direccion manual
  /// despues. Devuelve `null` cuando no hay ninguna de las dos.
  ///
  /// La manual no se prueba en el acto salvo que mDNS no pueda servir: en
  /// la LAN el descubrimiento tarda 1-2 s, y salir corriendo a una IP vieja
  /// guardada hace meses solo consigue un TCP que cuelga hasta el timeout.
  ReconnectTarget? _resolveTarget(
    List<bridge_pairing.DiscoveredHost> hosts,
  ) => resolveReconnectTarget(
    deviceName: widget.device.name,
    // `discoveredHostsProvider` solo ACUMULA (dedupe por nombre) y nunca
    // saca un host: el propio mdns_sd notifica la baja internamente, pero
    // `discovery.rs` solo reenvia `ServiceResolved`, nunca la remocion. Sin
    // este corte, un host encontrado una vez con WiFi quedaba "encontrado"
    // para siempre incluso ya sin LAN, y bloqueaba tanto la direccion
    // manual como el relay -- los dos niveles siguientes nunca se probaban
    // porque este siempre devolvia un target (viejo, inalcanzable). mDNS es
    // multicast de LAN: sin WiFi ninguna entrada puede ser de fiar.
    discovered: ref.read(isOnWifiProvider).value == false
        ? const <DiscoveredEndpoint>[]
        : hosts.map((h) => (name: h.name, host: h.host, port: h.port)),
    manual: widget.device.manualAddress,
    mdnsGraceElapsed: _mdnsGraceElapsed,
  );

  /// Si ya se le puede dar el turno a la direccion manual.
  bool get _mdnsGraceElapsed {
    // Sin WiFi, mDNS no puede funcionar ni esperando: es multicast de red
    // local. Gastar la gracia con datos moviles solo retrasaria la unica
    // via que puede andar, que es justamente el caso que esto viene a
    // resolver.
    if (ref.read(isOnWifiProvider).value == false) return true;
    return DateTime.now().difference(_reconnectingSince) >= _kMdnsGrace;
  }

  /// Fija, cambia o borra la direccion manual de esta PC.
  Future<void> _editManualAddress() async {
    final choice = await showManualHostDialog(
      context,
      initial: widget.device.manualAddress,
      confirmLabel: 'Guardar',
    );
    if (choice == null || !mounted) return;
    await ref
        .read(devicesRepositoryProvider)
        .setManualAddress(widget.device.id, choice.address);
    if (!mounted) return;
    // Escribir una direccion a mano ES la senal de que mDNS no va a servir,
    // asi que se le vence la gracia y el proximo intento la usa ya. Esperar
    // otros 6 s despues de que el usuario acaba de tipearla se sentiria como
    // que el boton no hizo nada.
    _reconnectingSince = _reconnectingSince.subtract(_kMdnsGrace);
    if (choice.address != null) await _maybeReconnect(_hosts);
  }

  void _handlePairingEvent(bridge_pairing.PairingEvent event) {
    // El unico que aplica al rol ya emparejado: el resto pertenece al
    // primer pairing, que ocurre en `AndroidPairingScreen`.
    if (event case bridge_pairing.PairingEvent_PairingRejected(:final reason)) {
      setState(() {
        _rejected = true;
        _lastReconnectError = reason;
      });
    }
  }

  /// Olvida el emparejamiento: al borrar la fila, `AndroidShell` vuelve
  /// sola a la pantalla de pairing (observa `pairedDevicesListProvider`).
  Future<void> _forgetDevice() async {
    await ref.read(devicesRepositoryProvider).deleteDevice(widget.device.id);
  }

  void _handleConnectionEvent(bridge.ConnectionEvent event) {
    switch (event) {
      case bridge.ConnectionEvent_Connected():
        setState(() {
          _connected = true;
          _lastReconnectError = null;
          // Se sigue reintentando aun despues de un rechazo (la PC puede
          // volver a autorizar el dispositivo desde su pantalla de
          // dispositivos, sin necesidad de re-emparejar), asi que hay que
          // poder salir de este estado sin reiniciar la app.
          _rejected = false;
        });
      case bridge.ConnectionEvent_Disconnected():
        // La gracia arranca de nuevo: la desconexion puede venir de un
        // cambio de red, y ahi mDNS merece su turno antes que la direccion
        // manual.
        _reconnectingSince = DateTime.now();
        setState(() {
          _connected = false;
          _reconnectRequested = false;
        });
      case bridge.ConnectionEvent_HardwareSnapshotReceived(:final field0):
        _recordSnapshot(field0);
      case bridge.ConnectionEvent_TopProcessesReceived(:final field0):
        ref.read(remoteTopProcessesProvider.notifier).state =
            TopProcesses.fromBridge(field0);
      case bridge.ConnectionEvent_ProcessTerminatedReceived(
        :final name,
        :final rejectedReason,
      ):
        // La PC puede rechazar el pedido entero (un proceso critico, o ella
        // misma). Sin este aviso, la fila se quedaria en "Cerrando…" para
        // siempre sin decir por que.
        if (rejectedReason != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name: $rejectedReason')),
          );
        }
      case bridge.ConnectionEvent_ActionsCatalogReceived(:final field0):
        setState(() {
          _actions = field0;
          if (_selectedGroupId != null &&
              !field0.any((a) => a.groupId == _selectedGroupId)) {
            _selectedGroupId = null;
          }
        });
      case bridge.ConnectionEvent_ActionAckReceived(
        :final actionId,
        :final success,
        :final error,
      ):
        // El ack ahora solo significa "la PC lo recibio y lo lanzo". El
        // resultado real llega por `ActionRunUpdateReceived` y se dibuja como
        // notificacion, asi que aca solo queda avisar cuando la PC ni siquiera
        // pudo empezar (ej. "accion no encontrada"): sin esto ese caso queda
        // mudo, porque nunca va a haber un run que reportar.
        if (mounted && !success) {
          // El ack solo trae el id -- se busca el nombre en el catalogo ya
          // recibido para no mostrarle al usuario un UUID crudo.
          final actionName = _actions
              .where((a) => a.id == actionId)
              .map((a) => a.name)
              .firstOrNull;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No se pudo ejecutar "${actionName ?? actionId}": '
                '${error ?? 'error desconocido'}',
              ),
            ),
          );
        }
      case bridge.ConnectionEvent_ActionRunUpdateReceived(
        :final runId,
        :final actionId,
        :final phase,
        :final exitCode,
        :final elapsedMs,
        :final outputTail,
      ):
        // Va al MISMO centro de notificaciones que usa la PC, asi que el
        // telefono muestra la misma tarjeta -- con su estado, su duracion y
        // su salida -- en vez del SnackBar plano de antes, que solo sabia
        // decir "ejecutada".
        ref
            .read(runCenterProvider.notifier)
            .applyRemoteUpdate(
              runId: runId,
              actionLabel:
                  _actions
                      .where((a) => a.id == actionId)
                      .map((a) => a.name)
                      .firstOrNull ??
                  actionId,
              phase: phase,
              elapsedMs: elapsedMs,
              exitCode: exitCode,
              outputTail: outputTail,
            );
      case bridge.ConnectionEvent_HubSubscriptionsSnapshotReceived(
        :final field0,
      ):
        ref.read(remoteHubSubscriptionsProvider.notifier).state = field0;
      case bridge.ConnectionEvent_HostComponentsReceived(:final field0):
        ref.read(remoteHostComponentsProvider.notifier).state =
            HostComponents.fromBridge(field0);
      case bridge.ConnectionEvent_AiStatusReceived(:final enabled, :final ready):
        ref.read(remoteAiStatusProvider.notifier).state = (
          enabled: enabled,
          ready: ready,
        );
      case bridge.ConnectionEvent_AiChatEventReceived():
        break; // lo atiende `remote_ai_chat_screen.dart`, con su propia suscripcion
      case bridge.ConnectionEvent_NotesResponseReceived():
      case bridge.ConnectionEvent_NotesChanged():
        // Los atiende `NotesSyncEngine`, que vive fuera del arbol de widgets:
        // lo que el usuario escribio sin cobertura tiene que salir hacia la PC
        // este o no montada esta pantalla.
        break;
      case bridge.ConnectionEvent_DeviceConnected():
      case bridge.ConnectionEvent_DeviceDisconnected():
      case bridge.ConnectionEvent_ActionExecutionRequested():
      case bridge.ConnectionEvent_AiMessageRequested():
      case bridge.ConnectionEvent_AiActivateRequested():
      case bridge.ConnectionEvent_AiApplyDraftRequested():
      case bridge.ConnectionEvent_AiRunDraftRequested():
      case bridge.ConnectionEvent_AiAskAboutProcessRequested():
        break; // eventos de rol host, no aplican aca
      case bridge.ConnectionEvent_RelayOfferReceived(
        :final host,
        :final port,
        :final tokenHex,
      ):
        // `host` vacio significa que la PC apago el tunel -- se olvida lo
        // guardado, no se deja una direccion muerta que se reintentaria
        // para siempre. Se usa como tercer nivel en `_maybeReconnect`.
        ref
            .read(devicesRepositoryProvider)
            .setRelayOffer(
              widget.device.id,
              host.isEmpty ? null : (host: host, port: port, tokenHex: tokenHex),
            );
    }
  }

}

/// Boton de entrada al chat remoto con el asistente de IA. Gateado por
/// `remoteAiStatusProvider.enabled` en `_buildTopBar` -- si el switch de
/// arriba esta apagado en la PC, el boton directamente no se dibuja, mismo
/// criterio que la IA sigue siendo opt-in tambien desde este lado.
class _RemoteAiChatButton extends ConsumerWidget {
  const _RemoteAiChatButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(remoteAiStatusProvider).ready;

    return IconButton(
      tooltip: 'Asistente de IA',
      onPressed: () => showRemoteAiChatScreen(context),
      // El punto no es un badge de cantidad (no hay "cuantos" en un chat):
      // marca si el motor ya esta listo, para que activar sea explicito y
      // no algo que el usuario descubre recien adentro.
      icon: Badge(
        isLabelVisible: !ready,
        label: const Text('!'),
        smallSize: 8,
        child: const Icon(Icons.smart_toy_outlined),
      ),
    );
  }
}

/// Boton de entrada al panel de solo lectura de las suscripciones en vivo de
/// la PC -- mismo lenguaje visual que `_HubSubscriptionsButton` de
/// `main.dart` (badge con la cuenta de activas), pero abre
/// `showRemoteHubSubscriptionsPanel` en vez del panel con crear/detener/
/// reiniciar, que sigue siendo exclusivo de la PC.
class _RemoteHubSubscriptionsButton extends StatelessWidget {
  const _RemoteHubSubscriptionsButton({required this.subscriptions});

  final List<bridge.HubSubscriptionSummary>? subscriptions;

  @override
  Widget build(BuildContext context) {
    final active = (subscriptions ?? const [])
        .where((s) => s.status == bridge.HubSubscriptionSummaryStatus.active)
        .length;

    return IconButton(
      tooltip: 'Suscripciones',
      onPressed: () => showRemoteHubSubscriptionsPanel(context),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        smallSize: 8,
        child: const Icon(Icons.podcasts_outlined),
      ),
    );
  }
}
