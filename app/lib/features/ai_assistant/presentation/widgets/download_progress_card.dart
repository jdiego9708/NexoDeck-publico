import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text.dart';
import '../../domain/setup_progress.dart';

/// Progreso del setup.
///
/// Nunca inventa un porcentaje: cuando el paso no tiene progreso medible
/// (verificar, descomprimir, cargar el modelo) muestra una barra indeterminada.
/// Fingir un numero es peor que admitir que no se sabe — sobre todo en el
/// verificado de un archivo de varios GB, que son 30-60 s de silencio.
class DownloadProgressCard extends StatelessWidget {
  const DownloadProgressCard({super.key, required this.progress, this.onCancel});

  final SetupProgress progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (progress.fraction != null)
              Text(
                '${(progress.fraction! * 100).toStringAsFixed(0)}%',
                // Cifras tabulares obligatorias: cambia varias veces por
                // segundo y sin esto el numero "baila" de ancho.
                style: AppText.numeric(theme.textTheme.titleSmall),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          child: TweenAnimationBuilder<double>(
            // Sin animar, la barra da saltos visibles con cada evento.
            tween: Tween(begin: 0, end: progress.fraction ?? 0),
            duration: AppDuration.state,
            curve: AppCurves.standard,
            builder: (context, value, _) => LinearProgressIndicator(
              value: progress.fraction == null ? null : value,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                progress.detail ?? '',
                style: AppText.numeric(
                  theme.textTheme.bodySmall,
                )?.copyWith(color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (progress.speedLabel != null)
              Text(
                progress.speedLabel!,
                style: AppText.numeric(
                  theme.textTheme.bodySmall,
                )?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),

        if (onCancel != null) ...[
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancelar la descarga'),
            ),
          ),
          Text(
            // Que la descarga reanude es la diferencia entre "cancelo y pierdo
            // 8 GB" y "cancelo y sigo despues". Vale decirlo.
            'Lo que ya se bajo se conserva: si volves a empezar, retoma donde quedo.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
