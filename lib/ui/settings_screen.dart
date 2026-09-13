import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/engine.dart';
import '../core/server.dart';
import '../core/settings.dart';
import '../core/vpn_controller.dart';
import '../core/windows_engine.dart';
import 'apps_screen.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final VpnController controller;

  AppSettings get s => controller.settings;

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([controller, s]),
            builder: (context, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _TopBar(title: 'تنظیمات پیشرفته', onBack: () => Navigator.of(context).pop()),
                    if (controller.state != VpnState.disconnected)
                      const _Hint('تغییرات اتصال از اتصال بعدی اعمال می‌شوند.'),
                    _Section(title: 'اتصال', icon: Icons.power_rounded, children: [
                      _SwitchRow(
                        icon: Icons.autorenew_rounded,
                        title: 'اتصال دوباره‌ی خودکار',
                        subtitle: 'اگر اتصال قطع شد، بهترین سرور بعدی را وصل کن',
                        value: s.autoReconnect,
                        onChanged: (v) => s.update((x) => x.autoReconnect = v),
                      ),
                      _SwitchRow(
                        icon: Icons.rocket_launch_rounded,
                        title: 'اتصال هنگام باز شدن برنامه',
                        value: s.connectOnLaunch,
                        onChanged: (v) => s.update((x) => x.connectOnLaunch = v),
                      ),
                      if (Platform.isAndroid)
                        _SwitchRow(
                          icon: Icons.lan_rounded,
                          title: 'فقط پراکسی (بدون VPN)',
                          subtitle: 'SOCKS روی 127.0.0.1:1080 — برای برنامه‌هایی که پراکسی را دستی تنظیم می‌کنند',
                          value: s.proxyOnly,
                          onChanged: (v) => s.update((x) => x.proxyOnly = v),
                        ),
                      if (Platform.isAndroid)
                        _ActionRow(
                          icon: Icons.shield_rounded,
                          title: 'Kill Switch (قطع اینترنت بدون VPN)',
                          subtitle: 'در تنظیمات VPN اندروید، Mobin VPN را «همیشه روشن» و «مسدود کردن اتصال بدون VPN» کنید',
                          onTap: () => const AndroidIntent(action: 'android.settings.VPN_SETTINGS').launch(),
                        ),
                      if (Platform.isWindows) ...[
                        _SwitchRow(
                          icon: Icons.vpn_lock_rounded,
                          title: 'VPN کامل (TUN)',
                          subtitle: WindowsEngine.isAdmin
                              ? 'همه‌ی برنامه‌ها و بازی‌ها از VPN عبور می‌کنند'
                              : 'همه‌ی برنامه‌ها و بازی‌ها — نیاز به اجرای برنامه به‌عنوان Administrator',
                          value: s.tunMode,
                          onChanged: (v) => s.update((x) => x.tunMode = v),
                        ),
                        if (s.tunMode && !WindowsEngine.isAdmin)
                          _ActionRow(
                            icon: Icons.admin_panel_settings_rounded,
                            title: 'اجرای دوباره به‌عنوان Administrator',
                            onTap: () async {
                              await controller.disconnect();
                              await WindowsEngine.relaunchAsAdmin();
                              exit(0);
                            },
                          ),
                        _SwitchRow(
                          icon: Icons.shield_rounded,
                          title: 'Kill Switch',
                          subtitle: s.tunMode
                              ? 'فقط ترافیک از تونل عبور می‌کند (strict route)'
                              : 'اگر هسته قطع شد، مرورگرها تا اتصال دوباره یا قطع دستی اینترنت ندارند',
                          value: s.killSwitch,
                          onChanged: (v) => s.update((x) => x.killSwitch = v),
                        ),
                        _SwitchRow(
                          icon: Icons.settings_ethernet_rounded,
                          title: 'تنظیم پراکسی ویندوز',
                          subtitle: 'خاموش: فقط پراکسی محلی اجرا می‌شود و خودتان تنظیمش می‌کنید',
                          value: s.systemProxy,
                          onChanged: (v) => s.update((x) => x.systemProxy = v),
                        ),
                        _TextRow(
                          icon: Icons.numbers_rounded,
                          title: 'پورت پراکسی محلی (HTTP/SOCKS)',
                          value: s.localPort == 0 ? 'خودکار' : '${s.localPort}',
                          onTap: () async {
                            final v = await _prompt(context, 'پورت (خالی = خودکار)', s.localPort == 0 ? '' : '${s.localPort}',
                                keyboard: TextInputType.number);
                            if (v == null) return;
                            final port = int.tryParse(v) ?? 0;
                            await s.update((x) => x.localPort = port > 1024 && port < 65536 ? port : 0);
                          },
                        ),
                        if (controller.engine.httpProxy != null)
                          _TextRow(
                            icon: Icons.link_rounded,
                            title: 'پراکسی فعال',
                            value: controller.engine.httpProxy!,
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: controller.engine.httpProxy!));
                              _toast(context, 'آدرس پراکسی کپی شد');
                            },
                          ),
                      ],
                    ]),
                    _Section(title: 'مسیریابی و DNS', icon: Icons.alt_route_rounded, children: [
                      _SwitchRow(
                        icon: Icons.flag_rounded,
                        title: 'سایت‌های ایرانی مستقیم',
                        subtitle: 'دامنه‌های .ir و شبکه‌ی محلی از VPN عبور نمی‌کنند (سریع‌تر، بانک‌ها کار می‌کنند)',
                        value: s.bypassIran,
                        onChanged: (v) => s.update((x) => x.bypassIran = v),
                      ),
                      if (Platform.isAndroid)
                        _ActionRow(
                          icon: Icons.apps_rounded,
                          title: 'برنامه‌های خارج از VPN',
                          subtitle: s.excludedApps.isEmpty
                              ? 'مثلاً بانک و تاکسی اینترنتی را مستقیم وصل کنید'
                              : '${s.excludedApps.length} برنامه مستقیم وصل می‌شوند',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AppsScreen(settings: s))),
                        ),
                      _SwitchRow(
                        icon: Icons.content_cut_rounded,
                        title: 'ضد فیلتر (TLS Fragment)',
                        subtitle: 'تکه‌تکه کردن شروع اتصال TLS برای عبور از فیلترینگ شدید؛ کمی کندتر',
                        value: s.fragment,
                        onChanged: (v) => s.update((x) => x.fragment = v),
                      ),
                      if (Platform.isAndroid)
                        _ChoiceRow<String>(
                          icon: Icons.dns_rounded,
                          title: 'DNS',
                          options: {...AppSettings.dnsServers, if (!AppSettings.dnsServers.containsKey(s.dns)) s.dns: s.dns},
                          value: s.dns,
                          onChanged: (v) => s.update((x) => x.dns = v),
                        ),
                    ]),
                    _Section(title: 'انتخاب سرور', icon: Icons.speed_rounded, children: [
                      _ChoiceRow<int>(
                        icon: Icons.format_list_numbered_rounded,
                        title: 'تعداد سرور برای حالت هوشمند',
                        subtitle: 'بیشتر = دقیق‌تر ولی کندتر',
                        options: const {20: '۲۰', 40: '۴۰', 80: '۸۰'},
                        value: s.poolSize,
                        onChanged: (v) => s.update((x) => x.poolSize = v),
                      ),
                      _ChoiceRow<int>(
                        icon: Icons.timer_outlined,
                        title: 'حداکثر زمان تست',
                        options: const {5: '۵ ثانیه', 8: '۸ ثانیه', 12: '۱۲ ثانیه'},
                        value: s.timeoutSeconds,
                        onChanged: (v) => s.update((x) => x.timeoutSeconds = v),
                      ),
                      _ChoiceRow<String>(
                        icon: Icons.network_ping_rounded,
                        title: 'آدرس تست پینگ',
                        options: AppSettings.testUrls,
                        value: s.testUrl,
                        onChanged: (v) => s.update((x) => x.testUrl = v),
                      ),
                      _ProtocolRow(settings: s),
                    ]),
                    _Section(title: 'لیست سرورها', icon: Icons.cloud_sync_rounded, children: [
                      _TextRow(
                        icon: Icons.add_link_rounded,
                        title: 'لینک اشتراک دلخواه',
                        value: s.customSubscription.isEmpty ? 'پیش‌فرض (Mobin)' : s.customSubscription,
                        onTap: () async {
                          final v = await _prompt(context, 'لینک اشتراک (خالی = پیش‌فرض)', s.customSubscription,
                              keyboard: TextInputType.url);
                          if (v == null) return;
                          await s.update((x) => x.customSubscription = v.trim());
                          await controller.refresh();
                        },
                      ),
                      _ActionRow(
                        icon: Icons.refresh_rounded,
                        title: 'به‌روزرسانی لیست سرورها',
                        subtitle: '${controller.servers.length} سرور فعال',
                        busy: controller.loading,
                        onTap: controller.refresh,
                      ),
                    ]),
                    _Section(title: 'درباره', icon: Icons.info_outline_rounded, children: [
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snap) => _TextRow(
                          icon: Icons.verified_rounded,
                          title: 'نسخه',
                          value: snap.data?.version ?? '…',
                        ),
                      ),
                      _ActionRow(
                        icon: Icons.system_update_rounded,
                        title: 'بررسی به‌روزرسانی',
                        onTap: () async {
                          final u = await controller.checkUpdate();
                          if (!context.mounted) return;
                          if (u == null) {
                            _toast(context, 'برنامه به‌روز است');
                          } else {
                            Navigator.of(context).pop();
                            await controller.installUpdate();
                          }
                        },
                      ),
                      _ActionRow(
                        icon: Icons.code_rounded,
                        title: 'کد برنامه در گیت‌هاب',
                        subtitle: 'github.com/hidooch980/mobin-vpn',
                        onTap: () {
                          Clipboard.setData(const ClipboardData(text: 'https://github.com/hidooch980/mobin-vpn'));
                          _toast(context, 'لینک کپی شد');
                        },
                      ),
                      _ActionRow(
                        icon: Icons.restart_alt_rounded,
                        title: 'بازگشت به تنظیمات پیش‌فرض',
                        danger: true,
                        onTap: () async {
                          await s.reset();
                          if (context.mounted) _toast(context, 'تنظیمات پیش‌فرض شد');
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, String initial, {TextInputType? keyboard}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF14142A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('ذخیره')),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Glass(radius: 16, padding: const EdgeInsets.all(10), onTap: onBack, child: const Icon(Icons.arrow_forward_rounded, color: Palette.text)),
          const SizedBox(width: 14),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Icon(Icons.info_rounded, size: 16, color: Color(0xFFFBBF24)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFFFBBF24))),
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Glass(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Row(children: [
                  Icon(icon, size: 18, color: const Color(0xFFA78BFA)),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFA78BFA))),
                ]),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.below, this.color});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing, below;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 19, color: color ?? Palette.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: color ?? Palette.text)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: const TextStyle(fontSize: 12, height: 1.5, color: Palette.muted)),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (below != null) Padding(padding: const EdgeInsetsDirectional.only(start: 48, top: 8), child: below),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: const Color(0xFFA78BFA)),
      );
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.icon, required this.title, this.subtitle, required this.options, required this.value, required this.onChanged});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => _RowShell(
        icon: icon,
        title: title,
        subtitle: subtitle,
        below: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: e.key == value,
                onSelected: (_) => onChanged(e.key),
                selectedColor: const Color(0xFF7C3AED),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                showCheckmark: false,
              ),
          ],
        ),
      );
}

class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({required this.settings});

  final AppSettings settings;

  static const _android = {Protocol.vless, Protocol.vmess, Protocol.trojan, Protocol.shadowsocks};

  @override
  Widget build(BuildContext context) {
    final available = Platform.isAndroid ? Protocol.values.where(_android.contains) : Protocol.values;
    return _RowShell(
      icon: Icons.security_rounded,
      title: 'پروتکل‌ها',
      subtitle: 'فقط سرورهای این پروتکل‌ها استفاده می‌شوند',
      below: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in available)
            FilterChip(
              label: Text(Server(uri: '', remark: '', countryCode: '', protocol: p).protocolLabel),
              selected: settings.protocols.contains(p),
              selectedColor: const Color(0xFF0E7490),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              onSelected: (on) {
                final next = {...settings.protocols};
                on ? next.add(p) : next.remove(p);
                if (next.isNotEmpty) settings.update((x) => x.protocols = next);
              },
            ),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.icon, required this.title, required this.value, this.onTap});

  final IconData icon;
  final String title, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _RowShell(
        icon: icon,
        title: title,
        onTap: onTap,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.title, this.subtitle, required this.onTap, this.busy = false, this.danger = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool busy, danger;

  @override
  Widget build(BuildContext context) => _RowShell(
        icon: icon,
        title: title,
        subtitle: subtitle,
        color: danger ? const Color(0xFFF87171) : null,
        onTap: busy ? null : onTap,
        trailing: busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_left_rounded, color: Palette.muted),
      );
}
