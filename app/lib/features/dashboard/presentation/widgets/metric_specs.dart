import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/cpu_frequency.dart';
import '../../domain/hardware_snapshot.dart';
import '../../domain/host_components.dart';
import '../../domain/metric_badge.dart';
import '../../domain/metric_kind.dart';
import '../../domain/metric_thresholds.dart';
import 'capacity_bar.dart';
import 'cpu_gauges.dart';
import 'disk_usage_list.dart';
import 'format_utils.dart';
import 'gpu_card_chart.dart';
import 'mini_bar_chart.dart';
import 'mini_line_chart.dart';
import 'ram_module_chart.dart';

/// Una metrica ya resuelta para pintar: que chart, que valor, que datos
/// secundarios. Separado del layout a proposito -- `MetricsPanel` decide
/// como acomodarlas (franja o riel) sin saber nada de hardware, y desktop y
/// movil comparten exactamente la misma lista.
class MetricSpec {
  const MetricSpec({
    required this.kind,
    required this.title,
    required this.accentColor,
    required this.chart,
    required this.valueText,
    this.subtitle,
    this.badges = const [],
    this.stackedChart = false,
    this.squareChart = false,
    this.stackedValues = false,
    this.badgesAreValues = false,
    this.bottomBar,
    this.fallbackBadges = const [],
    this.chartMinWidth = 0,
    this.headerBadge,
    this.widthUnits = 1,
    this.expandedTitle,
    this.expandedBuilder,
    this.valueAsBadge = false,
    this.valueColor,
  });

  /// Que recurso mide. Es la identidad de la metrica: el titulo es texto
  /// para el usuario y puede cambiar, esto no.
  final MetricKind kind;

  final String title;
  final Color accentColor;
  final Widget chart;
  final String valueText;

  /// Que pieza es: el modelo del procesador, de la memoria, de la GPU o el
  /// nombre del adaptador de red. Es informacion de contexto, no un valor que
  /// cambie, asi que se dibuja chico y atenuado bajo el titulo -- y solo si
  /// hay alto para el, porque nunca puede desplazar al dato.
  ///
  /// `null` en el telefono: recibe metricas de la PC por red, no sus piezas.
  final String? subtitle;

  /// Datos secundarios (MHz, °C, VRAM, total, subida). Se ocultan solos en
  /// las densidades mas apretadas. Cada uno puede llevar su propio color de
  /// alerta -- distinto del color de la tile -- y renunciar a la caja
  /// (`MetricBadge.plain`).
  final List<MetricBadge> badges;

  /// El grafico va a lo ancho, **debajo** del titulo, con el valor y los
  /// badges abajo -- en vez del reparto de siempre (grafico a la izquierda,
  /// texto a la derecha).
  ///
  /// Lo pide solo la RAM: su grafico son dos modulos que se llenan a lo
  /// largo, y encajonados en los 48 dp de ancho del chart lateral no se
  /// entenderia que son. Es un pedido, no una garantia: la tile lo concede
  /// unicamente si le sobra alto (ver `MetricTile`).
  final bool stackedChart;

  /// El grafico se dibuja dentro de un cuadrado centrado en vez de estirarse
  /// a lo ancho. Lo pide la Red: sus dos curvas (bajada y subida) se leen como
  /// una forma, y estiradas a lo ancho de la tile se aplastan hasta parecer
  /// dos rayas.
  final bool squareChart;

  /// El valor y los badges van uno **debajo** del otro en vez de en la misma
  /// linea. Lo pide la Red, que tiene dos cifras del mismo peso --bajada y
  /// subida-- y ninguna es el "valor" y la otra un adorno.
  final bool stackedValues;

  /// Los badges son cifras del mismo peso que el valor y van **sin caja**. Lo
  /// pide la Red: bajada y subida son lo mismo medido en dos sentidos. En el
  /// resto, el badge es un dato secundario y lleva su caja para no verse
  /// suelto al lado de un valor grande.
  final bool badgesAreValues;

  /// Barra de capacidad bajo el valor, con su cifra adentro. La usa la GPU
  /// para la VRAM: `2.5 GB/15.9 GB` como texto obligaba a hacer la division
  /// mentalmente para saber si queda lugar.
  final Widget? bottomBar;

  /// Datos que en el layout apilado los dibuja el **grafico** (o la barra de
  /// capacidad), y que vuelven a ser badges cuando la tile cae al reparto
  /// lateral, donde ese grafico no tiene ancho para mostrarlos.
  ///
  /// Son la VRAM de la GPU --que arriba vive dentro de [bottomBar]-- y la
  /// temperatura y la frecuencia del CPU, que viven dentro de `CpuGauges`.
  /// Sin esto desaparecian por completo en el telefono, que es justo la
  /// perdida de informacion que el riel viene evitando.
  final List<MetricBadge> fallbackBadges;

  /// Ancho que necesita el grafico para dibujar por su cuenta lo que dice
  /// [fallbackBadges]. Por debajo, la tile los agrega como badges tambien en
  /// el layout apilado.
  ///
  /// Lo pide el CPU: sus cifras y su termometro solo caben junto al chip a
  /// partir de [AppSizes.cpuGaugesFullWidth] --misma constante que mira
  /// `CpuGauges`, para que las dos decisiones no puedan desalinearse--. La GPU
  /// lo deja en 0: su [bottomBar] dibuja la VRAM a cualquier ancho.
  final double chartMinWidth;

  /// Dato que va arriba a la derecha, enfrentado al titulo, en el layout
  /// apilado. Es para lo que **describe al componente** y no cambia --cuantos
  /// modulos de memoria hay-- y que abajo, entre las cifras que se mueven,
  /// se leia como si fuera una medicion mas.
  final String? headerBadge;

  /// Cuantas columnas de la franja pide esta metrica. Solo el almacenamiento
  /// pide 2, y solo cuando hay mas de un disco que mostrar.
  ///
  /// Es un pedido, no una garantia: la franja lo concede unicamente si TODAS
  /// las tiles siguen entrando en una fila y con alto de sobra (ver
  /// `metricStripLayoutFor`). El riel vertical y la franja micro lo ignoran.
  final int widthUnits;

  /// Titulo cuando la tile se dibuja expandida. La metrica de disco se llama
  /// "Disco" mientras es una barra sola y "Almacenamiento" cuando pasa a ser
  /// la lista, que es lo que efectivamente muestra.
  final String? expandedTitle;

  /// Cuerpo alternativo para cuando la tile consigue el ancho que pidio. Si
  /// es `null`, la tile se dibuja siempre igual.
  final WidgetBuilder? expandedBuilder;

  /// El valor principal se dibuja con la caja de un badge en vez de como
  /// texto suelto. Lo pide la RAM: el pedido de diseno invierte el
  /// tratamiento de siempre entre el valor y su primer badge.
  final bool valueAsBadge;

  /// Color del valor principal (o de su caja, si [valueAsBadge]). `null` =
  /// el tratamiento de siempre (color heredado del texto, o
  /// `MetricSpec.accentColor` si es badge).
  final Color? valueColor;
}

/// Las 5 metricas de NexoDeck, en el orden en que se muestran. Es la unica
/// definicion: la usan `MetricsRow` (desktop, snapshot local) y
/// `ConnectedDeviceScreen` (Android, snapshot recibido por red), asi que el
/// telefono ve exactamente la misma informacion que la PC.
///
/// Los historiales los mantiene quien llama (en memoria, no se persisten);
/// aca solo se leen.
List<MetricSpec> buildMetricSpecs({
  required HardwareSnapshot snapshot,
  required ColorScheme scheme,
  HostComponents components = HostComponents.empty,
  required List<double> cpuHistory,
  required List<double> netRxHistoryKb,
  required List<double> netTxHistoryKb,
  Map<String, List<double>> diskReadHistoryKb = const {},
  Map<String, List<double>> diskWriteHistoryKb = const {},
}) {
  final ramFraction = snapshot.ramTotalMb == 0
      ? 0.0
      : snapshot.ramUsedMb / snapshot.ramTotalMb;
  final diskFraction = snapshot.diskTotalMb == 0
      ? 0.0
      : snapshot.diskUsedMb / snapshot.diskTotalMb;
  final gpuFraction = snapshot.gpuUsage != null
      ? snapshot.gpuUsage! / 100
      : null;
  // La red no tiene techo natural como los porcentajes: se escala contra el
  // pico reciente, con 20% de aire arriba para que el pico no toque el borde.
  final netMaxY =
      [
        1.0,
        ...netRxHistoryKb,
        ...netTxHistoryKb,
      ].reduce((a, b) => a > b ? a : b) *
      1.2;

  // Colores por umbral: cada metrica calcula el suyo una sola vez y lo
  // reusa en el grafico, el valor y los badges que correspondan -- ver
  // `metric_thresholds.dart` para de donde salen los numeros.
  final cpuColor = isCpuHot(snapshot.cpuTempC) ? scheme.error : scheme.primary;

  // El umbral por modulo (`kRamModuleHotFraction`) es el unico numero que dio
  // el pedido; se reusa tambien para el badge/valor agregados -- no hay una
  // cifra separada para "la RAM en general esta alta".
  final ramHot = isRamModuleHot(ramFraction);

  final gpuBusy = isGpuBusy(snapshot.gpuUsage);
  // En reposo, el color por defecto del modo (claro/oscuro) -- no el rojo
  // fijo que tenia antes-- y solo con uso adquiere el rojo de alerta.
  final gpuColor = gpuBusy ? scheme.error : scheme.onSurfaceVariant;

  final netRxKb = snapshot.netRxBytesPerSec / 1024;
  final netTxKb = snapshot.netTxBytesPerSec / 1024;
  // Contra el propio pico reciente (`netMaxY`), no contra un numero de KB/s
  // fijo: una fibra y un WiFi viejo no comparten ninguna cifra "alta" en
  // comun.
  final rxColor = isNetworkBusy(netRxKb, netMaxY) ? scheme.error : scheme.primary;
  final txColor = isNetworkBusy(netTxKb, netMaxY) ? scheme.error : scheme.tertiary;

  return [
    MetricSpec(
      kind: MetricKind.cpu,
      title: 'CPU',
      // El color de la tile entera sigue a la temperatura: el chip, el
      // numero de grados y el badge de hilos comparten esta misma variable,
      // asi que se encienden juntos sin tres chequeos sueltos.
      accentColor: cpuColor,
      // Temperatura y frecuencia a la izquierda, el chip con su historial en
      // el medio, el termometro a la derecha. Van en el grafico y no en los
      // badges porque son **lo que el chip esta haciendo**: al lado del dibujo
      // se leen juntas. Ver `CpuGauges`.
      chart: CpuGauges(
        usedFraction: snapshot.cpuUsage / 100,
        color: cpuColor,
        celsius: snapshot.cpuTempC,
        clockMhz: snapshot.cpuFreqMhz,
        history: MiniLineChart(series: [(cpuHistory, cpuColor)], maxY: 100),
      ),
      stackedChart: true,
      // Hilos y porcentaje quedan enfrentados en la fila de abajo.
      stackedValues: true,
      valueText: '${snapshot.cpuUsage.toStringAsFixed(0)}%',
      subtitle: components.cpuLabel,
      // Solo los hilos: la frecuencia y la temperatura se mudaron al grafico,
      // junto al chip. Cuantos hilos llevan trabajo de verdad dice algo que el
      // porcentaje solo no dice -- 4 hilos al 100% y 12 dormidos dan el mismo
      // 25% que 16 hilos al 25%.
      badges: [
        if (snapshot.cpuThreadsTotal > 0)
          MetricBadge(
            '${snapshot.cpuThreadsBusy}/${snapshot.cpuThreadsTotal} hilos',
          ),
      ],
      // Donde el grafico se queda sin ancho para el termometro y las cifras
      // --el riel y la franja de un telefono-- vuelven aca. Es la unica forma
      // de que en movil se sigan viendo: ver `CpuGauges`.
      fallbackBadges: [
        if (snapshot.cpuTempC != null)
          MetricBadge('${snapshot.cpuTempC!.toStringAsFixed(0)}°C'),
        if (snapshot.cpuFreqMhz != null)
          MetricBadge(formatCpuFrequency(snapshot.cpuFreqMhz!)),
      ],
      chartMinWidth: AppSizes.cpuGaugesFullWidth,
    ),
    MetricSpec(
      kind: MetricKind.ram,
      title: 'RAM',
      accentColor: scheme.secondary,
      // Dos modulos que se llenan, en vez del donut: es la unica metrica
      // cuyo grafico dibuja la cosa que mide. Ver `RamModuleChart`. El color
      // de alerta es POR MODULO -- cada uno pasa a `alertColor` cuando SU
      // PROPIO llenado (no el total) cruza el umbral.
      chart: RamModuleChart(
        usedFraction: ramFraction,
        color: scheme.secondary,
        alertColor: scheme.error,
        alertThreshold: kRamModuleHotFraction,
      ),
      stackedChart: true,
      valueText: formatMb(snapshot.ramUsedMb),
      // Pedido de diseno: el valor (los GB) pasa a llevar caja, y el primer
      // badge ("de 31.9 GB") la pierde -- se invierte el tratamiento visual
      // de los dos. Los dos (valor y % de uso) responden al mismo umbral.
      valueAsBadge: true,
      valueColor: ramHot ? scheme.error : null,
      subtitle: components.ramLabel,
      badges: [
        MetricBadge('de ${formatMb(snapshot.ramTotalMb)}', plain: true),
        // Anclado al borde derecho de la fila, pedido explicito.
        MetricBadge(
          '${(ramFraction * 100).round()}%',
          color: ramHot ? scheme.error : null,
          position: MetricBadgePosition.end,
        ),
      ],
      headerBadge: components.ramModulesLabel,
    ),
    MetricSpec(
      kind: MetricKind.disk,
      title: 'Disco',
      expandedTitle: 'Almacenamiento',
      accentColor: scheme.tertiary,
      chart: MiniBarChart(usedFraction: diskFraction, color: scheme.tertiary),
      valueText: formatMb(snapshot.diskUsedMb),
      // Mismo tratamiento que la RAM: el valor pasa a llevar caja, "de X TB"
      // la pierde, y el porcentaje queda anclado al borde derecho.
      valueAsBadge: true,
      badges: [
        MetricBadge('de ${formatMb(snapshot.diskTotalMb)}', plain: true),
        MetricBadge(
          '${(diskFraction * 100).round()}%',
          position: MetricBadgePosition.end,
        ),
      ],
      // Con un solo disco la lista repetiria letra por letra lo que ya dice
      // el agregado, asi que no se pide ancho de mas.
      widthUnits: snapshot.disks.length > 1 ? 2 : 1,
      expandedBuilder: snapshot.disks.length > 1
          ? (context) => DiskUsageList(
              disks: snapshot.disks,
              accentColor: scheme.tertiary,
              readHistoryKb: diskReadHistoryKb,
              writeHistoryKb: diskWriteHistoryKb,
            )
          : null,
    ),
    MetricSpec(
      kind: MetricKind.gpu,
      title: 'GPU',
      // En reposo, el color por defecto del modo; con uso, el rojo de
      // alerta -- ya no es un rojo fijo como antes.
      accentColor: gpuColor,
      // La placa con sus ventiladores girando al ritmo del uso: el grafico
      // dibuja la pieza que mide, igual que los modulos de la RAM.
      chart: GpuCardChart(usedFraction: gpuFraction, color: gpuColor),
      stackedChart: true,
      valueText: snapshot.gpuUsage != null
          ? '${snapshot.gpuUsage!.toStringAsFixed(0)}%'
          : 'N/D',
      subtitle: components.gpuLabel,
      badges: _gpuBadges(snapshot, scheme),
      // La VRAM sale de los badges y pasa a la barra: ahi la proporcion se ve
      // antes de leerse. Responde a su PROPIO umbral (cuanta VRAM ocupada),
      // independiente del uso de computo que maneja `gpuColor` -- una GPU
      // puede estar con la VRAM casi llena y el nucleo tranquilo, o al reves.
      bottomBar: snapshot.gpuVramFraction == null
          ? null
          : CapacityBar(
              fraction: snapshot.gpuVramFraction!,
              label:
                  '${formatMb(snapshot.gpuVramUsedMb!)} / ${formatMb(snapshot.gpuVramTotalMb!)}',
              color: isGpuVramHot(snapshot.gpuVramFraction)
                  ? scheme.error
                  : scheme.tertiary,
              // `onSecondary` (el color de siempre) no esta pensado para
              // contrastar contra rojo -- mismo motivo que
              // `labelOnFilledAlert` en `RamModuleChart`.
              labelOnFilled: isGpuVramHot(snapshot.gpuVramFraction)
                  ? scheme.onError
                  : scheme.onTertiary,
            ),
      fallbackBadges: [
        if (snapshot.gpuVramUsedMb != null && snapshot.gpuVramTotalMb != null)
          MetricBadge(
            '${formatMb(snapshot.gpuVramUsedMb!)}/${formatMb(snapshot.gpuVramTotalMb!)}',
          ),
      ],
    ),
    MetricSpec(
      kind: MetricKind.network,
      title: 'Red',
      accentColor: scheme.primary,
      // Bajada y subida, cada una con su color: el que ya usaba (primary/
      // tertiary) mientras esta tranquila, el de alerta cuando se acerca al
      // pico reciente.
      chart: MiniLineChart(
        series: [(netRxHistoryKb, rxColor), (netTxHistoryKb, txColor)],
        maxY: netMaxY,
        // Bajada hacia abajo, subida hacia arriba, desde una linea base
        // compartida -- pedido explicito, mismo espiritu que la senal de
        // vida de disco.
        mirrored: true,
      ),
      stackedChart: true,
      squareChart: true,
      stackedValues: true,
      badgesAreValues: true,
      valueText: '↓ ${formatBytesPerSec(snapshot.netRxBytesPerSec)}',
      valueColor: rxColor,
      subtitle: components.networkLabel,
      badges: [
        MetricBadge(
          '↑ ${formatBytesPerSec(snapshot.netTxBytesPerSec)}',
          color: txColor,
        ),
      ],
    ),
  ];
}

List<MetricBadge> _gpuBadges(HardwareSnapshot snapshot, ColorScheme scheme) {
  final parts = [
    // A mitad de camino entre el porcentaje (el valor principal) y el reloj
    // (anclado al borde derecho) -- pedido explicito.
    if (snapshot.gpuTempC != null)
      MetricBadge(
        '${snapshot.gpuTempC!.toStringAsFixed(0)}°C',
        color: isGpuHot(snapshot.gpuTempC) ? scheme.error : null,
        position: MetricBadgePosition.center,
      ),
    // La potencia, al lado de la temperatura: son las dos caras de lo mismo
    // --lo que la tarjeta esta quemando y lo caliente que eso la pone-- y
    // juntas se leen como un par. Sin decimales: la lectura de NVML se mueve
    // varios watts entre snapshots y el decimal solo agrega ruido.
    if (snapshot.gpuPowerWatts != null)
      MetricBadge(
        '${snapshot.gpuPowerWatts!.toStringAsFixed(0)} W',
        color: isGpuPowerHigh(snapshot.gpuPowerFraction) ? scheme.error : null,
        position: MetricBadgePosition.center,
      ),
    // El reloj actual, que sube y baja con la carga. La VRAM ya NO esta aca:
    // pasa a la barra de capacidad, donde la proporcion se ve sin dividir.
    // Anclado al borde derecho de la fila, pedido explicito.
    if (snapshot.gpuClockMhz != null)
      MetricBadge(
        '${snapshot.gpuClockMhz} MHz',
        color: isGpuFast(snapshot.gpuClockMhz) ? scheme.error : null,
        position: MetricBadgePosition.end,
      ),
  ];
  return parts.isEmpty ? [MetricBadge('Sin GPU detectada')] : parts;
}
