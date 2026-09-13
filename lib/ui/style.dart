import 'package:flutter/material.dart';

import '../core/engine.dart';

/// App colors for the active theme ("night map" design: deep navy / clean blue-white, blue accent,
/// amber for the selected server). [apply] is called whenever the theme changes and the app rebuilds.
class Palette {
  static bool isDark = true;
  static bool reduceMotion = false;

  static Color bg = const Color(0xFF0A1024);
  static Color surface = const Color(0xFF121A36);
  static Color raised = const Color(0xFF18224A);
  static Color text = const Color(0xFFE8ECFF);
  static Color muted = const Color(0xFF8D9AC6);
  static Color accent = const Color(0xFF6A8CFF);
  static Color amber = const Color(0xFFF5B83D);
  static Color mapDot = const Color(0x597896FF);
  static Color fill = const Color(0x14FFFFFF);
  static Color fillStrong = const Color(0x24FFFFFF);
  static Color border = const Color(0xFF243060);
  static Color sheet = const Color(0xFF121A36);
  static Color cardTop = const Color(0xFF141D3D);
  static Color cardBottom = const Color(0xFF111934);
  static Color shadow = const Color(0x00000000);
  static double auroraStrength = 0.16;

  static void apply(Brightness brightness, {required bool reduceMotion}) {
    Palette.reduceMotion = reduceMotion;
    isDark = brightness == Brightness.dark;
    // Calm system-tool palette: green-grey canvas, soft green primary, brighter green when connected.
    if (isDark) {
      bg = const Color(0xFF101411);
      surface = const Color(0xFF171C18);
      raised = const Color(0xFF222A24);
      text = const Color(0xFFE8F1EA);
      muted = const Color(0xFFB9C6BB);
      accent = const Color(0xFFA4D8BB);
      amber = const Color(0xFF67D89C);
      mapDot = const Color(0x33A4D8BB);
      fill = const Color(0x0FFFFFFF);
      fillStrong = const Color(0x1AFFFFFF);
      border = const Color(0xFF3B473E);
      sheet = const Color(0xFF171C18);
      cardTop = const Color(0xFF171C18);
      cardBottom = const Color(0xFF171C18);
      shadow = const Color(0x00000000);
      auroraStrength = 0.0;
    } else {
      bg = const Color(0xFFF4F7F4);
      surface = const Color(0xFFFFFFFF);
      raised = const Color(0xFFE7EEE9);
      text = const Color(0xFF17201A);
      muted = const Color(0xFF55635A);
      accent = const Color(0xFF3E7F5C);
      amber = const Color(0xFF238A55);
      mapDot = const Color(0x2E3E7F5C);
      fill = const Color(0x0A17201A);
      fillStrong = const Color(0x1417201A);
      border = const Color(0xFFCBD6CE);
      sheet = const Color(0xFFFFFFFF);
      cardTop = const Color(0xFFFFFFFF);
      cardBottom = const Color(0xFFFFFFFF);
      shadow = const Color(0x00000000);
      auroraStrength = 0.0;
    }
  }

  /// Shown only after a reported connection failure.
  static Color get failure => isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E);

  /// Three colors per connection state: primary, secondary, highlight.
  static List<Color> forState(VpnState state) {
    if (isDark) {
      return switch (state) {
        VpnState.connected => const [Color(0xFF67D89C), Color(0xFFA4D8BB), Color(0xFF3B473E)],
        VpnState.connecting || VpnState.disconnecting => const [Color(0xFFA4D8BB), Color(0xFF67D89C), Color(0xFF3B473E)],
        VpnState.disconnected => const [Color(0xFFA4D8BB), Color(0xFF67D89C), Color(0xFF3B473E)],
      };
    }
    return switch (state) {
      VpnState.connected => const [Color(0xFF238A55), Color(0xFF3E7F5C), Color(0xFFCBD6CE)],
      VpnState.connecting || VpnState.disconnecting => const [Color(0xFF3E7F5C), Color(0xFF238A55), Color(0xFFCBD6CE)],
      VpnState.disconnected => const [Color(0xFF3E7F5C), Color(0xFF238A55), Color(0xFFCBD6CE)],
    };
  }

  static Color forDelay(int? ms) {
    if (ms == null || ms <= 0) return muted;
    if (ms < 350) return isDark ? const Color(0xFF4ADE95) : const Color(0xFF0E9F6E);
    if (ms < 800) return isDark ? const Color(0xFFF5B83D) : const Color(0xFFC98300);
    return isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD93A3A);
  }
}

String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
  if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String timeAgo(DateTime time) {
  final d = DateTime.now().difference(time);
  if (d.inMinutes < 1) return 'همین الان';
  if (d.inHours < 1) return '${d.inMinutes} دقیقه پیش';
  if (d.inDays < 1) return '${d.inHours} ساعت پیش';
  return '${d.inDays} روز پیش';
}

/// Smoothly cross-fades a list of colors whenever [colors] changes.
class AnimatedColors extends StatefulWidget {
  const AnimatedColors({super.key, required this.colors, required this.builder});

  final List<Color> colors;
  final Widget Function(BuildContext context, List<Color> colors) builder;

  @override
  State<AnimatedColors> createState() => _AnimatedColorsState();
}

class _AnimatedColorsState extends State<AnimatedColors> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);
  late List<Color> _from = widget.colors, _to = widget.colors;

  List<Color> get _current {
    final t = Curves.easeInOutCubic.transform(_controller.value);
    return [for (var i = 0; i < _to.length; i++) Color.lerp(_from[i], _to[i], t)!];
  }

  @override
  void didUpdateWidget(AnimatedColors old) {
    super.didUpdateWidget(old);
    if (!_sameColors(old.colors, widget.colors)) {
      _from = _current;
      _to = widget.colors;
      _controller.forward(from: 0);
    }
  }

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _controller, builder: (context, _) => widget.builder(context, _current));
}
