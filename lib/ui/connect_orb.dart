import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine.dart';

/// The big animated power button: rotating gradient ring, ripples when connected, progress while scanning.
class ConnectOrb extends StatefulWidget {
  const ConnectOrb({super.key, required this.state, required this.colors, required this.onTap, this.progress});

  final VpnState state;
  final List<Color> colors;
  final VoidCallback onTap;
  final double? progress;

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with TickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.state == VpnState.connected;
    final busy = widget.state == VpnState.connecting || widget.state == VpnState.disconnecting;
    return Semantics(
      button: true,
      label: on ? 'قطع اتصال' : 'اتصال',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.93 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: SizedBox.square(
              dimension: 300,
              child: AnimatedBuilder(
                animation: Listenable.merge([_spin, _pulse]),
                builder: (context, _) => CustomPaint(
                  painter: _OrbPainter(
                    spin: _spin.value,
                    pulse: _pulse.value,
                    colors: widget.colors,
                    on: on,
                    busy: busy,
                    progress: widget.progress,
                  ),
                  child: Center(child: _core(on, busy)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _core(bool on, bool busy) {
    final breathe = busy ? 0.55 + 0.45 * math.sin(_pulse.value * math.pi * 2).abs() : 1.0;
    final c = widget.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: on
              ? [c[0], c[1]]
              : [const Color(0xFF1C1B33), const Color(0xFF0B0B18)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: on ? 0.35 : 0.14), width: 1.2),
        boxShadow: [
          BoxShadow(color: c[0].withValues(alpha: on ? 0.65 : 0.28), blurRadius: on ? 70 : 36, spreadRadius: on ? 6 : 0),
          BoxShadow(color: c[1].withValues(alpha: on ? 0.35 : 0.12), blurRadius: 110, spreadRadius: -10),
        ],
      ),
      child: Opacity(
        opacity: breathe,
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 78,
          color: on ? Colors.white : Color.lerp(Colors.white, c[0], busy ? 0.6 : 0.15),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.spin,
    required this.pulse,
    required this.colors,
    required this.on,
    required this.busy,
    required this.progress,
  });

  final double spin, pulse;
  final List<Color> colors;
  final bool on, busy;
  final double? progress;

  static const _coreRadius = 84.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    // Ripples radiating outwards.
    if (on || busy) {
      for (var i = 0; i < 3; i++) {
        final v = (pulse + i / 3) % 1.0;
        final r = _coreRadius + 12 + v * (maxR - _coreRadius - 12);
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6 + 2.2 * (1 - v)
            ..color = colors[i % colors.length].withValues(alpha: (1 - v) * (on ? 0.5 : 0.28)),
        );
      }
    }

    final ringR = _coreRadius + 24;
    final rect = Rect.fromCircle(center: center, radius: ringR);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    final rotation = spin * math.pi * 2 * (busy ? 4 : 1);
    final sweep = on
        ? math.pi * 2
        : busy
            ? math.pi * 2 * (0.25 + 0.35 * (0.5 + 0.5 * math.sin(pulse * math.pi * 2)))
            : math.pi * 0.7;
    final fraction = sweep / (math.pi * 2);
    final shader = SweepGradient(
      colors: on
          ? [colors[0], colors[1], colors[2], colors[0]]
          : [colors[0].withValues(alpha: 0), colors[0], colors[1]],
      stops: on ? const [0, 0.33, 0.66, 1] : [0, fraction * 0.55, fraction],
      transform: GradientRotation(rotation),
    ).createShader(rect);

    for (final glow in [true, false]) {
      canvas.drawArc(
        rect,
        rotation,
        sweep,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = glow ? 14 : 5
          ..maskFilter = glow ? const MaskFilter.blur(BlurStyle.normal, 12) : null
          ..color = Colors.white.withValues(alpha: glow ? 0.6 : 1),
      );
    }

    // Orbiting spark.
    final sparkAngle = rotation + sweep;
    final spark = center + Offset(math.cos(sparkAngle), math.sin(sparkAngle)) * ringR;
    canvas.drawCircle(spark, 9, Paint()..color = colors[1].withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(spark, 3.5, Paint()..color = Colors.white);

    // Scan progress.
    final p = progress;
    if (p != null) {
      final outer = Rect.fromCircle(center: center, radius: ringR + 16);
      canvas.drawArc(
        outer,
        -math.pi / 2,
        math.pi * 2 * p.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.5
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
