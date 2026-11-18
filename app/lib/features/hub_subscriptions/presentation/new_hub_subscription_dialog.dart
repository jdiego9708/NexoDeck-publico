import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/hub_subscriptions_provider.dart';

/// Atajos conocidos: los dos hubs que ya expone ExampleApi. El manager de
/// suscripciones es generico (URL/hub/metodo los pone el usuario) -- esto es
/// solo para no tener que escribirlos a mano cada vez.
class _KnownHub {
  const _KnownHub(this.label, this.hubPath, this.invokeMethod);
  final String label;
  final String hubPath;
  final String invokeMethod;
}

const _kKnownHubs = [
  _KnownHub(
    'Entrenamiento IA (ExampleApi)',
    '/hubs/plant-training-progress',
    'SubscribeToJob',
  ),
  _KnownHub(
    'Deteccion IA (ExampleApi)',
    '/hubs/plant-detection-progress',
    'SubscribeToJob',
  ),
];

Future<void> showNewHubSubscriptionDialog(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _NewHubSubscriptionSheet(),
  );
}

enum _Mode { signalR, rawWebSocket }

class _NewHubSubscriptionSheet extends ConsumerStatefulWidget {
  const _NewHubSubscriptionSheet();

  @override
  ConsumerState<_NewHubSubscriptionSheet> createState() =>
      _NewHubSubscriptionSheetState();
}

class _NewHubSubscriptionSheetState
    extends ConsumerState<_NewHubSubscriptionSheet> {
  final _formKey = GlobalKey<FormState>();
  _Mode _mode = _Mode.signalR;
  _KnownHub? _preset = _kKnownHubs.first;

  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController(
    text: 'http://localhost:5242',
  );
  final _hubPathController = TextEditingController(
    text: _kKnownHubs.first.hubPath,
  );
  final _invokeMethodController = TextEditingController(
    text: _kKnownHubs.first.invokeMethod,
  );
  final _jobIdController = TextEditingController();
  final _wsUrlController = TextEditingController(text: 'ws://');
  bool _allowInvalidCert = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _hubPathController.dispose();
    _invokeMethodController.dispose();
    _jobIdController.dispose();
    _wsUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Nueva suscripción',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(
                      value: _Mode.signalR,
                      label: Text('Hub SignalR'),
                      icon: Icon(Icons.podcasts_rounded),
                    ),
                    ButtonSegment(
                      value: _Mode.rawWebSocket,
                      label: Text('WebSocket crudo'),
                      icon: Icon(Icons.cable_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_mode == _Mode.signalR) ..._signalRFields() else ..._rawWebSocketFields(),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aceptar certificado TLS inválido'),
                  subtitle: const Text(
                    'Solo para https con certificado autofirmado de '
                    'desarrollo. Apagado, la conexión se rechaza si el '
                    'certificado no es de confianza.',
                  ),
                  value: _allowInvalidCert,
                  onChanged: (v) => setState(() => _allowInvalidCert = v),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text(
                      'Suscribirse',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _signalRFields() => [
    DropdownButtonFormField<_KnownHub?>(
      initialValue: _preset,
      decoration: const InputDecoration(labelText: 'Hub (atajo, opcional)'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Personalizado')),
        for (final hub in _kKnownHubs)
          DropdownMenuItem(value: hub, child: Text(hub.label)),
      ],
      onChanged: (hub) => setState(() {
        _preset = hub;
        if (hub != null) {
          _hubPathController.text = hub.hubPath;
          _invokeMethodController.text = hub.invokeMethod;
        }
      }),
    ),
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      controller: _baseUrlController,
      decoration: const InputDecoration(
        labelText: 'URL base',
        hintText: 'http://localhost:5242',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
    ),
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      controller: _hubPathController,
      decoration: const InputDecoration(
        labelText: 'Ruta del hub',
        hintText: '/hubs/plant-training-progress',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
    ),
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      controller: _invokeMethodController,
      decoration: const InputDecoration(
        labelText: 'Método a invocar',
        hintText: 'SubscribeToJob',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
    ),
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      controller: _jobIdController,
      decoration: const InputDecoration(
        labelText: 'Job id (argumento del método)',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
    ),
  ];

  List<Widget> _rawWebSocketFields() => [
    TextFormField(
      controller: _wsUrlController,
      decoration: const InputDecoration(
        labelText: 'URL del WebSocket',
        hintText: 'ws://host:puerto/ruta',
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? 'Requerido'
          : (!v.startsWith('ws://') && !v.startsWith('wss://'))
          ? 'Tiene que empezar con ws:// o wss://'
          : null,
    ),
  ];

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repository = ref.read(hubSubscriptionsRepositoryProvider);
    try {
      if (_mode == _Mode.signalR) {
        await repository.createSignalR(
          name: _nameController.text.trim(),
          baseUrl: _baseUrlController.text.trim(),
          hubPath: _hubPathController.text.trim(),
          invokeMethod: _invokeMethodController.text.trim(),
          invokeArgs: [_jobIdController.text.trim()],
          allowInvalidCert: _allowInvalidCert,
        );
      } else {
        await repository.createRawWebSocket(
          name: _nameController.text.trim(),
          wsUrl: _wsUrlController.text.trim(),
          allowInvalidCert: _allowInvalidCert,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
