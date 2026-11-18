import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/interactive_card.dart';
import '../../domain/docs_inbox.dart';

/// Una operacion de la propuesta: donde cae, y el antes y el despues con unas
/// lineas de contexto. El texto lo calcula Rust; aca solo se pinta.
class OperationDiffCard extends StatefulWidget {
  const OperationDiffCard({super.key, required this.operation});

  final DocOperation operation;

  @override
  State<OperationDiffCard> createState() => _OperationDiffCardState();
}

class _OperationDiffCardState extends State<OperationDiffCard> {
  /// Ver el despues renderizado en vez del texto. El texto es lo que se revisa;
  /// el renderizado sirve para ver si una tabla o una lista quedo bien armada.
  bool _rendered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final op = widget.operation;

    return InteractiveCard(
      radius: AppRadius.chip,
      accent: op.destructive ? theme.colorScheme.error : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_iconFor(op.kind), size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${op.kindLabel} · ${op.file}:${op.line}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _rendered = !_rendered),
                  child: Text(_rendered ? 'Ver texto' : 'Ver renderizado'),
                ),
              ],
            ),
            if (op.title.trim().isNotEmpty)
              Text(op.title, style: theme.textTheme.bodySmall),
            if (op.destructive)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Borra ${op.removedLines} líneas. Revisa que lo que desaparece '
                  'ya no sea cierto.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (_rendered)
              _Framed(
                tone: theme.colorScheme.primary,
                child: MarkdownBody(data: op.after, selectable: true),
              )
            else ...[
              _Block(
                label: 'Antes (−${op.removedLines})',
                text: op.before,
                tone: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Block(
                label: 'Después (+${op.addedLines})',
                text: op.after,
                tone: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
    'insert_section_top' => Icons.playlist_add_outlined,
    'set_last_updated' => Icons.event_outlined,
    'replace_exact' => Icons.find_replace_outlined,
    'append_under_heading' => Icons.subdirectory_arrow_right_outlined,
    'add_section' => Icons.post_add_outlined,
    'set_frontmatter_key' => Icons.sell_outlined,
    _ => Icons.edit_note_outlined,
  };
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.text, required this.tone});

  final String label;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
        const SizedBox(height: AppSpacing.xxs),
        _Framed(
          tone: tone,
          child: SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['Courier New', 'monospace'],
            ),
          ),
        ),
      ],
    );
  }
}

/// Un recuadro tenue y con altura acotada: una seccion nueva del diario puede
/// traer cien lineas, y sin tope empujaria todo lo demas fuera del dialogo.
class _Framed extends StatelessWidget {
  const _Framed({required this.tone, required this.child});

  final Color tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.badge),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}
