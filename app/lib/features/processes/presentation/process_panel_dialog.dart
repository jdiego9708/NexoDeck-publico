import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../dashboard/domain/metric_kind.dart';
import '../domain/process_panel_dock.dart';
import 'process_panel.dart';

/// Abre el desglose de procesos de una metrica como **dialogo**.
///
/// Es la presentacion de escritorio desde F4: el panel ya no se acopla a un
/// costado, porque competia por el ancho con el riel de metricas y el panel de
/// acciones del centro de control. Se cierra con el boton, `Esc` o el fondo.
Future<void> showProcessPanelDialog(BuildContext context, MetricKind metric) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 940,
        height: 660,
        child: ProcessPanel(
          metric: metric,
          dock: ProcessPanelDock.maximized,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
