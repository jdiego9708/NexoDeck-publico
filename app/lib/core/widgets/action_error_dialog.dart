import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Dialogo de error para cuando falla la ejecucion de una accion del deck
/// (app no encontrada, comando invalido, portapapeles inaccesible, etc.).
/// Entra amigable -- un mensaje humano, sin jerga tecnica -- y un boton
/// "Ver mas" revela el error real (`error.toString()`) para quien lo
/// necesite, sin exponerlo de primera mano.
Future<void> showActionErrorDialog(
  BuildContext context, {
  required String actionName,
  required Object error,
  required String friendlyMessage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ActionErrorDialog(
      actionName: actionName,
      error: error,
      friendlyMessage: friendlyMessage,
    ),
  );
}

class _ActionErrorDialog extends StatefulWidget {
  const _ActionErrorDialog({
    required this.actionName,
    required this.error,
    required this.friendlyMessage,
  });

  final String actionName;
  final Object error;
  final String friendlyMessage;

  @override
  State<_ActionErrorDialog> createState() => _ActionErrorDialogState();
}

class _ActionErrorDialogState extends State<_ActionErrorDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No se pudo ejecutar "${widget.actionName}"',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.friendlyMessage,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.error.toString(),
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: AppDuration.state,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(_expanded ? 'Ver menos' : 'Ver más'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
