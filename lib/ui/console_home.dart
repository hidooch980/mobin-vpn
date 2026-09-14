import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine.dart';
import '../core/network_info.dart';
import '../core/settings.dart';
import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'location_sheet.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'style.dart';
import 'widgets.dart';

/// App shell: bottom navigation with Home / Servers / Settings.
class ConsoleHome extends StatefulWidget {
  const ConsoleHome({super.key, required this.controller});

  final VpnController controller;

  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

class _ConsoleHomeState extends State<ConsoleHome> {
  final network = NetworkInfo();
  final _latency = <int>[];
  VpnState? _lastState;
  Timer? _probe, _netTimer;
  int _tab = AppNav.tab;

  VpnController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
    unawaited(network.refresh());
    _netTimer = Timer.periodic(const Duration(minutes: 2), (_) => network.refresh(proxy: c.engine.httpProxy));
    unawaited(_askReportsConsent());
  }

  /// Asked once: opt in to anonymous server quality reports.
  Future<void> _askReportsConsent() async {
    await c.ready.future;
    final s = c.settings;
    if (!mounted || s.reportsAsked) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr('کمک به انتخاب سرورهای بهتر', 'Help pick better servers')),
        content: Text(tr(
            'اجازه می‌دهید گزارش ناشناس کیفیت اتصال فرستاده شود؟ فقط شناسه‌ی ناشناس سرور، موفق یا ناموفق بودن، '
                'تأخیر، نوع شبکه و نام کلی اپراتور (مثل همراه اول یا ایرانسل) فرستاده می‌شود؛ بدون IP، نام یا اطلاعات وب‌گردی. '
                'بعداً از تنظیمات ← حریم خصوصی قابل تغییر است.',
            'Send anonymous connection quality reports? Only an anonymous server id, success or failure, latency, '
                'network type and the operator family (e.g. MCI or Irancell) are sent; no IP, name or browsing data. '
                'You can change this later in Settings → Privacy.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('نه، ممنون', 'No thanks'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('موافقم', 'Allow'))),
        ],
      ),
    );
    await s.update((x) {
      x.reportsAsked = true;
      if (accepted == true) x.anonymousReports = true;
    });
  }

  void _onController() {
    if (c.state == _lastState) return;
    _lastState = c.state;
    if (c.state == VpnState.connected) {
      _latency.clear();
      _probe?.cancel();
      _probe = Timer.periodic(const Duration(seconds: 10), (_) => _measure());
      unawaited(_measure());
    } else {
      _probe?.cancel();
    }
    if (c.state == VpnState.connected || c.state == VpnState.disconnected) {
      Future<void>.delayed(const Duration(milliseconds: 1500), () => network.refresh(proxy: c.engine.httpProxy));
    }
  }

  Future<void> _measure() async {
    final ms = await c.measureConnection();
    if (!mounted || ms == null) return;
    setState(() {
      _latency.add(ms);
      if (_latency.length > 24) _latency.removeAt(0);
    });
  }

  @override
  void dispose() {
    _probe?.cancel();
    _netTimer?.cancel();
    c.removeListener(_onController);
    super.dispose();
  }

  void _select(int i) => setState(() => _tab = AppNav.tab = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: IndexedStack(index: _tab, children: [
        _HomeTab(controller: c, network: network, latency: _latency),
        ServersScreen(controller: c, embedded: true, onConnect: () => _select(0)),
        SettingsScreen(controller: c),
      ]),
      bottomNavigationBar: _BottomBar(index: _tab, onSelect: _select),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home_rounded, tr('خانه', 'Home')),
      (Icons.dns_outlined, Icons.dns_rounded, tr('سرورها', 'Servers')),
      (Icons.settings_outlined, Icons.settings_rounded, tr('تنظیمات', 'Settings')),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Palette.isDark ? null : Border(top: BorderSide(color: Palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                for (final (i, (icon, activeIcon, label)) in items.indexed)
                  Expanded(
                    child: _BarItem(
                      icon: i == index ? activeIcon : icon,
                      label: label,
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.accent : Palette.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Palette.pillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: Duration(milliseconds: Palette.reduceMotion ? 0 : 220),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? Palette.accent.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(Palette.pillRadius),
              ),
              child: Icon(icon, size: 23, color: color),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.controller, required this.network, required this.latency});

  final VpnController controller;
  final NetworkInfo network;
  final List<int> latency;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, network, c.settings]),
      builder: (context, _) {
        final lastMs = latency.isEmpty ? null : latency.last;
        return SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentWidth),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Row(children: [
                    const _Logo(),
                    const SizedBox(width: 10),
                    Text('MolidoVPN',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Palette.text)),
                    const Spacer(),
                    _HeaderChip(controller: c),
                  ]),
                ),
                if (c.update != null) _UpdateLine(controller: c),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      const SizedBox(height: 18),
                      Center(child: _Squircle(controller: c)),
                      const SizedBox(height: 18),
                      _Status(controller: c, latency: lastMs),
                      const SizedBox(height: 14),
                      _LocationCard(controller: c),
                      const SizedBox(height: 12),
                      _ModeChips(controller: c),
                      const SizedBox(height: 12),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: ChoiceSettingRow<String>(
                          icon: Icons.dns_outlined,
                          title: 'DNS',
                          subtitle: tr('خودکار یا DNS گیمینگ ایرانی؛ از اتصال بعدی اعمال می‌شود.',
                              'Auto or Iranian gaming DNS; applies from the next connection.'),
                          options: {
                            'auto': tr('خودکار', 'Auto'),
                            for (final e in AppSettings.gamingDnsPresets.entries) e.key: e.value.$1,
                          },
                          value: c.settings.dnsPreset,
                          onChanged: (v) => c.settings.update((x) => x.dnsPreset = v),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Tiles(controller: c),
                      SectionHeader(tr('شبکه', 'Network')),
                      _Facts(controller: c, network: network, latency: latency),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/icon/icon.png',
        width: 32,
        height: 32,
        errorBuilder: (context, error, stack) => Container(
          width: 32,
          height: 32,
          color: Palette.accent.withValues(alpha: 0.16),
          child: Icon(Icons.shield_rounded, size: 20, color: Palette.accent),
        ),
      ),
    );
  }
}

(String, Color, bool) _stateLook(VpnController c) {
  final failed = c.state == VpnState.disconnected && c.error != null;
  return switch (c.state) {
    VpnState.connected => (tr('متصل', 'Connected'), Palette.connected, true),
    VpnState.connecting => (tr('در حال اتصال', 'Connecting'), Palette.connecting, true),
    VpnState.disconnecting => (tr('در حال قطع', 'Disconnecting'), Palette.connecting, true),
    VpnState.disconnected =>
      failed ? (tr('اتصال ناموفق', 'Failed'), Palette.danger, false) : (tr('قطع', 'Off'), Palette.muted, false),
  };
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final (label, color, glow) = _stateLook(controller);
    return StatusChip(label: label, color: color, glow: glow);
  }
}

class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: AppCard(
        onTap: c.installUpdate,
        color: Palette.accent.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(Icons.system_update_outlined, size: 18, color: Palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.updateProgress == null
                  ? tr('نسخه‌ی ${c.update!.version} آماده‌ی نصب است', 'Version ${c.update!.version} is ready to install')
                  : tr('دانلود ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪',
                      'Downloading ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}%'),
              style: TextStyle(color: Palette.accent, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(chevronEnd, color: Palette.accent),
        ]),
      ),
    );
  }
}

/// Hero connect control: a rounded square with a gradient ring; glows while connecting.
class _Squircle extends StatefulWidget {
  const _Squircle({required this.controller});

  final VpnController controller;

  @override
  State<_Squircle> createState() => _SquircleState();
}

class _SquircleState extends State<_Squircle> with SingleTickerProviderStateMixin {
  static const double _size = 190, _radius = 64, _ring = 4;
  bool _down = false;
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.state == VpnState.connecting || c.state == VpnState.disconnecting;
    final connected = c.state == VpnState.connected;
    final failed = c.state == VpnState.disconnected && c.error != null;
    final animate = busy && !Palette.reduceMotion;
    if (animate && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!animate && _pulse.isAnimating) _pulse.stop();

    final ring = failed
        ? [Palette.danger, Palette.danger.withValues(alpha: 0.6)]
        : busy
            ? [Palette.connecting, Palette.accent]
            : [Palette.accent, Palette.connected];
    final glowColor = failed ? Palette.danger : (busy ? Palette.connecting : (connected ? Palette.connected : Palette.accent));
    final label = switch (c.state) {
      VpnState.connected => tr('قطع اتصال', 'Disconnect'),
      VpnState.connecting => tr('لغو اتصال', 'Cancel'),
      VpnState.disconnecting => tr('در حال قطع', 'Stopping'),
      _ => tr('اتصال', 'Connect'),
    };
    final fg = connected ? Palette.bg : (failed ? Palette.danger : (busy ? Palette.connecting : Palette.accent));

    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            HapticFeedback.selectionClick();
            c.toggle();
          },
          child: AnimatedScale(
            scale: _down ? 0.96 : 1,
            duration: Duration(milliseconds: _down ? 90 : 180),
            curve: Curves.easeOutCubic,
            child: SizedBox.square(
              dimension: _size + 40,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final t = animate ? Curves.easeInOut.transform(_pulse.value) : (busy ? 0.6 : 0.0);
                    final base = connected ? 0.35 : 0.14;
                    return Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: ring),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: busy ? 0.18 + 0.32 * t : base),
                            blurRadius: busy ? 22 + 22 * t : 30,
                            spreadRadius: busy ? 1 + 6 * t : 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(_ring),
                      child: child,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_radius - _ring),
                      color: connected ? null : Palette.surface,
                      gradient: connected
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Palette.accent, Palette.connected],
                            )
                          : null,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.power_settings_new_rounded, size: 64, color: fg),
                      const SizedBox(height: 8),
                      Text(label,
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: connected ? Palette.bg : Palette.text)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.latency});

  final VpnController controller;
  final int? latency;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (title, color, _) = _stateLook(c);
    final failed = c.state == VpnState.disconnected && c.error != null;
    final connected = c.state == VpnState.connected;
    final sub = switch (c.state) {
      VpnState.connected => c.current == null
          ? ''
          : (c.activeMember != null
              ? '${serverTitle(c.current!)} · ${tr('مسیر فعال', 'active path')}: ${c.activeMember}'
              : c.switchedToBackup
                  ? '${serverTitle(c.current!)} · ${tr('به سرور پشتیبان منتقل شد', 'switched to backup server')}'
                  : serverTitle(c.current!)),
      VpnState.connecting => c.phase ?? '',
      _ => failed ? c.error! : tr('برای اتصال دکمه را بزنید', 'Tap the button to connect'),
    };
    final ms = latency ?? c.currentDelay;
    return Column(children: [
      Text(
          connected
              ? tr('متصل هستید', 'You are protected')
              : (c.state == VpnState.disconnected && !failed ? tr('متصل نیست', 'Not connected') : title),
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: connected ? Palette.connected : (failed ? Palette.danger : Palette.text))),
      const SizedBox(height: 4),
      SizedBox(
        height: 40,
        child: GestureDetector(
          onTap: failed ? c.clearError : null,
          child: Text(sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: failed ? color : Palette.muted)),
        ),
      ),
      if (c.state == VpnState.connecting && c.progress != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: c.progress, minHeight: 4, color: Palette.accent, backgroundColor: Palette.raised),
          ),
        ),
      if (connected && c.current != null)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(ms == null ? tr('در حال سنجش…', 'Measuring…') : '$ms ms',
              textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12.5, color: Palette.forDelay(ms))),
          Text('  ·  ', style: TextStyle(fontSize: 12, color: Palette.muted.withValues(alpha: 0.5))),
          Text(c.current!.protocolLabel, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
        ]),
    ]);
  }
}

bool _serverless(String transport) => transport == 'warp' || transport == 'psiphon' || transport == 'tor';

String _routeLabel(String transport) => switch (transport) {
      'v2ray' => tr('سرورهای V2Ray', 'V2Ray servers'),
      'warp' => tr('Cloudflare WARP (رایگان)', 'Cloudflare WARP (free)'),
      'psiphon' => tr('Psiphon (رایگان)', 'Psiphon (free)'),
      'tor' => tr('Tor (رایگان)', 'Tor (free)'),
      _ => tr('خودکار', 'Auto'),
    };

/// Current exit: flag, location name and mode. Opens the location picker.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final transport = c.settings.transport;
    final current = c.current;
    final code = current?.countryCode ??
        (_serverless(transport) ? (transport == 'warp' ? VpnController.warpCode : null) : c.selectedCountry);
    final title = current != null ? serverTitle(current) : (_serverless(transport) ? _routeLabel(transport) : locationLabel(c));
    final subtitle = current != null
        ? '${tr('سرور خروجی', 'Exit server')} · ${current.protocolLabel}'
        : '${tr('مسیر', 'Route')}: ${_routeLabel(transport)}';
    return AppCard(
      onTap: locked ? null : () => showLocationSheet(context, c),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
      child: Row(children: [
        FlagBadge(code: code, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.unfold_more_rounded, size: 20, color: locked ? Palette.border : Palette.muted),
        ),
      ]),
    );
  }
}

/// Auto chip followed by route chips (V2Ray, WARP, Psiphon, Tor).
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final transport = c.settings.transport;

    void setRoute(String value) => c.settings.update((s) => s.transport = value);

    Widget chip(IconData icon, String label, bool selected, VoidCallback onTap) =>
        _ModeChip(icon: icon, label: label, selected: selected, onTap: locked ? null : onTap);

    // Wrap, not a horizontal scroller: every tunnel/core stays visible at any window width.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Text(tr('تونل / هسته', 'Tunnel / core'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.muted)),
      ),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        chip(Icons.auto_awesome_rounded, tr('خودکار', 'Auto'), transport == 'auto' && c.selectedCountry == null, () {
          if (transport != 'auto') c.settings.update((s) => s.transport = 'auto');
          c.selectCountry(null);
        }),
        chip(Icons.dns_rounded, 'V2Ray', transport == 'v2ray', () => setRoute('v2ray')),
        chip(Icons.cloud_rounded, 'WARP', transport == 'warp', () => setRoute('warp')),
        chip(Icons.hub_rounded, 'Psiphon', transport == 'psiphon', () => setRoute('psiphon')),
        chip(Icons.lan_rounded, 'Tor', transport == 'tor', () => setRoute('tor')),
      ]),
    ]);
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.accent : (onTap == null ? Palette.muted : Palette.text);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Palette.pillRadius),
      side: selected ? BorderSide(color: Palette.accent) : (Palette.isDark ? BorderSide.none : BorderSide(color: Palette.border)),
    );
    return Material(
      color: selected ? Palette.accent.withValues(alpha: 0.16) : Palette.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// Download / upload / duration.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == VpnState.connected;
    Widget tile(IconData icon, String label, String value) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: Palette.accent),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.muted))),
              ]),
              const SizedBox(height: 8),
              Text(value,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: on ? Palette.text : Palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        );
    return Row(children: [
      tile(Icons.arrow_downward_rounded, tr('دانلود', 'Download'), on ? formatSpeed(c.traffic.down) : '—'),
      const SizedBox(width: 10),
      tile(Icons.arrow_upward_rounded, tr('آپلود', 'Upload'), on ? formatSpeed(c.traffic.up) : '—'),
      const SizedBox(width: 10),
      tile(Icons.timer_outlined, tr('مدت', 'Duration'),
          on && c.connectedAt != null ? formatDuration(DateTime.now().difference(c.connectedAt!)) : '—'),
    ]);
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.controller, required this.network, required this.latency});

  final VpnController controller;
  final NetworkInfo network;
  final List<int> latency;

  String get _typeLabel => L10n.en
      ? switch (network.type) {
          'wifi' => 'Wi-Fi',
          'mobile' => 'Mobile data',
          'ethernet' => 'Ethernet',
          'none' => 'No internet',
          _ => 'Internet',
        }
      : network.typeLabel;

  String get _providerLabel {
    if (!L10n.en) return network.providerLabel;
    final isp = network.isp;
    if (isp != null && isp.isNotEmpty) return isp;
    final carrier = network.carrier;
    return carrier != null && carrier.isNotEmpty ? carrier : 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final connected = c.state == VpnState.connected;
    Widget row(IconData icon, String label, String value, {Widget? trailing}) => SettingRow(
          icon: icon,
          title: label,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (trailing != null) ...[trailing, const SizedBox(width: 10)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 13.5, color: Palette.text, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
        );
    final code = network.countryCode;
    final country = code == null ? '' : countryText(code, network.countryLabel);
    final ip = network.ip == null ? '—' : '${network.ip}${country.isEmpty ? '' : ' · $country'}';
    final lastMs = latency.isEmpty ? null : latency.last;
    return CardGroup(children: [
      row(Icons.public_outlined, connected ? tr('IP خروجی', 'Exit IP') : tr('IP شما', 'Your IP'), ip),
      row(Icons.wifi_rounded, tr('شبکه', 'Network'), '$_typeLabel · $_providerLabel'),
      if (connected)
        row(Icons.speed_rounded, tr('تأخیر', 'Latency'), lastMs == null ? tr('در حال سنجش…', 'Measuring…') : '$lastMs ms',
            trailing: SizedBox(width: 90, height: 22, child: CustomPaint(painter: _LatencyGraph(latency, Palette.forDelay(lastMs))))),
    ]);
  }
}

class _LatencyGraph extends CustomPainter {
  _LatencyGraph(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = values.reduce(math.max).toDouble();
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] / peak) * (size.height - 2) - 1;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_LatencyGraph old) => true;
}
