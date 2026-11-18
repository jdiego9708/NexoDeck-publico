import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sensor_helper_controller.dart';

/// Explica por que falta la temperatura del procesador y ofrece activarla.
///
/// Es la contracara del hueco: antes, una instalacion por usuario dejaba la
/// ficha de CPU sin grados y **nada** lo decia -- "no instalado", "sin
/// permisos" y "esta maquina no lo soporta" se veian los tres igual, o sea que
/// no se veian.
Future<void> showSensorHelperDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const _SensorHelperDialog(),
  );
}

class _SensorHelperDialog extends ConsumerStatefulWidget {
  const _SensorHelperDialog();

  @override
  ConsumerState<_SensorHelperDialog> createState() =>
      _SensorHelperDialogState();
}

class _SensorHelperDialogState extends ConsumerState<_SensorHelperDialog> {
  bool _installing = false;
  String? _message;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _message = null;
    });

    final result = await ref.read(sensorHelperControllerProvider).install();
    if (!mounted) return;

    setState(() {
      _installing = false;
      _message = switch (result) {
        SensorHelperInstallResult(error: final String error) => error,
        SensorHelperInstallResult(succeeded: true) => null,
        // Acepto el UAC pero el servicio no quedo corriendo. El detalle esta
        // en el log del ayudante, que es donde se puede ver el motivo real.
        _ =>
          'No se pudo activar. El detalle queda en '
              r'%ProgramData%\NexoDeck\sensors.log',
      };
    });

    if (result.succeeded && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(sensorHelperStatusProvider);

    return AlertDialog(
      title: const Text('Temperatura del procesador'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Windows no deja leer la temperatura del procesador a un programa '
            'normal: hace falta un componente con permisos de sistema. '
            'NexoDeck lo trae incluido, pero registrarlo necesita tu permiso '
            'una sola vez.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          status.when(
            loading: () => const Text('Comprobando…'),
            error: (error, _) => Text('No se pudo comprobar: $error'),
            data: (value) => Text(
              switch (value) {
                SensorHelperStatus.running => 'Ya está activo.',
                SensorHelperStatus.stopped =>
                  'Está instalado pero detenido. Se reactiva solo al reiniciar '
                      'el equipo.',
                SensorHelperStatus.notInstalled =>
                  'Ahora mismo no está instalado, por eso la ficha de CPU no '
                      'muestra grados.',
                SensorHelperStatus.unsupported =>
                  'En este sistema la temperatura la da el propio sistema '
                      'operativo: no hace falta activar nada.',
              },
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          // Solo tiene sentido ofrecerlo cuando falta de verdad. Con el
          // servicio corriendo, el boton no haria mas que pedir un UAC para
          // reinstalar lo mismo.
          onPressed:
              _installing ||
                  status.value == SensorHelperStatus.running ||
                  status.value == SensorHelperStatus.unsupported
              ? null
              : _install,
          icon: _installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.shield_outlined),
          label: Text(_installing ? 'Activando…' : 'Activar'),
        ),
      ],
    );
  }
}
