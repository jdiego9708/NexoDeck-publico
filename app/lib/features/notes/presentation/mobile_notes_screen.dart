import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/mobile_notes_host.dart';
import '../application/notes_sync_engine.dart';
import '../data/drift_mobile_notes_store.dart';
import '../domain/note_editor.dart';

/// Abre las notas en el móvil.
Future<void> showMobileNotesScreen(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MobileNotesScreen()));
}

/// Las notas en Android: **la misma página del editor que en la PC**, en un
/// WebView, contestada por [MobileNotesHost] contra la copia local del teléfono.
///
/// Funciona entera sin conexión (decisión del usuario): se lee y se escribe en el
/// espejo, y el motor de sincronización manda los cambios a la PC cuando hay
/// sesión. Arriba, una franja fina dice si hay conexión y cuánto falta por
/// mandar: sin ella, escribir sin cobertura parecería igual que escribir con
/// ella, y el usuario no sabría si la PC ya lo tiene.
class MobileNotesScreen extends ConsumerStatefulWidget {
  const MobileNotesScreen({super.key});

  @override
  ConsumerState<MobileNotesScreen> createState() => _MobileNotesScreenState();
}

class _MobileNotesScreenState extends ConsumerState<MobileNotesScreen> {
  final _controller = WebViewController();
  MobileNotesHost? _host;

  /// La página avisó de que escucha. Antes, lo que se mande se perdería: el
  /// `ready` vuelve a pedirlo todo de todos modos.
  bool _pageReady = false;
  String? _error;
  String _theme = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_host?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final engine = ref.read(notesSyncEngineProvider);
    if (engine == null) {
      setState(
        () => _error = 'Las notas solo están disponibles en el teléfono.',
      );
      return;
    }
    final host = MobileNotesHost(
      store: DriftMobileNotesStore(ref.read(notesMirrorDaoProvider), engine),
      send: _send,
    )..start();
    _host = host;
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      // El nombre lo busca `bridge.ts` (`window.nexodeckIpc`): Android pone el
      // canal en la página antes de que corran sus scripts.
      await _controller.addJavaScriptChannel(
        'nexodeckIpc',
        onMessageReceived: (message) => unawaited(_onPage(message.message)),
      );
      // Un enlace de la nota nunca navega dentro del WebView: la página es la
      // app, y salir de ella dejaría la pantalla en blanco.
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      final html = await rootBundle.loadString('assets/editor/editor.html');
      await _controller.loadHtmlString(html);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _onPage(String raw) async {
    if (raw.contains('"type":"ready"')) {
      _pageReady = true;
      _theme = '';
      _pushTheme();
    }
    await _host?.receive(raw);
  }

  void _send(Map<String, Object?> message) {
    if (!_pageReady || !mounted) return;
    final json = jsonEncode(message);
    // El JSON va como literal de objeto, igual que `script_for` en Rust: todo
    // JSON válido es JavaScript válido y no hay nada que escapar.
    unawaited(
      _controller
          .runJavaScript('window.nexodeck && window.nexodeck.receive($json);')
          .catchError((Object _) {}),
    );
  }

  /// Los colores del tema de la app, para que la página no parezca otra app.
  void _pushTheme() {
    if (!_pageReady || !mounted) return;
    final theme = NoteEditorTheme.fromColorScheme(
      Theme.of(context).colorScheme,
    );
    final payload = {
      'dark': theme.dark,
      'surface': theme.surface,
      'surfaceContainer': theme.surfaceContainer,
      'surfaceContainerHigh': theme.surfaceContainerHigh,
      'onSurface': theme.onSurface,
      'onSurfaceVariant': theme.onSurfaceVariant,
      'primary': theme.primary,
      'onPrimary': theme.onPrimary,
      'primaryContainer': theme.primaryContainer,
      'outlineVariant': theme.outlineVariant,
      'error': theme.error,
      'tertiary': theme.tertiary,
    };
    final encoded = jsonEncode(payload);
    if (encoded == _theme) return;
    _theme = encoded;
    _send({'type': 'theme', 'theme': payload});
  }

  /// Atrás de Android: desde una nota vuelve a la lista (lo decide la página);
  /// desde la lista, sale de Notas.
  Future<void> _back() async {
    try {
      final used = await _controller.runJavaScriptReturningResult(
        'window.nexodeck && window.nexodeck.back ? window.nexodeck.back() : false',
      );
      if (used == true || used.toString() == 'true') return;
    } catch (_) {
      // Sin página no hay nada que cerrar dentro: se sale.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Cambiar el tema de la app con la pantalla abierta llega a la página.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushTheme());
    final error = _error;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const _SyncStrip(),
              Expanded(
                child: error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(error, textAlign: TextAlign.center),
                        ),
                      )
                    : WebViewWidget(controller: _controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conexión, cola pendiente y choques, en una línea. Sin nada que decir (con
/// conexión, sin pendientes) no ocupa sitio.
class _SyncStrip extends ConsumerWidget {
  const _SyncStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(notesSyncStatusProvider);
    final dao = ref.watch(notesMirrorDaoProvider);
    final theme = Theme.of(context);
    return StreamBuilder<int>(
      stream: dao.watchPendingCount(),
      builder: (context, snapshot) {
        final pending = snapshot.data ?? 0;
        final (icon, text, color) = switch ((
          status.online,
          status.syncing,
          pending,
        )) {
          (false, _, 0) => (
            Icons.cloud_off_outlined,
            'Sin conexión con la PC: lo que escribas se guarda en el teléfono.',
            theme.colorScheme.onSurfaceVariant,
          ),
          (false, _, final n) => (
            Icons.cloud_off_outlined,
            'Sin conexión: $n ${n == 1 ? 'cambio espera' : 'cambios esperan'} para ir a la PC.',
            theme.colorScheme.tertiary,
          ),
          (true, true, _) => (
            Icons.sync,
            'Sincronizando con la PC…',
            theme.colorScheme.primary,
          ),
          (true, false, final n) when n > 0 => (
            Icons.cloud_upload_outlined,
            '$n ${n == 1 ? 'cambio pendiente' : 'cambios pendientes'} de mandar.',
            theme.colorScheme.tertiary,
          ),
          _ => (null, null, null),
        };
        if (text == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          color: color!.withValues(alpha: 0.08),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
