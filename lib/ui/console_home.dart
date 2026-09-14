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

/// Single scrolling home, laid out like the Android app: header, connect squircle, status,
/// exit card, mode chips, DNS chip, servers row and stats. Settings and Servers open as full pages.
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
    if (AppNav.tab == 2) {
      // A theme/language switch rebuilt the app from Settings: reopen it.
      AppNav.tab = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSettings();
      });
    }
    unawaited(_askReportsConsent());
  }

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: c)));

  void _openServers() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServersScreen(controller: c)));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListenableBuilder(
        listenable: Listenable.merge([c, network, c.settings]),
        builder: (context, _) {
          final lastMs = _latency.isEmpty ? null : _latency.last;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kContentWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    _Header(controller: c, onSettings: _openSettings),
                    if (c.update != null) _UpdateLine(controller: c),
                    const SizedBox(height: 14),
                    Center(child: _Squircle(controller: c)),
                    _Status(controller: c, latency: lastMs),
                    const SizedBox(height: 12),
                    _ExitCard(controller: c, network: network, latency: _latency),
                    const SizedBox(height: 12),
                    _ModeChips(controller: c),
                    const SizedBox(height: 8),
                    _DnsChip(controller: c),
                    const SizedBox(height: 12),
                    CardGroup(children: [
                      NavSettingRow(
                        icon: Icons.dns_outlined,
                        title: tr('سرورها', 'Servers'),
                        value: digits(c.servers.length),
                        onTap: _openServers,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _Tiles(controller: c),
                    SectionHeader(tr('شبکه', 'Network')),
                    _Facts(controller: c, network: network, latency: _latency),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Logo + name + status pill, gear at the end.
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onSettings});

  final VpnController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final (label, color, glow) = _stateLook(controller);
    return Row(children: [
      const _Logo(),
      const SizedBox(width: 10),
      Text('MolidoVPN',
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Palette.text)),
      const SizedBox(width: 10),
      Flexible(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(Palette.pillRadius)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glow ? color : Palette.muted,
                boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)] : null,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: glow ? color : Palette.text)),
            ),
          ]),
        ),
      ),
      const Spacer(),
      IconButton(
        tooltip: tr('تنظیمات', 'Settings'),
        onPressed: onSettings,
        icon: Icon(Icons.settings_rounded, color: Palette.text),
      ),
    ]);
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
    VpnState.connecting => (tr('در حال اتصال...', 'Connecting...'), Palette.connecting, true),
    VpnState.disconnecting => (tr('در حال قطع', 'Disconnecting'), Palette.connecting, true),
    VpnState.disconnected =>
      failed ? (tr('اتصال ناموفق', 'Failed'), Palette.danger, true) : (tr('متصل نیست', 'Not connected'), Palette.muted, false),
  };
}

class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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

/// Android OrbitDialView: 190 px squircle, 64 corner, 4 px sweep-gradient ring, glow that breathes while
/// connecting, power glyph with a caption, or the session timer while connected.
class _Squircle extends StatefulWidget {
  const _Squircle({required this.controller});

  final VpnController controller;

  @override
  State<_Squircle> createState() => _SquircleState();
}

class _SquircleState extends State<_Squircle> with SingleTickerProviderStateMixin {
  static const double _size = 190, _radius = 64, _ring = 4;
  bool _down = false;
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
  Timer? _clock;

  @override
  void dispose() {
    _clock?.cancel();
    _loop.dispose();
    super.dispose();
  }

  void _syncClock(bool connected) {
    if (connected && _clock == null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!connected && _clock != null) {
      _clock!.cancel();
      _clock = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.state == VpnState.connecting || c.state == VpnState.disconnecting;
    final connected = c.state == VpnState.connected;
    final failed = c.state == VpnState.disconnected && c.error != null;
    final idle = c.state == VpnState.disconnected && !failed;
    final animate = busy && !Palette.reduceMotion;
    if (animate && !_loop.isAnimating) _loop.repeat();
    if (!animate && _loop.isAnimating) _loop.stop();
    _syncClock(connected);

    final (Color start, Color end) = failed
        ? (Palette.danger, Color.lerp(Palette.danger, Palette.connecting, 0.35)!)
        : busy
            ? (Palette.connecting, Palette.accent)
            : (Palette.accent, Palette.connected);
    final ringAlpha = idle ? 0.6 : 1.0;
    final iconColor = connected
        ? Palette.connected
        : (busy ? Palette.connecting : (failed ? Palette.danger : Palette.accent));
    final caption = switch (c.state) {
      VpnState.connecting => c.progress != null
          ? tr('در حال اتصال ${digits((c.progress! * 100).round())}٪', 'CONNECTING ${(c.progress! * 100).round()}%')
          : tr('در حال اتصال...', 'CONNECTING'),
      VpnState.disconnecting => tr('در حال قطع...', 'STOPPING'),
      VpnState.connected => tr('متصل شد', 'Connected'),
      _ => failed ? tr('تلاش مجدد', 'RETRY') : tr('برای اتصال لمس کنید', 'TAP TO CONNECT'),
    };
    final captionColor = failed ? Palette.errorText : (busy ? Palette.connecting : Palette.muted);
    final timer = connected && c.connectedAt != null ? formatDuration(DateTime.now().difference(c.connectedAt!)) : null;

    return Semantics(
      button: true,
      label: connected ? tr('قطع اتصال', 'Disconnect') : (busy ? tr('در حال اتصال', 'Connecting') : tr('اتصال', 'Connect')),
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
            scale: _down ? 0.965 : 1,
            duration: Duration(milliseconds: _down ? 110 : 190),
            curve: Curves.easeOutCubic,
            child: SizedBox.square(
              dimension: _size + 56,
              child: Center(
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, child) {
                    final f = animate ? _loop.value : 0.0;
                    final pulse = animate ? (f < 0.5 ? f * 2 : (1 - f) * 2) : (busy ? 0.5 : 0.0);
                    final (Color glow, double alpha, double blur) = busy
                        ? (Palette.connecting, 0.28 + 0.40 * pulse, 16 + 14 * pulse)
                        : connected
                            ? (Palette.connected, 0.30, 22.0)
                            : failed
                                ? (Palette.danger, 0.24, 14.0)
                                : (Palette.accent, 0.16, 14.0);
                    return Container(
                      width: _size,
                      height: _size,
                      padding: const EdgeInsets.all(_ring),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        gradient: SweepGradient(
                          colors: [
                            start.withValues(alpha: ringAlpha),
                            end.withValues(alpha: ringAlpha),
                            start.withValues(alpha: ringAlpha),
                          ],
                          stops: const [0, 0.5, 1],
                          transform: GradientRotation(f * 2 * math.pi),
                        ),
                        boxShadow: [BoxShadow(color: glow.withValues(alpha: alpha), blurRadius: blur * 2, spreadRadius: 1)],
                      ),
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_radius - _ring),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Palette.raised, Palette.surface],
                      ),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.power_settings_new_rounded, size: 56, color: iconColor),
                      const SizedBox(height: 10),
                      if (timer != null) ...[
                        Text(timer,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                                fontSize: 22,
                                fontFamily: Palette.monoFamily,
                                fontFamilyFallback: Palette.monoFallback,
                                letterSpacing: Palette.spacing(0.12, 22),
                                color: Palette.text)),
                        Text(tr('زمان اتصال', 'SESSION'),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: Palette.spacing(0.12, 9.5),
                                color: Palette.muted)),
                      ] else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: Palette.spacing(0.12, 12),
                                  color: captionColor)),
                        ),
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

/// Title + two-line detail + "`mode` · latency `ms`".
class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.latency});

  final VpnController controller;
  final int? latency;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (title, color, _) = _stateLook(c);
    final failed = c.state == VpnState.disconnected && c.error != null;
    final idle = c.state == VpnState.disconnected && !failed;
    final connected = c.state == VpnState.connected;
    final detail = switch (c.state) {
      VpnState.connected => c.current == null
          ? ''
          : '${c.activeMember != null ? '${serverTitle(c.current!)} · ${tr('مسیر فعال', 'active path')}: ${c.activeMember}' : c.switchedToBackup ? '${serverTitle(c.current!)} · ${tr('به سرور پشتیبان منتقل شد', 'switched to backup server')}' : serverTitle(c.current!)}'
              '${c.exitInIran ? ' · ${tr(VpnController.exitIranMessage, 'Exit is in Iran; some services (like Gemini) will not work')}' : ''}',
      VpnState.connecting => c.phase ?? '',
      _ => failed ? c.error! : '',
    };
    final ms = connected ? (latency ?? c.currentDelay) : null;
    final mode = connected && c.current != null ? c.current!.protocolLabel : _routeShort(c.settings.transport);
    final chipColor = Palette.muted.withValues(alpha: 0.95);
    return Column(children: [
      if (!idle) ...[
        const SizedBox(height: 4),
        Text(connected ? tr('متصل هستید', 'You are protected') : title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: L10n.en ? 21.0 : 25.0,
                fontWeight: FontWeight.w700,
                color: connected ? Palette.connected : (failed ? Palette.errorText : color))),
        const SizedBox(height: 3),
        GestureDetector(
          onTap: failed ? c.clearError : null,
          child: Text(detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: failed ? Palette.danger : Palette.muted)),
        ),
      ],
      if (c.state == VpnState.connecting && c.progress != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: c.progress, minHeight: 3, color: Palette.connecting, backgroundColor: Palette.raised),
          ),
        ),
      const SizedBox(height: 7),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(mode, style: TextStyle(fontSize: 12, color: chipColor)),
        Text('  ·  ', style: TextStyle(fontSize: 12, color: Palette.muted.withValues(alpha: 0.5))),
        Text(ms == null ? tr('تاخیر —', 'Latency —') : tr('تاخیر ${digits(ms)} ms', 'Latency $ms ms'),
            style: TextStyle(fontSize: 12, color: ms == null ? chipColor : Palette.forDelay(ms))),
      ]),
    ]);
  }
}

String _routeShort(String transport) => switch (transport) {
      'v2ray' => 'V2Ray',
      'warp' => 'WARP',
      'psiphon' => 'Psiphon',
      'tor' => 'Tor',
      _ => tr('خودکار', 'Auto'),
    };

/// Android ExitNodeCard: flag tile, caption, big monospace IP, country line, sparkline. Opens the location picker.
class _ExitCard extends StatelessWidget {
  const _ExitCard({required this.controller, required this.network, required this.latency});

  final VpnController controller;
  final NetworkInfo network;
  final List<int> latency;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final tunnelled = c.state == VpnState.connected;
    final ip = network.ip;
    final code = network.countryCode;
    final country = code == null ? '' : code.toUpperCase();
    final measuring = ip == null && c.state != VpnState.disconnected;
    final location = measuring
        ? tr('در حال خواندن از داخل تونل', 'reading from inside the tunnel')
        : country.isNotEmpty && tunnelled
            ? '$country · ${tr('از تونل', 'tunnelled')}'
            : country.isNotEmpty
                ? country
                : (tunnelled ? tr('از تونل', 'tunnelled') : tr('بدون تونل', 'not tunnelled'));
    final radius = BorderRadius.circular(22);
    final fill = Color.lerp(Palette.surface, Palette.text, 0.03)!;
    return Semantics(
      button: !locked,
      label: tr('انتخاب سرور یا کشور', 'Choose server or country'),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Palette.text.withValues(alpha: 0.09)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: locked ? null : () => showLocationSheet(context, c),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(13, 11, 15, 11),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color.lerp(Palette.surface, Palette.bg, 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Palette.text.withValues(alpha: 0.10)),
                ),
                child: FlagBadge(code: tunnelled ? (c.current?.countryCode ?? code) : code, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tunnelled ? tr('نود خروجی', 'EXIT NODE') : tr('آی‌پی شما', 'YOUR IP'),
                      style: TextStyle(
                          fontSize: L10n.en ? 9.5 : 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: Palette.spacing(0.14, 9.5),
                          color: Palette.faint.withValues(alpha: 0.95))),
                  const SizedBox(height: 2),
                  Text(
                    measuring ? tr('در حال سنجش…', 'measuring…') : (ip ?? tr('آی‌پی در دسترس نیست', 'IP unavailable')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: ip == null ? 13.0 : (ip.length > 20 ? 12.5 : 17.0),
                      fontWeight: FontWeight.w500,
                      fontFamily: Palette.monoFamily,
                      fontFamilyFallback: Palette.monoFallback,
                      color: Palette.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Palette.faint.withValues(alpha: 0.9))),
                ]),
              ),
              SizedBox(width: 52, height: 24, child: CustomPaint(painter: _Sparkline(List.of(latency), Palette.accent))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Smooth line over recent latency samples; a calm sine wave until there are enough samples.
class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (values.length < 2) {
      for (var i = 0; i <= 26; i++) {
        final x = size.width * i / 26;
        final y = size.height / 2 + math.sin(i / 26 * 3 * math.pi) * size.height * 0.28;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
    } else {
      final peak = values.reduce(math.max).toDouble();
      final low = values.reduce(math.min).toDouble();
      final span = math.max(1.0, peak - low);
      for (var i = 0; i < values.length; i++) {
        final x = size.width * i / (values.length - 1);
        final y = size.height - 2 - ((values[i] - low) / span) * (size.height - 4);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_Sparkline old) => true;
}

/// Mode rail: three equal-width chips per row (Auto, V2Ray, WARP / Psiphon, Tor).
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.state != VpnState.disconnected;
    final transport = c.settings.transport;

    void setRoute(String value) => c.settings.update((s) => s.transport = value);

    final chips = <Widget>[
      _ModeChip(
        label: tr('خودکار', 'Auto'),
        selected: transport == 'auto',
        onTap: locked
            ? null
            : () {
                if (transport != 'auto') setRoute('auto');
                c.selectCountry(null);
              },
      ),
      _ModeChip(label: 'V2Ray', selected: transport == 'v2ray', onTap: locked ? null : () => setRoute('v2ray')),
      _ModeChip(label: 'WARP', selected: transport == 'warp', onTap: locked ? null : () => setRoute('warp')),
      _ModeChip(label: 'Psiphon', selected: transport == 'psiphon', onTap: locked ? null : () => setRoute('psiphon')),
      _ModeChip(label: 'Tor', selected: transport == 'tor', onTap: locked ? null : () => setRoute('tor')),
    ];
    const perRow = 3;
    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Column(children: [
        for (var r = 0; r < chips.length; r += perRow) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(children: [
            for (var i = r; i < r + perRow; i++) ...[
              if (i > r) const SizedBox(width: 8),
              Expanded(child: i < chips.length ? chips[i] : const SizedBox.shrink()),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Palette.pillRadius),
      side: BorderSide(color: selected ? Palette.accent : Palette.raised, width: selected ? 1.4 : 1),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Palette.bg : Palette.raised,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Center(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Palette.accentText : Palette.muted)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "DNS: …" chip under the mode rail; opens the DNS picker.
class _DnsChip extends StatelessWidget {
  const _DnsChip({required this.controller});

  final VpnController controller;

  static String summary(String preset) =>
      AppSettings.gamingDnsPresets[preset]?.$1 ?? tr('خودکار', 'Auto');

  Future<void> _pick(BuildContext context) async {
    final s = controller.settings;
    final options = <String, String>{
      'auto': tr('خودکار', 'Auto'),
      for (final e in AppSettings.gamingDnsPresets.entries) e.key: e.value.$1,
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.sheet,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Palette.cardRadius))),
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          SectionHeader(tr('DNS (از اتصال بعدی اعمال می‌شود)', 'DNS (applies from the next connection)')),
          CardGroup(children: [
            for (final e in options.entries)
              SettingRow(
                title: e.value,
                onTap: () => Navigator.pop(context, e.key),
                trailing: e.key == s.dnsPreset ? Icon(Icons.check_rounded, color: Palette.accent) : null,
              ),
          ]),
        ]),
      ),
    );
    if (picked != null && picked != s.dnsPreset) await s.update((x) => x.dnsPreset = picked);
  }

  @override
  Widget build(BuildContext context) {
    final locked = controller.state != VpnState.disconnected;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Palette.pillRadius));
    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: Palette.raised,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: locked ? null : () => _pick(context),
          child: SizedBox(
            height: 34,
            child: Center(
              child: Text('DNS: ${summary(controller.settings.dnsPreset)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
            ),
          ),
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
