import 'dart:math';

import 'package:flutter/material.dart';

/// Fondo animado tipo "red neuronal" para las pantallas de escritorio:
/// nodos con leve deriva sinusoidal y lineas entre nodos cercanos, todo a
/// muy baja opacidad para no competir con el contenido. Ver
/// `main.dart::MyApp.build` (parametro `builder:` de `MaterialApp`) para
/// donde se monta -- solo desktop, gateado por `isDesktopWindowPlatform`.
class NeuralBackground extends StatefulWidget {
  const NeuralBackground({super.key});

  static const _nodeCount = 34;
  static const _connectionThreshold = 0.20; // fraccion de la diagonal
  static const _cycleDuration = Duration(seconds: 12);
  static const _minDrift = 2.0;
  static const _maxDrift = 6.0;

  @override
  State<NeuralBackground> createState() => _NeuralBackgroundState();
}

class _NeuralNode {
  const _NeuralNode({
    required this.x,
    required this.y,
    required this.phase,
    required this.driftRadius,
  });

  final double x;
  final double y;
  final double phase;
  final double driftRadius;
}

class _NeuralBackgroundState extends State<NeuralBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_NeuralNode> _nodes;
  late final List<(int, int)> _connections;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: NeuralBackground._cycleDuration,
    )..repeat(reverse: true);

    final random = Random(42);
    _nodes = List.generate(NeuralBackground._nodeCount, (_) {
      return _NeuralNode(
        x: random.nextDouble(),
        y: random.nextDouble(),
        phase: random.nextDouble() * 2 * pi,
        driftRadius:
            NeuralBackground._minDrift +
            random.nextDouble() *
                (NeuralBackground._maxDrift - NeuralBackground._minDrift),
      );
    });

    _connections = [
      for (var i = 0; i < _nodes.length; i++)
        for (var j = i + 1; j < _nodes.length; j++)
          if (_distance(_nodes[i], _nodes[j]) <
              NeuralBackground._connectionThreshold)
            (i, j),
    ];
  }

  static double _distance(_NeuralNode a, _NeuralNode b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _NeuralNetworkPainter(
            nodes: _nodes,
            connections: _connections,
            t: _controller.value,
            baseColor: scheme.surface,
            lineColor: scheme.outlineVariant,
            nodeColor: scheme.primary,
            isDark: scheme.brightness == Brightness.dark,
            repaint: _controller,
          ),
        );
      },
    );
  }
}

class _NeuralNetworkPainter extends CustomPainter {
  _NeuralNetworkPainter({
    required this.nodes,
    required this.connections,
    required this.t,
    required this.baseColor,
    required this.lineColor,
    required this.nodeColor,
    required this.isDark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_NeuralNode> nodes;
  final List<(int, int)> connections;
  final double t;

  /// Relleno opaco de base (`scheme.surface`) -- el `Scaffold` de cada
  /// pantalla de escritorio queda transparente para que este fondo se
  /// vea, asi que este painter es quien debe pintar el color de
  /// superficie real; sin esto, las zonas sin contenido mostrarian el
  /// color base de la ventana nativa (negro) en vez del tema.
  final Color baseColor;
  final Color lineColor;
  final Color nodeColor;
  final bool isDark;

  /// Los alphas se diferencian por luminancia: en oscuro `0.12` casi no se
  /// ve, y en claro el mismo valor resulta demasiado sucio sobre el blanco.
  double get _lineAlphaBase => isDark ? 0.08 : 0.06;
  double get _nodeAlphaBase => isDark ? 0.16 : 0.10;

  static const _pulseMin = 0.7;

  /// Vignette radial muy tenue en la esquina superior izquierda: le da algo
  /// de profundidad ambiental al fondo sin competir con el contenido.
  static const _vignetteAlpha = 0.035;

  double get _pulse => _pulseMin + (1 - _pulseMin) * t;

  Offset _positionOf(_NeuralNode node, Size size) {
    final dy = node.driftRadius * sin(2 * pi * (t + node.phase));
    final dx = node.driftRadius * cos(2 * pi * (t + node.phase));
    return Offset(node.x * size.width + dx, node.y * size.height + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    final vignette = Offset.zero & size;
    canvas.drawRect(
      vignette,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [
            nodeColor.withValues(alpha: _vignetteAlpha),
            nodeColor.withValues(alpha: 0),
          ],
        ).createShader(vignette),
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = lineColor.withValues(alpha: _lineAlphaBase * _pulse);

    for (final (i, j) in connections) {
      canvas.drawLine(
        _positionOf(nodes[i], size),
        _positionOf(nodes[j], size),
        linePaint,
      );
    }

    final nodePaint = Paint()
      ..color = nodeColor.withValues(alpha: _nodeAlphaBase * _pulse);
    for (final node in nodes) {
      canvas.drawCircle(_positionOf(node, size), 2.0, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralNetworkPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.isDark != isDark;
  }
}
