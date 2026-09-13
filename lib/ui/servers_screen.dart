import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/server.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'flag_badge.dart';
import 'glass.dart';
import 'style.dart';

/// Every server with manual ping test and one-tap connect to a specific server.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  static const _maxPing = 150;
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
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(c.state),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final list = _visible();
              final tested = list.where((s) => (c.delays[s.uri] ?? 0) > 0).length;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            Glass(
                              radius: 16,
                              padding: const EdgeInsets.all(10),
                              onTap: () => Navigator.of(context).pop(),
                              child: const Icon(Icons.arrow_forward_rounded, color: Palette.text),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('همه‌ی سرورها', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
                                  Text('${list.length} سرور · $tested پاسخ داده', style: const TextStyle(fontSize: 12, color: Palette.muted)),
                                ],
                              ),
                            ),
                            Tooltip(
                              message: 'مرتب‌سازی بر اساس پینگ',
                              child: Glass(
                                radius: 16,
                                padding: const EdgeInsets.all(10),
                                borderColor: _byPing ? const Color(0xFFA78BFA) : null,
                                onTap: () => setState(() => _byPing = !_byPing),
                                child: Icon(Icons.sort_rounded, color: _byPing ? const Color(0xFFA78BFA) : Palette.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setState(() => _query = v),
                                style: const TextStyle(color: Palette.text),
                                decoration: InputDecoration(
                                  hintText: 'جستجو: کشور، پروتکل…',
                                  hintStyle: const TextStyle(color: Palette.muted),
                                  prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.06),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                                backgroundColor: const Color(0xFF7C3AED),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: c.pinging
                                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.network_ping_rounded, size: 18),
                              label: Text(c.pinging ? 'در حال تست' : 'تست پینگ'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: list.length,
                          itemBuilder: (context, i) => _Entrance(
                            index: i,
                            child: _ServerTile(
                              server: list[i],
                              delay: c.delays[list[i].uri],
                              active: c.current?.uri == list[i].uri,
                              onTap: () {
                                Navigator.of(context).pop();
                                c.connectTo(list[i]);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 280 + math.min(index, 12) * 40),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: child)),
        child: child,
      );
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.delay, required this.active, required this.onTap});

  final Server server;
  final int? delay;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = delay;
    final delayText = d == null ? '—' : (d <= 0 ? 'قطع' : '$d ms');
    final color = d == null ? Palette.muted : (d <= 0 ? const Color(0xFFF87171) : Palette.forDelay(d));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderColor: active ? const Color(0xFF34D399) : null,
        onTap: onTap,
        child: Row(
          children: [
            FlagBadge(code: server.countryCode, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(6)),
                    child: Text(server.protocolLabel, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Palette.muted)),
                  ),
                ],
              ),
            ),
            if (active) const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Text(delayText, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
