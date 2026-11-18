import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import 'widgets/host_pin_card.dart';

/// Rol PC: hoja modal para emparejar un dispositivo nuevo, abierta desde
/// el FAB de `DevicesScreen`.
///
/// **No es descartable a proposito**: cerrarla tocando afuera o arrastrando,
/// con una solicitud pendiente en pantalla, dejaba al telefono esperando los
/// 120 s del `PAIRING_STEP_TIMEOUT` del host sin ninguna respuesta. La unica
/// salida es el boton de cerrar de `HostPinCard`, que antes de irse le
/// contesta. `isDismissible` se fija al abrir la ruta y no se puede alternar
/// despues, asi que condicionarlo a "hay solicitud pendiente" no es posible.
Future<void> showPairingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    // En una ventana ancha la hoja se estiraba a todo lo largo y el PIN
    // quedaba perdido en el medio de una banda vacia.
    constraints: const BoxConstraints(
      maxWidth: AppSizes.pairingContentMaxWidth + AppSpacing.xl * 2,
    ),
    builder: (context) => const SafeArea(child: HostPinCard()),
  );
}
