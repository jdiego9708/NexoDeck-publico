import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/action_error_dialog.dart';
import '../application/actions_provider.dart';
import '../domain/deck_export.dart';

/// Extension y filtro del selector de archivos. Un tipo propio (`.nexodeck`)
/// haria que el archivo no se pueda abrir con un editor de texto sin
/// renombrarlo; es JSON y conviene que se vea como tal.
const _deckTypeGroup = XTypeGroup(
  label: 'Deck de NexoDeck',
  extensions: ['json'],
);

/// Exporta el deck completo a un archivo elegido por el usuario.
Future<void> exportDeck(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final suggested =
      'nexodeck-deck-${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}.json';

  final location = await getSaveLocation(
    suggestedName: suggested,
    acceptedTypeGroups: const [_deckTypeGroup],
  );
  if (location == null) return; // cancelado
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final json = await ref
        .read(deckTransferRepositoryProvider)
        .exportToJson(at: now);
    await XFile.fromData(
      // `utf8` explicito: el nombre de una accion puede tener acentos o
      // emojis (la semilla trae "🔴 EN VIVO"), y guardar en la codificacion
      // por defecto del sistema los rompe al reimportar en otra maquina.
      Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    ).saveTo(location.path);

    messenger.showSnackBar(
      SnackBar(content: Text('Deck exportado a ${location.path}')),
    );
  } catch (e) {
    if (!context.mounted) return;
    await showActionErrorDialog(
      context,
      actionName: 'Exportar deck',
      error: e,
      friendlyMessage: 'No se pudo escribir el archivo. Revisá que la '
          'carpeta exista y que tengas permiso de escritura.',
    );
  }
}

/// Importa un deck desde un archivo. **Agrega, no reemplaza.**
Future<void> importDeck(BuildContext context, WidgetRef ref) async {
  final file = await openFile(acceptedTypeGroups: const [_deckTypeGroup]);
  if (file == null) return; // cancelado
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final content = await file.readAsString();
    final result = await ref
        .read(deckTransferRepositoryProvider)
        .importFromJson(content);

    final parts = <String>[
      '${result.actions} ${result.actions == 1 ? 'acción' : 'acciones'}',
      if (result.groups > 0)
        '${result.groups} ${result.groups == 1 ? 'grupo' : 'grupos'}',
    ];
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Importado: ${parts.join(' y ')}.'
          // Los pasos descartados se dicen SIEMPRE: una macro que perdió
          // pasos en silencio es peor que una que no se importa.
          '${result.droppedSteps > 0 ? ' Se descartaron '
                    '${result.droppedSteps} paso(s) de macro que apuntaban a '
                    'acciones que el archivo no traía.' : ''}',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  } on DeckImportException catch (e) {
    if (!context.mounted) return;
    await showActionErrorDialog(
      context,
      actionName: 'Importar deck',
      error: e,
      friendlyMessage: e.message,
    );
  } catch (e) {
    if (!context.mounted) return;
    await showActionErrorDialog(
      context,
      actionName: 'Importar deck',
      error: e,
      friendlyMessage: 'No se pudo leer el archivo.',
    );
  }
}
