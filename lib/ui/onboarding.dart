import 'package:flutter/material.dart';

import 'strings.dart';
import 'style.dart';

/// First launch: three short steps explaining one-button connect, the location card and full VPN (admin).
Future<void> showOnboarding(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _Onboarding());

class _Onboarding extends StatefulWidget {
  const _Onboarding();

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  int _step = 0;

  static List<(IconData, String, String)> get _steps => [
        (
          Icons.power_settings_new_rounded,
          tr('فقط یک دکمه', 'Just one button'),
          tr('دکمه‌ی بزرگ وسط صفحه را بزنید. برنامه خودش بهترین سرور را برای اینترنت شما پیدا می‌کند و وصل می‌شود.',
              'Press the big button in the middle. The app finds the best server for your internet and connects.'),
        ),
        (
          Icons.public_rounded,
          tr('مکان خودکار', 'Automatic location'),
          tr('به‌طور پیش‌فرض بهترین سرور انتخاب می‌شود. اگر کشور خاصی می‌خواهید، کارت «مکان» را بزنید.',
              'The best server is picked for you. If you want a specific country, tap the "Location" card.'),
        ),
        (
          Icons.admin_panel_settings_rounded,
          tr('VPN برای همه‌ی برنامه‌ها', 'VPN for every app'),
          tr('معمولاً مرورگرها از VPN استفاده می‌کنند. برای بازی‌ها و همه‌ی برنامه‌ها، «VPN کامل» را در تنظیمات پیشرفته روشن کنید؛ '
                  'برای آن برنامه را با کلیک راست و «Run as administrator» باز کنید.\n'
                  'اگر مشکل ادامه داشت، در تلگرام به @Molido_Vpn پیام دهید.',
              'Browsers use the VPN by default. For games and every app, turn on "Full VPN" in advanced settings; '
                  'for that, open the app with right-click and "Run as administrator".\n'
                  'If problems continue, message @Molido_Vpn on Telegram.'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final (icon, title, text) = _steps[_step];
    final last = _step == _steps.length - 1;
    return Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        backgroundColor: Palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Palette.cardRadius)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Icon(icon, size: 56, color: Palette.accent),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Palette.text)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.7, color: Palette.muted)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _steps.length; i++)
                Container(
                  width: i == _step ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _step ? Palette.accent : Palette.raised,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          if (_step > 0) TextButton(onPressed: () => setState(() => _step--), child: Text(tr('قبلی', 'Back'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.accent,
              foregroundColor: Palette.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Palette.pillRadius)),
            ),
            onPressed: last ? () => Navigator.pop(context) : () => setState(() => _step++),
            child: Text(last ? tr('شروع', 'Start') : tr('بعدی', 'Next')),
          ),
        ],
      ),
    );
  }
}
