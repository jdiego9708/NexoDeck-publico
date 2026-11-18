import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../domain/run_panel_dock.dart';
import 'run_panel.dart';

/// Abre el panel de ejecuciones como **dialogo**.
///
/// Es la presentacion de escritorio desde F4 (antes se acoplaba a un costado
/// del deck). El cronometro y la salida en vivo siguen igual; se cierra con el
/// boton, `Esc` o el fondo.
Future<void> showRunPanelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1000,
        height: 680,
        child: RunPanel(
          dock: RunPanelDock.maximized,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
