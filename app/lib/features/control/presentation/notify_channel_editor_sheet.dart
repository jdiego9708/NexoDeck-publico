import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/control_settings_controller.dart';
import '../domain/notify_channel.dart';

/// Crea o edita un canal de aviso.
///
/// El formulario es **generico a proposito**: un canal es un programa con sus
/// argumentos, y NexoDeck no sabe nada de WhatsApp. El boton de "script de
/// bash" es solo un atajo que rellena los campos con la invocacion correcta,
/// incluidos los dos detalles que ya costaron tiempo antes (la ruta 8.3 de Git
/// Bash y el `-l` que fija `HOME`).
Future<void> showNotifyChannelEditor(
  BuildContext context, {
  NotifyChannel? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NotifyChannelEditorSheet(existing: existing),
  );
}

class _NotifyChannelEditorSheet extends ConsumerStatefulWidget {
  const _NotifyChannelEditorSheet({this.existing});

  final NotifyChannel? existing;

  @override
  ConsumerState<_NotifyChannelEditorSheet> createState() =>
      _NotifyChannelEditorSheetState();
}

class _NotifyChannelEditorSheetState
    extends ConsumerState<_NotifyChannelEditorSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _programController;
  late final TextEditingController _argsController;
  late NotifyDelivery _delivery;
  late NotifyMinLevel _minLevel;
  late bool _enabled;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _programController = TextEditingController(text: existing?.program ?? '');
    _argsController = TextEditingController(
      text: existing?.args.join('\n') ?? '',
    );
    _delivery = existing?.delivery ?? NotifyDelivery.stdin;
    _minLevel = existing?.minLevel ?? NotifyMinLevel.milestone;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _programController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  Future<void> _fillFromBashScript() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const _ScriptPathDialog(),
    );
    if (path == null || path.trim().isEmpty) return;

    final preset = NotifyChannel.bashScript(
      id: 'temp',
      label: 'temp',
      scriptPath: path.trim(),
    );
    setState(() {
      _programController.text = preset.program;
      _argsController.text = preset.args.join('\n');
      _delivery = preset.delivery;
      if (_labelController.text.trim().isEmpty) {
        _labelController.text = 'Aviso por script';
      }
    });
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    final program = _programController.text.trim();
    if (label.isEmpty || program.isEmpty) {
      setState(() => _error = 'Hacen falta un nombre y un programa.');
      return;
    }

    final args = _argsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    // Un aviso que se interpola en una linea de shell funciona hasta el primer
    // mensaje con comillas. Se avisa aca, que es donde se puede corregir.
    if (_delivery == NotifyDelivery.argv &&
        !args.any((arg) => arg.trim() == '{{message}}') &&
        args.any((arg) => arg.contains('{{message}}'))) {
      setState(
        () => _error =
            'Poné {{message}} como argumento suelto, no dentro de otro: '
            'metido en una linea de shell se rompe con la primera comilla '
            'del mensaje.',
      );
      return;
    }
    if (_delivery == NotifyDelivery.argv &&
        !args.any((arg) => arg.contains('{{message}}'))) {
      setState(
        () => _error =
            'Con entrega por argumentos hace falta un {{message}}, o el aviso '
            'saldria vacio.',
      );
      return;
    }

    final channel = NotifyChannel(
      id: widget.existing?.id ??
          'ch_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      label: label,
      program: program,
      args: args,
      delivery: _delivery,
      minLevel: _minLevel,
      timeoutSecs: widget.existing?.timeoutSecs,
      enabled: _enabled,
    );

    await ref.read(controlSettingsControllerProvider).upsertChannel(channel);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? 'Canal de aviso nuevo' : 'Editar canal',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                helperText: 'Como se llama este destino, para vos',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _fillFromBashScript,
                icon: const Icon(Icons.terminal),
                label: const Text('Rellenar con un script de bash'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _programController,
              decoration: const InputDecoration(
                labelText: 'Programa',
                helperText: 'Ruta del ejecutable que manda el aviso',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _argsController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Argumentos, uno por linea',
                helperText:
                    'Con entrega por argumentos, {{message}} va en su propia '
                    'linea',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<NotifyDelivery>(
              segments: const [
                ButtonSegment(
                  value: NotifyDelivery.stdin,
                  label: Text('Por stdin'),
                ),
                ButtonSegment(
                  value: NotifyDelivery.argv,
                  label: Text('Por argumentos'),
                ),
              ],
              selected: {_delivery},
              onSelectionChanged: (values) =>
                  setState(() => _delivery = values.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Por stdin no hay nada que escapar: ningun shell llega a leer el '
              'texto del aviso.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<NotifyMinLevel>(
              initialValue: _minLevel,
              decoration: const InputDecoration(labelText: 'Nivel minimo'),
              items: const [
                DropdownMenuItem(
                  value: NotifyMinLevel.milestone,
                  child: Text('Todo: hitos y avisos criticos'),
                ),
                DropdownMenuItem(
                  value: NotifyMinLevel.always,
                  child: Text('Solo lo critico'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _minLevel = value ?? NotifyMinLevel.milestone),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Canal activo'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(onPressed: _save, child: const Text('Guardar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptPathDialog extends StatefulWidget {
  const _ScriptPathDialog();

  @override
  State<_ScriptPathDialog> createState() => _ScriptPathDialogState();
}

class _ScriptPathDialogState extends State<_ScriptPathDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ruta del script'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '/d/proyecto/scripts/avisar.sh',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'En formato de bash. El script tiene que aceptar el texto por su '
            'entrada estandar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Usar'),
        ),
      ],
    );
  }
}
