import 'package:flutter/material.dart';
import 'package:nexodeck/data/local/tables/action_parameters_table.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/action_param.dart';

/// Pide los valores de [parameters] antes de ejecutar una accion.
/// Devuelve `null` si el usuario cancela.
///
/// Toma una lista de parametros y no una `DeckAction` porque lo usan **las
/// dos puntas**: la PC le pasa `promptParametersFor(...)` (que para una
/// macro es la union de los parametros de sus pasos), y Android le pasa los
/// parametros que vinieron en el `ActionsCatalog`, donde no existe ninguna
/// `DeckAction` local que los contenga.
Future<Map<String, String>?> showParameterPromptDialog(
  BuildContext context, {
  required String title,
  required List<ActionParam> parameters,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) =>
        _ParameterPromptDialog(title: title, parameters: parameters),
  );
}

class _ParameterPromptDialog extends StatefulWidget {
  const _ParameterPromptDialog({required this.title, required this.parameters});

  final String title;
  final List<ActionParam> parameters;

  @override
  State<_ParameterPromptDialog> createState() => _ParameterPromptDialogState();
}

class _ParameterPromptDialogState extends State<_ParameterPromptDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final param in widget.parameters)
      param.key: TextEditingController(text: param.defaultValue ?? ''),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop({
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        // Ancho acotado, no fijo: este dialogo tambien se abre en el
        // telefono, donde 360 px fijos se desbordan en pantallas angostas.
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, param) in widget.parameters.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ParamField(
                    param: param,
                    controller: _controllers[param.key]!,
                    autofocus: index == 0,
                    // El ultimo campo cierra el dialogo con Enter; los
                    // anteriores pasan al siguiente. En una accion de un
                    // solo parametro esto convierte "escribir y Enter" en
                    // todo el flujo.
                    isLast: index == widget.parameters.length - 1,
                    onSubmitted: _submit,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Ejecutar')),
      ],
    );
  }
}

class _ParamField extends StatelessWidget {
  const _ParamField({
    required this.param,
    required this.controller,
    required this.autofocus,
    required this.isLast,
    required this.onSubmitted,
  });

  final ActionParam param;
  final TextEditingController controller;
  final bool autofocus;
  final bool isLast;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (param.inputType == ParamInputType.select) {
      final options = param.options;
      return DropdownButtonFormField<String>(
        initialValue: options.contains(controller.text) ? controller.text : null,
        decoration: InputDecoration(labelText: param.label),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) => controller.text = value ?? '',
      );
    }

    return TextField(
      controller: controller,
      autofocus: autofocus,
      decoration: InputDecoration(labelText: param.label),
      keyboardType: param.inputType == ParamInputType.number
          ? TextInputType.number
          : TextInputType.text,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onSubmitted: (_) {
        if (isLast) onSubmitted();
      },
    );
  }
}
