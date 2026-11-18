import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

import '../../../core/theme/app_spacing.dart';
import '../application/devices_provider.dart';
import '../application/network_status_provider.dart';
import '../application/pairing_provider.dart';
import '../data/device_identity.dart';
import '../data/devices_repository.dart';
import '../data/multicast_lock_service.dart';
import '../domain/connection_error.dart';
import '../domain/host_name.dart';
import '../domain/manual_host.dart';
import 'pairing_timings.dart';
import 'widgets/device_avatar.dart';
import 'widgets/discovered_hosts_list.dart';
import 'widgets/manual_host_dialog.dart';
import 'widgets/no_wifi_banner.dart';
import 'widgets/pin_confirm_dialog.dart';

/// En que punto del ritual esta el telefono.
///
/// Reemplaza al par `_connecting`/`_dialogShown`: dos booleanos paralelos que
/// podian desincronizarse y que, juntos, no alcanzaban para decirle al
/// usuario que estaba pasando.
enum _Phase {
  browsing,
  connecting,
  awaitingPin,
  awaitingHostDecision,
  success,
}

/// Rol Android, sin ningun dispositivo emparejado todavia: busca hosts por
/// mDNS y corre el flujo de pairing. `AndroidShell` la muestra hasta que
/// `pairedDevicesListProvider` deje de estar vacio.
class AndroidPairingScreen extends ConsumerStatefulWidget {
  const AndroidPairingScreen({super.key});

  @override
  ConsumerState<AndroidPairingScreen> createState() =>
      _AndroidPairingScreenState();
}

class _AndroidPairingScreenState extends ConsumerState<AndroidPairingScreen> {
  static const _multicastLock = MulticastLockService();

  _Phase _phase = _Phase.browsing;

  /// Como llamar a la PC mientras no llegue su nombre real con el PIN.
  ///
  /// Es un string ya listo para mostrar y no el `DiscoveredHost`: al host
  /// se puede llegar por mDNS o por una direccion escrita a mano, y en el
  /// segundo caso no hay ningun `DiscoveredHost` del que sacar un nombre.
  String? _targetLabel;

  /// Direccion escrita a mano con la que se esta emparejando, si fue por
  /// ese camino. Se guarda con el dispositivo al terminar: emparejar fuera
  /// de la LAN y no persistirla dejaria la reconexion sin a donde ir,
  /// porque mDNS ahi no encuentra nada.
  ManualHost? _manualAddress;

  /// Nombre REAL de la PC, que llega recien con el PIN.
  ///
  /// No es el mismo string que `DiscoveredHost.name`: mDNS anuncia el nombre
  /// sanitizado por `sanitize_instance_name` (todo lo no alfanumerico pasa a
  /// `-`), asi que `Juan's PC` se anuncia como `Juan-s-PC`. Por eso tampoco
  /// se pueden correlacionar eventos comparando nombres.
  String? _confirmedHostName;

  bridge.PairingEvent_HostPinReceived? _pinEvent;
  StreamSubscription<bridge.PairingEvent>? _pairingEvents;
  Timer? _handshakeTimer;
  Timer? _decisionTimer;

  @override
  void initState() {
    super.initState();
    _multicastLock.acquire();
    // Stream directo y no `ref.listen(...)`: Riverpod descarta el evento
    // cuando es `==` al anterior y estos son value types de freezed, asi
    // que reintentar el pairing contra la misma PC (mismo PIN, mismo
    // motivo de rechazo) perdia el segundo evento. Ver `pairingEventStream`.
    _pairingEvents = pairingEventStream(ref).listen(_handleEvent);
  }

  @override
  void dispose() {
    _pairingEvents?.cancel();
    _handshakeTimer?.cancel();
    _decisionTimer?.cancel();
    _multicastLock.release();
    super.dispose();
  }

  String get _hostLabel => _confirmedHostName ?? _targetLabel ?? 'la PC';

  void _backToBrowsing({String? message}) {
    _handshakeTimer?.cancel();
    _decisionTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.browsing;
      _targetLabel = null;
      _manualAddress = null;
      _confirmedHostName = null;
      _pinEvent = null;
    });
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // `null` mientras se resuelve el estado inicial -- no mostrar el aviso
    // todavia en ese caso, solo cuando se confirma que NO hay WiFi.
    final isOnWifi = ref.watch(isOnWifiProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Emparejar con una PC')),
      body: Column(
        children: [
          if (isOnWifi == false) const NoWifiBanner(),
          Expanded(
            child: _phase == _Phase.browsing
                ? DiscoveredHostsList(
                    onSelect: _connectToDiscovered,
                    onManual: _connectToManual,
                  )
                : _ProgressPanel(
                    hostName: _hostLabel,
                    status: _statusLine,
                    // Cancelar solo tiene sentido mientras se espera; en
                    // `success` ya esta hecho.
                    onCancel: _phase == _Phase.success
                        ? null
                        : () => _backToBrowsing(),
                    done: _phase == _Phase.success,
                  ),
          ),
        ],
      ),
    );
  }

  String get _statusLine => switch (_phase) {
    _Phase.browsing => '',
    _Phase.connecting => 'Conectando...',
    _Phase.awaitingPin => 'Esperando el PIN...',
    _Phase.awaitingHostDecision => 'Confirma el emparejamiento en la PC',
    _Phase.success => 'Listo',
  };

  void _connectToDiscovered(bridge.DiscoveredHost host) {
    _connect(
      host: host.host,
      port: host.port,
      label: hostDisplayName(host.name),
    );
  }

  /// Camino para alcanzar la PC cuando mDNS no puede: fuera de la LAN, por
  /// Tailscale. El pairing en si es identico -- mismo handshake, mismo PIN,
  /// mismo pinning; lo unico distinto es de donde sale la direccion.
  Future<void> _connectToManual() async {
    final choice = await showManualHostDialog(
      context,
      confirmLabel: 'Conectar',
    );
    final address = choice?.address;
    if (address == null || !mounted) return;
    _connect(
      host: address.host,
      port: address.port,
      label: address.display,
      manual: address,
    );
  }

  Future<void> _connect({
    required String host,
    required int port,
    required String label,
    ManualHost? manual,
  }) async {
    setState(() {
      _phase = _Phase.connecting;
      _targetLabel = label;
      _manualAddress = manual;
      _confirmedHostName = null;
    });
    // Si la PC anunciada por mDNS ya no contesta, sin esto el panel se queda
    // esperando para siempre: el host no manda nada y el error tampoco llega.
    _handshakeTimer = Timer(PairingTimings.connectHandshake, () {
      if (_phase == _Phase.connecting || _phase == _Phase.awaitingPin) {
        _backToBrowsing(message: 'La PC no respondio. Proba de nuevo.');
      }
    });

    try {
      final deviceName = await resolveDeviceName();
      await ref
          .read(pairingRepositoryProvider)
          .connectToHost(host: host, port: port, deviceName: deviceName);
      if (mounted && _phase == _Phase.connecting) {
        setState(() => _phase = _Phase.awaitingPin);
      }
    } catch (e) {
      // Un fallo antes de abrir la sesion (la PC anunciada por mDNS pero que
      // ya no acepta conexiones, TLS caido) no produce ningun evento de
      // pairing, asi que si no se limpia aca no se limpia nunca.
      if (!mounted) return;
      _backToBrowsing(message: describeConnectionError(e));
    }
  }

  Future<void> _handleEvent(bridge.PairingEvent event) async {
    switch (event) {
      case bridge.PairingEvent_HostPinReceived():
        // Gate por FASE y no por nombre: si el usuario cancelo, la sesion del
        // lado Rust sigue viva hasta el timeout de 120 s del host (no existe
        // un "cancelar" en el protocolo, ver `pairing_repository`), asi que
        // el PIN de un intento abandonado puede llegar tarde. Compararlo por
        // nombre no serviria: el nombre de mDNS y el real son distintos.
        if (_phase == _Phase.browsing || _phase == _Phase.success) return;
        if (_phase == _Phase.awaitingHostDecision) return;

        _handshakeTimer?.cancel();
        _pinEvent = event;
        if (mounted) {
          setState(() {
            _phase = _Phase.awaitingPin;
            _confirmedHostName = event.hostName;
          });
        }

        final confirmed = await showPinConfirmDialog(
          context,
          pin: event.pin,
          hostName: event.hostName,
        );
        if (!mounted) return;
        if (!confirmed) {
          _backToBrowsing();
          return;
        }

        setState(() => _phase = _Phase.awaitingHostDecision);
        // De aca en mas se espera a un HUMANO frente a la PC, por eso el
        // timeout es tan largo (ver `PairingTimings.hostDecision`).
        _decisionTimer = Timer(PairingTimings.hostDecision, () {
          if (_phase == _Phase.awaitingHostDecision) {
            _backToBrowsing(
              message: 'Nadie confirmo el emparejamiento en la PC.',
            );
          }
        });
        await ref.read(pairingRepositoryProvider).sendPairConfirm();

      case bridge.PairingEvent_PairingSucceeded(
        :final deviceId,
        :final certFingerprint,
      ):
        // Se procesa SIEMPRE, incluso si el usuario cancelo desde la UI.
        // Este evento solo puede llegar si ya se mando `PairConfirm` y la PC
        // acepto, o sea que el emparejamiento ocurrio de verdad: descartarlo
        // dejaria a la PC creyendo que tiene un dispositivo emparejado y al
        // telefono no, que es el peor estado posible.
        _handshakeTimer?.cancel();
        _decisionTimer?.cancel();
        final pin = _pinEvent;
        if (mounted) {
          setState(() {
            _phase = _Phase.success;
            _confirmedHostName = pin?.hostName ?? _confirmedHostName;
          });
        }
        await ref
            .read(devicesRepositoryProvider)
            .pairDevice(
              id: deviceId,
              name: pin?.hostName ?? 'PC',
              platform: devicePlatformFromBridge(
                pin?.hostPlatform ?? bridge.DevicePlatform.windows,
              ),
              certFingerprint: certFingerprint,
              manualAddress: _manualAddress,
            );
      // Sin navegacion explicita: AndroidShell observa
      // pairedDevicesListProvider y cambia a ConnectedDeviceScreen solo
      // con que esta escritura llegue a Drift.

      case bridge.PairingEvent_PairingRejected(:final reason):
        _backToBrowsing(message: 'Rechazado: $reason');

      case bridge.PairingEvent_DeviceRequestedPairing():
      case bridge.PairingEvent_PairingRequestedWhileDisarmed():
        break; // no aplican en rol cliente
    }
  }
}

/// Reemplaza al `CircularProgressIndicator` pelado que se mostraba entre el
/// tap y el dialogo del PIN: sin nombre de la PC, sin decir que estaba
/// pasando y sin forma de volver atras.
class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.hostName,
    required this.status,
    required this.onCancel,
    required this.done,
  });

  final String hostName;
  final String status;
  final VoidCallback? onCancel;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.pairingContentMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 28,
                    color: scheme.onPrimaryContainer,
                  ),
                )
              else
                const DeviceAvatar(size: 56),
              const SizedBox(height: AppSpacing.gutter),
              Text(
                hostName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                status,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.gutter),
              if (!done)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                  child: const LinearProgressIndicator(),
                ),
              if (onCancel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
