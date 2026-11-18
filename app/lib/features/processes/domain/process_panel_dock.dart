import '../../../core/theme/app_spacing.dart';

/// Donde vive el panel de procesos.
///
/// Es lo mismo que hace cualquier panel de un IDE: se acopla a un costado o
/// se agranda cuando querés mirarlo en serio. Acoplado el panel es angosto y
/// muestra lo justo; maximizado tapa el deck y muestra todas las columnas.
enum ProcessPanelDock {
  left(label: 'Anclar a la izquierda'),
  right(label: 'Anclar a la derecha'),
  maximized(label: 'Maximizar');

  const ProcessPanelDock({required this.label});

  final String label;

  bool get isSide =>
      this == ProcessPanelDock.left || this == ProcessPanelDock.right;

  /// Tolera un valor guardado que ya no exista: cae al lado izquierdo, que es
  /// donde nace el panel.
  static ProcessPanelDock fromName(String? name) => values.firstWhere(
    (dock) => dock.name == name,
    orElse: () => ProcessPanelDock.left,
  );
}

/// Cuanta informacion entra en una fila del panel.
///
/// La decide el **ancho medido**, no el estado del dock: es el mismo criterio
/// que ya usa el panel de metricas (mide espacio, no pregunta la plataforma),
/// y da el resultado que se espera igual --acoplado el panel es angosto y
/// maximizado es ancho--.
enum ProcessRowDensity {
  /// Nombre, el valor de la metrica elegida y el tiempo corriendo.
  compact,

  /// Ademas: CPU, memoria, GPU y disco por separado, y cuantos procesos
  /// agrupa.
  full;

  static ProcessRowDensity forWidth(double width) =>
      width >= AppSizes.processPanelFullColumnsWidth
      ? ProcessRowDensity.full
      : ProcessRowDensity.compact;
}
