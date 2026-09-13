import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/engine.dart';
import '../core/network_info.dart';
import '../core/vpn_controller.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'location_sheet.dart';
import 'log_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'style.dart';
import 'usage_screen.dart';

/// Connection console: quiet top, one large round control in the middle, the real status under it,
/// a single route picker, and live facts (exit IP, network, data, duration, latency) as plain rows.
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
      builder: (context, _) => Scaffold(
        backgroundColor: Palette.bg,
        drawer: _Drawer(controller: c, open: _open),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'منو',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: Icon(Icons.menu_rounded, color: Palette.muted),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'سرورها و تست پینگ',
                      onPressed: () => _open(ServersScreen(controller: c)),
                      icon: Icon(Icons.dns_outlined, color: Palette.muted),
                    ),
                  ]),
                ),
                if (c.update != null) _UpdateLine(controller: c),
                const Spacer(flex: 2),
                _Dial(controller: c),
                const SizedBox(height: 20),
                _Status(controller: c),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _RoutePicker(controller: c),
                ),
                const Spacer(flex: 3),
                _Facts(controller: c, network: network, latency: _latency),
                const SizedBox(height: 12),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return TextButton.icon(
      onPressed: c.installUpdate,
      icon: Icon(Icons.system_update_outlined, size: 18, color: Palette.accent),
      label: Text(
        c.updateProgress == null
            ? 'نسخه‌ی ${c.update!.version} آماده‌ی نصب است'
            : 'دانلود ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪',
        style: TextStyle(color: Palette.accent, fontSize: 14),
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
            dimension: 196,
            child: Stack(alignment: Alignment.center, children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) => CustomPaint(
                    size: const Size.square(196),
                    painter: _RingPainter(color: color, track: Palette.border, busy: busy, t: _spin.value, full: connected),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? color : Palette.raised,
                ),
                child: Icon(
                  connected ? Icons.power_settings_new_rounded : Icons.power_settings_new_rounded,
                  size: 64,
                  color: connected ? Palette.bg : color,
                ),
              ),
            ]),
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
  const _Status({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final failed = c.state == VpnState.disconnected && c.error != null;
    final title = switch (c.state) {
      VpnState.connected => 'متصل',
      VpnState.connecting => 'در حال اتصال',
      VpnState.disconnecting => 'در حال قطع',
      VpnState.disconnected => failed ? 'اتصال ناموفق' : 'متصل نیست',
    };
    final sub = switch (c.state) {
      VpnState.connected => c.current?.displayName ?? '',
      VpnState.connecting => c.phase ?? '',
      _ => failed ? c.error! : '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(children: [
        Text(title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: failed ? Palette.failure : (c.state == VpnState.connected ? Palette.amber : Palette.text),
            )),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: GestureDetector(
            onTap: failed ? c.clearError : null,
            child: Text(sub,
                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.5, color: Palette.muted)),
          ),
        ),
      ]),
    );
  }
}

/// Route picker: automatic, V2Ray servers, free WARP; Psiphon and Tor are listed as coming soon.
class _RoutePicker extends StatelessWidget {
  const _RoutePicker({required this.controller});

  final VpnController controller;

  static String label(String transport) => switch (transport) {
        'v2ray' => 'سرورهای V2Ray',
        'warp' => 'Cloudflare WARP (رایگان)',
        'psiphon' => 'Psiphon (رایگان)',
        'tor' => 'Tor (رایگان)',
        _ => 'خودکار',
      };

  static bool _serverless(String transport) => transport == 'warp' || transport == 'psiphon' || transport == 'tor';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final country = c.selectedCountry == null ? '' : ' · ${c.countries.where((g) => g.code == c.selectedCountry).firstOrNull?.name ?? ''}';
    return OutlinedButton(
      onPressed: locked ? null : () => _showRoutes(context, c),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: Palette.border),
        foregroundColor: Palette.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(children: [
        Icon(Icons.alt_route_rounded, color: Palette.muted, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('مسیر: ${label(c.settings.transport)}${_serverless(c.settings.transport) ? '' : country}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: locked ? Palette.muted : Palette.text)),
        ),
        Icon(Icons.expand_more_rounded, color: Palette.muted),
      ]),
    );
  }

  static void _showRoutes(BuildContext context, VpnController c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) {
        Widget option(String value, IconData icon, String title, String subtitle, {bool soon = false}) {
          final selected = c.settings.transport == value;
          return ListTile(
            enabled: !soon,
            leading: Icon(icon, color: soon ? Palette.border : (selected ? Palette.amber : Palette.muted)),
            title: Text(title, style: TextStyle(color: soon ? Palette.muted : Palette.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text(soon ? 'به‌زودی' : subtitle, style: TextStyle(color: Palette.muted, fontSize: 12.5)),
            trailing: selected ? Icon(Icons.check_rounded, color: Palette.amber) : null,
            onTap: soon
                ? null
                : () {
                    Navigator.of(sheet).pop();
                    c.settings.update((s) => s.transport = value);
                  },
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text('انتخاب مسیر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 6),
            option('auto', Icons.auto_mode_rounded, 'خودکار', 'سرورهای V2Ray، بعد WARP رایگان، و در آخر Psiphon'),
            option('v2ray', Icons.dns_outlined, 'سرورهای V2Ray', 'لیست سرورهای تست‌شده؛ کشور را هم می‌توانید انتخاب کنید'),
            option('warp', Icons.cloud_outlined, 'Cloudflare WARP', 'رایگان و بدون سرور؛ چند آدرس کلادفلر امتحان می‌شود'),
            option('psiphon', Icons.hub_outlined, 'Psiphon', 'رایگان؛ خودش سرور پیدا می‌کند؛ اتصال ممکن است تا یک دقیقه طول بکشد',
                soon: !Platform.isAndroid),
            option('tor', Icons.lan_outlined, 'Tor', 'رایگان و ناشناس؛ کندتر؛ اگر مسدود بود از پل meek استفاده می‌کند',
                soon: !Platform.isAndroid),
            if (!_serverless(c.settings.transport))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    showLocationSheet(context, c);
                  },
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('انتخاب کشور'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: Palette.text),
                ),
              ),
          ]),
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
    Widget row(String label, String value, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 12, color: Palette.muted)),
            const Spacer(),
            if (trailing != null) ...[trailing, const SizedBox(width: 10)],
            Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 14, color: Palette.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    final ip = network.ip == null ? '—' : '${network.ip}${network.countryLabel.isEmpty ? '' : ' · ${network.countryLabel}'}';
    final lastMs = latency.isEmpty ? null : latency.last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Divider(color: Palette.border, height: 1),
        row(connected ? 'IP خروجی' : 'IP شما', ip),
        Divider(color: Palette.border, height: 1),
        row('شبکه', '${network.typeLabel} · ${network.providerLabel}'),
        if (connected) ...[
          Divider(color: Palette.border, height: 1),
          row('مصرف', '↓ ${formatSpeed(c.traffic.down)}   ↑ ${formatSpeed(c.traffic.up)}'),
          Divider(color: Palette.border, height: 1),
          row('مدت', c.connectedAt == null ? '—' : formatDuration(DateTime.now().difference(c.connectedAt!))),
          Divider(color: Palette.border, height: 1),
          row('تأخیر', lastMs == null ? 'در حال سنجش…' : '$lastMs ms',
              trailing: SizedBox(width: 90, height: 22, child: CustomPaint(painter: _LatencyGraph(latency, Palette.amber)))),
        ],
        Divider(color: Palette.border, height: 1),
      ]),
    );
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
      child: SafeArea(
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text('MolidoVPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text)),
          ),
          Divider(color: Palette.border),
          item(Icons.dns_outlined, 'سرورها و تست پینگ', () => open(ServersScreen(controller: c))),
          item(Icons.cloud_download_outlined, 'به‌روزرسانی سرورها', c.refresh),
          item(Icons.add_link_rounded, 'کانفیگ‌های من', () => open(ImportScreen(controller: c))),
          item(Icons.insights_outlined, 'آمار مصرف', () => open(UsageScreen(controller: c))),
          item(Icons.settings_outlined, 'تنظیمات', () => open(SettingsScreen(controller: c))),
          Divider(color: Palette.border),
          item(Icons.bug_report_outlined, 'گزارش خطا', () => open(LogScreen(controller: c))),
          item(Icons.help_outline_rounded, 'راهنما', () => open(const HelpScreen())),
        ]),
      ),
    );
  }
}
