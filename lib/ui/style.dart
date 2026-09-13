import 'package:flutter/material.dart';

import '../core/engine.dart';

/// App colors for the active theme. [apply] is called whenever the theme changes and the app rebuilds.
class Palette {
  static bool isDark = true;
  static bool reduceMotion = false;

  static Color bg = const Color(0xFF05050D);
  static Color text = const Color(0xFFF4F4FF);
  static Color muted = const Color(0xFF9A9AB8);
  static Color accent = const Color(0xFFA78BFA);
  static Color fill = const Color(0x0FFFFFFF);
  static Color fillStrong = const Color(0x1CFFFFFF);
  static Color border = const Color(0x1FFFFFFF);
  static Color sheet = const Color(0xF20B0B1A);
  static Color cardTop = const Color(0x1CFFFFFF);
  static Color cardBottom = const Color(0x08FFFFFF);
  static Color shadow = const Color(0x00000000);

  static void apply(Brightness brightness, {required bool reduceMotion}) {
    Palette.reduceMotion = reduceMotion;
    isDark = brightness == Brightness.dark;
    if (isDark) {
      bg = const Color(0xFF05050D);
      text = const Color(0xFFF4F4FF);
      muted = const Color(0xFF9A9AB8);
      accent = const Color(0xFFA78BFA);
      fill = const Color(0x0FFFFFFF);
      fillStrong = const Color(0x1CFFFFFF);
      border = const Color(0x1FFFFFFF);
      sheet = const Color(0xF20B0B1A);
      cardTop = const Color(0x1CFFFFFF);
      cardBottom = const Color(0x08FFFFFF);
      shadow = const Color(0x00000000);
    } else {
      bg = const Color(0xFFF2F1FA);
      text = const Color(0xFF16142E);
      muted = const Color(0xFF6D6B8A);
      accent = const Color(0xFF6D28D9);
      fill = const Color(0x0D1E1B4B);
      fillStrong = const Color(0x1A1E1B4B);
      border = const Color(0x1A1E1B4B);
      sheet = const Color(0xF7FBFAFF);
      cardTop = const Color(0xF2FFFFFF);
      cardBottom = const Color(0xC7FFFFFF);
      shadow = const Color(0x1F3B2A7A);
    }
  }

  static List<Color> forState(VpnState state) {
    if (isDark) {
      return switch (state) {
        VpnState.connected => const [Color(0xFF10E0A0), Color(0xFF06B6D4), Color(0xFF3B82F6)],
        VpnState.connecting || VpnState.disconnecting => const [Color(0xFFFFB020), Color(0xFFF0487F), Color(0xFF8B5CF6)],
        VpnState.disconnected => const [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFFDB2777)],
      };
    }
    return switch (state) {
      VpnState.connected => const [Color(0xFF059669), Color(0xFF0891B2), Color(0xFF2563EB)],
      VpnState.connecting || VpnState.disconnecting => const [Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF7C3AED)],
      VpnState.disconnected => const [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFFDB2777)],
    };
  }

  static Color forDelay(int? ms) {
    if (ms == null || ms <= 0) return muted;
    if (ms < 350) return isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    if (ms < 800) return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
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
