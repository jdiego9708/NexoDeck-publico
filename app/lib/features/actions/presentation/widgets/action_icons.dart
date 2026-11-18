import 'package:flutter/material.dart';

/// Set fijo de iconos seleccionables en el editor. `commandTemplate`/`icon`
/// se guardan como texto simple en Drift (ver tabla `actions_table.dart`),
/// asi que este mapa es la unica traduccion string -> `IconData`.
const Map<String, IconData> kActionIcons = {
  'bolt': Icons.bolt,
  'terminal': Icons.terminal,
  'content_paste': Icons.content_paste,
  'code': Icons.code,
  'videocam': Icons.videocam,
  'mic': Icons.mic,
  'storage': Icons.storage,
  'edit': Icons.edit,
  'folder': Icons.folder,
  'settings': Icons.settings,
};

IconData iconForName(String name) => kActionIcons[name] ?? Icons.bolt;

/// Paleta compartida entre el editor de acciones y el editor de grupos,
/// para no duplicarla en dos archivos.
const kActionColorPalette = [
  '#6366F1',
  '#22C55E',
  '#EF4444',
  '#F59E0B',
  '#0EA5E9',
  '#EC4899',
];

Color colorFromHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}
