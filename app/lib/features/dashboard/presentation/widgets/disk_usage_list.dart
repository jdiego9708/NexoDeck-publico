import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../domain/hardware_snapshot.dart';
import '../../domain/metric_thresholds.dart';
import 'disk_heartbeat.dart';
import 'format_utils.dart';

/// Fraccion a partir de la cual un disco se pinta en el color de alerta. No
/// es decorativo: un disco al 95% es un problema que hay que ver de un
/// vistazo, y con el color del resto se pierde entre las demas barras.
const _kAlmostFullFraction = 0.9;

/// Lista de discos, una fila por disco: identificador, etiqueta del volumen,
/// barra de progreso y `usado/total`.
///
/// Es el cuerpo que dibuja la tile de almacenamiento cuando tiene espacio
/// (ver `MetricSpec.expandedBuilder`). Reemplaza al agregado, que solo podia
/// decir cuanto queda **entre todos** los discos -- y "2.1 TB de 2.3 TB" no
/// sirve para saber cual de los tres esta por llenarse.
///
/// **Se adapta al ancho, no al modo.** Con lugar (la franja, el panel
/// maximizado) cada disco entra en una linea; en el riel lateral, donde hay
/// ~190 dp, la etiqueta y las cifras van arriba y la barra debajo. Meter las
/// tres cosas en una linea a ese ancho dejaba la barra en un hilo y la
/// etiqueta sin lugar.
///
/// **Scrollea en vez de comprimir.** Con cuatro o cinco discos las filas no
/// entran en el alto de la tile; achicarlas dejaria la barra y la cifra
/// ilegibles, que es justo lo que la lista venia a mostrar. Mismo criterio
/// que el riel de metricas en un telefono bajo.
class DiskUsageList extends StatelessWidget {
  const DiskUsageList({
    super.key,
    required this.disks,
    required this.accentColor,
    this.readHistoryKb = const {},
    this.writeHistoryKb = const {},
  });

  final List<DiskUsage> disks;
  final Color accentColor;

  /// Historial reciente de actividad, por `mountPoint`. Lo mantiene quien
  /// llama (`MetricsRow`/`ConnectedDeviceScreen`, mismo patron que
  /// `cpuHistory`), no esta lista: un disco sin entrada todavia (recien
  /// aparecido) simplemente dibuja la senal de vida plana.
  final Map<String, List<double>> readHistoryKb;
  final Map<String, List<double>> writeHistoryKb;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = constraints.maxWidth >= AppSizes.diskRowInlineWidth;
        return ListView.builder(
          padding: EdgeInsets.zero,
          // Todas las filas miden lo mismo: con `itemExtent` el `ListView` no
          // necesita medir hijo por hijo y no scrollea si entran todos.
          itemExtent: inline
              ? AppSizes.diskRowExtent
              : AppSizes.diskRowStackedExtent,
          itemCount: disks.length,
          itemBuilder: (context, index) {
            final disk = disks[index];
            return _DiskRow(
              disk: disk,
              accentColor: accentColor,
              inline: inline,
              readHistoryKb: readHistoryKb[disk.mountPoint] ?? const [],
              writeHistoryKb: writeHistoryKb[disk.mountPoint] ?? const [],
            );
          },
        );
      },
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({
    required this.disk,
    required this.accentColor,
    required this.inline,
    required this.readHistoryKb,
    required this.writeHistoryKb,
  });

  final DiskUsage disk;
  final Color accentColor;
  final bool inline;
  final List<double> readHistoryKb;
  final List<double> writeHistoryKb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = disk.usedFraction;
    final barColor = fraction >= _kAlmostFullFraction
        ? theme.colorScheme.error
        : accentColor;

    final bar = _UsageBar(fraction: fraction, color: barColor);
    // `null` es "esta PC no sabe medirlo" (fuera de Windows, o un volumen sin
    // letra), no "reposo": ahi no se dibuja nada en vez de mentir con una
    // linea plana que parece un dato real.
    final heartbeat = disk.readBytesPerSec == null
        ? null
        : DiskHeartbeat(
            readHistoryKb: readHistoryKb,
            writeHistoryKb: writeHistoryKb,
            color: accentColor,
          );
    // `null` es "no se pudo leer" (fuera de Windows, o un disco que no
    // publica el atributo), no "frio": mismo criterio que la senal de vida.
    final temperature = disk.tempC == null
        ? null
        : _Temperature(
            tempC: disk.tempC!,
            hot: isDiskHot(disk.kind, disk.tempC),
            stale: disk.isTempStale,
            theme: theme,
          );
    final usage = Text(
      formatMbPair(disk.usedMb, disk.totalMb),
      // Cifras tabulares por el mismo motivo que el valor de la metrica: el
      // usado se actualiza solo y sin esto la fila "baila". Un punto mas chico
      // que el resto: acompana a la barra, que es la que cuenta la historia.
      style: AppText.numeric(
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // Identificador y etiqueta, sin la senal de vida: esa va anclada al
    // borde derecho de la fila (ver `row` abajo), no pegada al nombre --
    // ahi es donde sobra espacio, tanto en la franja ancha como en el riel.
    final identifier = [
      SizedBox(
        width: AppSizes.diskMountPointWidth,
        child: _MountPoint(disk: disk, theme: theme),
      ),
      // La etiqueta solo cuando hay lugar y existe: un `C:` recien
      // instalado no tiene ninguna.
      if (disk.label.isNotEmpty) ...[
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: _Label(disk: disk, theme: theme)),
      ],
    ];

    final row = inline
        ? Row(
            children: [
              ...identifier,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: bar),
              const SizedBox(width: AppSpacing.sm),
              usage,
              if (temperature != null) ...[
                const SizedBox(width: AppSpacing.xs),
                temperature,
              ],
              if (heartbeat != null) ...[
                const SizedBox(width: AppSpacing.sm),
                heartbeat,
              ],
            ],
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ...identifier,
                    // Empuja lo que sigue al borde derecho de ESTA fila (la
                    // del identificador), dejando la etiqueta anclada a la
                    // izquierda -- `Flexible` en la etiqueta no estira, solo
                    // evita desbordar, asi que hace falta este relleno.
                    // Incondicional desde que hay dos cosas que pueden caer
                    // aca: metido dentro del `if` del latido, un disco con
                    // temperatura pero sin latido quedaba pegado al nombre.
                    const Spacer(),
                    ?temperature,
                    if (heartbeat != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      heartbeat,
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                // La cifra va **al final de su barra** y no arriba con la
                // etiqueta: asi se lee donde termina el llenado, que es donde
                // el ojo ya esta mirando.
                Row(
                  children: [
                    Expanded(child: bar),
                    const SizedBox(width: AppSpacing.xs),
                    // Se achica antes que desbordar: en el riel el ancho lo
                    // manda el nombre del volumen, que puede ser cualquier
                    // cosa.
                    FittedBox(fit: BoxFit.scaleDown, child: usage),
                  ],
                ),
              ],
            ),
          );

    // El tipo de medio y el porcentaje exacto son datos de consulta, no de
    // vistazo: no compiten por el ancho de la fila.
    return Tooltip(message: _tooltip(fraction), child: row);
  }

  String _tooltip(double fraction) {
    final name = disk.label.isEmpty ? disk.mountPoint : disk.label;
    final kind = switch (disk.kind) {
      DiskMediaKind.ssd => 'SSD',
      DiskMediaKind.hdd => 'HDD',
      DiskMediaKind.unknown => 'Tipo desconocido',
    };
    final percent = (fraction * 100).round();
    // Ya son tres lineas y una es condicional: concatenar a mano se vuelve
    // ilegible.
    return [
      '$name · $kind',
      '${formatMb(disk.usedMb)} de ${formatMb(disk.totalMb)} usados ($percent%)',
      // Dos particiones del mismo disco muestran el mismo numero, y aca hay
      // lugar para decir por que: el sensor es del disco fisico, no del
      // volumen.
      if (disk.tempC != null)
        '${disk.tempC!.toStringAsFixed(0)}°C (sensor del disco fisico)'
            // Un disco dormido no contesta la consulta de temperatura, y
            // despertarlo solo para medirlo seria peor que mostrar la
            // ultima lectura conocida.
            '${disk.isTempStale ? ', hace ${_ageLabel(disk.tempAgeSecs!)} (disco en reposo)' : ''}',
    ].join('\n');
  }
}

/// "hace 4 min", "hace 2 h". Se redondea a la baja a proposito: decir menos
/// tiempo del que paso es peor que decir mas.
String _ageLabel(int seconds) {
  if (seconds < 60) return '$seconds s';
  if (seconds < 3600) return '${seconds ~/ 60} min';
  if (seconds < 86400) return '${seconds ~/ 3600} h';
  return '${seconds ~/ 86400} d';
}

class _MountPoint extends StatelessWidget {
  const _MountPoint({required this.disk, required this.theme});

  final DiskUsage disk;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      disk.mountPoint,
      style: AppText.numeric(
        theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Temperatura del disco. Mismo cuerpo chico y atenuado que la capacidad: es
/// un dato de acompanamiento, no el que cuenta la historia de la fila --
/// salvo cuando cruza el umbral de SU medio (un plato y una memoria flash no
/// sufren a la misma temperatura, ver `metric_thresholds`), y ahi pasa al
/// color de alerta.
class _Temperature extends StatelessWidget {
  const _Temperature({
    required this.tempC,
    required this.hot,
    required this.stale,
    required this.theme,
  });

  final double tempC;
  final bool hot;

  /// Lectura vieja: el disco se durmio y ya no contesta. Se atenua en vez de
  /// desaparecer -- un disco dormido no se calienta, asi que su ultima lectura
  /// sigue siendo la mejor verdad disponible, pero presentarla igual que una
  /// recien medida seria mentir.
  final bool stale;

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${tempC.toStringAsFixed(0)}°C',
      // Cifras tabulares por lo mismo que la capacidad: se actualiza sola y
      // sin esto la fila "baila" al pasar de 9 a 10 grados.
      style: AppText.numeric(
        theme.textTheme.labelSmall?.copyWith(
          color: hot
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: stale ? 0.45 : 1,
                ),
          fontSize: 10,
          fontWeight: hot ? FontWeight.w700 : null,
        ),
      ),
      maxLines: 1,
    );
  }
}

/// Etiqueta del volumen, atenuada: identifica al disco pero no compite con
/// la letra de unidad, que es lo que el usuario busca primero.
class _Label extends StatelessWidget {
  const _Label({required this.disk, required this.theme});

  final DiskUsage disk;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      disk.label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Barra de progreso propia y no `LinearProgressIndicator`: hace falta
/// controlar el alto exacto, el radio y el color del track para que la fila
/// entre en [AppSizes.diskRowExtent] y se vea de la misma familia que el
/// resto de los charts.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSizes.diskBarHeight / 2);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: AppSizes.diskBarHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            // Animada por el mismo motivo que los charts: el valor cambia una
            // vez por segundo y un salto seco llama mas la atencion que el
            // dato.
            Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: AppDuration.chart,
                curve: AppCurves.standard,
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
