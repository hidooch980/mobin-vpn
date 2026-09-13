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
    // Material look in the style of v2rayNG: blue primary, plain grey/white grounds, flat cards.
    if (isDark) {
      bg = const Color(0xFF121212);
      surface = const Color(0xFF1E1E1E);
      raised = const Color(0xFF242424);
      text = const Color(0xFFE6E6E6);
      muted = const Color(0xFF9E9E9E);
      accent = const Color(0xFF64B5F6);
      amber = const Color(0xFF64B5F6);
      mapDot = const Color(0x33E6E6E6);
      fill = const Color(0x0FFFFFFF);
      fillStrong = const Color(0x1AFFFFFF);
      border = const Color(0xFF2C2C2C);
      sheet = const Color(0xFF1E1E1E);
      cardTop = const Color(0xFF1E1E1E);
      cardBottom = const Color(0xFF1E1E1E);
      shadow = const Color(0x00000000);
      auroraStrength = 0.0;
    } else {
      bg = const Color(0xFFF2F2F2);
      surface = const Color(0xFFFFFFFF);
      raised = const Color(0xFFFFFFFF);
      text = const Color(0xFF212121);
      muted = const Color(0xFF757575);
      accent = const Color(0xFF1976D2);
      amber = const Color(0xFF1976D2);
      mapDot = const Color(0x2E212121);
      fill = const Color(0x0A000000);
      fillStrong = const Color(0x14000000);
      border = const Color(0xFFE0E0E0);
      sheet = const Color(0xFFFFFFFF);
      cardTop = const Color(0xFFFFFFFF);
      cardBottom = const Color(0xFFFFFFFF);
      shadow = const Color(0x14000000);
      auroraStrength = 0.0;
    }
  }

  /// Three colors per connection state: primary, secondary, highlight.
  static List<Color> forState(VpnState state) {
    if (isDark) {
      return switch (state) {
        VpnState.connected => const [Color(0xFF66BB6A), Color(0xFF43A047), Color(0xFF81C784)],
        VpnState.connecting || VpnState.disconnecting => const [Color(0xFFFFB74D), Color(0xFFFFA726), Color(0xFF64B5F6)],
        VpnState.disconnected => const [Color(0xFF64B5F6), Color(0xFF42A5F5), Color(0xFF90CAF9)],
      };
    }
    return switch (state) {
      VpnState.connected => const [Color(0xFF43A047), Color(0xFF2E7D32), Color(0xFF66BB6A)],
      VpnState.connecting || VpnState.disconnecting => const [Color(0xFFF57C00), Color(0xFFEF6C00), Color(0xFF1976D2)],
      VpnState.disconnected => const [Color(0xFF1976D2), Color(0xFF1565C0), Color(0xFF42A5F5)],
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
