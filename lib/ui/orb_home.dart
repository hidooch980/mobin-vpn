import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/network_info.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'connect_orb.dart';
import 'flag_badge.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'location_sheet.dart';
import 'log_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'style.dart';
import 'usage_screen.dart';

/// Home: large connect orb in the middle, the user's network (type, operator, IP) above the stats,
/// automatic/selected location card and quick links below. Emerald logo colors.
class OrbHome extends StatefulWidget {
  const OrbHome({super.key, required this.controller});

  final VpnController controller;

  @override
  State<OrbHome> createState() => _OrbHomeState();
}

class _OrbHomeState extends State<OrbHome> {
  final network = NetworkInfo();
  VpnState? _lastState;
  Timer? _timer;

  VpnController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
    unawaited(network.refresh());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refreshNetwork());
  }

  void _refreshNetwork() => network.refresh(proxy: c.engine.httpProxy);

  // Re-read IP and provider whenever the tunnel goes up or down (own IP ↔ VPN IP).
  void _onController() {
    if (c.state == _lastState) return;
    final settled = c.state == VpnState.connected || c.state == VpnState.disconnected;
    _lastState = c.state;
    if (settled) Future<void>.delayed(const Duration(milliseconds: 1500), _refreshNetwork);
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_onController);
    super.dispose();
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, network]),
      builder: (context, _) {
        final colors = Palette.forState(c.state);
        return Scaffold(
          backgroundColor: Palette.bg,
          drawer: _Menu(controller: c, open: _open),
          body: AuroraBackground(
            colors: colors,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: [
                      _TopBar(open: _open, controller: c),
                      if (c.update != null || c.error != null) _Notice(controller: c),
                      const Spacer(),
                      _StatusTitle(controller: c, colors: colors),
                      const SizedBox(height: 6),
                      ConnectOrb(state: c.state, colors: colors, progress: c.progress, onTap: c.toggle),
                      const Spacer(),
                      _NetworkCard(network: network, controller: c, onRefresh: _refreshNetwork),
                      const SizedBox(height: 10),
                      _Stats(controller: c),
                      const SizedBox(height: 10),
                      _LocationCard(controller: c, onServers: () => _open(ServersScreen(controller: c))),
                      const SizedBox(height: 14),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.open, required this.controller});

  final void Function(Widget page) open;
  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: Palette.text),
          style: IconButton.styleFrom(
            backgroundColor: Palette.surface,
            side: BorderSide(color: Palette.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Builder(builder: (context) => action(Icons.menu_rounded, 'منو', () => Scaffold.of(context).openDrawer())),
        const SizedBox(width: 10),
        ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/icon/icon.png', width: 34, height: 34)),
        const SizedBox(width: 8),
        Text('MolidoVPN', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Palette.text)),
        const Spacer(),
        action(Icons.dns_rounded, 'سرورها و تست پینگ', () => open(ServersScreen(controller: controller))),
      ]),
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
    final color = update != null ? Palette.accent : Palette.forDelay(9999);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: update != null ? c.installUpdate : c.clearError,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(update != null ? Icons.system_update_rounded : Icons.error_outline_rounded, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  update != null
                      ? (c.updateProgress == null
                          ? 'نسخه‌ی ${update.version} آماده است؛ لمس کنید'
                          : 'دانلود ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪')
                      : c.error!,
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: Palette.text),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusTitle extends StatelessWidget {
  const _StatusTitle({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (title, sub) = switch (c.state) {
      VpnState.disconnected => ('محافظت نمی‌شوید', 'برای اتصال، دکمه را لمس کنید'),
      VpnState.connecting => ('در حال اتصال…', c.phase ?? ''),
      VpnState.disconnecting => ('در حال قطع…', ''),
      VpnState.connected => ('متصل و امن', c.connectedAt == null ? '' : formatDuration(DateTime.now().difference(c.connectedAt!))),
    };
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: Text(title,
            key: ValueKey(title),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: c.state == VpnState.connected ? colors[0] : Palette.text)),
      ),
      const SizedBox(height: 4),
      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Palette.muted)),
    ]);
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.network, required this.controller, required this.onRefresh});

  final NetworkInfo network;
  final VpnController controller;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = controller.state == VpnState.connected;
    final icon = switch (network.type) {
      'wifi' => Icons.wifi_rounded,
      'mobile' => Icons.signal_cellular_alt_rounded,
      'ethernet' => Icons.settings_ethernet_rounded,
      'none' => Icons.signal_wifi_off_rounded,
      _ => Icons.public_rounded,
    };
    final title = connected ? 'IP شما پنهان است' : '${network.typeLabel} · ${network.providerLabel}';
    final ipLine = network.ip == null
        ? (network.loading ? 'در حال دریافت IP…' : 'IP در دسترس نیست')
        : '${network.ip}${network.countryLabel.isEmpty ? '' : '  ·  ${network.countryLabel}'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: connected ? Palette.accent.withValues(alpha: 0.6) : Palette.border),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Palette.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(connected ? Icons.shield_rounded : icon, color: Palette.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.text)),
            const SizedBox(height: 2),
            Text(connected ? 'IP جدید: $ipLine' : 'IP دستگاه: $ipLine',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'به‌روزرسانی',
          onPressed: network.loading ? null : onRefresh,
          icon: network.loading
              ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.accent))
              : Icon(Icons.refresh_rounded, color: Palette.muted, size: 20),
        ),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == VpnState.connected;
    Widget cell(IconData icon, String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.border)),
            child: Column(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(value,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.text, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Text(label, style: TextStyle(fontSize: 11, color: Palette.muted)),
            ]),
          ),
        );
    return Row(children: [
      cell(Icons.south_rounded, 'دانلود', on ? formatSpeed(c.traffic.down) : '—', Palette.accent),
      const SizedBox(width: 8),
      cell(Icons.north_rounded, 'آپلود', on ? formatSpeed(c.traffic.up) : '—', Palette.amber),
      const SizedBox(width: 8),
      cell(Icons.bolt_rounded, 'پینگ', c.currentDelay == null ? '—' : '${c.currentDelay} ms', Palette.forDelay(c.currentDelay)),
    ]);
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.controller, required this.onServers});

  final VpnController controller;
  final VoidCallback onServers;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final server = c.current ?? c.chosen;
    final auto = c.chosen == null;
    final title = server?.displayName ?? (c.selectedCountry == null ? 'خودکار · بهترین سرور' : 'خودکار در ${c.countries.where((g) => g.code == c.selectedCountry).firstOrNull?.name ?? ''}');
    final subtitle = auto
        ? (c.current != null ? 'خودکار · اگر قطع شد خودش عوض می‌کند' : 'سریع‌ترین سرور سالم انتخاب می‌شود')
        : 'انتخاب دستی · ${server!.protocolLabel}';
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showLocationSheet(context, c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Palette.border)),
          child: Row(children: [
            FlagBadge(code: server?.countryCode ?? c.selectedCountry, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.text)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.muted)),
              ]),
            ),
            if (!auto)
              TextButton(onPressed: () => c.choose(null), child: Text('خودکار', style: TextStyle(color: Palette.accent))),
            IconButton(tooltip: 'همه‌ی سرورها', onPressed: onServers, icon: Icon(Icons.chevron_left_rounded, color: Palette.muted)),
          ]),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.controller, required this.open});

  final VpnController controller;
  final void Function(Widget page) open;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget item(IconData icon, String title, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: Palette.accent),
          title: Text(title, style: TextStyle(color: Palette.text)),
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        );
    return Drawer(
      backgroundColor: Palette.surface,
      child: SafeArea(
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/icon/icon.png', width: 52, height: 52)),
              const SizedBox(width: 12),
              Text('MolidoVPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.text)),
            ]),
          ),
          Divider(color: Palette.border),
          item(Icons.dns_rounded, 'سرورها و تست پینگ', () => open(ServersScreen(controller: c))),
          item(Icons.cloud_download_rounded, 'به‌روزرسانی سرورها', c.refresh),
          item(Icons.add_link_rounded, 'کانفیگ‌های من', () => open(ImportScreen(controller: c))),
          item(Icons.insights_rounded, 'آمار مصرف', () => open(UsageScreen(controller: c))),
          item(Icons.settings_rounded, 'تنظیمات', () => open(SettingsScreen(controller: c))),
          Divider(color: Palette.border),
          item(Icons.bug_report_rounded, 'گزارش خطا', () => open(LogScreen(controller: c))),
          item(Icons.help_outline_rounded, 'راهنما', () => open(const HelpScreen())),
        ]),
      ),
    );
  }
}
