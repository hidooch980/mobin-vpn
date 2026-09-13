import 'package:flutter/material.dart';

import '../core/engine.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _sections = <(IconData, String, List<String>)>[
    (Icons.touch_app_rounded, 'شروع سریع', [
      'دکمه‌ی بزرگ وسط صفحه را بزنید. برنامه چند سرور را با اینترنت خودتان تست می‌کند و به سریع‌ترین وصل می‌شود.',
      'بار اول اندروید اجازه‌ی VPN می‌خواهد؛ «تأیید» را بزنید.',
      'برای قطع، دوباره همان دکمه را بزنید.',
    ]),
    (Icons.public_rounded, 'انتخاب موقعیت', [
      'کارت «موقعیت» پایین صفحه را لمس کنید.',
      'هوشمند: سریع‌ترین سرور از همه‌ی کشورها.',
      'گیمینگ 🎮: سرورهای نزدیک به ایران با پینگ کم و پایدار.',
      'علاقه‌مندی‌ها ⭐: فقط سرورهایی که در «همه‌ی سرورها» ستاره زده‌اید.',
    ]),
    (Icons.wifi_off_rounded, 'اگر وصل نشد', [
      '۱. در تنظیمات «ضد فیلتر (TLS Fragment)» را روشن کنید.',
      '۲. «آدرس تست پینگ» را روی Cloudflare بگذارید.',
      '۳. از پایین صفحه‌ی اصلی لیست سرورها را به‌روزرسانی کنید.',
      '۴. یک کشور دیگر یا حالت گیمینگ را امتحان کنید.',
      '۵. اگر باز هم نشد: تنظیمات ← گزارش خطا ← کپی، و برای پشتیبان بفرستید.',
    ]),
    (Icons.speed_rounded, 'اگر کند بود', [
      'از «همه‌ی سرورها» دکمه‌ی «تست پینگ» را بزنید و سرور سبز (کمتر از ۳۵۰ms) را انتخاب کنید.',
      'سایت‌های ایرانی به‌طور پیش‌فرض مستقیم باز می‌شوند تا سرعتشان کم نشود.',
      'در گوشی‌های ضعیف «کاهش انیمیشن» را از تنظیمات ← ظاهر روشن کنید.',
    ]),
    (Icons.widgets_rounded, 'ویجت و دکمه‌ی سریع (اندروید)', [
      'ویجت: صفحه‌ی اصلی گوشی را نگه دارید ← ویجت‌ها ← Mobin VPN.',
      'دکمه‌ی سریع: نوار اعلان را کامل پایین بکشید ← ویرایش (✏️) ← Mobin VPN را به کاشی‌ها بکشید.',
    ]),
    (Icons.desktop_windows_rounded, 'ویندوز', [
      'حالت عادی مرورگرها و بیشتر برنامه‌ها را از VPN عبور می‌دهد.',
      'برای بازی‌ها و همه‌ی برنامه‌ها «VPN کامل (TUN)» را روشن کنید؛ برنامه باید به‌عنوان Administrator اجرا شود.',
    ]),
    (Icons.shield_moon_rounded, 'امنیت', [
      'سرورهای رایگان را افراد ناشناس اجرا می‌کنند. رمزها و اطلاعات بانکی را فقط در سایت‌های HTTPS وارد کنید.',
      'بانک‌ها و سایت‌های ایرانی را با «سایت‌های ایرانی مستقیم» یا «برنامه‌های خارج از VPN» مستقیم وصل کنید.',
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
                      child: Icon(Icons.arrow_forward_rounded, color: Palette.text),
                    ),
                    const SizedBox(width: 14),
                    Text('راهنما', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
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
