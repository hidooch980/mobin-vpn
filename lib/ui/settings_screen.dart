import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/engine.dart';
import '../core/server.dart';
import '../core/settings.dart';
import '../core/vpn_controller.dart';
import '../core/win_startup.dart';
import '../core/windows_engine.dart';
import '../main.dart' show appNavigatorKey;
import 'apps_screen.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'log_screen.dart';
import 'style.dart';
import 'widgets.dart';

/// Settings in the Android app's layout: section headers over grouped rounded cards.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final VpnController controller;

  AppSettings get s => controller.settings;

  /// A theme switch rebuilds the whole app (and its navigator); reopen this screen on top of the new home.
  void _changeAppearance(Future<void> Function() change) {
    change();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (context, a, b) => SettingsScreen(controller: controller),
      ));
    });
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'تنظیمات',
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, s]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            if (controller.state != VpnState.disconnected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Palette.muted),
                  const SizedBox(width: 6),
                  Text('تغییرات اتصال از اتصال بعدی اعمال می‌شوند.', style: TextStyle(fontSize: 12.5, color: Palette.muted)),
                ]),
              ),

            const SectionHeader('شروع و اتصال خودکار'),
            CardGroup(children: [
              SwitchSettingRow(
                icon: Icons.bolt_rounded,
                title: 'اتصال خودکار',
                subtitle: 'با باز شدن برنامه، پس از دریافت سرورها خودش وصل می‌شود',
                value: s.connectOnLaunch,
                onChanged: (v) => s.update((x) => x.connectOnLaunch = v),
              ),
              if (Platform.isWindows)
                SwitchSettingRow(
                  icon: Icons.power_settings_new_rounded,
                  title: 'اجرا با روشن شدن ویندوز',
                  subtitle: 'همراه با «اتصال خودکار»، از همان ابتدای روشن شدن ویندوز وصل هستید',
                  value: s.launchAtStartup,
                  onChanged: (v) {
                    WinStartup.setEnabled(v);
                    s.update((x) => x.launchAtStartup = v);
                  },
                ),
              SwitchSettingRow(
                icon: Icons.autorenew_rounded,
                title: 'اتصال دوباره‌ی خودکار',
                subtitle: 'اگر اتصال قطع شد، بهترین سرور بعدی را وصل کن',
                value: s.autoReconnect,
                onChanged: (v) => s.update((x) => x.autoReconnect = v),
              ),
            ]),

            const SectionHeader('محافظت'),
            CardGroup(children: [
              if (Platform.isWindows) ...[
                SwitchSettingRow(
                  icon: Icons.vpn_lock_rounded,
                  title: 'VPN کامل (TUN)',
                  subtitle: WindowsEngine.isAdmin
                      ? 'همه‌ی برنامه‌ها و بازی‌ها از VPN عبور می‌کنند'
                      : 'همه‌ی برنامه‌ها و بازی‌ها — نیاز به اجرای برنامه به‌عنوان Administrator',
                  value: s.tunMode,
                  onChanged: (v) => s.update((x) => x.tunMode = v),
                ),
                if (s.tunMode && !WindowsEngine.isAdmin)
                  NavSettingRow(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'اجرای دوباره به‌عنوان Administrator',
                    onTap: () async {
                      await controller.disconnect();
                      await WindowsEngine.relaunchAsAdmin();
                      exit(0);
                    },
                  ),
                SwitchSettingRow(
                  icon: Icons.shield_outlined,
                  title: 'Kill Switch',
                  subtitle: s.tunMode
                      ? 'فقط ترافیک از تونل عبور می‌کند (strict route)'
                      : 'اگر هسته قطع شد، مرورگرها تا اتصال دوباره یا قطع دستی اینترنت ندارند',
                  value: s.killSwitch,
                  onChanged: (v) => s.update((x) => x.killSwitch = v),
                ),
              ],
              if (Platform.isAndroid) ...[
                SwitchSettingRow(
                  icon: Icons.lan_outlined,
                  title: 'فقط پراکسی (بدون VPN)',
                  subtitle: 'SOCKS روی 127.0.0.1:1080 — برای برنامه‌هایی که پراکسی را دستی تنظیم می‌کنند',
                  value: s.proxyOnly,
                  onChanged: (v) => s.update((x) => x.proxyOnly = v),
                ),
                NavSettingRow(
                  icon: Icons.shield_outlined,
                  title: 'Kill Switch (قطع اینترنت بدون VPN)',
                  subtitle: 'در تنظیمات VPN اندروید، MolidoVPN را «همیشه روشن» و «مسدود کردن اتصال بدون VPN» کنید',
                  onTap: () => const AndroidIntent(action: 'android.settings.VPN_SETTINGS').launch(),
                ),
              ],
              SwitchSettingRow(
                icon: Icons.flag_outlined,
                title: 'سایت‌های ایرانی مستقیم',
                subtitle: 'دامنه‌های .ir و شبکه‌ی محلی از VPN عبور نمی‌کنند (سریع‌تر، بانک‌ها کار می‌کنند)',
                value: s.bypassIran,
                onChanged: (v) => s.update((x) => x.bypassIran = v),
              ),
            ]),

            if (Platform.isWindows) ...[
              const SectionHeader('پراکسی ویندوز'),
              CardGroup(children: [
                SwitchSettingRow(
                  icon: Icons.settings_ethernet_rounded,
                  title: 'تنظیم پراکسی ویندوز',
                  subtitle: 'خاموش: فقط پراکسی محلی اجرا می‌شود و خودتان تنظیمش می‌کنید',
                  value: s.systemProxy,
                  onChanged: (v) => s.update((x) => x.systemProxy = v),
                ),
                NavSettingRow(
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
                  NavSettingRow(
                    icon: Icons.link_rounded,
                    title: 'پراکسی فعال',
                    value: controller.engine.httpProxy!,
                    ltrValue: true,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: controller.engine.httpProxy!));
                      _toast(context, 'آدرس پراکسی کپی شد');
                    },
                  ),
              ]),
            ],

            const SectionHeader('مسیریابی و ضد فیلتر'),
            CardGroup(children: [
              if (Platform.isAndroid)
                NavSettingRow(
                  icon: Icons.apps_rounded,
                  title: 'برنامه‌های خارج از VPN',
                  subtitle: s.excludedApps.isEmpty
                      ? 'مثلاً بانک و تاکسی اینترنتی را مستقیم وصل کنید'
                      : '${s.excludedApps.length} برنامه مستقیم وصل می‌شوند',
                  onTap: () => _push(context, AppsScreen(settings: s)),
                ),
              SwitchSettingRow(
                icon: Icons.cloud_outlined,
                title: 'Cloudflare WARP روی سرور',
                subtitle: 'سایت‌هایی که IP سرورهای رایگان را بسته‌اند باز می‌شوند (مثلاً بعضی سرویس‌های هوش مصنوعی)؛ پینگ کمی بیشتر',
                value: s.warp,
                onChanged: (v) async {
                  await s.update((x) => x.warp = v);
                  if (v && !await controller.ensureWarp() && context.mounted) {
                    _toast(context, 'ثبت WARP الان ممکن نشد؛ هنگام اتصال دوباره تلاش می‌شود');
                  }
                },
              ),
              SwitchSettingRow(
                icon: Icons.content_cut_rounded,
                title: 'ضد فیلتر (TLS Fragment)',
                subtitle: 'تکه‌تکه کردن شروع اتصال TLS برای عبور از فیلترینگ شدید؛ کمی کندتر',
                value: s.fragment,
                onChanged: (v) => s.update((x) => x.fragment = v),
              ),
              if (Platform.isAndroid)
                ChoiceSettingRow<String>(
                  icon: Icons.dns_outlined,
                  title: 'DNS',
                  options: {...AppSettings.dnsServers, if (!AppSettings.dnsServers.containsKey(s.dns)) s.dns: s.dns},
                  value: s.dns,
                  onChanged: (v) => s.update((x) => x.dns = v),
                ),
            ]),

            const SectionHeader('انتخاب سرور'),
            CardGroup(children: [
              ChoiceSettingRow<int>(
                icon: Icons.format_list_numbered_rounded,
                title: 'تعداد سرور برای حالت هوشمند',
                subtitle: 'بیشتر = دقیق‌تر ولی کندتر',
                options: const {20: '۲۰', 40: '۴۰', 80: '۸۰'},
                value: s.poolSize,
                onChanged: (v) => s.update((x) => x.poolSize = v),
              ),
              ChoiceSettingRow<int>(
                icon: Icons.timer_outlined,
                title: 'حداکثر زمان تست',
                options: const {5: '۵ ثانیه', 8: '۸ ثانیه', 12: '۱۲ ثانیه'},
                value: s.timeoutSeconds,
                onChanged: (v) => s.update((x) => x.timeoutSeconds = v),
              ),
              ChoiceSettingRow<String>(
                icon: Icons.network_ping_rounded,
                title: 'آدرس تست پینگ',
                options: AppSettings.testUrls,
                value: s.testUrl,
                onChanged: (v) => s.update((x) => x.testUrl = v),
              ),
              _ProtocolRow(settings: s),
            ]),

            const SectionHeader('لیست سرورها'),
            CardGroup(children: [
              NavSettingRow(
                icon: Icons.bookmark_added_outlined,
                title: 'کانفیگ‌های من (وارد کردن دستی / QR)',
                value: '${s.manualConfigs.length} کانفیگ',
                onTap: () => _push(context, ImportScreen(controller: controller)),
              ),
              NavSettingRow(
                icon: Icons.add_link_rounded,
                title: 'لینک اشتراک دلخواه',
                value: s.customSubscription.isEmpty ? 'پیش‌فرض (Molido)' : s.customSubscription,
                ltrValue: s.customSubscription.isNotEmpty,
                onTap: () async {
                  final v = await _prompt(context, 'لینک اشتراک (خالی = پیش‌فرض)', s.customSubscription,
                      keyboard: TextInputType.url);
                  if (v == null) return;
                  await s.update((x) => x.customSubscription = v.trim());
                  await controller.refresh();
                },
              ),
              NavSettingRow(
                icon: Icons.refresh_rounded,
                title: 'به‌روزرسانی لیست سرورها',
                value: '${controller.servers.length} سرور',
                busy: controller.loading,
                onTap: controller.refresh,
              ),
            ]),

            const SectionHeader('ظاهر'),
            CardGroup(children: [
              ChoiceSettingRow<String>(
                icon: Icons.brightness_6_outlined,
                title: 'تم',
                options: const {'system': 'خودکار', 'light': 'روشن', 'dark': 'تیره'},
                value: s.themeMode,
                onChanged: (v) => _changeAppearance(() => s.update((x) => x.themeMode = v)),
              ),
              SwitchSettingRow(
                icon: Icons.animation_rounded,
                title: 'کاهش انیمیشن',
                subtitle: 'برای کامپیوترها و گوشی‌های ضعیف روان‌تر',
                value: s.reduceMotion,
                onChanged: (v) => _changeAppearance(() => s.update((x) => x.reduceMotion = v)),
              ),
            ]),

            const SectionHeader('حریم خصوصی'),
            CardGroup(children: [
              SwitchSettingRow(
                icon: Icons.insights_outlined,
                title: 'گزارش ناشناس کیفیت سرورها',
                subtitle: 'فقط شناسه‌ی ناشناس سرور، موفق یا ناموفق بودن اتصال، تأخیر و نوع شبکه فرستاده می‌شود؛ '
                    'بدون IP، نام یا اطلاعات وب‌گردی. به انتخاب سرورهای بهتر برای همه کمک می‌کند.',
                value: s.anonymousReports,
                onChanged: (v) => s.update((x) => x.anonymousReports = v),
              ),
            ]),

            const SectionHeader('پشتیبانی'),
            CardGroup(children: [
              NavSettingRow(
                icon: Icons.menu_book_outlined,
                title: 'راهنما',
                subtitle: 'اگر وصل نشد یا کند بود، اینجا را بخوانید',
                onTap: () => _push(context, const HelpScreen()),
              ),
              NavSettingRow(
                icon: Icons.bug_report_outlined,
                title: 'گزارش خطا',
                subtitle: 'جزئیات آخرین اتصال‌ها؛ کپی کنید و بفرستید',
                onTap: () => _push(context, LogScreen(controller: controller)),
              ),
            ]),

            const SectionHeader('درباره'),
            CardGroup(children: [
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) => NavSettingRow(
                  icon: Icons.verified_outlined,
                  title: 'نسخه',
                  value: snap.data?.version ?? '…',
                  ltrValue: true,
                ),
              ),
              NavSettingRow(
                icon: Icons.system_update_outlined,
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
              NavSettingRow(
                icon: Icons.code_rounded,
                title: 'کد برنامه در گیت‌هاب',
                subtitle: 'github.com/hidooch980/mobin-vpn',
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'https://github.com/hidooch980/mobin-vpn'));
                  _toast(context, 'لینک کپی شد');
                },
              ),
              NavSettingRow(
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
        backgroundColor: Palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(fontSize: 16, color: Palette.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: Palette.text),
          decoration: InputDecoration(
            filled: true,
            fillColor: Palette.raised,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    ),
  );
}

class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({required this.settings});

  final AppSettings settings;

  static const _android = {Protocol.vless, Protocol.vmess, Protocol.trojan, Protocol.shadowsocks};

  @override
  Widget build(BuildContext context) {
    final xrayOnly = Platform.isAndroid; // Android runs Xray only
    final available = xrayOnly ? Protocol.values.where(_android.contains) : Protocol.values;
    return SettingRow(
      icon: Icons.security_outlined,
      title: 'پروتکل‌ها',
      subtitle: 'فقط سرورهای این پروتکل‌ها استفاده می‌شوند',
      below: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in available)
          AppChip(
            label: Server(uri: '', remark: '', countryCode: '', protocol: p).protocolLabel,
            selected: settings.protocols.contains(p),
            onTap: () {
              final next = {...settings.protocols};
              next.contains(p) ? next.remove(p) : next.add(p);
              if (next.isNotEmpty) settings.update((x) => x.protocols = next);
            },
          ),
      ]),
    );
  }
}
