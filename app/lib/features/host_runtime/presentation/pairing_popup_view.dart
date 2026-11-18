import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../pairing/presentation/widgets/host_pin_card.dart';
import '../application/host_presentation_controller.dart';

/// La ventana emergente de emparejamiento del modo solo telefono: la misma
/// `HostPinCard` que muestra la hoja de siempre, pero como pantalla entera.
///
/// Reusar la tarjeta no es comodidad: el PIN es un ritual de dos pantallas, y
/// el widget que lo dibuja tiene que ser el mismo en todos lados (ver
/// "Pairing" en `CLAUDE.md`).
class PairingPopupView extends ConsumerWidget {
  const PairingPopupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.pairingContentMaxWidth + AppSpacing.xl * 2,
              ),
              child: HostPinCard(
                onClosed: (paired) => ref
                    .read(hostPresentationControllerProvider)
                    .endPairingPopup(paired: paired),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
