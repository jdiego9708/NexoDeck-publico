import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_surface.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../application/devices_provider.dart';
import '../../application/pairing_provider.dart';
import '../../data/devices_repository.dart';
import '../../data/pairing_repository.dart';
import '../pairing_timings.dart';
import 'device_avatar.dart';
import 'pin_display.dart';

/// Cuantas `HostPinCard` hay montadas ahora mismo.
///
/// Lo consulta `HostPresentationController` antes de abrir otra: una segunda
/// tarjeta volveria a llamar a `arm_pairing`, que **reemplaza** el PIN, y el
/// telefono veria uno distinto del que muestra la primera. Es un contador
/// estatico y no un provider porque se toca desde `initState`/`dispose`, donde
/// Riverpod no permite modificar estado.
int _mountedHostPinCards = 0;

bool get isHostPinCardMounted => _mountedHostPinCards > 0;

/// Rol PC: arma el pairing al abrirse, muestra el PIN generado, y espera a
/// que un dispositivo lo pida -- entonces ofrece Aceptar/Rechazar. Vive
/// dentro de `showPairingSheet`.
class HostPinCard extends ConsumerStatefulWidget {
  const HostPinCard({super.key, this.onClosed});

  /// Si esta puesto, la tarjeta llama a esto al terminar (con `true` si se
  /// emparejo) en vez de popear su ruta. Lo usa la ventana emergente del modo
  /// solo telefono, donde la tarjeta es la pantalla entera.
  final ValueChanged<bool>? onClosed;

  @override
  ConsumerState<HostPinCard> createState() => _HostPinCardState();
}

class _HostPinCardState extends ConsumerState<HostPinCard> {
  String? _pin;
  String? _error;
  bridge.PairingEvent_DeviceRequestedPairing? _pendingRequest;
  String? _succeededWith;
  StreamSubscription<bridge.PairingEvent>? _pairingEvents;
  late final PairingRepository _repository;

  @override
  void initState() {
    super.initState();
    _mountedHostPinCards++;
    // Se lee aca y no en `dispose`: `ref` no se puede usar cuando el widget ya
    // se esta desmontando, y `dispose` necesita el repositorio para desarmar el
    // pairing y contestarle a un telefono que quede esperando.
    _repository = ref.read(pairingRepositoryProvider);
    _arm();
    // Stream directo y no `ref.listen(...)`: Riverpod descarta el evento
    // cuando es `==` al anterior y estos son value types de freezed. Dos
    // dispositivos con el mismo nombre y plataforma pidiendo pairing uno
    // detras del otro generan eventos identicos, y el segundo se perdia.
    // Ver `pairingEventStream`.
    _pairingEvents = pairingEventStream(ref).listen(_handleEvent);
  }

  Future<void> _arm() async {
    setState(() {
      _error = null;
      _pin = null;
    });
    try {
      final pin = await ref.read(pairingRepositoryProvider).armPairing();
      if (mounted) setState(() => _pin = pin);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _mountedHostPinCards--;
    _pairingEvents?.cancel();
    // La tarjeta puede desmontarse sin pasar por `_close()`: en la ventana
    // emergente, si el usuario vuelve a la interfaz completa desde la bandeja
    // con una solicitud en pantalla. Sin contestar, el telefono esperaria los
    // 120 s del host.
    if (_pendingRequest != null) {
      unawaited(_repository.confirmPairing(false).catchError((Object _) {}));
    }
    _repository.disarmPairing();
    super.dispose();
  }

  /// Cierra la hoja **contestandole al telefono si habia una solicitud
  /// pendiente**.
  ///
  /// Sin esto, cerrar con una solicitud en pantalla dejaba al telefono
  /// esperando hasta el `PAIRING_STEP_TIMEOUT` de 120 s del host
  /// (`nexodeck-transport/src/server.rs`) sin ninguna respuesta. Es un bug,
  /// no una cuestion estetica: dos minutos mirando un spinner.
  Future<void> _close() async {
    if (_pendingRequest != null) {
      await ref.read(pairingRepositoryProvider).confirmPairing(false);
      // Ya se le contesto: `dispose` no tiene que volver a hacerlo.
      _pendingRequest = null;
    }
    _finish(paired: false);
  }

  /// Sale de la tarjeta. Dentro de la hoja es un `pop`; en la ventana
  /// emergente del modo solo telefono (`PairingPopupView`) la tarjeta ES la
  /// pantalla, no hay ruta que popear, y decide quien la aloja.
  void _finish({required bool paired}) {
    if (!mounted) return;
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed(paired);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con una solicitud pendiente hay que pasar si o si por `_close()`,
      // que es quien le contesta al telefono.
      canPop: _pendingRequest == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(onClose: _close),
            const SizedBox(height: AppSpacing.gutter),
            AnimatedSize(
              duration: AppDuration.state,
              curve: AppCurves.standard,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppDuration.state,
                child: _buildBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _error;
    if (error != null) {
      return EmptyState(
        key: const ValueKey('error'),
        icon: Icons.link_off,
        title: 'No se pudo preparar el emparejamiento',
        message: error,
        action: FilledButton.tonalIcon(
          onPressed: _arm,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }

    final succeeded = _succeededWith;
    if (succeeded != null) {
      return _SuccessPanel(key: const ValueKey('success'), deviceName: succeeded);
    }

    final pin = _pin;
    if (pin == null) {
      return const Padding(
        key: ValueKey('arming'),
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final pending = _pendingRequest;
    return Column(
      key: const ValueKey('pin'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Compara este PIN con el que aparece en el telefono',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.gutter),
        PinDisplay(pin: pin),
        const SizedBox(height: AppSpacing.gutter),
        if (pending == null)
          const _WaitingRow()
        else
          _PendingRequestCard(
            request: pending,
            onReject: () => _respond(false),
            onAccept: () => _respond(true),
          ),
      ],
    );
  }

  void _handleEvent(bridge.PairingEvent event) {
    switch (event) {
      case bridge.PairingEvent_DeviceRequestedPairing():
        setState(() => _pendingRequest = event);
      case bridge.PairingEvent_PairingSucceeded(
        :final deviceId,
        :final certFingerprint,
      ):
        _onPairingSucceeded(deviceId, certFingerprint);
      case bridge.PairingEvent_PairingRejected(:final reason):
        if (mounted) {
          setState(() => _pendingRequest = null);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Rechazado: $reason')));
        }
      case bridge.PairingEvent_HostPinReceived():
      case bridge.PairingEvent_PairingRequestedWhileDisarmed():
        // El primero no aplica en rol host; el segundo lo atiende
        // `HostRuntime`, que es quien abre esta tarjeta.
        break;
    }
  }

  Future<void> _onPairingSucceeded(
    String deviceId,
    String certFingerprint,
  ) async {
    final request = _pendingRequest;
    if (request != null) {
      await ref
          .read(devicesRepositoryProvider)
          .pairDevice(
            id: deviceId,
            name: request.deviceName,
            platform: devicePlatformFromBridge(request.platform),
            certFingerprint: certFingerprint,
          );
    }
    if (!mounted) return;
    // Momento de exito antes de cerrar: la hoja se cerraba en seco y el
    // usuario no llegaba a ver que habia funcionado.
    setState(() {
      _succeededWith = request?.deviceName;
      _pendingRequest = null;
    });
    await Future<void>.delayed(PairingTimings.successDwell);
    _finish(paired: true);
  }

  Future<void> _respond(bool accept) async {
    await ref.read(pairingRepositoryProvider).confirmPairing(accept);
    if (!accept && mounted) setState(() => _pendingRequest = null);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Emparejar dispositivo',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// "Esperando" con senal de vida. Antes era un `Text` estatico, que en una
/// espera de hasta dos minutos se lee como que la app se colgo.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            'Esperando a que el telefono ingrese el PIN...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// La solicitud entrante en su propia superficie. Antes era texto plano
/// debajo del PIN, sin ninguna jerarquia: lo mas importante de la pantalla
/// se veia igual que una nota al pie.
class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({
    required this.request,
    required this.onReject,
    required this.onAccept,
  });

  final bridge.PairingEvent_DeviceRequestedPairing request;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppSurface.cardDecoration(scheme, accent: scheme.primary),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DeviceAvatar(platform: devicePlatformFromBridge(request.platform)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.deviceName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Quiere emparejarse con este equipo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onReject, child: const Text('Rechazar')),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: onAccept, child: const Text('Aceptar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({super.key, this.deviceName});

  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.check_rounded,
      title: deviceName == null
          ? 'Dispositivo emparejado'
          : 'Emparejado con "$deviceName"',
      message: 'Ya podes controlarlo desde el telefono.',
    );
  }
}
