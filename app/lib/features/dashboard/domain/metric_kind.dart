/// Que recurso mide una tile de metricas.
///
/// Hasta ahora la unica identidad de una metrica era su titulo (`'CPU'`), que
/// alcanzaba mientras nadie tuviera que decidir nada en funcion de cual era.
/// El panel de procesos si lo necesita: hay que saber por que columna ordenar
/// y cuales metricas ni siquiera pueden desglosarse.
enum MetricKind {
  cpu,
  ram,
  disk,
  gpu,
  network;

  /// Si tiene sentido preguntarse "quien esta consumiendo esto".
  ///
  /// Red queda afuera **por una limitacion real, no por falta de ganas**: en
  /// Windows no hay API de usuario que reparta trafico de red por proceso;
  /// hace falta ETW (trazas del kernel), que es un proyecto aparte. Disco SI
  /// se puede: `sysinfo::Process::disk_usage()` ya usa `GetProcessIoCounters`
  /// (la misma fuente que el Administrador de tareas), sin ETW de por medio
  /// -- corrige una suposicion vieja de este comentario. Mientras Red no
  /// tenga fuente, esa tile no se ofrece como clicable -- una tile que
  /// responde al clic sin mostrar nada es peor que una que no invita a
  /// tocarla.
  bool get supportsProcessBreakdown =>
      this == MetricKind.cpu ||
      this == MetricKind.ram ||
      this == MetricKind.gpu ||
      this == MetricKind.disk;

  /// Titulo del panel cuando se desglosa esta metrica.
  String get processPanelTitle => switch (this) {
    MetricKind.cpu => 'Procesos · CPU',
    MetricKind.ram => 'Procesos · Memoria',
    MetricKind.gpu => 'Procesos · GPU',
    MetricKind.disk => 'Procesos · Disco',
    MetricKind.network => 'Procesos · Red',
  };
}
