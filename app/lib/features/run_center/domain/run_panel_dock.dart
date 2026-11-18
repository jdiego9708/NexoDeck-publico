/// Donde vive el panel de ejecuciones.
///
/// Mismo molde que `ProcessPanelDock`: se acopla a un costado o se agranda
/// cuando hay que mirar la salida en serio. Es un enum aparte y no el mismo
/// porque los dos paneles se anclan por su cuenta -- mirar los procesos a la
/// izquierda no obliga a mirar las ejecuciones ahi.
enum RunPanelDock {
  left(label: 'Anclar a la izquierda'),
  right(label: 'Anclar a la derecha'),
  maximized(label: 'Maximizar');

  const RunPanelDock({required this.label});

  final String label;

  bool get isSide => this == RunPanelDock.left || this == RunPanelDock.right;

  /// Tolera un valor guardado que ya no exista (bajar de version, renombrar
  /// el enum): cae a la derecha, que es de donde vienen los toasts.
  static RunPanelDock fromName(String? name) => values.firstWhere(
    (dock) => dock.name == name,
    orElse: () => RunPanelDock.right,
  );
}
