import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/account.dart';
import '../core/engine.dart';
import '../core/server.dart';
import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'log_screen.dart';
import 'settings_screen.dart';
import 'style.dart';
import 'usage_screen.dart';

/// Home in the style of v2rayNG: app bar with actions, drawer, group tabs, server cards with delay,
/// a round connect button and a status bar at the bottom.
class ClassicHome extends StatefulWidget {
  const ClassicHome({super.key, required this.controller});

  final VpnController controller;

  @override
  State<ClassicHome> createState() => _ClassicHomeState();
}

class _ClassicHomeState extends State<ClassicHome> {
  String _status = '';

  VpnController get c => widget.controller;

  /// Tabs: all, favorites (when any), then one per country.
  List<(String?, String)> get _groups => [
        (null, 'همه'),
        if (c.settings.favorites.isNotEmpty) (VpnController.favoritesMode, '⭐'),
        for (final g in c.countries) (g.code, g.name),
      ];

  List<Server> _serversFor(String? code) => switch (code) {
        null => c.servers,
        VpnController.favoritesMode => c.servers.where(c.isFavorite).toList(),
        _ => c.servers.where((s) => s.countryCode == code).toList(),
      };

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _connectPressed() async {
    HapticFeedback.mediumImpact();
    if (c.state != VpnState.disconnected) return c.toggle();
    final chosen = c.chosen;
    chosen == null ? await c.connect() : await c.connectTo(chosen);
  }

  Future<void> _testConnection() async {
    if (c.state != VpnState.connected) return;
    setState(() => _status = 'در حال تست…');
    final ms = await c.measureConnection();
    if (!mounted) return;
    setState(() => _status = ms == null ? 'تست ناموفق: اینترنت از تونل عبور نمی‌کند' : 'موفق: ارتباط $ms میلی‌ثانیه طول کشید');
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final groups = _groups;
        final primary = Palette.forState(VpnState.disconnected)[0];
        return DefaultTabController(
          key: ValueKey(groups.length),
          length: groups.length,
          child: Scaffold(
            backgroundColor: Palette.bg,
            drawer: _Drawer(controller: c, open: _open),
            appBar: AppBar(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 2,
              titleSpacing: 0,
              title: Row(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset('assets/icon/icon.png', width: 28, height: 28)),
                const SizedBox(width: 10),
                const Text('MolidoVPN', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
              ]),
              actions: [
                IconButton(
                  tooltip: 'تست پینگ همه‌ی سرورها',
                  onPressed: c.pinging || c.state == VpnState.connecting
                      ? null
                      : () {
                          final code = groups[DefaultTabController.maybeOf(context)?.index ?? 0].$1;
                          c.pingServers(_serversFor(code));
                        },
                  icon: c.pinging
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.speed_rounded),
                ),
                IconButton(
                  tooltip: 'افزودن کانفیگ',
                  onPressed: () => _open(ImportScreen(controller: c)),
                  icon: const Icon(Icons.add_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'refresh':
                        c.refresh();
                        _toast('در حال به‌روزرسانی لیست سرورها…');
                      case 'usage':
                        _open(UsageScreen(controller: c));
                      case 'settings':
                        _open(SettingsScreen(controller: c));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'refresh', child: Text('به‌روزرسانی اشتراک')),
                    PopupMenuItem(value: 'usage', child: Text('آمار مصرف')),
                    PopupMenuItem(value: 'settings', child: Text('تنظیمات')),
                  ],
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                dividerColor: Colors.transparent,
                tabs: [for (final (_, label) in groups) Tab(text: label)],
              ),
            ),
            body: Column(children: [
              if (c.update != null || c.error != null) _Notice(controller: c),
              Expanded(
                child: TabBarView(children: [
                  for (final (code, _) in groups) _ServerList(controller: c, servers: _serversFor(code)),
                ]),
              ),
            ]),
            floatingActionButton: _Fab(controller: c, onPressed: _connectPressed),
            bottomNavigationBar: _StatusBar(controller: c, text: _status, onTap: _testConnection),
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final update = c.update;
    final isUpdate = update != null;
    return Material(
      color: (isUpdate ? Palette.accent : Palette.forDelay(9999)).withValues(alpha: 0.12),
      child: InkWell(
        onTap: isUpdate ? c.installUpdate : c.clearError,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(isUpdate ? Icons.system_update_rounded : Icons.error_outline_rounded,
                color: isUpdate ? Palette.accent : Palette.forDelay(9999), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isUpdate
                    ? (c.updateProgress == null
                        ? 'نسخه‌ی ${update.version} آماده است؛ برای نصب لمس کنید'
                        : 'در حال دانلود ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪')
                    : c.error!,
                style: TextStyle(fontSize: 13, color: Palette.text, height: 1.5),
              ),
            ),
            if (!isUpdate) Icon(Icons.close_rounded, size: 18, color: Palette.muted),
          ]),
        ),
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  const _ServerList({required this.controller, required this.servers});

  final VpnController controller;
  final List<Server> servers;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (servers.isEmpty) {
      return Center(
        child: Text(c.loading ? 'در حال دریافت سرورها…' : 'سروری نیست؛ از منو «به‌روزرسانی اشتراک» را بزنید',
            style: TextStyle(color: Palette.muted)),
      );
    }
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        itemCount: servers.length,
        itemBuilder: (context, i) => _ServerCard(controller: c, server: servers[i]),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.controller, required this.server});

  final VpnController controller;
  final Server server;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final selected = (c.current ?? c.chosen)?.uri == server.uri;
    final active = c.current?.uri == server.uri;
    final d = c.delays[server.uri];
    final delayText = d == null ? '' : (d <= 0 ? '-1ms' : '${d}ms');
    final delayColor = d == null ? Palette.muted : (d <= 0 ? Palette.forDelay(9999) : Palette.forDelay(d));
    final host = Uri.tryParse(server.uri.split('#').first)?.host ?? '';
    final indicator = active ? Palette.forState(VpnState.connected)[0] : Palette.accent;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: Palette.isDark ? 0 : 1,
      color: Palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        onTap: () => c.choose(server),
        onLongPress: () => c.toggleFavorite(server),
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 5, color: selected ? indicator : Colors.transparent),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FlagBadge(code: server.countryCode, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(server.displayName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.text)),
                  const SizedBox(height: 3),
                  Text(
                    host.length > 6 ? '${host.substring(0, 3)}***${host.substring(host.length - 3)}' : host,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (c.isFavorite(server)) Icon(Icons.star_rounded, size: 15, color: Colors.amber.shade600),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: Palette.border), borderRadius: BorderRadius.circular(4)),
                    child: Text(server.protocolLabel.toLowerCase(), style: TextStyle(fontSize: 11, color: Palette.muted)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(delayText,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: delayColor, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({required this.controller, required this.onPressed});

  final VpnController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final connected = state == VpnState.connected;
    final busy = state == VpnState.connecting || state == VpnState.disconnecting;
    final color = connected ? Palette.forState(VpnState.connected)[0] : (busy ? Palette.forState(VpnState.connecting)[0] : Colors.grey.shade600);
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: color,
      foregroundColor: Colors.white,
      tooltip: connected ? 'قطع اتصال' : (busy ? 'لغو' : 'اتصال'),
      child: busy
          ? const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(connected ? Icons.stop_rounded : Icons.power_settings_new_rounded, key: ValueKey(connected), size: 30),
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.text, required this.onTap});

  final VpnController controller;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final label = switch (c.state) {
      VpnState.disconnected => 'متصل نیست',
      VpnState.connecting => c.phase ?? 'در حال اتصال…',
      VpnState.disconnecting => 'در حال قطع…',
      VpnState.connected => text.isEmpty ? 'متصل است، برای تست اتصال لمس کنید' : text,
    };
    final speed = c.state == VpnState.connected ? '↓ ${formatSpeed(c.traffic.down)}  ↑ ${formatSpeed(c.traffic.up)}' : '';
    return Material(
      color: Palette.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: Palette.text))),
              if (speed.isNotEmpty)
                Text(speed, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: Palette.muted)),
              const SizedBox(width: 72), // keep clear of the connect button
            ]),
          ),
        ),
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.controller, required this.open});

  final VpnController controller;
  final void Function(Widget page) open;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final account = c.account;
    Widget item(IconData icon, String title, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: Palette.muted),
          title: Text(title, style: TextStyle(color: Palette.text)),
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        );
    return Drawer(
      backgroundColor: Palette.surface,
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: BoxDecoration(color: Palette.forState(VpnState.disconnected)[0]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/icon/icon.png', width: 56, height: 56)),
            const SizedBox(height: 10),
            const Text('MolidoVPN', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            if (Account.configured && account.user != null)
              Text(account.displayName.isEmpty ? (account.user!.email ?? '') : account.displayName,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        item(Icons.cloud_download_rounded, 'به‌روزرسانی اشتراک', c.refresh),
        item(Icons.add_link_rounded, 'کانفیگ‌های من', () => open(ImportScreen(controller: c))),
        item(Icons.insights_rounded, 'آمار مصرف', () => open(UsageScreen(controller: c))),
        item(Icons.settings_rounded, 'تنظیمات', () => open(SettingsScreen(controller: c))),
        const Divider(),
        item(Icons.bug_report_rounded, 'گزارش خطا', () => open(LogScreen(controller: c))),
        item(Icons.help_outline_rounded, 'راهنما', () => open(const HelpScreen())),
        if (Account.configured) item(Icons.logout_rounded, 'خروج از حساب', account.signOut),
      ]),
    );
  }
}
