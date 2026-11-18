import 'package:flutter/material.dart';
import 'package:nexodeck/data/local/tables/devices_table.dart';

import '../../../../core/theme/app_spacing.dart';

/// Icono por plataforma. Vive aca y no dentro de una pantalla para que las
/// dos listas de dispositivos (la de la PC y la del telefono) no terminen con
/// dos mapeos distintos.
IconData deviceIconFor(DevicePlatform platform) => switch (platform) {
  DevicePlatform.android => Icons.phone_android,
  DevicePlatform.ios => Icons.phone_iphone,
  DevicePlatform.windows => Icons.desktop_windows,
  DevicePlatform.linux => Icons.computer,
};

/// Badge tonal cuadrado que identifica a un dispositivo, en el mismo lenguaje
/// visual que el badge de `EmptyState` y el chip de icono de las acciones.
///
/// Con `platform == null` usa un icono neutral a proposito: la lista de hosts
/// descubiertos trabaja con `DiscoveredHost`, que **no trae plataforma** (ver
/// `discovery.rs`, solo expone name/host/port). Mostrar un icono de Windows
/// fijo, como se hacia antes, es mentirle al usuario cuando la PC es Linux;
/// arreglarlo de verdad pide sumar el dato al anuncio mDNS.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({super.key, this.platform, this.size = 40});

  final DevicePlatform? platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final platform = this.platform;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Icon(
        platform == null ? Icons.devices_outlined : deviceIconFor(platform),
        size: size * 0.5,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}
