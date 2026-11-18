import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/chat_entry.dart';

/// Traza de una llamada a herramienta.
///
/// Deliberadamente discreta: es contexto de "que esta haciendo", no parte de la
/// respuesta. Pero **no** se puede ocultar del todo — mientras el asistente
/// revisa el disco o verifica un ejecutable pasan varios segundos en los que la
/// pantalla, si no, parece congelada.
///
/// `entry.result` puede traer mas de una linea (`agent.rs::with_detail`): la
/// primera es el conteo corto ("11 resultados"), el resto es el detalle real
/// (las rutas). Colapsada solo se ve la primera; expandir revela el resto —
/// antes ese detalle ni siquiera viajaba del lado Rust, ahora que hay donde
/// mostrarlo sin ensuciar la vista por defecto, tiene sentido mandarlo.
class ToolTraceTile extends StatefulWidget {
  const ToolTraceTile({super.key, required this.entry});

  final ToolEntry entry;

  @override
  State<ToolTraceTile> createState() => _ToolTraceTileState();
}

class _ToolTraceTileState extends State<ToolTraceTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = widget.entry;
    final color = entry.done && !entry.ok ? scheme.error : scheme.onSurfaceVariant;

    final resultLines = entry.result?.split('\n') ?? const [];
    final firstLine = resultLines.isEmpty ? null : resultLines.first;
    final detail = resultLines.length > 1 ? resultLines.skip(1).join('\n') : null;
    final canExpand = entry.done && detail != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs),
      child: InkWell(
        onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: entry.done
                      ? Icon(
                          entry.ok ? Icons.check_circle_outline : Icons.error_outline,
                          size: 14,
                          color: color,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: entry.summary,
                      children: [
                        if (firstLine != null && firstLine.isNotEmpty)
                          TextSpan(
                            text: ' · $firstLine',
                            style: TextStyle(color: color.withValues(alpha: 0.75)),
                          ),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canExpand)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: color.withValues(alpha: 0.6),
                  ),
              ],
            ),
            if (_expanded && detail != null)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.xxs, left: 24),
                padding: const EdgeInsets.all(AppSpacing.xs),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.xs),
                ),
                child: Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
