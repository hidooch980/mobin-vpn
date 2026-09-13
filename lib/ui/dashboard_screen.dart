import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/countries.dart';
import '../core/engine.dart';
import '../core/server.dart';
import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'location_sheet.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'style.dart';
import 'usage_screen.dart';
import 'world_map.dart';

/// Home: dotted world map with the route to the server on top; a sheet below with the connection,
/// live speed, connect mode, location tabs and the server list with ping.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final colors = Palette.forState(c.state);
        final serverCode = c.current?.countryCode ??
            (c.selectedCountry != null && countryPositions.containsKey(c.selectedCountry) ? c.selectedCountry : null);
        return Scaffold(
          backgroundColor: Palette.bg,
          body: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > 900;
              final map = _MapHeader(controller: c, colors: colors, serverCode: serverCode);
              final sheet = _Sheet(controller: c, colors: colors);
              if (wide) {
                return Row(children: [
                  Expanded(flex: 5, child: map),
                  SizedBox(width: 460, child: sheet),
                ]);
              }
              return Column(children: [
                SizedBox(height: math.max(230, box.maxHeight * 0.34), child: map),
                Expanded(child: sheet),
              ]);
            },
          ),
        );
      },
    );
  }
}

Route<void> _fadeRoute(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, a, b) => page,
      transitionsBuilder: (context, a, b, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
        child: child,
      ),
    );

class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.controller, required this.colors, required this.serverCode});

  final VpnController controller;
  final List<Color> colors;
  final String? serverCode;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final connected = c.state == VpnState.connected;
    final busy = c.state == VpnState.connecting || c.state == VpnState.disconnecting;
    final (label, dotColor) = switch (c.state) {
      VpnState.connected => ('محافظت‌شده', colors[0]),
      VpnState.connecting => ('در حال اتصال', colors[0]),
      VpnState.disconnecting => ('در حال قطع', colors[0]),
      VpnState.disconnected => ('محافظت نمی‌شوید', Palette.muted),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.2, -0.3),
              radius: 1.2,
              colors: [colors[1].withValues(alpha: Palette.auroraStrength), Palette.bg],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 70, 8, 26),
          child: WorldMap(
            serverCode: serverCode,
            connected: connected,
            busy: busy,
            accent: connected ? colors[0] : Palette.accent,
            dot: Palette.mapDot,
            home: Palette.amber,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mobin', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Palette.text, height: 1.1)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: dotColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dotColor)),
                    ]),
                  ),
                ]),
                const Spacer(),
                _IconAction(
                  icon: Icons.insights_rounded,
                  tooltip: 'آمار مصرف',
                  onTap: () => Navigator.of(context).push(_fadeRoute(UsageScreen(controller: c))),
                ),
                const SizedBox(width: 8),
                _IconAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'تنظیمات',
                  onTap: () => Navigator.of(context).push(_fadeRoute(SettingsScreen(controller: c))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Palette.surface.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Palette.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, color: Palette.text, size: 22)),
          ),
        ),
      );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      decoration: BoxDecoration(
        color: Palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Palette.border)),
        boxShadow: [BoxShadow(color: Palette.shadow, blurRadius: 30, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 12),
                  _Banners(controller: c),
                  _RouteRow(controller: c, colors: colors),
                  const SizedBox(height: 12),
                  _LiveStats(controller: c, colors: colors),
                  const SizedBox(height: 12),
                  _ModeSwitch(controller: c, colors: colors),
                  const SizedBox(height: 14),
                  _LocationTabs(controller: c),
                  const SizedBox(height: 8),
                  _ServerPreview(controller: c),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: _ConnectButton(controller: c, colors: colors),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final update = c.update, error = c.error;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Column(children: [
        if (update != null)
          _Banner(
            icon: Icons.system_update_rounded,
            color: Palette.accent,
            text: c.updateProgress == null
                ? 'نسخه‌ی ${update.version} آماده است — برای به‌روزرسانی لمس کنید'
                : 'در حال دانلود… ${((c.updateProgress ?? 0) * 100).toStringAsFixed(0)}٪',
            onTap: c.installUpdate,
          ),
        if (error != null)
          _Banner(icon: Icons.error_outline_rounded, color: Palette.forDelay(9999), text: error, onTap: c.clearError, closable: true),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text, required this.onTap, this.closable = false});

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  final bool closable;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: Palette.text, fontSize: 12.5, height: 1.6))),
                if (closable) Icon(Icons.close_rounded, size: 16, color: Palette.muted),
              ]),
            ),
          ),
        ),
      );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = c.current;
    final selected = c.selectedCountry;
    final String title, subtitle;
    final String? flag;
    if (current != null) {
      flag = current.countryCode;
      title = current.displayName;
      subtitle = current.protocolLabel;
    } else {
      flag = selected;
      title = switch (selected) {
        null => 'هوشمند · بهترین سرور',
        VpnController.gamingMode => 'گیمینگ',
        VpnController.favoritesMode => 'علاقه‌مندی‌ها',
        final code => countryName(code),
      };
      subtitle = c.state == VpnState.connecting ? (c.phase ?? '') : 'برای تغییر موقعیت لمس کنید';
    }
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showLocationSheet(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Column(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Palette.amber.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(Icons.home_rounded, color: Palette.amber, size: 20),
            ),
            const SizedBox(height: 2),
            Text('شما', style: TextStyle(fontSize: 10.5, color: Palette.muted)),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _DashedLine(color: c.state == VpnState.connected ? colors[0] : Palette.border),
            ),
          ),
          FlagBadge(key: ValueKey(flag), code: flag, size: 40),
          const SizedBox(width: 10),
          Flexible(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.text)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Palette.muted)),
            ]),
          ),
          Icon(Icons.unfold_more_rounded, color: Palette.muted, size: 20),
        ]),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: LayoutBuilder(
          builder: (context, box) {
            final count = (box.maxWidth / 9).floor().clamp(1, 60);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(count, (_) => Container(width: 5, height: 2, color: color)),
            );
          },
        ),
      );
}

/// Ping, download, upload and a live download sparkline.
class _LiveStats extends StatefulWidget {
  const _LiveStats({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  State<_LiveStats> createState() => _LiveStatsState();
}

class _LiveStatsState extends State<_LiveStats> {
  final _samples = <double>[];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final c = widget.controller;
      if (c.state != VpnState.connected) {
        if (_samples.isNotEmpty) setState(_samples.clear);
        return;
      }
      setState(() {
        _samples.add(c.traffic.down.toDouble());
        if (_samples.length > 40) _samples.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final on = c.state == VpnState.connected;
    Widget cell(String label, String value, Color color) => Expanded(
          child: Column(children: [
            Text(label, style: TextStyle(fontSize: 11, color: Palette.muted)),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(18), border: Border.all(color: Palette.border)),
      child: Column(children: [
        Row(children: [
          cell('پینگ', c.currentDelay == null ? '—' : '${c.currentDelay} ms', Palette.forDelay(c.currentDelay)),
          cell('دانلود', on ? formatSpeed(c.traffic.down) : '—', Palette.text),
          cell('آپلود', on ? formatSpeed(c.traffic.up) : '—', Palette.text),
          cell('مدت', on && c.connectedAt != null ? formatDuration(DateTime.now().difference(c.connectedAt!)) : '—', Palette.text),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SparkPainter(List.of(_samples), on ? widget.colors[0] : Palette.border),
          ),
        ),
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.samples, this.color);

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    if (samples.length < 2) {
      canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), base);
      return;
    }
    final peak = samples.reduce(math.max).clamp(1.0, double.infinity);
    final dx = size.width / 39;
    final line = Path(), area = Path()..moveTo(size.width, size.height);
    for (var i = 0; i < samples.length; i++) {
      // RTL: newest sample on the left edge.
      final x = size.width - (samples.length - 1 - i) * dx;
      final y = size.height - samples[i] / peak * (size.height - 4) - 1;
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
      area.lineTo(x, y);
    }
    area
      ..lineTo(size.width - (samples.length - 1) * dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final busy = controller.state == VpnState.connecting || controller.state == VpnState.disconnecting;
    Widget option(String value, IconData icon, String label) {
      final selected = settings.connectMode == value;
      return Expanded(
        child: GestureDetector(
          onTap: busy ? null : () => settings.update((s) => s.connectMode = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? Palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: selected ? Colors.white : Palette.muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: selected ? Colors.white : Palette.muted)),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Palette.fill, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        option('direct', Icons.bolt_rounded, 'اتصال مستقیم'),
        option('test', Icons.network_ping_rounded, 'با تست پینگ'),
      ]),
    );
  }
}

class _LocationTabs extends StatelessWidget {
  const _LocationTabs({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final tabs = <(String?, String)>[
      (null, '✨ هوشمند'),
      if (c.settings.favorites.isNotEmpty) (VpnController.favoritesMode, '⭐ علاقه‌مندی'),
      (VpnController.gamingMode, '🎮 گیمینگ'),
      for (final g in c.countries) (g.code, g.name),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (code, label) = tabs[i];
          final selected = c.selectedCountry == code;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              c.selectCountry(code);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Palette.amber : Palette.fill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? const Color(0xFF1A1400) : Palette.muted,
                  )),
            ),
          );
        },
      ),
    );
  }
}

class _ServerPreview extends StatelessWidget {
  const _ServerPreview({required this.controller});

  final VpnController controller;

  static const _rows = 6;

  List<Server> _servers() {
    final c = controller;
    final code = c.selectedCountry;
    final list = switch (code) {
      null || VpnController.gamingMode => c.servers,
      VpnController.favoritesMode => c.servers.where(c.isFavorite).toList(),
      _ => c.servers.where((s) => s.countryCode == code).toList(),
    };
    int key(Server s) {
      final d = c.delays[s.uri];
      return d == null ? 1 << 30 : (d <= 0 ? 1 << 29 : d);
    }

    return (List.of(list)..sort((a, b) => key(a).compareTo(key(b)))).take(_rows).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final servers = _servers();
    return Container(
      decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(18), border: Border.all(color: Palette.border)),
      child: Column(children: [
        for (final s in servers) _ServerRow(controller: c, server: s),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(c.loading ? 'در حال دریافت سرورها…' : 'سروری در این بخش نیست', style: TextStyle(color: Palette.muted)),
          ),
        InkWell(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
          onTap: () => Navigator.of(context).push(_fadeRoute(ServersScreen(controller: c))),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('همه‌ی ${c.servers.length} سرور و تست پینگ',
                  style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w700, fontSize: 13)),
              Icon(Icons.chevron_left_rounded, color: Palette.accent),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.controller, required this.server});

  final VpnController controller;
  final Server server;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final active = c.current?.uri == server.uri;
    final d = c.delays[server.uri];
    final color = d == null ? Palette.muted : (d <= 0 ? Palette.forDelay(9999) : Palette.forDelay(d));
    return InkWell(
      onTap: () => c.connectTo(server),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Palette.amber.withValues(alpha: 0.10) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Palette.border),
            right: BorderSide(color: active ? Palette.amber : Colors.transparent, width: 3),
          ),
        ),
        child: Row(children: [
          FlagBadge(code: server.countryCode, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.displayName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Palette.text)),
              Text(server.protocolLabel, style: TextStyle(fontSize: 11, color: Palette.muted)),
            ]),
          ),
          if (c.isFavorite(server)) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, size: 16, color: Palette.amber)),
          Text(d == null ? '—' : (d <= 0 ? 'قطع' : '$d ms'),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (label, icon) = switch (c.state) {
      VpnState.disconnected => ('اتصال', Icons.power_settings_new_rounded),
      VpnState.connecting => ('لغو', Icons.close_rounded),
      VpnState.connected => ('قطع اتصال', Icons.stop_rounded),
      VpnState.disconnecting => ('در حال قطع…', Icons.hourglass_top_rounded),
    };
    final progress = c.progress;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          c.toggle();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          height: 58,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            gradient: LinearGradient(colors: [colors[0], colors[1]]),
            boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (c.state == VpnState.connecting)
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: progress ?? 0.12,
                  heightFactor: 1,
                  child: ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
                ),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            ]),
          ]),
        ),
      ),
    );
  }
}
