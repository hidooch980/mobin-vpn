import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'connect_orb.dart';
import 'flag_badge.dart';
import 'glass.dart';
import 'location_sheet.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'style.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.controller.state == VpnState.connected && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return AnimatedColors(
          colors: Palette.forState(c.state),
          builder: (context, colors) => Scaffold(
            body: AuroraBackground(
              colors: colors,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _Header(controller: c, colors: colors),
                          _UpdateBanner(controller: c, colors: colors),
                          const Spacer(),
                          _StatusText(controller: c, colors: colors),
                          const SizedBox(height: 8),
                          ConnectOrb(state: c.state, colors: colors, progress: c.progress, onTap: c.toggle),
                          const Spacer(),
                          _ErrorBanner(controller: c),
                          _Stats(controller: c),
                          const SizedBox(height: 12),
                          _LocationCard(controller: c),
                          const SizedBox(height: 10),
                          _Footer(controller: c),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
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

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [colors[0], colors[2]]),
            boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.5), blurRadius: 18)],
          ),
          child: const Icon(Icons.shield_moon_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (r) => LinearGradient(colors: [Colors.white, colors[1]]).createShader(r),
              child: const Text('Mobin', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            ),
            const Text('VPN آزاد برای خانواده', style: TextStyle(fontSize: 11.5, color: Palette.muted)),
          ],
        ),
        const Spacer(),
        _RoundButton(
          tooltip: 'همه‌ی سرورها',
          icon: Icons.dns_rounded,
          onTap: () => Navigator.of(context).push(_fadeRoute(ServersScreen(controller: controller))),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          tooltip: 'تنظیمات پیشرفته',
          icon: Icons.tune_rounded,
          onTap: () => Navigator.of(context).push(_fadeRoute(SettingsScreen(controller: controller))),
        ),
      ],
    );
  }
}

Route<void> _fadeRoute(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, a, b) => page,
      transitionsBuilder: (context, a, b, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    );

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Glass(
        radius: 16,
        padding: const EdgeInsets.all(10),
        onTap: onTap,
        child: Icon(icon, color: Palette.text, size: 24),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final update = controller.update;
    final progress = controller.updateProgress;
    return AnimatedSize(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      child: update == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Glass(
                radius: 20,
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                borderColor: colors[1].withValues(alpha: 0.6),
                onTap: controller.installUpdate,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.system_update_rounded, color: colors[1]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            progress == null
                                ? 'نسخه‌ی جدید ${update.version} آماده است'
                                : 'در حال دانلود… ${(progress * 100).toStringAsFixed(0)}٪',
                            style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                        if (progress == null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(colors: [colors[0], colors[1]]),
                            ),
                            child: const Text('به‌روزرسانی', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          ),
                      ],
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: progress),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(colors[1]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.controller, required this.colors});

  final VpnController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (title, subtitle) = switch (c.state) {
      VpnState.disconnected => ('آماده‌ی اتصال', 'برای اتصال، دکمه را لمس کنید'),
      VpnState.connecting => (
          'در حال اتصال…',
          c.progressTotal > 0 ? '${c.phase ?? ''}  ${c.progressDone}/${c.progressTotal}' : (c.phase ?? ''),
        ),
      VpnState.connected => ('متصل هستید', formatDuration(DateTime.now().difference(c.connectedAt ?? DateTime.now()))),
      VpnState.disconnecting => ('در حال قطع اتصال…', ''),
    };
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(a), child: child),
          ),
          child: ShaderMask(
            key: ValueKey(title),
            shaderCallback: (r) => LinearGradient(colors: [Colors.white, Color.lerp(Colors.white, colors[0], 0.55)!]).createShader(r),
            child: Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 22,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              subtitle,
              key: ValueKey(c.state == VpnState.connected ? 'timer' : subtitle),
              style: const TextStyle(fontSize: 14.5, color: Palette.muted, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: error == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Glass(
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                borderColor: const Color(0xFFF87171).withValues(alpha: 0.5),
                onTap: controller.clearError,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(error, style: const TextStyle(color: Palette.text, fontSize: 13.5))),
                    const Icon(Icons.close_rounded, color: Palette.muted, size: 18),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final show = c.state == VpnState.connected;
    return AnimatedSize(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        child: !show
            ? const SizedBox(width: double.infinity)
            : Row(
                children: [
                  Expanded(child: _Stat(icon: Icons.south_rounded, label: 'دانلود', value: formatSpeed(c.traffic.down), color: const Color(0xFF34D399))),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(icon: Icons.north_rounded, label: 'آپلود', value: formatSpeed(c.traffic.up), color: const Color(0xFF60A5FA))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      icon: Icons.bolt_rounded,
                      label: 'پینگ',
                      value: c.currentDelay == null ? '—' : '${c.currentDelay} ms',
                      color: Palette.forDelay(c.currentDelay),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 20,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.text, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Palette.muted)),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = c.current;
    final selected = c.selectedCountry;
    final group = c.countries.where((g) => g.code == selected).firstOrNull;

    final String title, subtitle;
    final String? flag;
    if (current != null) {
      flag = current.countryCode;
      title = current.displayName;
      subtitle = switch (selected) {
        null => 'هوشمند · ${current.protocolLabel}',
        VpnController.gamingMode => 'گیمینگ · ${current.protocolLabel}',
        _ => current.protocolLabel,
      };
    } else if (selected == VpnController.gamingMode) {
      flag = selected;
      title = 'گیمینگ · کمترین پینگ';
      subtitle = 'سرورهای نزدیک با پینگ پایدار';
    } else if (selected == null) {
      flag = null;
      title = 'هوشمند · بهترین سرور';
      subtitle = 'بر اساس سرعت اینترنت خودتان انتخاب می‌شود';
    } else {
      flag = selected;
      title = group?.name ?? selected;
      subtitle = '${group?.servers.length ?? 0} سرور · سریع‌ترین انتخاب می‌شود';
    }

    return Glass(
      radius: 26,
      padding: const EdgeInsets.all(14),
      onTap: () => showLocationSheet(context, c),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: FlagBadge(key: ValueKey(flag), code: flag, size: 48),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('موقعیت', style: TextStyle(fontSize: 11.5, color: Palette.muted)),
                const SizedBox(height: 2),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Palette.text)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ],
            ),
          ),
          if (c.currentDelay != null)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Palette.forDelay(c.currentDelay).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${c.currentDelay}ms', textDirection: TextDirection.ltr, style: TextStyle(color: Palette.forDelay(c.currentDelay), fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          const Icon(Icons.unfold_more_rounded, color: Palette.muted),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final updated = c.updatedAt;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          updated == null ? 'در حال دریافت لیست سرورها…' : '${c.servers.length} سرور · به‌روزرسانی ${timeAgo(updated)}',
          style: const TextStyle(fontSize: 12, color: Palette.muted),
        ),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'به‌روزرسانی لیست',
          onPressed: c.loading ? null : c.refresh,
          icon: AnimatedRotation(
            turns: c.loading ? 3 : 0,
            duration: Duration(milliseconds: c.loading ? 2400 : 0),
            child: const Icon(Icons.refresh_rounded, size: 18, color: Palette.muted),
          ),
        ),
      ],
    );
  }
}
