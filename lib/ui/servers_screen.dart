import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/server.dart';
import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'style.dart';
import 'widgets.dart';

/// Every server with manual ping test and one-tap connect to a specific server.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  // Every listed server is tested; results appear live as each one finishes.
  static const _maxPing = 100000;
  String _query = '';
  bool _byPing = false;

  List<Server> _visible() {
    final c = widget.controller;
    final q = _query.trim().toLowerCase();
    final list = c.servers
        .where((s) =>
            q.isEmpty ||
            s.displayName.contains(q) ||
            s.countryCode.toLowerCase().contains(q) ||
            s.protocolLabel.toLowerCase().contains(q))
        .toList();
    if (_byPing) {
      int key(Server s) {
        final d = c.delays[s.uri];
        return d == null ? 1 << 30 : (d <= 0 ? 1 << 29 : d);
      }

      list.sort((a, b) => key(a).compareTo(key(b)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final list = _visible();
        final tested = list.where((s) => (c.delays[s.uri] ?? 0) > 0).length;
        return PageShell(
          title: 'سرورها',
          subtitle: '${list.length} سرور · $tested پاسخ داده',
          actions: [
            IconButton(
              tooltip: 'مرتب‌سازی بر اساس پینگ',
              onPressed: () => setState(() => _byPing = !_byPing),
              icon: Icon(Icons.sort_rounded, color: _byPing ? Palette.accent : Palette.muted),
            ),
          ],
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(color: Palette.text),
                    decoration: InputDecoration(
                      hintText: 'جستجو: کشور، پروتکل…',
                      hintStyle: TextStyle(color: Palette.muted),
                      prefixIcon: Icon(Icons.search_rounded, color: Palette.muted),
                      filled: true,
                      fillColor: Palette.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Palette.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Palette.accent)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: c.pinging || c.state == VpnState.connecting
                      ? null
                      : () {
                          c.pingServers(list.take(_maxPing).toList());
                          setState(() => _byPing = true);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.accent,
                    foregroundColor: Palette.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: c.pinging
                      ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.muted))
                      : const Icon(Icons.network_ping_rounded, size: 18),
                  label: Text(c.pinging ? 'در حال تست' : 'تست پینگ'),
                ),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                itemBuilder: (context, i) => _Entrance(
                  index: i,
                  child: _ServerTile(
                    server: list[i],
                    delay: c.delays[list[i].uri],
                    active: c.current?.uri == list[i].uri,
                    favorite: c.isFavorite(list[i]),
                    onStar: () => c.toggleFavorite(list[i]),
                    onTap: () {
                      Navigator.of(context).pop();
                      c.connectTo(list[i]);
                    },
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Palette.reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + math.min(index, 12) * 30),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child)),
      child: child,
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.delay,
    required this.active,
    required this.favorite,
    required this.onStar,
    required this.onTap,
  });

  final Server server;
  final int? delay;
  final bool active, favorite;
  final VoidCallback onTap, onStar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        borderColor: active ? Palette.amber : null,
        onTap: onTap,
        child: Row(children: [
          FlagBadge(code: server.countryCode, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text)),
              const SizedBox(height: 4),
              Row(children: [
                ProtocolTag(server.protocolLabel),
                if (active) ...[
                  const SizedBox(width: 8),
                  Text('متصل', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Palette.amber)),
                ],
              ]),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: favorite ? 'حذف از علاقه‌مندی‌ها' : 'افزودن به علاقه‌مندی‌ها',
            onPressed: onStar,
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: favorite ? const Color(0xFFFBBF24) : Palette.muted,
            ),
          ),
          const SizedBox(width: 4),
          DelayPill(ms: delay),
        ]),
      ),
    );
  }
}
