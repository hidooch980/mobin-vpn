import 'dart:io';

import 'package:flutter/material.dart';

import '../core/countries.dart';

/// Country flag. Windows cannot render flag emoji, so it gets a colored code badge instead.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.code, this.size = 44});

  /// null = automatic mode.
  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    if (code == null) {
      return _circle(
        const [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5),
      );
    }
    if (!Platform.isWindows) {
      return _circle(
        [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)],
        Text(flagEmoji(code), style: TextStyle(fontSize: size * 0.56)),
      );
    }
    final hue = (code.codeUnitAt(0) * 31 + code.codeUnitAt(code.length - 1) * 17) % 360;
    return _circle(
      [HSLColor.fromAHSL(1, hue.toDouble(), 0.7, 0.55).toColor(), HSLColor.fromAHSL(1, (hue + 50) % 360, 0.75, 0.4).toColor()],
      Text(code, style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
    );
  }

  Widget _circle(List<Color> colors, Widget child) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: child,
      );
}
