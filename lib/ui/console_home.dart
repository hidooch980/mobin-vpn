import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine.dart';
import '../core/network_info.dart';
import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'location_sheet.dart';
import 'log_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'style.dart';
import 'usage_screen.dart';
import 'widgets.dart';

/// Home screen in the Android app's structure: header with status chip and settings, one large round
/// connect control, status + detail line, live stat tiles, the exit/route card and network facts.
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

  VpnController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
    unawaited(network.refresh());
    _netTimer = Timer.periodic(const Duration(minutes: 2), (_) => network.refresh(proxy: c.engine.httpProxy));
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

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, network, c.settings]),
      builder: (context, _) {
        final lastMs = _latency.isEmpty ? null : _latency.last;
        return Scaffold(
          backgroundColor: Palette.bg,
          drawer: _Drawer(controller: c, open: _open),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kContentWidth),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                    child: Row(children: [
                      Builder(
                        builder: (context) => IconButton(
                          tooltip: 'منو',
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: Icon(Icons.menu_rounded, color: Palette.text),
                        ),
                      ),
                      Text('MolidoVPN',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: Palette.muted)),
                      const Spacer(),
                      _HeaderChip(controller: c),
                      IconButton(
                        tooltip: 'تنظیمات',
                        onPressed: () => _open(SettingsScreen(controller: c)),
                        icon: Icon(Icons.settings_outlined, color: Palette.text),
                      ),
                    ]),
                  ),
                  if (c.update != null) _UpdateLine(controller: c),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        const SizedBox(height: 10),
                        Center(child: _Dial(controller: c)),
                        const SizedBox(height: 16),
                        _Status(controller: c, latency: lastMs),
                        const SizedBox(height: 14),
                        _Tiles(controller: c),
                        const SizedBox(height: 12),
                        _ExitCard(controller: c, onServers: () => _open(ServersScreen(controller: c))),
                        const SectionHeader('شبکه'),
                        _Facts(controller: c, network: network, latency: _latency),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

(String, Color, bool) _stateLook(VpnController c) {
  final failed = c.state == VpnState.disconnected && c.error != null;
  return switch (c.state) {
    VpnState.connected => ('متصل', Palette.amber, true),
    VpnState.connecting => ('در حال اتصال', Palette.forState(VpnState.connecting).first, true),
    VpnState.disconnecting => ('در حال قطع', Palette.forState(VpnState.disconnecting).first, true),
    VpnState.disconnected => failed ? ('اتصال ناموفق', Palette.failure, false) : ('قطع', Palette.muted, false),
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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: AppCard(
        onTap: c.installUpdate,
        borderColor: Palette.accent.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(Icons.system_update_outlined, size: 18, color: Palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.updateProgress == null
                  ? 'نسخه‌ی ${c.update!.version} آماده‌ی نصب است'
                  : 'دانلود ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪',
              style: TextStyle(color: Palette.accent, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: Palette.accent),
        ]),
      ),
    );
  }
}

/// The only large filled control: presses to 97%, ring and icon follow the state.
class _Dial extends StatefulWidget {
  const _Dial({required this.controller});

  final VpnController controller;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> with SingleTickerProviderStateMixin {
  bool _down = false;
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.state == VpnState.connecting || c.state == VpnState.disconnecting;
    final connected = c.state == VpnState.connected;
    final failed = c.state == VpnState.disconnected && c.error != null;
    if (busy && !_spin.isAnimating) _spin.repeat();
    if (!busy && _spin.isAnimating) _spin.stop();
    final color = failed ? Palette.failure : (connected ? Palette.amber : Palette.accent);
    final label = switch (c.state) {
      VpnState.connected => 'قطع اتصال',
      VpnState.connecting => 'لغو اتصال',
      _ => 'اتصال',
    };
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
            scale: _down ? 0.97 : 1,
            duration: Duration(milliseconds: _down ? 90 : 180),
            curve: Curves.easeOutCubic,
            child: SizedBox.square(
              dimension: 220,
              child: Stack(alignment: Alignment.center, children: [
                // Soft halo, stronger while connected.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: connected ? 0.28 : 0.10), blurRadius: 36, spreadRadius: 2),
                    ],
                  ),
                ),
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(208),
                      painter: _RingPainter(color: color, track: Palette.border, busy: busy, t: _spin.value, full: connected),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 184,
                  height: 184,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? color : Palette.surface,
                    border: Border.all(color: connected ? color : Palette.border),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.power_settings_new_rounded, size: 60, color: connected ? Palette.bg : color),
                    const SizedBox(height: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: connected ? Palette.bg : Palette.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.track, required this.busy, required this.t, required this.full});

  final Color color, track;
  final bool busy, full;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (busy) {
      canvas.drawArc(rect, t * math.pi * 2 - math.pi / 2, math.pi * 0.6, false, paint..color = color);
    } else if (full) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color || old.busy != busy || old.full != full;
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
      VpnState.connected => c.current?.displayName ?? '',
      VpnState.connecting => c.phase ?? '',
      _ => failed ? c.error! : 'برای اتصال دکمه را بزنید',
    };
    final ms = latency ?? c.currentDelay;
    return Column(children: [
      Text(connected ? 'متصل' : (c.state == VpnState.disconnected && !failed ? 'متصل نیست' : title),
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: connected ? Palette.amber : (failed ? Palette.failure : Palette.text))),
      const SizedBox(height: 3),
      SizedBox(
        height: 40,
        child: GestureDetector(
          onTap: failed ? c.clearError : null,
          child: Text(sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: failed ? color : Palette.muted)),
        ),
      ),
      if (c.state == VpnState.connecting && c.progress != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: c.progress, minHeight: 4, color: Palette.accent, backgroundColor: Palette.border),
          ),
        ),
      if (connected && c.current != null)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(ms == null ? 'در حال سنجش…' : '$ms ms',
              textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12.5, color: Palette.forDelay(ms))),
          Text('  ·  ', style: TextStyle(fontSize: 12, color: Palette.muted.withValues(alpha: 0.5))),
          Text(c.current!.protocolLabel, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
        ]),
    ]);
  }
}

/// Download / upload / duration, like the Android home tiles.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == VpnState.connected;
    Widget tile(IconData icon, String label, String value) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 15, color: Palette.accent),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: Palette.muted)),
              ]),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: on ? Palette.text : Palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        );
    return Row(children: [
      tile(Icons.arrow_downward_rounded, 'دانلود', on ? formatSpeed(c.traffic.down) : '—'),
      const SizedBox(width: 9),
      tile(Icons.arrow_upward_rounded, 'آپلود', on ? formatSpeed(c.traffic.up) : '—'),
      const SizedBox(width: 9),
      tile(Icons.timer_outlined, 'مدت', on && c.connectedAt != null ? formatDuration(DateTime.now().difference(c.connectedAt!)) : '—'),
    ]);
  }
}

/// Exit node + route: which location/mode is used and how, with shortcuts to change it.
class _ExitCard extends StatelessWidget {
  const _ExitCard({required this.controller, required this.onServers});

  final VpnController controller;
  final VoidCallback onServers;

  static String routeLabel(String transport) => switch (transport) {
        'v2ray' => 'سرورهای V2Ray',
        'warp' => 'Cloudflare WARP (رایگان)',
        'psiphon' => 'Psiphon (رایگان)',
        'tor' => 'Tor (رایگان)',
        _ => 'خودکار',
      };

  static bool serverless(String transport) => transport == 'warp' || transport == 'psiphon' || transport == 'tor';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final transport = c.settings.transport;
    final current = c.current;
    final code = current?.countryCode ?? (serverless(transport) ? (transport == 'warp' ? VpnController.warpCode : null) : c.selectedCountry);
    final title = current != null ? current.displayName : (serverless(transport) ? routeLabel(transport) : locationLabel(c));
    final subtitle = current != null
        ? 'سرور خروجی · ${current.protocolLabel}'
        : 'مسیر: ${routeLabel(transport)}${c.isGaming ? ' · پینگ پایدار برای بازی' : ''}';
    return CardGroup(children: [
      InkWell(
        onTap: locked ? null : () => _showRoutes(context, c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            FlagBadge(code: code, size: 42),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.text)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
              ]),
            ),
            Icon(Icons.expand_more_rounded, color: locked ? Palette.border : Palette.muted),
          ]),
        ),
      ),
      NavSettingRow(
        icon: Icons.dns_outlined,
        title: 'سرورها و تست پینگ',
        value: '${c.servers.length}',
        onTap: onServers,
      ),
    ]);
  }

  static void _showRoutes(BuildContext context, VpnController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.bg,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: kContentWidth + 40),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) {
        Widget option(String value, IconData icon, String title, String subtitle, {bool soon = false}) {
          final selected = c.settings.transport == value;
          return SettingRow(
            icon: icon,
            title: title,
            subtitle: soon ? 'به‌زودی' : subtitle,
            trailing: selected ? Icon(Icons.check_circle_rounded, color: Palette.accent) : null,
            onTap: soon
                ? null
                : () {
                    Navigator.of(sheet).pop();
                    if (serverless(value) && c.isGaming) c.selectCountry(null);
                    c.settings.update((s) => s.transport = value);
                  },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2))),
              const SectionHeader('حالت اتصال'),
              CardGroup(children: [
                SettingRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'هوشمند',
                  subtitle: 'سریع‌ترین سرور برای اینترنت شما',
                  trailing: c.selectedCountry == null && !serverless(c.settings.transport)
                      ? Icon(Icons.check_circle_rounded, color: Palette.accent)
                      : null,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    if (serverless(c.settings.transport)) c.settings.update((s) => s.transport = 'auto');
                    c.selectCountry(null);
                  },
                ),
                SettingRow(
                  icon: Icons.sports_esports_outlined,
                  title: 'حالت گیمینگ',
                  subtitle: 'کمترین و پایدارترین پینگ از سرورهای نزدیک؛ مناسب بازی‌های آنلاین',
                  trailing: c.isGaming ? Icon(Icons.check_circle_rounded, color: Palette.accent) : null,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    if (serverless(c.settings.transport)) c.settings.update((s) => s.transport = 'auto');
                    c.selectCountry(VpnController.gamingMode);
                  },
                ),
                NavSettingRow(
                  icon: Icons.public_rounded,
                  title: 'انتخاب کشور',
                  value: locationLabel(c),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    showLocationSheet(context, c);
                  },
                ),
              ]),
              const SectionHeader('مسیر'),
              CardGroup(children: [
                option('auto', Icons.alt_route_rounded, 'خودکار', 'سرورهای V2Ray، بعد WARP رایگان، و در آخر Psiphon'),
                option('v2ray', Icons.dns_outlined, 'سرورهای V2Ray', 'لیست سرورهای تست‌شده؛ کشور را هم می‌توانید انتخاب کنید'),
                option('warp', Icons.cloud_outlined, 'Cloudflare WARP', 'رایگان و بدون سرور؛ چند آدرس کلادفلر امتحان می‌شود'),
                option('psiphon', Icons.hub_outlined, 'Psiphon', 'رایگان؛ خودش سرور پیدا می‌کند؛ اتصال ممکن است تا یک دقیقه طول بکشد',
                    soon: !Platform.isAndroid),
                option('tor', Icons.lan_outlined, 'Tor', 'رایگان و ناشناس؛ کندتر؛ اگر مسدود بود از پل meek استفاده می‌کند',
                    soon: !Platform.isAndroid),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.controller, required this.network, required this.latency});

  final VpnController controller;
  final NetworkInfo network;
  final List<int> latency;

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
    final ip = network.ip == null ? '—' : '${network.ip}${network.countryLabel.isEmpty ? '' : ' · ${network.countryLabel}'}';
    final lastMs = latency.isEmpty ? null : latency.last;
    return CardGroup(children: [
      row(Icons.public_outlined, connected ? 'IP خروجی' : 'IP شما', ip),
      row(Icons.wifi_rounded, 'شبکه', '${network.typeLabel} · ${network.providerLabel}'),
      if (connected)
        row(Icons.speed_rounded, 'تأخیر', lastMs == null ? 'در حال سنجش…' : '$lastMs ms',
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
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color);
  }

  @override
  bool shouldRepaint(_LatencyGraph old) => true;
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.controller, required this.open});

  final VpnController controller;
  final void Function(Widget page) open;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget item(IconData icon, String title, VoidCallback onTap) => NavSettingRow(
          icon: icon,
          title: title,
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        );
    return Drawer(
      backgroundColor: Palette.bg,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
            child: Text('MolidoVPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.text)),
          ),
          const SectionHeader('سرورها'),
          CardGroup(children: [
            item(Icons.dns_outlined, 'سرورها و تست پینگ', () => open(ServersScreen(controller: c))),
            item(Icons.cloud_download_outlined, 'به‌روزرسانی سرورها', c.refresh),
            item(Icons.add_link_rounded, 'کانفیگ‌های من', () => open(ImportScreen(controller: c))),
          ]),
          const SectionHeader('برنامه'),
          CardGroup(children: [
            item(Icons.insights_outlined, 'آمار مصرف', () => open(UsageScreen(controller: c))),
            item(Icons.settings_outlined, 'تنظیمات', () => open(SettingsScreen(controller: c))),
            item(Icons.bug_report_outlined, 'گزارش خطا', () => open(LogScreen(controller: c))),
            item(Icons.help_outline_rounded, 'راهنما', () => open(const HelpScreen())),
          ]),
        ]),
      ),
    );
  }
}
