import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Approximate [longitude, latitude] of each country's main hub, for the route line on the map.
const Map<String, (double, double)> countryPositions = {
  'IR': (53, 32), 'AE': (55, 24), 'AL': (20, 41), 'AM': (45, 40), 'AR': (-64, -34), 'AT': (15, 48),
  'AU': (145, -35), 'AZ': (49, 40), 'BE': (4, 51), 'BG': (25, 43), 'BR': (-47, -15), 'CA': (-79, 45),
  'CH': (8, 47), 'CL': (-71, -33), 'CN': (116, 40), 'CY': (33, 35), 'CZ': (14, 50), 'DE': (10, 51),
  'DK': (12, 56), 'EE': (25, 59), 'ES': (-4, 40), 'FI': (25, 61), 'FR': (2, 47), 'GB': (-1, 52),
  'GE': (44, 42), 'GR': (23, 38), 'HK': (114, 22), 'HR': (16, 45), 'HU': (19, 47), 'ID': (107, -6),
  'IE': (-7, 53), 'IL': (35, 32), 'IN': (77, 21), 'IQ': (44, 33), 'IS': (-22, 64), 'IT': (12, 42),
  'JP': (139, 36), 'KR': (127, 37), 'KZ': (71, 51), 'LT': (24, 55), 'LU': (6, 50), 'LV': (24, 57),
  'MD': (29, 47), 'MX': (-99, 19), 'MY': (102, 3), 'NL': (5, 52), 'NO': (10, 60), 'NZ': (175, -41),
  'OM': (58, 23), 'PH': (121, 14), 'PK': (70, 30), 'PL': (20, 52), 'PT': (-9, 39), 'QA': (51, 25),
  'RO': (26, 45), 'RS': (20, 44), 'RU': (38, 56), 'SA': (46, 24), 'SC': (55, -4), 'SE': (18, 59),
  'SG': (104, 1), 'SI': (15, 46), 'SK': (19, 48), 'TH': (100, 14), 'TR': (32, 39), 'TW': (121, 25),
  'UA': (31, 50), 'US': (-95, 38), 'VN': (106, 16), 'ZA': (25, -29),
};

// Deliberately simplified continent outlines [lon, lat] — enough for a stylized dot map.
const _land = <List<(double, double)>>[
  [(-168, 65), (-140, 70), (-95, 72), (-80, 63), (-60, 55), (-52, 47), (-70, 43), (-76, 35), (-81, 25), (-97, 26), (-97, 18), (-88, 15), (-83, 9), (-79, 8), (-90, 14), (-105, 20), (-112, 30), (-117, 33), (-124, 40), (-125, 49), (-135, 58), (-150, 60), (-165, 60)],
  [(-55, 60), (-40, 60), (-20, 70), (-20, 80), (-60, 82), (-72, 77)],
  [(-80, 10), (-62, 11), (-50, 0), (-35, -7), (-40, -22), (-48, -28), (-58, -38), (-66, -55), (-74, -50), (-72, -30), (-70, -18), (-81, -5)],
  [(-10, 36), (-9, 43), (-2, 44), (-5, 48), (0, 50), (8, 54), (10, 58), (5, 62), (15, 69), (28, 71), (40, 67), (45, 55), (40, 47), (30, 45), (28, 41), (20, 40), (15, 38), (12, 44), (8, 44), (3, 43), (-5, 36)],
  [(-6, 50), (1, 51), (2, 53), (-2, 56), (-3, 58), (-6, 57), (-5, 54)],
  [(-17, 21), (-10, 30), (-5, 36), (10, 37), (20, 32), (32, 31), (35, 28), (43, 12), (51, 12), (40, -5), (40, -15), (35, -25), (28, -34), (18, -34), (12, -18), (9, -2), (9, 4), (-5, 5), (-17, 14)],
  [(28, 41), (36, 36), (35, 32), (44, 12), (55, 17), (57, 24), (62, 25), (68, 24), (73, 20), (78, 8), (82, 15), (88, 22), (92, 21), (98, 16), (100, 8), (104, 2), (106, 10), (109, 20), (117, 24), (122, 30), (122, 40), (130, 42), (135, 45), (142, 53), (160, 60), (180, 65), (180, 72), (140, 73), (100, 78), (70, 73), (55, 68), (45, 68), (40, 67), (45, 55), (40, 47), (48, 42), (40, 41)],
  [(95, 5), (105, -6), (120, -9), (140, -8), (140, -2), (120, 2), (110, 2), (100, 3)],
  [(114, -22), (122, -17), (131, -11), (137, -12), (142, -11), (146, -19), (153, -26), (150, -37), (141, -38), (131, -31), (117, -35), (114, -26)],
  [(130, 31), (135, 34), (140, 36), (142, 43), (145, 44), (140, 40), (133, 35)],
];

/// Stylized dotted world map with an animated route from Iran to the server's country.
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.serverCode, required this.connected, required this.busy, required this.accent, required this.dot, required this.home});

  /// Country of the (selected or connected) server; null draws no route.
  final String? serverCode;
  final bool connected, busy;
  final Color accent, dot, home;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _MapPainter(_anim, widget.serverCode, widget.connected, widget.busy, widget.accent, widget.dot, widget.home),
          size: Size.infinite,
        ),
      );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.anim, this.serverCode, this.connected, this.busy, this.accent, this.dot, this.home) : super(repaint: anim);

  final Animation<double> anim;
  final String? serverCode;
  final bool connected, busy;
  final Color accent, dot, home;

  static const _latTop = 76.0, _latBottom = -50.0;
  static final Map<String, ui.Picture> _dotCache = {};

  Offset _project(Size size, double lon, double lat) =>
      Offset((lon + 180) / 360 * size.width, (_latTop - lat) / (_latTop - _latBottom) * size.height);

  static bool _inside(List<(double, double)> poly, double x, double y) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final (xi, yi) = poly[i];
      final (xj, yj) = poly[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  ui.Picture _dots(Size size) {
    final key = '${size.width.round()}x${size.height.round()}:${dot.toARGB32()}';
    return _dotCache.putIfAbsent(key, () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = dot;
      final step = math.max(7.0, size.width / 58);
      for (var y = step / 2; y < size.height; y += step) {
        for (var x = step / 2; x < size.width; x += step) {
          final lon = x / size.width * 360 - 180;
          final lat = _latTop - y / size.height * (_latTop - _latBottom);
          if (_land.any((p) => _inside(p, lon, lat))) canvas.drawCircle(Offset(x, y), step * 0.2, paint);
        }
      }
      return recorder.endRecording();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawPicture(_dots(size));
    final t = anim.value;
    final (hl, hb) = countryPositions['IR']!;
    final from = _project(size, hl, hb);

    final target = serverCode == null ? null : countryPositions[serverCode];
    if (target != null) {
      final to = _project(size, target.$1, target.$2);
      final mid = Offset((from.dx + to.dx) / 2, math.min(from.dy, to.dy) - (from - to).distance * 0.35 - 10);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: connected ? 0.9 : 0.45),
      );
      // Travelling packet along the route.
      if (connected || busy) {
        final metric = path.computeMetrics().firstOrNull;
        if (metric != null) {
          final tangent = metric.getTangentForOffset(metric.length * t);
          if (tangent != null) {
            canvas.drawCircle(tangent.position, 7, Paint()..color = accent.withValues(alpha: 0.25));
            canvas.drawCircle(tangent.position, 3.2, Paint()..color = accent);
          }
        }
      }
      _pin(canvas, to, accent, t);
    }
    _pin(canvas, from, home, (t + 0.5) % 1);
  }

  void _pin(Canvas canvas, Offset at, Color color, double t) {
    canvas.drawCircle(at, 6 + 12 * t, Paint()..color = color.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(at, 6, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawCircle(at, 3.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.serverCode != serverCode || old.connected != connected || old.busy != busy || old.accent != accent || old.dot != dot;
}
