import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/pairing.dart' as bridge;

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../application/pairing_provider.dart';
import '../../domain/host_name.dart';
import '../pairing_timings.dart';
import 'device_avatar.dart';

/// Rol Android: hosts NexoDeck descubiertos por mDNS en la red local.
///
/// Es `Stateful` por el temporizador de busqueda: `discoveredHostsProvider`
/// hace `await for` sobre el stream de Rust, asi que **solo emite despues del
/// primer host** y nunca entrega una lista vacia. Sin un timer propio, "no
/// hay ninguna PC" es indistinguible de "todavia no llego la primera", y el
/// usuario se quedaba mirando un spinner para siempre.
class DiscoveredHostsList extends ConsumerStatefulWidget {
  const DiscoveredHostsList({
    required this.onSelect,
    required this.onManual,
    super.key,
  });

  final void Function(bridge.DiscoveredHost host) onSelect;

  /// Escribir la direccion a mano. Acompania a la lista en TODOS sus
  /// estados --buscando, sin resultados y con resultados-- porque fuera de
  /// la LAN mDNS no encuentra nada nunca: si la opcion viviera solo en el
  /// estado "no encontre ninguna PC", el usuario en datos moviles tendria
  /// que esperar los 8 s del cartel para descubrir que existe.
  final VoidCallback onManual;

  @override
  ConsumerState<DiscoveredHostsList> createState() =>
      _DiscoveredHostsListState();
}

class _DiscoveredHostsListState extends ConsumerState<DiscoveredHostsList> {
  Timer? _searchTimer;
  bool _searchExhausted = false;

  @override
  void initState() {
    super.initState();
    _restartSearchTimer();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _restartSearchTimer() {
    _searchTimer?.cancel();
    _searchExhausted = false;
    _searchTimer = Timer(PairingTimings.discoverySearchHint, () {
      if (mounted) setState(() => _searchExhausted = true);
    });
  }

  void _retry() {
    // `discoveredHostsProvider` es `autoDispose`: invalidarlo cierra el
    // stream viejo y arranca un `browse` nuevo del lado Rust.
    ref.invalidate(discoveredHostsProvider);
    setState(_restartSearchTimer);
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(discoveredHostsProvider);

    return hosts.when(
      // `data` con lista vacia no ocurre hoy (ver el comentario de la clase),
      // pero se contempla igual para no depender de ese detalle del provider.
      data: (list) => list.isEmpty ? _searching() : _list(list),
      loading: _searching,
      error: (error, stackTrace) => EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo buscar en la red',
        message: '$error',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            _manualButton(),
          ],
        ),
      ),
    );
  }

  Widget _manualButton() => TextButton.icon(
    onPressed: widget.onManual,
    icon: const Icon(Icons.lan_outlined),
    label: const Text('Conectar por direccion'),
  );

  Widget _searching() {
    if (!_searchExhausted) {
      return EmptyState(
        leading: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        icon: Icons.wifi_find,
        title: 'Buscando tu PC en la red...',
        message: 'Los dos equipos tienen que estar en la misma red WiFi.',
        action: _manualButton(),
      );
    }
    return EmptyState(
      icon: Icons.wifi_find,
      title: 'No encontramos ninguna PC',
      message:
          'Verifica que NexoDeck este abierto en la PC y que las dos esten '
          'en la misma red. Si estas con datos moviles, conectate por '
          'direccion.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Buscar de nuevo'),
          ),
          _manualButton(),
        ],
      ),
    );
  }

  Widget _list(List<bridge.DiscoveredHost> list) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      // +1: la ultima fila no es un host sino la salida manual, para el
      // caso de que mDNS encuentre OTRA PC pero no la que el usuario
      // quiere alcanzar por Tailscale.
      itemCount: list.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == list.length) {
          return Center(child: _manualButton());
        }
        return _HostTile(
          host: list[index],
          onTap: () => widget.onSelect(list[index]),
          entryDelay:
              AppDuration.staggerSlow *
              index.clamp(0, AppMotion.maxStaggerSteps),
        );
      },
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.host,
    required this.onTap,
    required this.entryDelay,
  });

  final bridge.DiscoveredHost host;
  final VoidCallback onTap;
  final Duration entryDelay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InteractiveCard(
      onTap: onTap,
      semanticLabel: hostDisplayName(host.name),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            // Sin plataforma: `DiscoveredHost` solo trae name/host/port. Antes
            // habia un icono de Windows fijo, que miente cuando la PC es Linux.
            const DeviceAvatar(),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // El nombre crudo es el fullname de mDNS: al usuario se le
                    // mostraba "MI-PC._nexodeck._tcp.local." como nombre de su
                    // computadora.
                    hostDisplayName(host.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${host.host}:${host.port}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    ).animate(delay: entryDelay).fadeIn(duration: AppDuration.entry).slideY(
      // Los hosts aparecen de a uno a medida que mDNS los resuelve, asi que
      // la entrada escalonada se nota de verdad y no es decorativa.
      begin: 0.12,
      end: 0,
      duration: AppDuration.entry,
      curve: AppCurves.standard,
    );
  }
}
