import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexodeck/data/local/database.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/hardware_history_provider.dart';
import '../data/hardware_history_repository.dart';
import '../domain/history_series.dart';
import 'widgets/history_chart.dart';

/// Historial persistido de las metricas. Es la contraparte de la fila de
/// metricas en vivo: esa mantiene ~30 muestras en memoria y se pierde al
/// cerrar la app, esta lee `hardware_history`.
Future<void> showHistoryDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const Dialog(
      insetPadding: EdgeInsets.all(AppSpacing.xl),
      child: SizedBox(width: 900, height: 620, child: _HistoryView()),
    ),
  );
}

class _HistoryView extends ConsumerWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(historyRangeProvider);
    final history = ref.watch(hardwareHistoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                'Historial',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              for (final option in HistoryRange.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: range == option,
                    onSelected: (_) => ref
                        .read(historyRangeProvider.notifier)
                        .state = option,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('No se pudo leer el historial: $error')),
            data: (rows) => rows.isEmpty
                ? const EmptyState(
                    icon: Icons.timeline_outlined,
                    title: 'Todavía no hay historial',
                    // Se dice el ritmo real: si no, un usuario que abre esto
                    // a los 5 segundos de instalar la app cree que esta roto.
                    message: 'Se guarda una muestra cada 15 segundos mientras '
                        'NexoDeck está abierto. Volvé en un rato.',
                  )
                : _buildCharts(context, rows, scheme),
          ),
        ),
      ],
    );
  }

  Widget _buildCharts(
    BuildContext context,
    List<HardwareHistoryData> rows,
    ColorScheme scheme,
  ) {
    List<(DateTime, double?)> pick(double? Function(HardwareHistoryData) f) =>
        [for (final row in rows) (row.timestamp, f(row))];

    // La RAM se guarda en MB usados y totales; lo que interesa mirar en el
    // tiempo es el porcentaje (los totales no cambian).
    final ram = pick(
      (r) => r.ramTotalMb > 0 ? r.ramUsedMb / r.ramTotalMb * 100 : null,
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        HistoryChart(
          title: 'CPU',
          unit: '%',
          fixedMaxY: 100,
          series: [(bucketSeries(pick((r) => r.cpuUsage)), scheme.primary)],
        ),
        const SizedBox(height: AppSpacing.lg),
        HistoryChart(
          title: 'RAM',
          unit: '%',
          fixedMaxY: 100,
          series: [(bucketSeries(ram), scheme.tertiary)],
        ),
        const SizedBox(height: AppSpacing.lg),
        HistoryChart(
          title: 'GPU',
          unit: '%',
          fixedMaxY: 100,
          // Sin GPU legible las filas guardan `null` y `bucketSeries` los
          // descarta, asi que la tarjeta muestra su propio vacio en vez de
          // una linea plana en 0 que seria mentira.
          series: [(bucketSeries(pick((r) => r.gpuUsage)), scheme.secondary)],
        ),
        const SizedBox(height: AppSpacing.lg),
        HistoryChart(
          title: 'Red',
          unit: 'KB/s',
          series: [
            (
              bucketSeries(
                pick((r) => r.netRxBytesPerSec?.toDouble()),
              ).map((p) => HistoryPoint(p.at, p.value / 1024)).toList(),
              scheme.primary,
            ),
            (
              bucketSeries(
                pick((r) => r.netTxBytesPerSec?.toDouble()),
              ).map((p) => HistoryPoint(p.at, p.value / 1024)).toList(),
              scheme.error,
            ),
          ],
          legend: const ['Bajada', 'Subida'],
        ),
      ],
    );
  }
}
