import 'package:flutter/material.dart';

import '../core/engine.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'strings.dart';
import 'style.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static List<(IconData, String, List<String>)> get _sections => [
    (Icons.touch_app_rounded, tr('شروع سریع', 'Quick start'), [
      tr('دکمه‌ی بزرگ وسط صفحه را بزنید. برنامه چند سرور را با اینترنت خودتان تست می‌کند و به سریع‌ترین وصل می‌شود.', 'Tap the big button in the middle. The app tests several servers on your own internet and connects to the fastest.'),
      tr('بار اول اندروید اجازه‌ی VPN می‌خواهد؛ «تأیید» را بزنید.', 'The first time, Android asks for VPN permission; tap OK.'),
      tr('برای قطع، دوباره همان دکمه را بزنید.', 'Tap the same button again to disconnect.'),
    ]),
    (Icons.public_rounded, tr('انتخاب موقعیت', 'Choosing a location'), [
      tr('کارت «موقعیت» پایین صفحه را لمس کنید.', 'Tap the location card under the connect button.'),
      tr('هوشمند: سریع‌ترین سرور از همه‌ی کشورها.', 'Smart: the fastest server from all countries.'),
      tr('علاقه‌مندی‌ها ⭐: فقط سرورهایی که در «همه‌ی سرورها» ستاره زده‌اید.', 'Favorites ⭐: only servers you starred in the Servers tab.'),
    ]),
    (Icons.wifi_off_rounded, tr('اگر وصل نشد', 'If it does not connect'), [
      tr('۱. در تنظیمات «ضد فیلتر (TLS Fragment)» را روشن کنید.', '1. Turn on Anti-filter (TLS Fragment) in Settings.'),
      tr('۲. «آدرس تست پینگ» را روی Cloudflare بگذارید.', '2. Set Ping test URL to Cloudflare.'),
      tr('۳. از پایین صفحه‌ی اصلی لیست سرورها را به‌روزرسانی کنید.', '3. Refresh the server list from Settings.'),
      tr('۴. یک کشور دیگر یا حالت «با تست پینگ» را امتحان کنید.', '4. Try another country or another route (WARP, Psiphon, Tor).'),
      tr('۵. اگر باز هم نشد: تنظیمات ← گزارش خطا ← کپی، و برای پشتیبان بفرستید.', '5. Still failing: Settings → Error report → Copy, and send it to support.'),
    ]),
    (Icons.speed_rounded, tr('اگر کند بود', 'If it is slow'), [
      tr('از «همه‌ی سرورها» دکمه‌ی «تست پینگ» را بزنید و سرور سبز (کمتر از ۳۵۰ms) را انتخاب کنید.', 'In the Servers tab tap Ping test and pick a green server (under 350 ms).'),
      tr('سایت‌های ایرانی به‌طور پیش‌فرض مستقیم باز می‌شوند تا سرعتشان کم نشود.', 'Iranian sites open directly by default so they stay fast.'),
      tr('در گوشی‌های ضعیف «کاهش انیمیشن» را از تنظیمات ← ظاهر روشن کنید.', 'On slow devices turn on Reduce motion in Settings.'),
    ]),
    (Icons.widgets_rounded, tr('ویجت و دکمه‌ی سریع (اندروید)', 'Widget and quick tile (Android)'), [
      tr('ویجت: صفحه‌ی اصلی گوشی را نگه دارید ← ویجت‌ها ← MolidoVPN.', 'Widget: long-press the home screen → Widgets → MolidoVPN.'),
      tr('دکمه‌ی سریع: نوار اعلان را کامل پایین بکشید ← ویرایش (✏️) ← MolidoVPN را به کاشی‌ها بکشید.', 'Quick tile: pull down the notification shade → Edit (✏️) → drag MolidoVPN into the tiles.'),
    ]),
    (Icons.desktop_windows_rounded, tr('ویندوز', 'Windows'), [
      tr('حالت عادی مرورگرها و بیشتر برنامه‌ها را از VPN عبور می‌دهد.', 'Normal mode routes browsers and most apps through the VPN.'),
      tr('برای بازی‌ها و همه‌ی برنامه‌ها «VPN کامل (TUN)» را روشن کنید؛ برنامه باید به‌عنوان Administrator اجرا شود.', 'For games and all apps turn on Full VPN (TUN); the app must run as Administrator.'),
    ]),
    (Icons.shield_moon_rounded, tr('امنیت', 'Security'), [
      tr('سرورهای رایگان را افراد ناشناس اجرا می‌کنند. رمزها و اطلاعات بانکی را فقط در سایت‌های HTTPS وارد کنید.', 'Free servers are run by unknown people. Enter passwords and banking details only on HTTPS sites.'),
      tr('بانک‌ها و سایت‌های ایرانی را با «سایت‌های ایرانی مستقیم» یا «برنامه‌های خارج از VPN» مستقیم وصل کنید.', 'Connect banks and Iranian sites directly with Iranian sites direct or Apps outside VPN.'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Row(children: [
                    Glass(
                      radius: 16,
                      padding: const EdgeInsets.all(10),
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(backIcon, color: Palette.text),
                    ),
                    const SizedBox(width: 14),
                    Text(tr('راهنما', 'Help'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Palette.text)),
                  ]),
                  const SizedBox(height: 16),
                  for (final (i, (icon, title, lines)) in _sections.indexed)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 350 + i * 70),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) =>
                          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child)),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Glass(
                          radius: 22,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(icon, color: Palette.accent, size: 22),
                                const SizedBox(width: 10),
                                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.text)),
                              ]),
                              const SizedBox(height: 10),
                              for (final line in lines)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(line, style: TextStyle(fontSize: 13.5, height: 1.8, color: Palette.text)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
