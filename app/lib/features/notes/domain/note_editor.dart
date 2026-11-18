import 'package:flutter/material.dart';
import 'package:nexodeck/src/rust/api/editor.dart' as bridge;

/// Si se puede abrir la ventana del editor en esta máquina.
class NoteEditorAvailability {
  const NoteEditorAvailability({
    required this.available,
    this.version,
    this.reason,
  });

  factory NoteEditorAvailability.fromBridge(bridge.EditorAvailability item) =>
      NoteEditorAvailability(
        available: item.available,
        version: item.version,
        reason: item.reason,
      );

  final bool available;

  /// La versión de WebView2 Runtime.
  final String? version;

  /// Por qué no, dicho para el usuario.
  final String? reason;
}

enum NoteEditorEventKind {
  opened,
  saved,
  conflict,
  closed,
  error,

  /// La ventana de notas pide el buzón: las propuestas se aprueban en la app.
  showInbox,

  /// Un tipo que esta versión de la app no conoce.
  unknown;

  static NoteEditorEventKind parse(String value) => switch (value) {
    'opened' => opened,
    'saved' => saved,
    'conflict' => conflict,
    'closed' => closed,
    'error' => error,
    'show_inbox' => showInbox,
    _ => unknown,
  };
}

class NoteEditorEvent {
  const NoteEditorEvent({
    required this.seq,
    required this.kind,
    this.path,
    this.detail,
  });

  factory NoteEditorEvent.fromBridge(bridge.EditorEventItem item) =>
      NoteEditorEvent(
        seq: item.seq,
        kind: NoteEditorEventKind.parse(item.kind),
        path: item.path,
        detail: item.detail,
      );

  final int seq;
  final NoteEditorEventKind kind;
  final String? path;
  final String? detail;
}

/// Los colores de la app para la ventana del editor, que es una página web y
/// no hereda el tema de Flutter.
class NoteEditorTheme {
  const NoteEditorTheme({
    required this.dark,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.outlineVariant,
    required this.error,
    required this.tertiary,
  });

  factory NoteEditorTheme.fromColorScheme(ColorScheme scheme) =>
      NoteEditorTheme(
        dark: scheme.brightness == Brightness.dark,
        surface: hexColor(scheme.surface),
        surfaceContainer: hexColor(scheme.surfaceContainer),
        surfaceContainerHigh: hexColor(scheme.surfaceContainerHigh),
        onSurface: hexColor(scheme.onSurface),
        onSurfaceVariant: hexColor(scheme.onSurfaceVariant),
        primary: hexColor(scheme.primary),
        onPrimary: hexColor(scheme.onPrimary),
        primaryContainer: hexColor(scheme.primaryContainer),
        outlineVariant: hexColor(scheme.outlineVariant),
        error: hexColor(scheme.error),
        tertiary: hexColor(scheme.tertiary),
      );

  final bool dark;
  final String surface;
  final String surfaceContainer;
  final String surfaceContainerHigh;
  final String onSurface;
  final String onSurfaceVariant;
  final String primary;
  final String onPrimary;
  final String primaryContainer;
  final String outlineVariant;
  final String error;
  final String tertiary;

  bridge.EditorThemeDto toBridge() => bridge.EditorThemeDto(
    dark: dark,
    surface: surface,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    outlineVariant: outlineVariant,
    error: error,
    tertiary: tertiary,
  );
}

/// `#RRGGBB`, sin alfa: la página del editor solo acepta ese formato.
String hexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// La ruta que escribió el usuario para una nota nueva, relativa a la bóveda y
/// con `.md`; `null` si no vale.
///
/// Rust vuelve a comprobarla (y además los junctions): esto es para decirlo en
/// el diálogo y no con un error después de pulsar.
String? normalizeNewNotePath(String input) {
  var path = input.trim().replaceAll(r'\', '/');
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  if (path.toLowerCase().endsWith('.md')) {
    path = path.substring(0, path.length - 3);
  }
  if (path.isEmpty || path.contains(':')) {
    return null;
  }
  final segments = path.split('/');
  final invalid = segments.any(
    (segment) =>
        segment.trim().isEmpty || segment == '..' || segment.startsWith('.'),
  );
  return invalid ? null : '$path.md';
}

/// Una ruta a partir del título, mientras el usuario no escriba la suya.
String suggestNotePath(String title) {
  final slug = title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[<>:"/\\|?*#^\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), '-');
  return slug;
}

/// Está en `privado/` (a cualquier nivel): ningún agente la lee y no entra en el
/// índice, así que no tiene detalle en el diálogo.
bool isPrivateNotePath(String path) =>
    path.replaceAll(r'\', '/').toLowerCase().split('/').contains('privado');
