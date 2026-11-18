import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/manual_host.dart';

/// Lo que eligio el usuario en el dialogo.
///
/// Existe para poder distinguir tres desenlaces con un solo valor de
/// retorno: cancelar (el dialogo devuelve `null`), guardar una direccion
/// (`address` con valor) y **borrar la que habia** (`address` en `null`).
/// Con un `ManualHost?` pelado, borrar y cancelar serian el mismo `null`.
class ManualHostChoice {
  const ManualHostChoice(this.address);

  final ManualHost? address;
}

/// Pide la direccion fija de una PC (IP o nombre, con puerto opcional).
///
/// Se abre desde los dos lugares donde hace falta: la pantalla de pairing
/// --para emparejar sin que mDNS encuentre nada-- y la de reconexion, para
/// agregarsela despues a una PC ya emparejada.
Future<ManualHostChoice?> showManualHostDialog(
  BuildContext context, {
  ManualHost? initial,
  required String confirmLabel,
}) {
  return showDialog<ManualHostChoice>(
    context: context,
    builder: (_) => _ManualHostDialog(
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _ManualHostDialog extends StatefulWidget {
  const _ManualHostDialog({required this.initial, required this.confirmLabel});

  final ManualHost? initial;
  final String confirmLabel;

  @override
  State<_ManualHostDialog> createState() => _ManualHostDialogState();
}

class _ManualHostDialogState extends State<_ManualHostDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial?.display ?? '',
  );

  /// Error del ultimo intento de confirmar. Se limpia al escribir: marcar
  /// en rojo mientras el usuario todavia esta tipeando la direccion es
  /// ruido, no ayuda.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseManualHost(_controller.text);
    switch (parsed) {
      case ManualHostInvalid(:final message):
        setState(() => _error = message);
      case ManualHostParsed(:final value):
        Navigator.of(context).pop(ManualHostChoice(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Conectar por direccion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Para usar el deck fuera de tu red (con datos moviles), instala '
            'Tailscale en la PC y en el telefono, y escribi aca la direccion '
            '100.x que Tailscale le da a la PC.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.gutter),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Direccion de la PC',
              hintText: '100.101.102.103',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'El puerto es opcional: sin el se usa el $kDefaultTransportPort.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        // Solo cuando ya habia una: en el alta no hay nada que borrar y el
        // boton seria una tercera opcion muerta al lado de las dos reales.
        if (widget.initial != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const ManualHostChoice(null)),
            child: const Text('Borrar'),
          ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
