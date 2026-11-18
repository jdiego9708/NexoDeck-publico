import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// Prueba de viabilidad del editor de notas en Android (paso 0).
///
/// Solo sirve para contestar una pregunta: **¿se puede escribir de verdad en
/// CodeMirror desde un móvil?** Tildes y ñ, el corrector, colocar el cursor con
/// el dedo, seleccionar, y la barra de formato con el teclado abierto.
///
/// La página va en línea, en un solo fichero (`melos run editor:build`), y sin
/// `window.ipc` carga sus datos de muestra: no habla con la PC.
///
/// Es temporal: se borra cuando el paso 0 esté decidido.
class EditorSpikeScreen extends StatefulWidget {
  const EditorSpikeScreen({super.key});

  @override
  State<EditorSpikeScreen> createState() => _EditorSpikeScreenState();
}

class _EditorSpikeScreenState extends State<EditorSpikeScreen> {
  final _controller = WebViewController();
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Una página mínima, para separar "el WebView no va en este teléfono" de "no
  /// va nuestra página". Si esto tampoco se ve, el problema no es el editor.
  static const _hello =
      '<!doctype html><html lang="es"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1"></head>'
      '<body style="font:16px system-ui;padding:24px">'
      '<h1>WebView vivo</h1>'
      '<p>Si lees esto, el motor pinta y ejecuta JavaScript.</p>'
      '<p><input id="t" style="font:16px system-ui;width:90%;padding:8px" '
      'placeholder="escribe aquí: ñandú, acción"></p>'
      '<script>document.getElementById("t").addEventListener("input",'
      'e=>nexodeckSpike.postMessage("input:"+e.target.value))</script>'
      '</body></html>';

  Future<void> _load() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.addJavaScriptChannel(
        'nexodeckSpike',
        onMessageReceived: (message) =>
            debugPrint('[spike] ${message.message}'),
      );
      await _controller.loadHtmlString(_hello);
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  /// La página del editor de verdad, 841 KB en una sola cadena.
  Future<void> _loadEditor() async {
    try {
      final html = await rootBundle.loadString('assets/editor/editor.html');
      debugPrint('[spike] cargando el editor, ${html.length} caracteres');
      // Sin `baseUrl`: todo viaja incrustado y no se pide nada más.
      await _controller.loadHtmlString(html);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  /// Vuelca al log lo que hay escrito en el editor: es lo que se compara con lo
  /// que se tecleó (`adb logcat -s flutter`).
  Future<void> _dump() async {
    await _controller.runJavaScript(
      "nexodeckSpike.postMessage(document.querySelector('.cm-content')?.innerText ?? 'sin editor')",
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba del editor'),
        actions: [
          IconButton(
            tooltip: 'Cargar el editor de verdad',
            onPressed: _ready ? _loadEditor : null,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Volcar el texto al log',
            onPressed: _ready ? _dump : null,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
