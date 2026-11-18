import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/src/rust/api/usb.dart' as bridge;

import '../../../../core/theme/app_spacing.dart';
import '../../application/usb_events_provider.dart';

/// Rol PC: estado del cable USB (Fase 5). Solo aparece cuando hay algo que
/// decir -- si no hay nada enchufado no ocupa lugar.
///
/// El caso importante es `DriverBlocked`: Windows tiene atado al telefono un
/// driver que no es WinUSB, asi que no se le puede hablar hasta cambiarlo
/// (ver ADR 0002). Es el unico estado que necesita una accion del usuario;
/// el resto es informativo, y el puente se recupera solo.
class UsbStatusBanner extends ConsumerWidget {
  const UsbStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(usbStatusProvider);
    if (status == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (icon, message, isProblem) = switch (status) {
      bridge.UsbEvent_PhoneDetected(:final product) => (
        Icons.usb,
        'Dispositivo detectado por cable: ${product ?? 'Android'}',
        false,
      ),
      bridge.UsbEvent_DriverBlocked(:final vendorId, :final productId) => (
        Icons.usb_off,
        'El dispositivo USB ${_hex(vendorId)}:${_hex(productId)} esta tomado '
            'por otro driver. Hace falta instalar WinUSB para usarlo por '
            'cable; mientras tanto, sigue funcionando por WiFi.',
        true,
      ),
      bridge.UsbEvent_AccessoryModeStarted() => (
        Icons.usb,
        'Preparando la conexion por cable...',
        false,
      ),
      bridge.UsbEvent_AccessoryConnected() => (
        Icons.usb,
        'Conectado por cable.',
        false,
      ),
      bridge.UsbEvent_AccessoryDisconnected() => (
        Icons.usb_off,
        'Se desconecto el cable.',
        false,
      ),
      bridge.UsbEvent_Failed(:final detail) => (
        Icons.error_outline,
        'Error en la conexion por cable: $detail',
        true,
      ),
    };

    final color = isProblem
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final onColor = isProblem
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: onColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: onColor),
            ),
          ),
        ],
      ),
    );
  }

  String _hex(int value) => value.toRadixString(16).padLeft(4, '0');
}
