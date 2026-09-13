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
    if (isDark) {
      bg = const Color(0xFF0A1024);
      surface = const Color(0xFF121A36);
      raised = const Color(0xFF18224A);
      text = const Color(0xFFE8ECFF);
      muted = const Color(0xFF8D9AC6);
      accent = const Color(0xFF6A8CFF);
      amber = const Color(0xFFF5B83D);
      mapDot = const Color(0x597896FF);
      fill = const Color(0x14FFFFFF);
      fillStrong = const Color(0x24FFFFFF);
      border = const Color(0xFF243060);
      sheet = const Color(0xFF121A36);
      cardTop = const Color(0xFF141D3D);
      cardBottom = const Color(0xFF111934);
      shadow = const Color(0x00000000);
      auroraStrength = 0.16;
    } else {
      bg = const Color(0xFFEEF2FB);
      surface = const Color(0xFFFFFFFF);
      raised = const Color(0xFFF3F6FD);
      text = const Color(0xFF131A33);
      muted = const Color(0xFF5E6A8C);
      accent = const Color(0xFF2F5BFF);
      amber = const Color(0xFFC98300);
      mapDot = const Color(0x552F5BFF);
      fill = const Color(0x0D1E2A5A);
      fillStrong = const Color(0x1A1E2A5A);
      border = const Color(0xFFDCE3F3);
      sheet = const Color(0xFFFFFFFF);
      cardTop = const Color(0xFFFFFFFF);
      cardBottom = const Color(0xFFFBFCFF);
      shadow = const Color(0x1A2F5BFF);
      auroraStrength = 0.10;
    }
  }

  /// Three colors per connection state: primary, secondary, highlight.
  static List<Color> forState(VpnState state) {
    if (isDark) {
      return switch (state) {
        VpnState.connected => const [Color(0xFF2FD39A), Color(0xFF3D6BFF), Color(0xFF22D3EE)],
        VpnState.connecting || VpnState.disconnecting => const [Color(0xFFF5B83D), Color(0xFFFF8A3D), Color(0xFF6A8CFF)],
        VpnState.disconnected => const [Color(0xFF3D6BFF), Color(0xFF6A8CFF), Color(0xFF22D3EE)],
      };
    }
    return switch (state) {
      VpnState.connected => const [Color(0xFF0E9F6E), Color(0xFF2F5BFF), Color(0xFF0891B2)],
      VpnState.connecting || VpnState.disconnecting => const [Color(0xFFD97706), Color(0xFFEA580C), Color(0xFF2F5BFF)],
      VpnState.disconnected => const [Color(0xFF2F5BFF), Color(0xFF4F74FF), Color(0xFF0891B2)],
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
