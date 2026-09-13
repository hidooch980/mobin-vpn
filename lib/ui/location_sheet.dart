import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'style.dart';

Future<void> showLocationSheet(BuildContext context, VpnController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _LocationSheet(controller: controller),
  );
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.controller});

  final VpnController controller;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  String _query = '';

  void _pick(String? code) {
    Navigator.of(context).pop();
    widget.controller.selectCountry(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = _query.trim().toLowerCase();
    final groups = c.countries
        .where((g) => q.isEmpty || g.name.contains(q) || g.code.toLowerCase().contains(q))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B1A).withValues(alpha: 0.82),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 18),
                const Text('انتخاب موقعیت', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Palette.text)),
                const SizedBox(height: 4),
                Text('${c.servers.length} سرور تست‌شده در ${c.countries.length} کشور',
                    style: const TextStyle(fontSize: 13, color: Palette.muted)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: Palette.text),
                    decoration: InputDecoration(
                      hintText: 'جستجوی کشور…',
                      hintStyle: const TextStyle(color: Palette.muted),
                      prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      if (q.isEmpty)
                        _Entrance(
                          index: 0,
                          child: _Tile(
                            code: null,
                            title: 'هوشمند',
                            subtitle: 'اتصال خودکار به سریع‌ترین سرور برای اینترنت شما',
                            selected: c.selectedCountry == null,
                            onTap: () => _pick(null),
                          ),
                        ),
                      if (q.isEmpty && c.settings.favorites.isNotEmpty)
                        _Entrance(
                          index: 1,
                          child: _Tile(
                            code: VpnController.favoritesMode,
                            title: 'علاقه‌مندی‌ها',
                            subtitle: '${c.settings.favorites.length} سرور ستاره‌دار · سریع‌ترین انتخاب می‌شود',
                            selected: c.selectedCountry == VpnController.favoritesMode,
                            onTap: () => _pick(VpnController.favoritesMode),
                          ),
                        ),
                      if (q.isEmpty)
                        _Entrance(
                          index: 1,
                          child: _Tile(
                            code: VpnController.gamingMode,
                            title: 'گیمینگ',
                            subtitle: 'کمترین و پایدارترین پینگ از سرورهای نزدیک به ایران',
                            selected: c.isGaming,
                            onTap: () => _pick(VpnController.gamingMode),
                          ),
                        ),
                      for (final (i, g) in groups.indexed)
                        _Entrance(
                          index: i + 2,
                          child: _Tile(
                            code: g.code,
                            title: g.name,
                            subtitle: '${g.servers.length} سرور',
                            selected: c.selectedCountry == g.code,
                            onTap: () => _pick(g.code),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + math.min(index, 14) * 45),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 28 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.code, required this.title, required this.subtitle, required this.selected, required this.onTap});

  final String? code;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: selected ? 0.10 : 0.035),
              border: Border.all(
                color: selected ? const Color(0xFF8B5CF6).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.06),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                FlagBadge(code: code, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: selected
                      ? const Icon(Icons.check_circle_rounded, key: ValueKey(true), color: Color(0xFFA78BFA))
                      : const Icon(Icons.chevron_left_rounded, key: ValueKey(false), color: Palette.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
