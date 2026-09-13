import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'style.dart';

/// Slowly drifting aurora blobs + twinkling particles, tinted by the connection state.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.colors, required this.child});

  final List<Color> colors;
  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, child) => CustomPaint(
        painter: _AuroraPainter(_loop.value, widget.colors),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  static final _particles = List.generate(70, (i) {
    final r = math.Random(i * 7919 + 13);
    return (x: r.nextDouble(), y: r.nextDouble(), size: 0.5 + r.nextDouble() * 1.6, phase: r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.bg);
    final a = t * 2 * math.pi;
    final s = size.longestSide;
    final blobs = [
      (Offset(size.width * (0.15 + 0.18 * math.sin(a)), size.height * (0.18 + 0.10 * math.cos(a * 2))), s * 0.62, colors[0]),
      (Offset(size.width * (0.90 + 0.14 * math.cos(a)), size.height * (0.46 + 0.14 * math.sin(a))), s * 0.55, colors[1]),
      (Offset(size.width * (0.35 + 0.22 * math.sin(a + 2)), size.height * (0.95 + 0.06 * math.cos(a + 1))), s * 0.66, colors[2]),
    ];
    for (final (center, radius, color) in blobs) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.42),
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0),
          ], stops: const [0, 0.45, 1]).createShader(rect),
      );
    }

    for (final p in _particles) {
      final y = (p.y - t * (0.35 + p.phase * 0.5)) % 1.0;
      final twinkle = 0.5 + 0.5 * math.sin(a * 9 + p.phase * math.pi * 2);
      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.size,
        Paint()..color = Colors.white.withValues(alpha: 0.08 + 0.45 * twinkle),
      );
    }

    final vignette = Rect.fromCircle(center: size.center(Offset.zero), radius: s * 0.8);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Palette.bg.withValues(alpha: 0.75)],
          stops: const [0.45, 1],
        ).createShader(vignette),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => true;
}
