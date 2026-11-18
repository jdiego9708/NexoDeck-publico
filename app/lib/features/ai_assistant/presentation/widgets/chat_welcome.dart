import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Estado vacio del chat: la invitacion a empezar, sobre una red neuronal
/// tenue.
///
/// Es el mismo chat de siempre (`AiChatView`) el que lo dibuja cuando el hilo
/// esta vacio; lo unico que cambia es esto. La red es decorativa y no
/// interactiva (`IgnorePointer`): los ejemplos se tienen que poder tocar.
class ChatWelcome extends StatelessWidget {
  const ChatWelcome({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  /// Ejemplos concretos y del dominio del usuario. Un "¿en que te ayudo?"
  /// vacio no le dice a nadie que clase de cosas puede pedir.
  static const _examples = [
    'Que abra mi proyecto y corra flutter analyze mostrandome el informe',
    'Que compile y ejecute la app en modo debug en el telefono conectado',
    'Que haga commit de todo y lo suba a la rama actual',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: _NeuralWeb()),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 28,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.gutter),
                  Text(
                    'Iniciá una conversación',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Preguntale lo que necesites al bot de NexoDeck: puede '
                    'crear botones, explicarte algo o correr un comando. '
                    'Escribilo como se lo explicarias a alguien.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final example in _examples)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ActionChip(
                        label: Text(
                          example,
                          style: theme.textTheme.bodySmall,
                        ),
                        onPressed: () => onPick(example),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La red: nodos que derivan despacio y se conectan con **curvas onduladas**,
/// con un pulso chico viajando por cada conexion. Decorativa y sutil: no
/// compite con el texto.
class _NeuralWeb extends StatefulWidget {
  const _NeuralWeb();

  @override
  State<_NeuralWeb> createState() => _NeuralWebState();
}

class _NeuralWebState extends State<_NeuralWeb>
    with SingleTickerProviderStateMixin {
  static const _nodeCount = 26;

  /// Fraccion de la diagonal dentro de la cual dos nodos se conectan.
  static const _linkThreshold = 0.24;

  late final AnimationController _controller;
  late final List<Offset> _nodes;
  late final List<double> _phases;
  late final List<(int, int)> _links;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    // Semilla fija: la red es la misma en cada arranque, no baila de un frame
    // a otro.
    final random = Random(7);
    _nodes = List.generate(
      _nodeCount,
      (_) => Offset(random.nextDouble(), random.nextDouble()),
    );
    _phases = List.generate(_nodeCount, (_) => random.nextDouble() * 2 * pi);
    _links = [
      for (var i = 0; i < _nodeCount; i++)
        for (var j = i + 1; j < _nodeCount; j++)
          if ((_nodes[i] - _nodes[j]).distance < _linkThreshold) (i, j),
    ];
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
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _WebPainter(
          nodes: _nodes,
          phases: _phases,
          links: _links,
          t: _controller.value,
          accent: scheme.primary,
          isDark: scheme.brightness == Brightness.dark,
          repaint: _controller,
        ),
      ),
    );
  }
}

class _WebPainter extends CustomPainter {
  _WebPainter({
    required this.nodes,
    required this.phases,
    required this.links,
    required this.t,
    required this.accent,
    required this.isDark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<Offset> nodes;
  final List<double> phases;
  final List<(int, int)> links;
  final double t;
  final Color accent;
  final bool isDark;

  /// Mas visibles que el fondo ambiental de la ventana (`NeuralBackground`),
  /// porque aca es el tema del estado vacio y no un simple acompañamiento.
  double get _lineAlpha => isDark ? 0.16 : 0.10;
  double get _nodeAlpha => isDark ? 0.22 : 0.14;
  double get _pulseAlpha => isDark ? 0.55 : 0.45;

  Offset _positionOf(int index, Size size) {
    final node = nodes[index];
    final phase = phases[index];
    // Deriva sinusoidal: cada nodo respira en su propio desfase.
    final dx = 4 * cos(2 * pi * (t + phase));
    final dy = 4 * sin(2 * pi * (t + phase));
    return Offset(node.dx * size.width + dx, node.dy * size.height + dy);
  }

  /// Punto de una cuadratica de Bezier en el parametro [p] (0..1).
  static Offset _bezier(Offset a, Offset control, Offset b, double p) {
    final u = 1 - p;
    return a * (u * u) + control * (2 * u * p) + b * (p * p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = accent.withValues(alpha: _lineAlpha);
    final pulsePaint = Paint()..color = accent.withValues(alpha: _pulseAlpha);
    final nodePaint = Paint()..color = accent.withValues(alpha: _nodeAlpha);

    for (final (i, j) in links) {
      final a = _positionOf(i, size);
      final b = _positionOf(j, size);
      final direction = b - a;
      final length = direction.distance;
      if (length == 0) continue;
      final perpendicular = Offset(-direction.dy / length, direction.dx / length);
      // El punto de control se aparta del medio y oscila: la recta se vuelve
      // una onda.
      final wave = sin(2 * pi * (t + phases[i])) * (length * 0.12);
      final control = (a + b) / 2 + perpendicular * wave;

      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy),
        linePaint,
      );

      // Pulso viajando por la conexion, con desfase propio por enlace.
      final progress = (t + phases[j]) % 1.0;
      canvas.drawCircle(
        _bezier(a, control, b, progress),
        1.8,
        pulsePaint,
      );
    }

    for (var i = 0; i < nodes.length; i++) {
      canvas.drawCircle(_positionOf(i, size), 2.2, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WebPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.accent != accent ||
        oldDelegate.isDark != isDark;
  }
}
